const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const cli_args = @import("args.zig");
const scene = @import("scene.zig");
const action = @import("action.zig");

const now = @import("scene/util.zig").now;
const parseArgs = cli_args.parseArgs;
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const Words = @import("words.zig").Words;

pub const NUM_FRAME_TIMINGS = 16;
pub const FrameTimings = RingBuffer(u64, NUM_FRAME_TIMINGS);

/// What frame of the game are we on
frame_counter: u64 = 0,
/// The time taken to render a frame in ns
frame_timings: FrameTimings = .fill(0),

/// Arena alloctator used to store/render each scene
scene_arena: std.heap.ArenaAllocator,
/// Current scene of the game
current_scene: scene.Scene = .{ .menu_scene = .{} },
/// Struct used to generate tests
words: Words,
/// Game seed
seed: u64,
fps: u64,
animation_duration: u64,
cursor_shape: vaxis.Cell.CursorShape,

/// I have issues when using stack buffers for my render functions,
/// so I pass to to each function which needs to render stuff and
/// they must just alloc the memory they need in here.
///
/// Gets cleared the end of each frame.
frame_print_buffer: std.ArrayList(u8),

pub fn init(
    alloc: std.mem.Allocator,
    args: cli_args.Args,
) !@This() {
    return @This(){
        .scene_arena = std.heap.ArenaAllocator.init(alloc),
        .frame_print_buffer = try .initCapacity(alloc, 1024),
        .words = args.words,
        .seed = args.seed,
        .fps = args.fps,
        .animation_duration = args.animation_duration,
        .cursor_shape = args.cursor_shape,
    };
}

pub inline fn render(
    self: *@This(),
    window: vaxis.Window,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    return self.current_scene.render(.{
        .alloc = self.scene_arena.allocator(),
        .words = &self.words,
        .frame_counter = self.frame_counter,
        .frame_timings_ns = &self.frame_timings,
        .root_window = window,
        .frame_print_buffer = &self.frame_print_buffer,
        .animation_duration = self.animation_duration,
        .cursor_shape = self.cursor_shape,
    });
}

/// Runs each frame
///
/// Updates the internal data and then sleeps for the correct time to ensure that
/// we try to match the fps
pub fn tickFrame(
    self: *@This(),
    frame_start: std.time.Instant,
) void {
    const requested_frame_duration_ns = std.time.ns_per_s / self.fps;
    const this_frame_time = now().since(frame_start);

    self.frame_counter += 1;
    self.frame_timings.append(this_frame_time);
    self.frame_print_buffer.clearRetainingCapacity();

    defer std.Thread.sleep(requested_frame_duration_ns -| this_frame_time);
}

pub fn reinit(
    self: *@This(),
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    switch (self.current_scene) {
        .time_scene => |*time_scene| {
            _ = self.scene_arena.reset(.retain_capacity);
            self.words.reseed(self.seed);

            time_scene.* = try .init(
                self.scene_arena.allocator(),
                &self.words,
                codepoint_limit,
                time_scene.test_duration_ns,
            );
        },
        .word_scene => |*word_scene| {
            _ = self.scene_arena.reset(.retain_capacity);
            self.words.reseed(self.seed);

            word_scene.* = try .init(
                self.scene_arena.allocator(),
                &self.words,
                codepoint_limit,
                word_scene.initial_words,
            );
        },
        .menu_scene => {},
        .test_results_scene => {},
        .custom_game_selection_scene => {},
    }
}

