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
initial_words: u32 = 0,
/// The time from when the test starts to the end of the test in nanoseconds
words_remaining: u32 = 0,

/// How many wrong keys the user has pressed
mistake_counter: u32 = 0,
/// How many right keys the user has pressed
correct_counter: u32 = 0,

peak_wpm: f32 = 0,

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
        .initial_words = num_words,
        .words_remaining = num_words,
        .character_buffer = try CharacterBuffer.init(
            alloc,
            words,
            codepoint_limit,
        ),
    };
}

/// Clears screen and renders the current state.
pub fn render(
    self: *WordsScene,
    data: super.RenderData,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    const game_window = try layout.gameWindow(
        data.root_window,
        data.words.max_codepoints,
    );

    const charbuf_window = layout.charBufWindow(game_window);

    self.character_buffer.render(
        charbuf_window,
        data.cursor_shape,
    );

    const wpm = util.wordsPerMinute(self.correct_counter, self.test_start);
    self.peak_wpm = @max(self.peak_wpm, wpm);

    if (game_window.height - charbuf_window.height > 2 and
        game_window.width > 10)
    {
        const statistics = [_]stat.Statistic{
            // .{
            //     .label = "fps: ",
            //     .value = util.framesPerSecond(data.frame_timings_ns),
            // },
            .{
                .label = "words left: ",
                .value = @as(f32, @floatFromInt(self.words_remaining)),
            },
            .{
                .label = "wpm: ",
                .value = wpm,
            },
        };

        try stat.renderStatistics(game_window, &statistics, data);
    }
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

    const test_duration_ns = if (self.test_start) |start| util.now().since(start) else 0;

    return TestResultsScene{
        .peak_wpm = self.peak_wpm,
        .test_duration_seconds = @as(f32, @floatFromInt(test_duration_ns)) / 1e9,
        .average_accuracy = util.accuracy(self.correct_counter, self.mistake_counter),
        .average_wpm = util.wordsPerMinute(self.correct_counter, self.test_start),
    };
}
