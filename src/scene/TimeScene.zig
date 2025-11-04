const std = @import("std");
const super = @import("../scene.zig");
const layout = @import("window_layout.zig");
const util = @import("util.zig");
const stat = @import("statistics.zig");

const CharacterBuffer = @import("../CharacterBuffer.zig");
const Words = @import("../words.zig").Words;
const TestResultsScene = @import("TestResultsScene.zig");

const TimeScene = @This();

/// Set to non-null when the first key is pressed
test_start: ?std.time.Instant = null,

/// The time from when the test starts to the end of the test in nanoseconds
test_duration_ns: u64 = 0,

/// How many wrong keys the user has pressed
mistake_counter: u32 = 0,
/// How many right keys the user has pressed
correct_counter: u32 = 0,

peak_wpm: f32 = 0.0,

/// A scrollable character buffer.
character_buffer: CharacterBuffer,

/// Contructs a new game
pub fn init(
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    test_duration_ns: u64,
) error{ OutOfMemory, EmptyLineNotAllowed }!TimeScene {
    return TimeScene{
        .test_duration_ns = test_duration_ns,
        .character_buffer = try CharacterBuffer.init(
            alloc,
            words,
            codepoint_limit,
        ),
    };
}

/// Initializes the game with some new lines reusing the allocated memory
pub fn reinit(
    self: *TimeScene,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    test_duration_ns: u64,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    try self.character_buffer.reinit(alloc, words, codepoint_limit);
    self.mistake_counter = 0;
    self.correct_counter = 0;
    self.test_duration_ns = test_duration_ns;
    self.test_start = null;
}

/// Clears screen and renders the current state.
pub fn render(
    self: *TimeScene,
    data: super.RenderData,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    const game_window = try layout.gameWindow(
        data.root_window,
        data.words.max_codepoints,
    );

    self.character_buffer.render(layout.charBufWindow(game_window));

    const fps = util.framesPerSecond(data.frame_timings_ns);
    const wpm = util.wordsPerMinute(
        self.correct_counter,
        self.mistake_counter,
        self.test_start,
    );
    const time_left = @as(f32, @floatFromInt(
        self.timeLeftNanoSeconds() / 1_000_000_000,
    ));
    const num_statistics = 3;
    try stat.renderStatistics(
        num_statistics,
        &.{
            .{ .value = time_left, .label = "time: " },
            .{ .value = fps, .label = "fps: " },
            .{ .value = wpm, .label = "wpm: " },
        },
        data,
    );

    self.peak_wpm = @max(self.peak_wpm, wpm);
}

pub fn deinit(
    self: *TimeScene,
    alloc: std.mem.Allocator,
) void {
    self.character_buffer.deinit(alloc);
}

/// The `InGameAction.undo` action handler
pub fn processUndo(self: *TimeScene) void {
    _ = self.character_buffer.processUndo();
}

/// The `InGameAction.undo` action handler
pub fn processUndoWord(self: *TimeScene) void {
    _ = self.character_buffer.processUndoWord();
}

/// The `InGameAction.key_press` action handler.
///
/// The `Words` param is for in case we need to generate another sentence.
///
/// The `codepoint_limit` is the number of characters we want to render
/// at most in a line *including* spaces.
pub fn processKeyPress(
    self: *TimeScene,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    typed_codepoint: u21,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    const outcome = try self.character_buffer.processKeyPress(
        alloc,
        words,
        codepoint_limit,
        typed_codepoint,
    );

    if (self.test_start == null) self.test_start = util.now();

    switch (outcome.valid) {
        .right => self.correct_counter += 1,
        .wrong => self.mistake_counter += 1,
    }
}

pub fn isComplete(self: *const TimeScene) ?TestResultsScene {
    const test_start = self.test_start orelse return null;

    // Return if we are still in the test window
    if (util.now().since(test_start) <= self.test_duration_ns) return null;

    return TestResultsScene{
        .peak_wpm = self.peak_wpm,
        .test_duration_seconds = @as(f32, @floatFromInt(self.test_duration_ns)) / 1e9,
        .average_wpm = util.wordsPerMinute(
            self.correct_counter,
            self.mistake_counter,
            test_start,
        ),
    };
}

pub fn timeLeftNanoSeconds(self: *const TimeScene) u64 {
    const test_start = self.test_start orelse return self.test_duration_ns;
    return self.test_duration_ns -| util.now().since(test_start);
}