pub fn processKeyPress(
    self: *@This(),
    key: vaxis.Key,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!enum { continue_game, graceful_exit } {
    const menuEventHandler = action.MenuSceneAction.processKeydown;
    const gameEventHandler = action.GameSceneAction.processKeydown;
    const resultsEventHandler = action.ResultsSceneAction.processKeydown;
    const customGameEventHandler = action.CustomGameSelectionAction.processKeydown;

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
                        .time => supermenu.selection = .{ .time_game_menu = .default },
                        .word => supermenu.selection = .{ .word_game_menu = .default },
                    }
                },
                .time_game_menu => |inner_menu| {
                    const test_duration_ns: u64 = switch (inner_menu) {
                        .time015 => 15 * 1e9,
                        .time030 => 30 * 1e9,
                        .time060 => 60 * 1e9,
                        .time120 => 120 * 1e9,
                        ._custom => {
                            _ = self.scene_arena.reset(.retain_capacity);
                            self.current_scene = .{ .custom_game_selection_scene = .init(
                                "Game duration: ",
                                .{ .time = 0 },
                            ) };
                            return .continue_game;
                        },
                    };

                    _ = self.scene_arena.reset(.retain_capacity);
                    self.current_scene = .{
                        .time_scene = try .init(
                            self.scene_arena.allocator(),
                            &self.words,
                            codepoint_limit,
                            test_duration_ns,
                        ),
                    };
                },
                .word_game_menu => |inner_menu| {
                    const total_words: u32 = switch (inner_menu) {
                        .words010 => 10,
                        .words025 => 25,
                        .words050 => 50,
                        .words100 => 100,
                        .__custom => {
                            _ = self.scene_arena.reset(.retain_capacity);
                            self.current_scene = .{ .custom_game_selection_scene = .init(
                                "Number of words: ",
                                .{ .word = 0 },
                            ) };
                            return .continue_game;
                        },
                    };

                    _ = self.scene_arena.reset(.retain_capacity);
                    self.current_scene = .{
                        .word_scene = try .init(
                            self.scene_arena.allocator(),
                            &self.words,
                            codepoint_limit,
                            total_words,
                        ),
                    };
                },
            },
        },
        .custom_game_selection_scene => |*custom_game| switch (customGameEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .goback => {
                _ = self.scene_arena.reset(.retain_capacity);
                switch (custom_game.custom_game_type) {
                    .time => self.current_scene = .{
                        .menu_scene = .{ .selection = .{ .word_game_menu = .default } },
                    },
                    .word => self.current_scene = .{
                        .menu_scene = .{ .selection = .{ .time_game_menu = .default } },
                    },
                }
            },
            .select => {
                _ = self.scene_arena.reset(.retain_capacity);
                switch (custom_game.custom_game_type) {
                    .time => |time_seconds| self.current_scene = .{
                        .time_scene = try .init(
                            self.scene_arena.allocator(),
                            &self.words,
                            codepoint_limit,
                            @as(u64, @intCast(time_seconds)) *| 1_000_000_000,
                        ),
                    },
                    .word => |num_words| self.current_scene = .{
                        .word_scene = try .init(
                            self.scene_arena.allocator(),
                            &self.words,
                            codepoint_limit,
                            num_words,
                        ),
                    },
                }
            },
            .undo_key_press => custom_game.processUndo(),
            .undo_word => custom_game.processUndoWord(),
            .key_press => |cp| custom_game.processKeyPress(cp),
        },
        .test_results_scene => switch (resultsEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => {
                _ = self.scene_arena.reset(.retain_capacity);
                self.current_scene = .{ .menu_scene = .{} };
            },
        },
        .time_scene => |*time_scene| switch (gameEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => {
                _ = self.scene_arena.reset(.retain_capacity);
                self.current_scene = .{ .menu_scene = .{} };
            },
            .new_random_game => {
                self.seed = @bitCast(std.time.microTimestamp());
                self.words.reseed(self.seed);

                _ = self.scene_arena.reset(.retain_capacity);
                time_scene.* = try .init(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    time_scene.test_duration_ns,
                );
            },
            .restart_current_game => {
                self.words.reseed(self.seed);
                _ = self.scene_arena.reset(.retain_capacity);

                time_scene.* = try .init(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    time_scene.test_duration_ns,
                );
            },
            .undo_key_press => time_scene.processUndo(),
            .undo_word => time_scene.processUndoWord(),
            .key_press => |codepoint| {
                try time_scene.processKeyPress(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    codepoint,
                );
            },
        },
        .word_scene => |*word_scene| switch (gameEventHandler(key)) {
            .none => return .continue_game,
            .quit => return .graceful_exit,
            .return_to_menu => {
                _ = self.scene_arena.reset(.retain_capacity);
                self.current_scene = .{ .menu_scene = .{} };
            },
            .new_random_game => {
                self.seed = @bitCast(std.time.microTimestamp());
                self.words.reseed(self.seed);

                _ = self.scene_arena.reset(.retain_capacity);
                word_scene.* = try .init(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    word_scene.initial_words,
                );
            },
            .restart_current_game => {
                self.words.reseed(self.seed);
                _ = self.scene_arena.reset(.retain_capacity);

                word_scene.* = try .init(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    word_scene.initial_words,
                );
            },
            .undo_key_press => word_scene.processUndo(),
            .undo_word => word_scene.processUndoWord(),
            .key_press => |codepoint| {
                try word_scene.processKeyPress(
                    self.scene_arena.allocator(),
                    &self.words,
                    codepoint_limit,
                    codepoint,
                );
            },
        },
    }

    return .continue_game;
}

pub fn deinit(self: *@This()) void {
    self.words.deinit(self.scene_arena.child_allocator);
    self.frame_print_buffer.deinit(self.scene_arena.child_allocator);
    self.scene_arena.deinit();
}
