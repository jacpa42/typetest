const std = @import("std");
const clap = @import("clap");
const Words = @import("words.zig").Words;

const KIB = 1024;
const MAX_FILE_SIZE = 512 * KIB;

const MAX_WORD_COUNT = 1000;
const DEFAULT_WORD_COUNT = 50;

const params = clap.parseParamsComptime(
    \\-h, --help              Display this help and exit.
    \\-w, --word-count <int>  Number of words to show.
    \\-s, --seed       <seed> Seed to use for rng.
    \\-f, --word-file  <file> File to select words from. Ignored if stdin is not empty.
);

/// All the relevant stuff we need after argument parsing
pub const Args = struct {
    word_buffer: []const u8,
    words: Words,
    seed: u64 = 0,
    word_count: u64 = 0,

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        alloc.free(self.word_buffer);
        self.word_buffer = undefined;

        self.words.deinit(alloc);
    }
};

pub fn parseArgs(alloc: std.mem.Allocator) !Args {
    var res = try clap.parse(
        clap.Help,
        &params,
        .{
            .file = clap.parsers.string,
            .seed = clap.parsers.int(u64, 10),
            .int = parsers.int(u64, 1, MAX_WORD_COUNT),
        },
        .{ .allocator = alloc },
    );
    defer res.deinit();

    if (res.args.help > 0) printHelp("");

    const word_buffer = readWordFileIntoMemory(
        alloc,
        res.args.@"word-file",
    ) catch |err| {
        const info = switch (err) {
            error.MissingInput => "You need to provide input words via stdin or via a file with --word-file\n\n",
            error.InvalidUtf8 => "The file path provided is not valid utf8\n\n",

            inline else => |e| "An unexpected error has occured: " ++ @errorName(e) ++ "\n\n",
        };

        printHelp(info);
    };

    const words = Words.init(
        alloc,
        word_buffer,
        MAX_WORD_COUNT,
    ) catch |err| {
        const info = switch (err) {
            error.OutOfMemory => "We ran out of memory trying to allocate your input :(\n\n",
            error.InvalidUtf8 => "The file contents provided is not valid utf8\n\n",
        };
        printHelp(info);
    };

    return Args{
        .word_buffer = word_buffer,
        .words = words,
        .seed = res.args.seed orelse 0,
        .word_count = res.args.@"word-count" orelse DEFAULT_WORD_COUNT,
    };
}

/// Prints the help to stderr along with an info message and exits the program
fn printHelp(info: []const u8) noreturn {
    const help_style = clap.HelpOptions{
        .description_indent = 0,
        .indent = 2,
        .markdown_lite = true,
        .description_on_new_line = false,
        .spacing_between_parameters = 0,
    };

    var buf: [1024]u8 = undefined;
    var writer = std.fs.File.stderr().writer(&buf);

    writer.interface.writeAll(info) catch std.process.exit(1);

    clap.help(&writer.interface, clap.Help, &params, help_style) catch std.process.exit(1);
    writer.interface.flush() catch std.process.exit(1);

    std.process.exit(0);
}

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

const ReadWordFileError =
    error{MissingInput} ||
    std.fs.File.OpenError ||
    std.Io.Reader.LimitedAllocError;

/// If `stdin` is not piped then try use the passed path arg.
pub fn readWordFileIntoMemory(
    gpa: std.mem.Allocator,
    path: ?[]const u8,
) ReadWordFileError![]const u8 {
    var wordfile = std.fs.File.stdin();
    defer wordfile.close();

    if (std.fs.File.stdin().isTty()) {
        wordfile = try std.fs.cwd().openFile(path orelse return error.MissingInput, .{});
    }

    var buf: [KIB]u8 = undefined;
    var file_reader = wordfile.reader(&buf);

    const word_buf = try file_reader.interface.allocRemaining(
        gpa,
        .limited(MAX_FILE_SIZE),
    );

    return word_buf;
}
