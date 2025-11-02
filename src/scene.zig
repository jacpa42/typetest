const std = @import("std");
const vaxis = @import("vaxis");
const Line = @import("Line.zig");
const stat = @import("scene/statistics.zig");
const State = @import("State.zig");
const character_style = @import("character_style.zig");
const CharacterBuffer = @import("CharacterBuffer.zig");
const RingBuffer = @import("ring_buffer.zig").RingBuffer;
const now = @import("time.zig").now;
const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;

pub const KeyPressOutcome = enum { right, wrong };

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

pub const Scene = union(enum) {
    menu_scene: MenuScene,
    time_scene: TimeScene,
    test_results_scene: TestResultsScene,
};

/// All the information on how well we did during the test
pub const TestResultsScene = struct {
    average_wpm: f32,

    /// Clears screen and renders the current state.
    pub fn render(
        self: *const @This(),
        data: RenderData,
    ) void {
        const layout = @import("scene/window_layout.zig");
        const game_window = layout.gameWindow(data.root_window);

        // as we add more stats here we need to change how they are rendered

        const middle_box_width = game_window.width / 2;
        const middle_box_height = game_window.height / 2;
        const middle_box = game_window.child(.{
            .width = middle_box_width,
            .height = middle_box_height,
            .x_off = (game_window.width - middle_box_width) / 2,
            .y_off = (game_window.height - middle_box_height) / 2,
            .border = .{ .where = .all },
        });

        var buf: [256]u8 = undefined;

        const print_buf = std.fmt.bufPrint(
            &buf,
            "average wpm: {d:4.2}",
            .{self.average_wpm},
        ) catch std.process.exit(1);

        // const col_offset = (middle_box_width -| @as(u16, @truncate(print_buf.len))) / 2;
        const col_offset = 0;
        _ = middle_box.printSegment(
            .{ .text = print_buf },
            .{ .col_offset = col_offset },
        );
    }
};

pub const MenuItem = enum {
    exit,
    time15,
    time30,
    time60,
    time120,

    pub const COUNT: comptime_int = @typeInfo(@This()).@"enum".fields.len;

    inline fn displayName(self: @This()) []const u8 {
        return switch (self) {
            .exit => "quit",
            .time15 => "  15s",
            .time30 => "  30s",
            .time60 => "  60s",
            .time120 => " 120s",
        };
    }
};

pub const MenuScene = struct {
    selection: MenuItem = @enumFromInt(0),

    /// Clears screen and renders the current state
    pub fn render(self: *const @This(), data: RenderData) void {
        const layout = @import("scene/window_layout.zig");
        const main_window = layout.gameWindow(data.root_window);
        const list_items = layout.menuListItems(main_window);

        const SegmentWithOffset = struct { seg: vaxis.Segment, num_codepoints: u16 };
        var menu_item_segment_offsets: [MenuItem.COUNT]SegmentWithOffset = comptime blk: {
            var segments: [MenuItem.COUNT]SegmentWithOffset = undefined;
            for (0.., &segments) |idx, *seg| {
                const menu_item: MenuItem = @enumFromInt(idx);
                const text = menu_item.displayName();
                seg.seg = .{
                    .text = text,
                    .style = .{},
                };

                seg.num_codepoints = 0;
                var iter = std.unicode.Utf8View.initComptime(text).iterator();
                while (iter.nextCodepointSlice() != null) seg.num_codepoints += 1;
            }
            break :blk segments;
        };

        menu_item_segment_offsets[@intFromEnum(self.selection)].seg.style = .{
            .bg = .{ .index = 1 },
        };

        for (menu_item_segment_offsets, 0..) |segment_offset, row| {
            std.debug.assert(list_items.width >= segment_offset.num_codepoints);

            const opts = vaxis.Window.PrintOptions{
                .row_offset = @truncate(row),
                .col_offset = (list_items.width -| segment_offset.num_codepoints) / 2,
                .wrap = .none,
            };

            _ = list_items.printSegment(segment_offset.seg, opts);
        }
    }

    pub fn moveSelectionDown(self: *@This()) void {
        const next: u32 = (@intFromEnum(self.selection) + 1) % MenuItem.COUNT;
        self.selection = @enumFromInt(next);
    }

    pub fn moveSelectionUp(self: *@This()) void {
        if (@intFromEnum(self.selection) == 0) {
            self.selection = @enumFromInt(MenuItem.COUNT - 1);
        } else {
            const next: u32 = (@intFromEnum(self.selection) - 1) % MenuItem.COUNT;
            self.selection = @enumFromInt(next);
        }
    }
};

/// Stuff we need to pass in to the `render` method from global state to render the game
pub const RenderData = struct {
    frame_number: u64,
    root_window: vaxis.Window,
    words: *Words,
    /// several recording of the frame time
    frame_timings_ns: *const State.FrameTimings,
};

