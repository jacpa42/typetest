const std = @import("std");
const clap = @import("clap");
const Words = @import("words.zig").Words;

const KIB = 1024;
const MAX_FILE_SIZE = 512 * KIB;

const MIN_WORD_COUNT = 1;
const MAX_WORD_COUNT = std.math.maxInt(u32);

const MIN_TIME_GAME_DURATION = 1;
const MAX_TIME_GAME_DURATION = std.math.maxInt(u32);

const DEFAULT_WORD_COUNT = 50;
const DEFAULT_ANIMIATION_DURATION = 500;

const params = clap.parseParamsComptime(
    \\-h, --help             Display this help and exit
    \\-s, --seed <seed>      Seed to use for rng (default is a random seed)
    \\-f, --word-file <file> File to select words from (ignored if stdin is not empty)
    \\-a, --duration <dur>   Duration of the title screen animation in frames
);

/// All the relevant stuff we need after argument parsing
pub const Args = struct {
    word_buffer: []const u8,
    words: Words,
    seed: u64,
    animation_duration: u64,
};

pub fn parseArgs(alloc: std.mem.Allocator) !Args {
    var res = clap.parse(
        clap.Help,
        &params,
        .{
            .file = clap.parsers.string,
            .seed = clap.parsers.int(u64, 10),
            .dur = clap.parsers.int(u64, 10),
        },
        .{ .allocator = alloc },
    ) catch |err| {
        var buf: [1024]u8 = undefined;
        const errname = @errorName(err);
        const errmsg = std.fmt.bufPrint(
            &buf,
            "An unexpected error has occured during argument parsing: {s}\n\n",
            .{errname},
        ) catch std.process.exit(1);
        printHelp(errmsg);
    };
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

    const words = Words.init(alloc, word_buffer) catch |err| {
        const info = switch (err) {
            error.OutOfMemory => "We ran out of memory trying to allocate your input :(\n\n",
            error.InvalidUtf8 => "The input provided is not valid utf8\n\n",
            error.EmptyFile => "The input provided is contains no words\n\n",
        };
        printHelp(info);
    };

    var animation_duration: u64 = undefined;
    if (res.args.duration) |d| {
        if (d <= 0) {
            printHelp("The animation duration must be greater than 0 :)\n\n");
        } else {
            animation_duration = d;
        }
    } else {
        animation_duration = DEFAULT_ANIMIATION_DURATION;
    }

    return Args{
        .word_buffer = word_buffer,
        .words = words,
        .animation_duration = animation_duration,
        .seed = res.args.seed orelse (@bitCast(std.time.microTimestamp() *% 115578717622022981)),
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
