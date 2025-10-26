const std = @import("std");
const clap = @import("clap");

const DEFAULT_WORD_COUNT = 50;
const MAX_WORD_COUNT = 100_000;

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

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
        .{ .allocator = gpa.allocator() },
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

    var words = try Words.parseFromPath(gpa.allocator(), res.args.@"word-file");
    defer words.deinit(gpa.allocator());

    const word_count = res.args.@"word-count" orelse DEFAULT_WORD_COUNT;
    var rng = std.Random.DefaultPrng.init(res.args.seed orelse 0);

    for (1..word_count + 1) |word| {
        const idx = @as(usize, @truncate(rng.next())) % words.wordCount();
        std.debug.print("{:7}: {s}\n", .{ word, words.getWordUnchecked(idx) });
    }

    const stdout = std.fs.File.stdout();
    var winsize = try getTerminalSize(stdout);
    winsize = undefined;
}

fn getTerminalSize(
    file: std.fs.File,
) error{ TerminalUnsupported, GetSizeFail }!struct { w: u16, h: u16 } {
    if (!file.supportsAnsiEscapeCodes()) return error.TerminalUnsupported;

    const builtin = @import("builtin");

    return switch (builtin.os.tag) {
        .linux, .macos => blk: {
            var buf: std.posix.winsize = undefined;
            break :blk switch (std.posix.errno(
                std.posix.system.ioctl(
                    file.handle,
                    std.posix.T.IOCGWINSZ,
                    @intFromPtr(&buf),
                ),
            )) {
                .SUCCESS => .{ .w = buf.col, .h = buf.row },
                else => error.GetSizeFail,
            };
        },
        .windows => blk: {
            var buf: std.os.windows.CONSOLE_SCREEN_BUFFER_INFO = undefined;
            break :blk switch (std.os.windows.kernel32.GetConsoleScreenBufferInfo(
                file.handle,
                &buf,
            )) {
                std.os.windows.TRUE => .{
                    .w = @intCast(buf.srWindow.Right - buf.srWindow.Left + 1),
                    .h = @intCast(buf.srWindow.Bottom - buf.srWindow.Top + 1),
                },
                else => error.GetSizeFail,
            };
        },
        else => @compileError("Your platform is unsupported."),
    };
}

const Words = struct {
    /// Allocated slice of mem. utf8
    word_buf: []const u8,
    /// Indices of newline characters in `word_buf`
    newlines: []const usize,

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