/// This is just a bunch of unicode codepoints seperated by spaces.
/// All the data required to track a `time` game scene
///
/// The way this test works is that we write a `sentence` into the sentence buf
/// each time the user runs out of words in the current sentence. As we are pulling
/// from words on the fly we need:
/// - A namespace which performs rng to get the next word.
/// - A pointer to `Words` which outlives the test
pub const TimeScene = struct {
    /// Set to non-null when the first key is pressed
    test_start: ?std.time.Instant = null,

    /// The time from when the test starts to the end of the test in nanoseconds
    test_duration_ns: u64 = 0,

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
        test_duration_ns: u64,
    ) error{ OutOfMemory, NoWords }!@This() {
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
        self: *@This(),
        alloc: std.mem.Allocator,
        words: *Words,
        codepoint_limit: u16,
        test_duration_ns: u64,
    ) error{OutOfMemory}!void {
        try self.character_buffer.reinit(alloc, words, codepoint_limit);
        self.mistake_counter = 0;
        self.correct_counter = 0;
        self.test_duration_ns = test_duration_ns;
        self.test_start = null;
    }

    /// Clears screen and renders the current state.
    pub fn render(
        self: *const @This(),
        data: RenderData,
    ) void {
        const layout = @import("scene/window_layout.zig");
        const game_window = layout.gameWindow(data.root_window);

        self.character_buffer.render(layout.charBufWindow(game_window));

        var splits: [2]vaxis.Window = undefined;
        layout.runningStatisticsWindows(game_window, &splits);

        {
            var wpm: f32 = 0.0;
            if (self.test_start) |test_start| {
                wpm = wordsPerMinute(self.correct_counter, self.mistake_counter, test_start);
            }

            stat.renderStatistic("wpm: ", @as(u16, @intFromFloat(wpm)), splits[0]);
        }
        {
            const fps: f32 = framesPerSecond(data.frame_timings_ns);
            stat.renderStatistic("fps: ", @as(u16, @intFromFloat(fps)), splits[1]);
        }
    }

    pub fn deinit(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) void {
        self.character_buffer.deinit(alloc);
    }

    /// The `InGameAction.undo` action handler
    pub fn processUndo(self: *@This()) void {
        self.character_buffer.processUndo();
    }

    /// The `InGameAction.key_press` action handler.
    ///
    /// The `Words` param is for in case we need to generate another sentence.
    ///
    /// The `codepoint_limit` is the number of characters we want to render
    /// at most in a line *including* spaces.
    pub fn processKeyPress(
        self: *@This(),
        alloc: std.mem.Allocator,
        words: *Words,
        codepoint_limit: u16,
        typed_codepoint: u21,
    ) error{ OutOfMemory, NoWords }!void {
        const outcome = try self.character_buffer.processKeyPress(
            alloc,
            words,
            codepoint_limit,
            typed_codepoint,
        );

        if (self.test_start == null) self.test_start = now();

        switch (outcome) {
            .right => self.correct_counter += 1,
            .wrong => self.mistake_counter += 1,
        }
    }

    pub fn isComplete(self: *const @This()) ?TestResultsScene {
        const test_start = self.test_start orelse return null;

        // Return if we are still in the test window
        if (now().since(test_start) <= self.test_duration_ns) return null;

        return TestResultsScene{
            .average_wpm = wordsPerMinute(
                self.correct_counter,
                self.mistake_counter,
                test_start,
            ),
        };
    }
};

pub fn wordsPerMinute(
    correct: u32,
    mistakes: u32,
    test_start: std.time.Instant,
) f32 {
    return charactersPerSecond(correct, mistakes, test_start) * 60.0 / 5.0;
}

/// The number of characters per second the user is typeing
pub fn charactersPerSecond(
    correct: u32,
    mistakes: u32,
    test_start: std.time.Instant,
) f32 {
    const elapsed = @as(f32, @floatFromInt(now().since(test_start))) / 1e9;

    const total_chars = @as(f32, @floatFromInt(correct + mistakes));
    const accuracy = @as(f32, @floatFromInt(correct)) / @max(total_chars, 1.0);

    return (total_chars * accuracy) / @max(elapsed, 1.0);
}

/// The number of characters per second the user is typeing
pub fn framesPerSecond(frame_timings: *const State.FrameTimings) f32 {
    var average: f32 = 0.0;
    const count: f32 = comptime State.NUM_FRAME_TIMINGS;

    if (State.NUM_FRAME_TIMINGS == 0) @compileError("retard");

    inline for (frame_timings.items) |frame_time| {
        average += 1e9 / @as(f32, @floatFromInt(frame_time));
    }

    return average / count;
}
