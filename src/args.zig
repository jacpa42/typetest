const std = @import("std");
const clap = @import("clap");

const Words = @import("Words.zig");
const max_word_count = 100_000;
const default_word_count = 50;
const params = clap.parseParamsComptime(
    \\-h, --help              Display this help and exit.
    \\-w, --word-count <int>  Number of words to show.
    \\-s, --seed       <seed> Seed to use for rng.
    \\-f, --word-file  <file> File to select words from. Ignored if stdin is not empty.
);

/// All the relevant stuff we need after argument parsing
pub const Args = struct {
    words: Words,
    seed: u64,
    word_count: u64,

    pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
        self.words.deinit(alloc);
    }
};

const ParseArgsError = error{};

pub fn parseArgs(alloc: std.mem.Allocator) !Args {
    var res = try clap.parse(
        clap.Help,
        &params,
        .{
            .file = clap.parsers.string,
            .seed = clap.parsers.int(u64, 10),
            .int = parsers.int(u64, 1, max_word_count),
        },
        .{ .allocator = alloc },
    );
    defer res.deinit();

    if (res.args.help > 0) {
        const help_style = clap.HelpOptions{
            .description_indent = 0,
            .indent = 2,
            .markdown_lite = true,
            .description_on_new_line = false,
            .spacing_between_parameters = 0,
        };

        const result = clap.helpToFile(
            .stderr(),
            clap.Help,
            &params,
            help_style,
        );

        result catch std.process.exit(1);

        std.process.exit(0);
    }

    const words = try Words.parseFromPath(
        alloc,
        res.args.@"word-file",
        max_word_count,
    );

    return .{
        .words = words,
        .seed = res.args.seed orelse 0,
        .word_count = res.args.@"word-count" orelse default_word_count,
    };
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
