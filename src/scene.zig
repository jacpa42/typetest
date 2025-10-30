const std = @import("std");
const vaxis = @import("vaxis");
const Line = @import("Line.zig");
const stat = @import("scene/statistics.zig");

const now = @import("time.zig").now;
const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;
const TimeGameStatistic = stat.TimeGameStatistic;

/// This is the number of sentences which we try to render while the user is typing.
pub const NUM_RENDER_LINES = 5;

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

const CharacterStyle = enum(u2) {
    untyped,
    cursor,
    wrong,
    right,

    pub inline fn style(self: @This()) vaxis.Style {
        return switch (self) {
            .untyped => .{ .dim = true },
            .right => .{
                .fg = .{ .index = 10 },
                .italic = true,
            },
            .wrong => .{
                .fg = .{ .index = 9 },
                .bold = true,
            },
            .cursor => .{
                .italic = true,
                .fg = .{ .index = 0 },
                .bg = .{ .index = 15 },
            },
        };
    }
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
        var win = data.win;
        win.clear();

        const layout = @import("scene/window_layout.zig");
        const game_window = layout.gameWindow(win);

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
        var win = data.win;
        win.clear();

        const layout = @import("scene/window_layout.zig");
        const main_window = layout.gameWindow(win);
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
    win: vaxis.Window,
    words: *Words,
    current_frame_time_ns: u64,
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
    test_duration_ns: u64,

    /// How many wrong keys the user has pressed
    mistake_counter: u32 = 0,
    /// How many right keys the user has pressed
    correct_counter: u32 = 0,

    /// A buffer which holds the sentences. Note that each line is allocated using the `alloc` field.
    lines: [NUM_RENDER_LINES]Line,

    /// A cache of all the characters which have been pressed thus far
    render_characters: std.ArrayList(
        struct {
            /// The codepoint slice which was supposed to have been typed
            true_codepoint_slice: []const u8,
            /// A character style indicating the result of the keypress to the user
            style: CharacterStyle,
        },
    ) = .empty,

    pub fn init(
        alloc: std.mem.Allocator,
        words: *Words,
        codepoint_limit: usize,
        test_duration_ns: u64,
    ) error{OutOfMemory}!@This() {
        var lines: [NUM_RENDER_LINES]Line = undefined;

        inline for (0..NUM_RENDER_LINES) |idx| {
            var alist = std.ArrayList(Word).empty;

            try words.fillRandomLine(
                alloc,
                &alist,
                codepoint_limit,
            );

            lines[idx] = Line.initUnchecked(alist);
        }

        return TimeScene{
            .test_duration_ns = test_duration_ns,
            .lines = lines,
        };
    }

    /// Clears screen and renders the current state.
    pub fn render(
        self: *const @This(),
        data: RenderData,
    ) void {
        var win = data.win;
        win.clear();

        const layout = @import("scene/window_layout.zig");
        const game_window = layout.gameWindow(win);
        const text_window = layout.textWindow(game_window);

        self.renderTextWindow(text_window);

        var splits: [TimeGameStatistic.COUNT]vaxis.Window = undefined;
        layout.runningStatisticsWindows(game_window, &splits);

        for (0.., splits) |idx, draw_window| {
            const statistic: TimeGameStatistic = @enumFromInt(idx);
            self.renderStatWindow(data, draw_window, statistic);
        }
    }

    /// Clears screen and renders the current state.
    pub fn renderTextWindow(
        self: *const @This(),
        win: vaxis.Window,
    ) void {
        var vertical_offset = (win.height -| NUM_RENDER_LINES) / 2;

        // Render the stuff the user has typed thus far
        {
            var line = self.lines[0];
            var col: u16 = @truncate((win.width -| line.num_codepoints) / 2);

            for (self.render_characters.items) |typed_char| {
                const cell = vaxis.Cell{
                    .char = .{
                        .grapheme = typed_char.true_codepoint_slice,
                        .width = 1,
                    },
                    .style = typed_char.style.style(),
                };
                win.writeCell(col, vertical_offset, cell);
                col += 1;
            }

            // render the next char with the cursor style
            if (line.nextCodepoint()) |cursor_char| {
                const cell = vaxis.Cell{
                    .char = .{
                        .grapheme = cursor_char,
                        .width = 1,
                    },
                    .style = CharacterStyle.cursor.style(),
                };
                win.writeCell(col, vertical_offset, cell);
                col += 1;
            }

            // render the rest of the line
            while (line.nextCodepoint()) |codepoint| {
                const cell = vaxis.Cell{
                    .char = .{
                        .grapheme = codepoint,
                        .width = 1,
                    },
                    .style = CharacterStyle.untyped.style(),
                };
                win.writeCell(col, vertical_offset, cell);
                col += 1;
            }
        }

        // Render inactive lines
        {
            vertical_offset += 1;
            for (self.lines[1..]) |line| {
                if (line.words.items.len == 0) continue;

                var col_offset: u16 = @truncate((win.width -| line.num_codepoints) / 2);

                for (line.words.items[0 .. line.words.items.len - 1]) |word| {
                    const segments: [2]vaxis.Segment = .{
                        vaxis.Segment{
                            .text = word.buf,
                            .style = CharacterStyle.untyped.style(),
                        },
                        vaxis.Segment{ .text = " " },
                    };

                    const print_opts = vaxis.PrintOptions{
                        .col_offset = col_offset,
                        .row_offset = vertical_offset,
                        .wrap = .none,
                    };

                    _ = win.print(&segments, print_opts);

                    col_offset += @truncate(word.num_codepoints + 1);
                }

                // print the final inactive word
                _ = win.printSegment(
                    vaxis.Segment{
                        .text = line.words.items[line.words.items.len - 1].buf,
                        .style = CharacterStyle.untyped.style(),
                    },
                    .{
                        .col_offset = col_offset,
                        .row_offset = vertical_offset,
                        .wrap = .none,
                    },
                );

                vertical_offset += 1;
            }
        }
    }

    /// Clears screen and renders the current state.
    pub fn renderStatWindow(
        self: *const @This(),
        data: RenderData,
        text_box: vaxis.Window,
        statistic: TimeGameStatistic,
    ) void {
        var buf: [128]u8 = undefined;
        var segment: vaxis.Segment = .{ .text = "" };

        defer {
            const len = std.unicode.utf8CountCodepoints(segment.text) catch unreachable;
            const col_offset = (text_box.width -| @as(u16, @truncate(len))) / 2;

            _ = text_box.printSegment(segment, .{
                .col_offset = col_offset,
                .wrap = .none,
            });
        }

        switch (statistic) {
            .fps => {
                const frames_per_second = 1e9 / @as(f32, @floatFromInt(data.current_frame_time_ns));
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "fps: {d}",
                    .{frames_per_second},
                ) catch unreachable;
            },
            .wpm => {
                var words_per_minute: f32 = 0.0;
                if (self.test_start) |start| {
                    words_per_minute = wordsPerMinute(
                        self.correct_counter,
                        self.mistake_counter,
                        start,
                    );
                }
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "wpm: {d:4.2}",
                    .{words_per_minute},
                ) catch unreachable;
            },
            .mistake_counter => {
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "mistakes: {}",
                    .{self.mistake_counter},
                ) catch unreachable;
            },
            .time_left => {
                var time_left_seconds = @as(f32, @floatFromInt(self.test_duration_ns)) / 1e9;
                if (self.test_start) |start| {
                    const elapsed = @as(f32, @floatFromInt(now().since(start))) / 1e9;
                    time_left_seconds = @max(0.0, time_left_seconds - elapsed);
                }
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "time left: {:.1}",
                    .{time_left_seconds},
                ) catch unreachable;
            },
        }
    }

    /// Resets the current game with the words
    pub fn newGame(
        self: *@This(),
        alloc: std.mem.Allocator,
        test_duration_ns: u64,
        codepoint_limit: usize,
        words: *Words,
    ) error{OutOfMemory}!void {
        self.render_characters.clearRetainingCapacity();

        inline for (&self.lines) |*line| {
            var alist = line.words;
            alist.clearRetainingCapacity();

            try words.fillRandomLine(
                alloc,
                &alist,
                codepoint_limit,
            );
            line.* = .initUnchecked(alist);
        }

        // reset all variables expect keep the new lines
        self.* = .{
            .test_duration_ns = test_duration_ns,
            .lines = self.lines,
            .render_characters = self.render_characters,
        };
    }

    pub fn deinit(
        self: *@This(),
        alloc: std.mem.Allocator,
    ) void {
        self.render_characters.deinit(alloc);
        inline for (&self.lines) |*line| {
            line.words.deinit(alloc);
        }
    }

    /// The `InGameAction.undo` action handler
    pub fn processUndo(self: *@This()) void {
        if (self.lines[0].prevCodepoint() != null) {
            _ = self.render_characters.pop();
        }
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
        codepoint_limit: usize,
        codepoint: u21,
    ) error{OutOfMemory}!void {
        var true_codepoint_slice: []const u8 = undefined;
        var true_codepoint: u21 = undefined;

        if (self.test_start == null) {
            self.test_start = now();
        }

        if (self.lines[0].nextCodepoint()) |next_codepoint_slice| {
            true_codepoint_slice = next_codepoint_slice;
        } else {
            // Save this arraylist for later
            var reused_words_arraylist = self.lines[0].words;

            // Overwrite the first part of the buffer with the new lines
            {
                @memmove(
                    self.lines[0 .. NUM_RENDER_LINES - 1],
                    self.lines[1..NUM_RENDER_LINES],
                );
            }

            // Generate the new line and put it at the back of the `lines` buffer
            {
                try words.fillRandomLine(
                    alloc,
                    &reused_words_arraylist,
                    codepoint_limit,
                );
                self.lines[NUM_RENDER_LINES - 1] = Line.initUnchecked(reused_words_arraylist);
            }

            // Finally clear the typed words as we are on the newline :)
            {
                self.render_characters.clearRetainingCapacity();
            }

            true_codepoint_slice = self.lines[0].nextCodepoint() orelse unreachable;
        }

        true_codepoint = std.unicode.utf8Decode(true_codepoint_slice) catch unreachable;

        var style: CharacterStyle = undefined;
        if (true_codepoint == codepoint) {
            style = CharacterStyle.right;
            self.correct_counter += 1;
        } else {
            style = CharacterStyle.wrong;
            self.mistake_counter += 1;
        }

        try self.render_characters.append(alloc, .{
            .style = style,
            .true_codepoint_slice = true_codepoint_slice,
        });
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
