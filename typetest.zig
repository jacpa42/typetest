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
        \\-f, --word-file  <file> File to select words from. Ignored if stdin is not empty.
        \\
    );

    var res = try clap.parse(
        clap.Help,
        &params,
        .{
            .file = clap.parsers.string,
            .int = parsers.int(u32, 1, MAX_WORD_COUNT),
        },
        .{ .allocator = gpa.allocator() },
    );
    defer res.deinit();

    var words: Words = undefined;
    defer words.deinit(gpa.allocator());
    // If we are piping stuff into the program we read that rather than the file path provided
    if (std.fs.File.stdin().isTty()) {
        const path = res.args.@"word-file" orelse return error.MissingInput;

        var wordfile = try std.fs.cwd().openFile(path, .{});
        defer wordfile.close();

        words = try Words.parseFromFile(gpa.allocator(), wordfile);
    } else {
        words = try Words.parseFromFile(gpa.allocator(), std.fs.File.stdin());
    }

    var word_idx: usize = 1;
    var word_count = res.args.@"word-count" orelse DEFAULT_WORD_COUNT;

    while (word_count > 0) {
        word_idx = (word_idx << 1) % words.wordCount();
        std.debug.print("{:4}: {s}\n", .{ word_idx, words.getWordUnchecked(word_idx) });
        word_count -= 1;
    }

    // todo: choose some random words from the wordfile
    // todo: print out words and listen for keyboard input.

    // `clap.help` is a function that can print a simple help message. It can print any `Param`
    // where `Id` has a `description` and `value` method (`Param(Help)` is one such parameter).
    // The last argument contains options as to how `help` should print those parameters. Using
    // `.{}` means the default options.
    if (res.args.help != 0) return clap.helpToFile(.stderr(), clap.Help, &params, .{});
}

const Words = struct {
    /// Allocated slice of mem. utf8
    word_buf: []const u8,
    /// Indices of newline characters in `word_buf`
    newlines: []const usize,

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

    fn parseFromReader(
        gpa: std.mem.Allocator,
        reader: *std.fs.File.Reader,
    ) WordsParseError!@This() {
        const KIB = 1024;

        const word_buf = try reader.interface.allocRemaining(
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

    fn parseFromFile(
        gpa: std.mem.Allocator,
        file: std.fs.File,
    ) WordsParseError!@This() {
        const KIB = 1024;
        var buf: [KIB]u8 = undefined;
        var file_reader = file.reader(&buf);
        return @This().parseFromReader(gpa, &file_reader);
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
