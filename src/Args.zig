const std = @import("std");
const clap = @import("clap");
const wd = @import("words.zig");
const vaxis = @import("vaxis");
const Words = wd.Words;

const Args = @This();

word_buffer: []const u8,
words: Words,
seed: u64,
fps: u64,
animation_duration: u64,
cursor_shape: vaxis.Cell.CursorShape,

const KIB = 1024;
const MAX_FILE_SIZE = 512 * KIB;

const MIN_WORD_COUNT = 1;
const MAX_WORD_COUNT = std.math.maxInt(u32);

const DEFAULT_WORD_COUNT = 50;
const DEFAULT_ANIMIATION_DURATION = 500;
const DEFAULT_FPS = 60;

const params = clap.parseParamsComptime(
    \\-h, --help                 Display this help and exit
    \\-s, --seed <seed>          Seed to use for rng (default is a random)
    \\-a, --duration <dur>       Duration of the title screen animation in frames
    \\-c, --cursor-shape <shape> Cursor style (default is block): block  | beam | underline
    \\-m, --mode <mode>          Word generation mode (default is random): random | sequential
    \\-w, --word-file <file>     File to select words from (ignored if stdin is not empty)
    \\-l, --lowercase            Whether or not to make all words lowercase.
    \\-b, --blink                Whether or not the cursor blinks
    \\-f, --fps <fps>            Desired frame rate for the game (default is 60)
);

const value_parsers = .{
    .file = clap.parsers.string,
    .mode = clap.parsers.enumeration(wd.RngMode),
    .seed = clap.parsers.int(u64, 10),
    .dur = clap.parsers.int(u64, 10),
    .shape = clap.parsers.enumeration(CursorShape),
    .fps = parsers.int(u64, 24, std.math.maxInt(u64)),
};

const opts = clap.ParseOptions{ .allocator = undefined };

pub fn parse(alloc: std.mem.Allocator) !Args {
    const res = clap.parse(clap.Help, &params, value_parsers, opts) catch |err| {
        const info = switch (err) {
            error.NameNotPartOfEnum => "The enumeration values are listed in the help menu below\n\n",
            inline else => |e| "Failed to parse command line arguments: " ++ @errorName(e) ++ "\n\n",
        };
        printHelp(info);
    };

    if (res.args.help > 0) printHelp("");

    const word_buffer = readWordFileIntoMemory(
        alloc,
        res.args.@"word-file",
    ) catch |err| {
        const info = switch (err) {
            error.MissingInput => "You need to provide input words via stdin or via a file with --word-file\n\n",
            error.InvalidUtf8 => "The file path provided is not valid UTF-8\n\n",
            inline else => |e| "An unexpected error has occurred: " ++ @errorName(e) ++ "\n\n",
        };
        printHelp(info);
    };

    const rand_seed = std.time.microTimestamp() *% 115578717622022981;
    const seed: u64 = res.args.seed orelse @bitCast(rand_seed);
    const rng = switch (res.args.mode orelse .random) {
        .sequential => wd.WordRng{ .sequential = 0 },
        .random => wd.WordRng{ .random = .init(seed) },
    };
    const words = Words.init(alloc, rng, res.args.lowercase > 0, word_buffer) catch |err| {
        const info = switch (err) {
            error.OutOfMemory => "We ran out of memory trying to allocate your input :(\n\n",
            error.InvalidUtf8 => "The input provided is not valid UTF-8\n\n",
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

    const blink = res.args.blink > 0;
    const cursor_shape: vaxis.Cell.CursorShape =
        switch (res.args.@"cursor-shape" orelse CursorShape.default) {
            .block => if (blink) .block_blink else .block,
            .underline => if (blink) .underline_blink else .underline,
            .beam => if (blink) .beam_blink else .beam,
        };

    return Args{
        .word_buffer = word_buffer,
        .words = words,
        .animation_duration = animation_duration,
        .seed = seed,
        .cursor_shape = cursor_shape,
        .fps = res.args.fps orelse DEFAULT_FPS,
    };
}

const CursorShape = enum {
    beam,
    block,
    underline,

    const default = CursorShape.block;
};

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

pub const parsers = struct {
    pub fn int(comptime T: type, min: comptime_int, max: comptime_int) fn (in: []const u8) std.fmt.ParseIntError!T {
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

    pub fn @"bool"(comptime default: bool) fn (in: []const u8) error{InvalidCharacter}!bool {
        return struct {
            fn parse(in: []const u8) error{InvalidCharacter}!bool {
                if (in.len == 0) {
                    return default;
                } else if (std.mem.eql(u8, in, "false")) {
                    return false;
                } else if (std.mem.eql(u8, in, "true")) {
                    return true;
                }
                return error.InvalidCharacter;
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

test "using allocator undefined is okay for arg parsing :)" {
    const argbuf: []const u8 =
        "--seed 132532 " ++
        "--duration 2139 " ++
        "--cursor-shape block " ++
        "--mode sequential " ++
        "--word-file /home/jacob/Documents/dissertation.pdf " ++
        "--lowercase " ++
        "--blink " ++
        "--fps 144";
    var my_pog_iter = std.mem.splitScalar(u8, argbuf, ' ');
    _ = try clap.parseEx(clap.Help, &params, value_parsers, &my_pog_iter, opts);
}
