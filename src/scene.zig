const std = @import("std");
const vaxis = @import("vaxis");
const Words = @import("words.zig").Words;
const FrameTimings = @import("State.zig").FrameTimings;

pub const MenuScene = @import("scene/MenuScene.zig");
pub const TimeScene = @import("scene/TimeScene.zig");
pub const WordScene = @import("scene/WordScene.zig");
pub const TestResultsScene = @import("scene/TestResultsScene.zig");
pub const CustomGameScene = @import("scene/CustomGameScene.zig");

pub const Scene = union(enum) {
    menu_scene: MenuScene,
    time_scene: TimeScene,
    word_scene: WordScene,
    test_results_scene: TestResultsScene,
    custom_game_scene: CustomGameScene,

    pub fn render(
        self: *Scene,
        data: RenderData,
    ) error{ EmptyLineNotAllowed, OutOfMemory }!void {
        switch (self.*) {
            inline else => |*sc| try sc.render(data),
        }
    }
};

/// Stuff we need to pass in to the `render` method from global state to render the game
pub const RenderData = struct {
    alloc: std.mem.Allocator,
    frame_counter: u64,
    /// In frames
    animation_duration: u64,
    root_window: vaxis.Window,
    cursor_shape: vaxis.Cell.CursorShape,
    words: *Words,
    /// Several recording of the frame time
    frame_timings_ns: *const FrameTimings,
    /// I have issues when using stack buffers for my render functions,
    /// so I pass to to each function which needs to render stuff and
    /// they must just alloc the memory they need in here.
    ///
    /// Get cleared the end of each frame
    frame_print_buffer: *std.ArrayList(u8),
};

pub const KeyPressOutcome = struct {
    true_codepoint: u21,
    true_codepoint_slice: []const u8,
    valid: enum { right, wrong },
};

pub const InGameAction = union(enum) {
    /// Returns to main menu
    exit_game,
    /// Restarts the current game
    restart_game,
    /// Creates a new random game
    new_random_game,

    /// Undoes the latest key press (if any)
    undo_key_press,

    /// Does a key press with the provided code
    key_press: u21,
};

pub const MenuAction = union(enum) {
    /// Exit the program
    quit,
    /// Start a time based game
    start_time_game,
};
