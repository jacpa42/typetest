const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const cli_args = @import("args.zig");
const scene = @import("scene.zig");
const action = @import("action.zig");

const now = @import("time.zig").now;
const parseArgs = cli_args.parseArgs;
const Args = cli_args.Args;
const State = @import("State.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

pub fn main() !void {
    const alloc = std.heap.page_allocator;

    var game_state = State.init(try parseArgs(alloc));
    defer game_state.deinit(alloc);

    // Init tty
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

    var win = vx.window();
    var render_width = (win.width * 3) / 5;

    game_loop: while (true) {
        const frame_start = now();
        defer game_state.tickFrame(frame_start, 60);

        while (loop.tryEvent()) |event| {
            switch (event) {
                .winsize => |ws| {
                    try vx.resize(alloc, tty.writer(), ws);
                    win = vx.window();
                    render_width = (win.width * 3) / 5;
                },

                .key_press => |key| {
                    const result = try game_state.processKeyPress(alloc, key, render_width - 2);
                    switch (result) {
                        .continue_game => {},
                        .graceful_exit => break :game_loop,
                    }
                },
            }
        }

        switch (game_state.current_scene) {
            .time_scene => |*time_scene| {
                if (time_scene.isComplete()) |results| {
                    time_scene.deinit(alloc);
                    game_state.current_scene = scene.Scene{ .test_results_scene = results };
                }
            },

            .word_scene => |*word_scene| {
                if (word_scene.isComplete()) |results| {
                    word_scene.deinit(alloc);
                    game_state.current_scene = scene.Scene{ .test_results_scene = results };
                }
            },
            .menu_scene => {},
            .test_results_scene => {},
        }

        win.clear();
        try game_state.render(win);
        try vx.render(tty.writer());
    }
}
