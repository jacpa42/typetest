const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const DEFAULT_WORD_COUNT = 50;
const MAX_WORD_COUNT = 100_000;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        switch (gpa.deinit()) {
            .ok => {},
            .leak => {
                std.debug.print("memory leak somewhere buddy :)\n", .{});
            },
        }
    }

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-w, --word-count <int>  Number of words to show.
        \\-s, --seed       <seed> Seed to use for rng.
        \\-f, --word-file  <file> File to select words from. Ignored if stdin is not empty.
        \\
    );

    var res = try clap.parse(
        clap.Help,
        &params,
        .{
            .file = clap.parsers.string,
            .seed = clap.parsers.int(u64, 10),
            .int = parsers.int(u32, 1, MAX_WORD_COUNT),
        },
        .{ .allocator = alloc },
    );
    defer res.deinit();

    // `clap.help` is a function that can print a simple help message. It can print any `Param`
    // where `Id` has a `description` and `value` method (`Param(Help)` is one such parameter).
    // The last argument contains options as to how `help` should print those parameters. Using
    // `.{}` means the default options.
    if (res.args.help > 0) {
        return clap.helpToFile(.stderr(), clap.Help, &params, .{
            .description_indent = 0,
            .indent = 2,
            .markdown_lite = true,
            .description_on_new_line = false,
            .spacing_between_parameters = 0,
        });
    }

    var words = try Words.parseFromPath(alloc, res.args.@"word-file");
    defer words.deinit(alloc);

    const words_for_test = try words.generateRandomWords(
        alloc,
        res.args.seed orelse 0,
        res.args.@"word-count" orelse DEFAULT_WORD_COUNT,
    );
    defer alloc.free(words_for_test);

    // Init tty
    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{});
    // Deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(alloc, tty.writer());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.writer());

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();

        // Exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else {
                    // todo: print the key on screen :)
                }
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell. Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            else => {},
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        // Create a style
        const style: vaxis.Style = .{};

        const box_width = win.width / 2;
        const box_height = win.height / 2;

        // Create a bordered child window
        const child = win.child(.{
            .x_off = (win.width - box_width) / 2,
            .y_off = (win.height - box_height) / 2,
            .width = box_width,
            .height = box_height,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        // todo: Each time the user presses a key we need to render if they typed that correctly.

        child.writeCell(1, 0, .{
            .char = .{ .width = 1, .grapheme = "🫡" },
            .style = .{ .bg = .{ .index = 0 } },
        });

        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());
    }
}

const Words = struct {
    /// Allocated slice of mem. utf8
    word_buf: []const u8,
    /// Indices of newline characters in `word_buf`
    newlines: []const usize,

    /// Returns count number of words.
    fn generateRandomWords(
        self: *const @This(),
        alloc: std.mem.Allocator,
        seed: u64,
        count: usize,
    ) error{OutOfMemory}![]const u8 {
        // We want a line of words which is the length of the test length
        var rng = std.Random.DefaultPrng.init(seed);
        var current_word_buf = std.ArrayList(u8).empty;
        defer current_word_buf.deinit(alloc);

        for (0..count) |_| {
            const idx =
                rng.random().intRangeLessThan(usize, 0, self.wordCount());
            const next_word = self.getWordUnchecked(idx);

            try current_word_buf.ensureUnusedCapacity(alloc, next_word.len + 1);
            current_word_buf.appendSliceAssumeCapacity(next_word);
            current_word_buf.appendAssumeCapacity(' ');
        }

        return try current_word_buf.toOwnedSlice(alloc);
    }

    /// Returns a (utf8) word from the wordbuf at the index
    fn getWordUnchecked(self: *const @This(), idx: usize) []const u8 {
        std.debug.assert(idx + 1 < self.newlines.len);
        return self.word_buf[self.newlines[idx] + 1 .. self.newlines[idx + 1]];
    }

    /// the total number of words
    fn wordCount(self: *const @This()) usize {
        std.debug.assert(self.newlines.len > 0);
        return self.newlines.len - 1;
    }

    fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
        gpa.free(self.word_buf);
        gpa.free(self.newlines);
    }

    const WordsParseError =
        error{ OutOfMemory, InvalidUtf8, EmptyFile } ||
        std.fs.File.OpenError ||
        std.Io.Reader.LimitedAllocError;

    fn parseFromFile(
        gpa: std.mem.Allocator,
        file: std.fs.File,
    ) WordsParseError!@This() {
        const KIB = 1024;
        var buf: [KIB]u8 = undefined;
        var file_reader = file.reader(&buf);

        const word_buf = try file_reader.interface.allocRemaining(
            gpa,
            .limited(KIB * KIB * KIB),
        );
        errdefer gpa.free(word_buf);

        var newlines_array_list = try std.ArrayList(usize).initCapacity(gpa, MAX_WORD_COUNT);
        errdefer newlines_array_list.deinit(gpa);

        var utf8_iter = (try std.unicode.Utf8View.init(word_buf)).iterator();
        var idx: usize = 0;

        // Insert an artificial newline at the beginning to not skip first word
        newlines_array_list.appendAssumeCapacity(0);

        while (utf8_iter.nextCodepointSlice()) |cp_slice| {
            // Check for newline character
            if (cp_slice[0] == '\n') try newlines_array_list.append(gpa, idx);
            idx += cp_slice.len;
        }

        if (newlines_array_list.items.len == 1) return error.EmptyFile;
        newlines_array_list.appendAssumeCapacity(word_buf.len);
        const newlines = try newlines_array_list.toOwnedSlice(gpa);

        return Words{ .word_buf = word_buf, .newlines = newlines };
    }

    /// If `stdin` is not piped then try use the path var
    fn parseFromPath(
        gpa: std.mem.Allocator,
        path: ?[]const u8,
    ) (error{MissingInputFile} || WordsParseError)!@This() {
        const stdin = std.fs.File.stdin();
        if (stdin.isTty()) {
            const wordfile = try std.fs.cwd().openFile(path orelse return error.MissingInputFile, .{});
            defer wordfile.close();

            return try Words.parseFromFile(gpa, wordfile);
        } else {
            return try Words.parseFromFile(gpa, stdin);
        }
    }
};

const parsers = struct {
    fn int(comptime T: type, min: comptime_int, max: comptime_int) fn (in: []const u8) std.fmt.ParseIntError!T {
        return struct {
            fn parse(in: []const u8) std.fmt.ParseIntError!T {
                const value = switch (@typeInfo(T).int.signedness) {
                    .signed => try std.fmt.parseUnsigned(T, in, 10),
                    .unsigned => try std.fmt.parseInt(T, in, 10),
                };

                if (value < min or value > max) return error.Overflow else return value;
            }
        }.parse;
    }
};
