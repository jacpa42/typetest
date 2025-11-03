const std = @import("std");
const super = @import("../scene.zig");
const layout = @import("window_layout.zig");
const util = @import("util.zig");
const stat = @import("statistics.zig");

const CharacterBuffer = @import("../CharacterBuffer.zig");
const Words = @import("../words.zig").Words;
const TestResultsScene = @import("TestResultsScene.zig");

const WordsScene = @This();

/// Set to non-null when the first key is pressed
test_start: ?std.time.Instant = null,

/// The time from when the test starts to the end of the test in nanoseconds
words_remaining: u32 = 0,

/// How many wrong keys the user has pressed
mistake_counter: u32 = 0,
/// How many right keys the user has pressed
correct_counter: u32 = 0,

/// A scrollable character buffer.
character_buffer: CharacterBuffer,

/// Contructs a new game
pub fn init(
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    num_words: u32,
) error{ OutOfMemory, EmptyLineNotAllowed }!WordsScene {
    return WordsScene{
        .words_remaining = num_words,
        .character_buffer = try CharacterBuffer.init(
            alloc,
            words,
            codepoint_limit,
        ),
    };
}

/// Initializes the game with some new lines reusing the allocated memory
pub fn reinit(
    self: *WordsScene,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    num_words: u32,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    try self.character_buffer.reinit(alloc, words, codepoint_limit);
    self.mistake_counter = 0;
    self.correct_counter = 0;
    self.words_remaining = num_words;
    self.test_start = null;
}

/// Clears screen and renders the current state.
pub fn render(
    self: *const WordsScene,
    data: super.RenderData,
) error{WindowTooSmall}!void {
    const game_window = try layout.gameWindow(data.root_window);

    self.character_buffer.render(layout.charBufWindow(game_window));

    const fps = util.framesPerSecond(data.frame_timings_ns);
    const wpm: f32 = util.wordsPerMinute(
        self.correct_counter,
        self.mistake_counter,
        self.test_start,
    );
    const words_left = @as(f32, @floatFromInt(self.words_remaining));

    stat.renderStatistics(
        &.{
            .{ .value = words_left, .label = "words left: " },
            .{ .value = fps, .label = "fps: " },
            .{ .value = wpm, .label = "wpm: " },
        },
        layout.runningStatisticsWindow(game_window),
    );
}

pub fn deinit(
    self: *WordsScene,
    alloc: std.mem.Allocator,
) void {
    self.character_buffer.deinit(alloc);
}

/// The `InGameAction.undo` action handler
pub fn processUndo(self: *WordsScene) void {
    const prev_codepoint_slice = self.character_buffer.processUndo() orelse return;

    if (prev_codepoint_slice[0] == ' ') {
        self.words_remaining += 1;
    }
}

/// The `InGameAction.undo` action handler
pub fn processUndoWord(self: *WordsScene) void {
    if (self.character_buffer.processUndoWord()) {
        self.words_remaining += 1;
    }
}

/// The `InGameAction.key_press` action handler.
///
/// The `Words` param is for in case we need to generate another sentence.
///
/// The `codepoint_limit` is the number of characters we want to render
/// at most in a line *including* spaces.
pub fn processKeyPress(
    self: *WordsScene,
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
    if (outcome.true_codepoint == ' ') self.words_remaining -|= 1;

    switch (outcome.valid) {
        .right => self.correct_counter += 1,
        .wrong => self.mistake_counter += 1,
    }
}

pub fn isComplete(self: *const WordsScene) ?TestResultsScene {
    if (self.words_remaining > 0) return null;

    return TestResultsScene{
        .average_wpm = util.wordsPerMinute(
            self.correct_counter,
            self.mistake_counter,
            self.test_start,
        ),
    };
}
