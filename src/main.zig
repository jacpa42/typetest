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
    // Lets try to reuse a 1 MIB buffer for all our memory needs :)
    const mem: []u8 = try std.heap.page_allocator.alloc(u8, 1024 * 1024);
    defer std.heap.page_allocator.free(mem);

    var gpa = std.heap.FixedBufferAllocator.init(mem);
    const alloc = gpa.allocator();

    var args = try parseArgs(alloc);
    defer args.deinit(alloc);

    const frame_delay: u64 = 6944 * 1e3; // 6.644ms / 144hz
    var game_state = State{};
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
    var render_width = @min(30, win.width / 2);
    var render_height = @min(scene.NUM_RENDER_LINES, win.height);

    game_loop: while (true) {
        const frame_start = now();
        defer {
            const elapsed_ms = now().since(frame_start);
            std.Thread.sleep(frame_delay -| elapsed_ms);
        }

        while (loop.tryEvent()) |event| {
            switch (event) {
                .winsize => |ws| {
                    try vx.resize(alloc, tty.writer(), ws);
                    win = vx.window();
                    render_width = @min(30, win.width / 2);
                    render_height = @min(scene.NUM_RENDER_LINES, win.height);
                },

                .key_press => |key| {
                    const codepoint_limit = render_width - 2;
                    const result = try game_state.processKeyPress(
                        alloc,
                        key,
                        codepoint_limit,
                        &args,
                    );
                    switch (result) {
                        .should_quit => break :game_loop,
                        .redraw => continue,
                    }
                },
            }
        }

        game_state.render(win);
        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());
    }
}
