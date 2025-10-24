const std = @import("std");
const clap = @import("clap");

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help              Display this help and exit.
        \\-f, --word-file <file>  File to select words from
        \\
    );

    var res = try clap.parse(
        clap.Help,
        &params,
        .{ .file = clap.parsers.string },
        .{ .allocator = gpa.allocator() },
    );
    defer res.deinit();

    var word_file = try WordFile.parse(
        gpa.allocator(),
        res.args.@"word-file" orelse return error.WordFileRequired,
    );
    defer word_file.deinit(gpa.allocator());

    std.debug.print("{any}\n", .{word_file.word_buf.len});

    // todo: choose some random words from the wordfile
    // todo: print out words and listen for keyboard input.

    // `clap.help` is a function that can print a simple help message. It can print any `Param`
    // where `Id` has a `description` and `value` method (`Param(Help)` is one such parameter).
    // The last argument contains options as to how `help` should print those parameters. Using
    // `.{}` means the default options.
    if (res.args.help != 0) return clap.helpToFile(.stderr(), clap.Help, &params, .{});
}

const WordFileParse = error{
    OutOfMemory,
} ||
    std.fs.File.OpenError ||
    std.Io.Reader.LimitedAllocError;

const WordFile = struct {
    /// The literal raw contents of the file.
    ///
    /// Each `word` is just each line
    word_buf: []const u8,

    // Todo: add a structure here which includes the string slices for each word so we can randomly select words to choose next.

    fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        gpa.free(self.word_buf);
    }

    /// Opens the file relative to the cwd
    fn parse(
        gpa: std.mem.Allocator,
        path: []const u8,
    ) WordFileParse!@This() {
        const f = try std.fs.cwd().openFile(path, .{});

        const KIB = 1024;
        var buf: [KIB]u8 = undefined;
        var reader = f.reader(&buf);

        const contents = try reader.interface.allocRemaining(gpa, .limited(KIB * KIB * KIB));

        return WordFile{ .word_buf = contents };
    }
};
