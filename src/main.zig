const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const cli_args = @import("args.zig");
const scene = @import("scene.zig");

const now = @import("scene/util.zig").now;
const State = @import("State.zig");

test {
    std.testing.refAllDecls(@This());
}

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}).init;
    defer if (gpa.deinit() == .leak) std.debug.print("Leak detected!!\n", .{});

    const alloc = gpa.allocator();
    var game_state = try State.init(alloc, try cli_args.parseArgs(alloc));
    defer game_state.deinit();

    var tty_buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&tty_buffer);
    defer tty.deinit();

    var vx = try vaxis.init(alloc, .{});
    defer vx.deinit(alloc, tty.writer());

    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();
    try loop.start();
    defer loop.stop();

    try vx.enterAltScreen(tty.writer());
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    game_loop: while (true) {
        const frame_start = now();
        defer game_state.tickFrame(frame_start);

        while (loop.tryEvent()) |event| switch (event) {
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
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
        };

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
            .custom_game_scene => {},
        }

        vx.window().clear();
        vx.window().hideCursor();
        try game_state.render(vx.window());
        try vx.render(tty.writer());
    }
}
