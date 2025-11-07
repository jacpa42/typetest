const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const cli_args = @import("args.zig");
const scene = @import("scene.zig");
const action = @import("action.zig");

const now = @import("scene/util.zig").now;
const State = @import("State.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    const gpa = std.heap.page_allocator;

    var game_state = try State.init(gpa);
    defer game_state.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(gpa, .{});
    defer vx.deinit(gpa, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    game_loop: while (true) {
        const frame_start = now();
        defer game_state.tickFrame(frame_start);

        while (loop.tryEvent()) |event| {
            switch (event) {
                .winsize => |ws| {
                    try vx.resize(gpa, tty.writer(), ws);
                    try game_state.reinit(((vx.screen.width * 5) / 8) -| 2);
                },

                .key_press => |key| {
                    const result = try game_state.processKeyPress(
                        key,
                        ((vx.screen.width * 5) / 8) -| 2,
                    );
                    switch (result) {
                        .continue_game => {},
                        .graceful_exit => break :game_loop,
                    }
                },
            }
        }

        switch (game_state.current_scene) {
            .time_scene => |*time_scene| if (time_scene.isComplete()) |results| {
                _ = game_state.scene_arena.reset(.retain_capacity);
                game_state.current_scene = scene.Scene{ .test_results_scene = results };
            },

            .word_scene => |*word_scene| if (word_scene.isComplete()) |results| {
                _ = game_state.scene_arena.reset(.retain_capacity);
                game_state.current_scene = scene.Scene{ .test_results_scene = results };
            },
            .menu_scene => {},
            .test_results_scene => {},
            .custom_game_selection_scene => {},
        }

        vx.window().clear();
        vx.window().hideCursor();
        try game_state.render(vx.window());
        try vx.render(tty.writer());
    }
}

test "statistic formatting" {
    const labels: [7][]const u8 = .{
        "wpm: ",
        "ti食me left: ",
        "words left: ",
        "fp食s食: ",
        "mistakes: ",
        "雨: ",
        "🐐雨食: ",
    };
    var prng = std.Random.DefaultPrng.init(0);
    const statistic = @import("scene/statistics.zig");

    for (0.., labels) |seed, label| {
        std.debug.print("using seed: {}\n", .{seed});
        prng.seed(@as(u64, seed));
        var rng = prng.random();
        const true_value = rng.int(u32);

        const stat = statistic.Statistic{
            .label = label,
            .value = true_value,
        };
        const fmt_stat = statistic.FormattedStatistic.init(stat);

        {
            const fmt_len = try std.unicode.utf8CountCodepoints(label) + fmt_stat.getValue().len;
            try std.testing.expect(fmt_stat.codepoint_len == fmt_len);
        }

        {
            const parsed_value = try std.fmt.parseInt(u32, fmt_stat.getValue(), 10);
            std.debug.print("true_value: {}, formatted_value: {s}\n", .{ true_value, fmt_stat.getValue() });
            std.debug.print("formatted_value_buf: {s}\n", .{fmt_stat.value_buffer});
            try std.testing.expect(parsed_value == true_value);
        }
    }
}
