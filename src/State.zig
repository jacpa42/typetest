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

pub inline fn render(
    self: *const @This(),
    data: scene.RenderData,
) error{WindowTooSmall}!void {
    return self.current_scene.render(data);
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
) error{ OutOfMemory, EmptyLineNotAllowed }!enum { continue_game, graceful_exit } {
    const menuEventHandler = action.MenuAction.processKeydown;
    const gameEventHandler = action.InGameAction.processKeydown;
    const resultsEventHandler = action.ResultsAction.processKeydown;

    switch (self.current_scene) {
        .menu_scene => |*supermenu| switch (menuEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .goback => switch (supermenu.selection) {
                .main_menu => return .graceful_exit,
                .time_game_menu => supermenu.selection = .{ .main_menu = .default },
                .word_game_menu => supermenu.selection = .{ .main_menu = .default },
            },
            .move_up => supermenu.moveSelection(.up),
            .move_down => supermenu.moveSelection(.down),
            .select => switch (supermenu.selection) {
                .main_menu => |inner_menu| {
                    switch (inner_menu) {
                        .exit => return .graceful_exit,
                        .time => supermenu.selection = .{ .time_game_menu = .default },
                        .word => supermenu.selection = .{ .word_game_menu = .default },
                    }
                },
                .time_game_menu => |inner_menu| {
                    const test_duration_ns: u64 = switch (inner_menu) {
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
                .word_game_menu => |inner_menu| {
                    const total_words: u32 = switch (inner_menu) {
                        .words10 => 10,
                        .words25 => 25,
                        .words50 => 50,
                        .words100 => 100,
                    };

                    self.current_scene = .{
                        .word_scene = try .init(
                            alloc,
                            &args.words,
                            codepoint_limit,
                            total_words,
                        ),
                    };
                },
            },
        },
        .test_results_scene => switch (resultsEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => self.current_scene = .{ .menu_scene = .{} },
        },
        .time_scene => |*time_scene| switch (gameEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => {
                time_scene.deinit(alloc);
                self.current_scene = .{ .menu_scene = .{} };
            },
            .new_random_game => {
                args.seed = @bitCast(std.time.microTimestamp());
                args.words.reseed(args.seed);

                try time_scene.reinit(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    time_scene.test_duration_ns,
                );
            },
            .restart_current_game => {
                args.words.reseed(args.seed);

                try time_scene.reinit(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    time_scene.test_duration_ns,
                );
            },
            .undo_key_press => time_scene.processUndo(),
            .key_press => |codepoint| {
                try time_scene.processKeyPress(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    codepoint,
                );
            },
        },

        .word_scene => |*word_scene| switch (gameEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => {
                word_scene.deinit(alloc);
                self.current_scene = .{ .menu_scene = .{} };
            },
            .new_random_game => {
                args.seed = @bitCast(std.time.microTimestamp());
                args.words.reseed(args.seed);

                try word_scene.reinit(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    word_scene.words_remaining,
                );
            },
            .restart_current_game => {
                args.words.reseed(args.seed);

                try word_scene.reinit(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    word_scene.words_remaining,
                );
            },
            .undo_key_press => word_scene.processUndo(),
            .key_press => |codepoint| {
                try word_scene.processKeyPress(
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
        .word_scene => |*word_scene| word_scene.deinit(alloc),
    }
}
