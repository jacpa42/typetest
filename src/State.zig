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
const RingBuffer = @import("ring_buffer.zig").RingBuffer;

pub const NUM_FRAME_TIMINGS = 20;
pub const FrameTimings = RingBuffer(u64, NUM_FRAME_TIMINGS);

/// What frame of the game are we on
frame_counter: u64 = 0,
/// The time taken to render a frame in ns
frame_timings: FrameTimings = .fill(0),
/// Current scene of the game
current_scene: scene.Scene = .{ .menu_scene = .{} },

pub fn render(
    self: *const @This(),
    data: scene.RenderData,
) void {
    switch (self.current_scene) {
        .menu_scene => |menu_scene| menu_scene.render(data),
        .time_scene => |*time_scene| time_scene.render(data),
        .test_results_scene => |*test_results| test_results.render(data),
    }
}

/// Runs each frame
///
/// Updates the internal data and then sleeps for the correct time to ensure that
/// we try to match the fps
pub fn tickFrame(
    self: *@This(),
    frame_start: std.time.Instant,
    desired_fps: u64,
) void {
    const frame_delay_ns: u64 = @as(u64, 1e9) / desired_fps;
    const this_frame_time = now().since(frame_start);

    self.frame_counter += 1;
    self.frame_timings.append(this_frame_time);

    defer std.Thread.sleep(frame_delay_ns -| this_frame_time);
}

pub fn processKeyPress(
    self: *@This(),
    alloc: std.mem.Allocator,
    key: vaxis.Key,
    codepoint_limit: u16,
    args: *Args,
) error{OutOfMemory}!enum { continue_game, graceful_exit } {
    const menuEvent = action.MenuAction.processKeydown;
    const gameEvent = action.InGameAction.processKeydown;
    const resultsEvent = action.ResultsAction.processKeydown;

    switch (self.current_scene) {
        .menu_scene => |*menu| switch (menuEvent(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .move_up => menu.moveSelectionUp(),
            .move_down => menu.moveSelectionDown(),
            .select => {
                const test_duration_ns: u64 = switch (menu.selection) {
                    .exit => return .graceful_exit,
                    .time15 => 15 * 1e9,
                    .time30 => 30 * 1e9,
                    .time60 => 60 * 1e9,
                    .time120 => 120 * 1e9,
                };

                self.current_scene = .{
                    .time_scene = try .init(
                        alloc,
                        &args.words,
                        codepoint_limit,
                        test_duration_ns,
                    ),
                };
            },
        },
        .test_results_scene => switch (resultsEvent(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => self.current_scene = .{ .menu_scene = .{} },
        },
        .time_scene => |*timegame| switch (gameEvent(key)) {
            .none => return .continue_game,
            .exit_game => {
                timegame.deinit(alloc);
                self.current_scene = .{ .menu_scene = .{} };
            },
            .new_random_game => {
                try timegame.newGame(
                    alloc,
                    timegame.test_duration_ns,
                    codepoint_limit,
                    &args.words,
                );
            },
            .undo_key_press => timegame.processUndo(),
            .key_press => |codepoint| {
                try timegame.processKeyPress(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    codepoint,
                );
            },
        },
    }

    return .continue_game;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    switch (self.current_scene) {
        .menu_scene => {},
        .test_results_scene => {},
        .time_scene => |*time_scene| time_scene.deinit(alloc),
    }
}
