const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("scene.zig");
const Line = @import("Line.zig");
const character_style = @import("character_style.zig");

const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;
const now = @import("time.zig").now;
const KeyPressOutcome = scene.KeyPressOutcome;

/// I need a struct to handle this logic:
///
/// We want to keep the users cursor within the top half of the screen.
/// When they start typing their cursor is at the top of the screen, but
/// once they reach half way, we want to drop off the first line and
/// generate a new line.
pub const CharacterBuffer = @This();

/// This is the number of sentences which we try to render while the user is typing.
pub const NUM_RENDER_LINES = 5;
/// If the user types past this number of lines then we generate more lines
pub const MAX_LINE_NO = (NUM_RENDER_LINES / 2) + (NUM_RENDER_LINES % 2);

const RenderChar = struct {
    /// The codepoint slice which was supposed to have been typed
    true_codepoint_slice: []const u8,
    /// A character style indicating the result of the keypress to the user
    style: vaxis.Style,
};

// todo: I want to scroll only when I reach MAX_LINE_NO. I will need to
// rework the way in which the game is processed and rendered :(
//
/// A buffer which holds the sentences. Note that each line is allocated using the `alloc` field.
lines: [NUM_RENDER_LINES]Line,

/// An array of all the characters which have been pressed thus far
render_chars: [MAX_LINE_NO]std.ArrayList(RenderChar) = @splat(.empty),

/// The current line the user is writing to
current_line: std.math.IntFittingRange(0, MAX_LINE_NO + 1) = 0,

/// Creates a new game allocating new memory
pub fn init(
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!CharacterBuffer {
    var lines: [NUM_RENDER_LINES]Line = undefined;

    inline for (&lines) |*line| {
        var word_array_list = std.ArrayList(u8).empty;

        const total_codepoints_with_spaces = try words.fillRandomLine(
            alloc,
            &word_array_list,
            codepoint_limit,
        );

        line.* = try Line.init(word_array_list, total_codepoints_with_spaces);
    }

    return CharacterBuffer{ .lines = lines };
}

/// Initializes a new instance of `CharacterBuffer` without discarding the allocated memory in the various arraylists.
///
/// Must be called on defined member of `CharacterBuffer`.
pub fn reinit(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    inline for (&self.lines) |*line| {
        var reused_array_list = line.words;
        const total_codepoints_with_spaces = try words.fillRandomLine(
            alloc,
            &reused_array_list,
            codepoint_limit,
        );

        line.* = try .init(
            reused_array_list,
            total_codepoints_with_spaces,
        );
    }

    inline for (&self.render_chars) |*rchars| {
        rchars.clearRetainingCapacity();
    }

    self.current_line = 0;
}

pub fn deinit(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
) void {
    inline for (&self.lines) |*line| {
        line.deinit(alloc);
    }

    inline for (&self.render_chars) |*rchars| {
        rchars.deinit(alloc);
    }
}

/// Renders self onto the window.
pub fn render(
    self: *const CharacterBuffer,
    win: vaxis.Window,
) void {
    var row: u16 = 0;

    // Render the typed out characters
    for (self.render_chars[0..self.current_line]) |rchars| {
        var col =
            (win.width -| @as(u16, @truncate(rchars.items.len))) / 2;

        for (rchars.items) |rchar| {
            win.writeCell(col, row, .{
                .char = .{ .grapheme = rchar.true_codepoint_slice },
                .style = rchar.style,
            });
            col += 1;
        }

        row += 1;
    }

    var cursor_col: u16 = 0;
    // Render the partially typed out current line
    {
        var current_line_copy = self.lines[self.current_line];
        var col = (win.width -| current_line_copy.total_codepoints) / 2;

        for (self.getCurrentCharacterBufConst().items) |rchar| {
            win.writeCell(col, row, .{
                .char = .{ .grapheme = rchar.true_codepoint_slice },
                .style = rchar.style,
            });

            col += 1;
        }

        cursor_col = col;

        while (current_line_copy.next()) |codepoint| : (col += 1) {
            win.writeCell(col, row, .{
                .char = .{ .grapheme = codepoint },
                .style = character_style.untyped,
            });
        }

        row += 1;
    }

    // print the remaining untyped lines
    for (self.lines[self.current_line + 1 ..]) |*line| {
        var untyped_line_copy = line.*;
        var col =
            (win.width -| untyped_line_copy.total_codepoints) / 2;

        while (untyped_line_copy.next()) |codepoint| : (col += 1) {
            win.writeCell(col, row, .{
                .char = .{ .grapheme = codepoint },
                .style = character_style.untyped,
            });
        }

        row += 1;
    }

    // Render the cursor
    {
        var cursor_row = self.current_line;
        var cursor_codepoint: []const u8 = undefined;

        if (self.getCurrentLineConst().peekNext()) |codepoint| {
            cursor_codepoint = codepoint;
        }

        // we need to move to a newline and take the first character of the next line
        else {
            cursor_row = self.current_line + 1;

            std.debug.assert(cursor_row < self.lines.len);
            const next_row = &self.lines[cursor_row];

            cursor_col = (win.width -| next_row.total_codepoints) / 2;
            cursor_codepoint = next_row.peekNext() orelse unreachable;
        }

        win.writeCell(cursor_col, cursor_row, .{
            .char = .{ .grapheme = cursor_codepoint },
            .style = character_style.cursor,
        });
    }
}

/// The `InGameAction.key_press` action handler.
///
/// param `typed_codepoint`: The character which the user typed
/// param `[alloc,words,codepoint_limit]`: In case we need to generate another line
/// returns `enum { right, wrong }`: Whether the user typed the correct or incorrect key.
pub fn processKeyPress(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
    typed_codepoint: u21,
) error{ OutOfMemory, EmptyLineNotAllowed }!KeyPressOutcome {
    var true_codepoint_slice: []const u8 = try self.nextCodePointSlice(alloc, words, codepoint_limit);
    const true_codepoint: u21 = std.unicode.utf8Decode(true_codepoint_slice) catch unreachable;

    var style: vaxis.Style = undefined;
    var ret: KeyPressOutcome = .{
        .true_codepoint = true_codepoint,
        .true_codepoint_slice = true_codepoint_slice,
        .valid = undefined,
    };

    if (true_codepoint == typed_codepoint) {
        style = character_style.right;
        ret.valid = .right;
    } else {
        style = character_style.wrong;
        ret.valid = .wrong;

        // This fixes some jank in the rendering that i dont like
        if (true_codepoint == ' ') {
            style = comptime character_style.invert_fg_bg(character_style.wrong);
            true_codepoint_slice = "█";
        }
    }

    try self.getCurrentCharacterBuf().append(alloc, .{
        .style = style,
        .true_codepoint_slice = true_codepoint_slice,
    });

    return ret;
}

/// The `InGameAction.undo` action handler.
///
/// Essentially want to pop the latest character if we can.
pub fn processUndo(self: *CharacterBuffer) void {
    std.debug.assert(self.current_line < @min(self.lines.len, self.render_chars.len));

    // 1. If we have characters typed in the current line, we pop this
    if (self.getCurrentLine().prev() != null) {
        _ = self.getCurrentCharacterBuf().pop();
    }

    // 2. Else if we have lines above our current one, we move up a line
    else if (self.current_line > 0) {
        std.debug.assert(self.getCurrentCharacterBuf().items.len == 0);
        std.debug.assert(self.getCurrentLine().iter.i == 0);

        self.current_line -= 1;

        std.debug.assert(self.getCurrentCharacterBuf().items.len > 0);
        std.debug.assert(self.getCurrentLine().iter.i > 0);
    }

    // 3. Else we must be out of characters
    else {
        std.debug.assert(self.current_line == 0);
        std.debug.assert(self.getCurrentLine().prev() == null);
        std.debug.assert(self.getCurrentCharacterBuf().items.len == 0);
    }
}

/// Retrieves the next codepoint from self.
///
/// error occurs when we try to allocate a new line and potentially oom
fn nextCodePointSlice(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }![]const u8 {
    // If we have characters left to type on this line, then compare against that
    if (self.getCurrentLine().next()) |next_codepoint_slice| {
        return next_codepoint_slice;
    }

    // else if we haven't reached MAX_LINE_NO, then just increment the current line
    else if (self.current_line < MAX_LINE_NO - 1) {
        self.current_line += 1;
        // A new line is guaranteed to be non-empty, so catch unreachable is put in here
        return self.getCurrentLine().next() orelse unreachable;
    }

    // We must scroll down a line and leave self.current_line untouched
    else {
        try self.scrollDownLine(alloc, words, codepoint_limit);

        // A new line is guaranteed to be non-empty, so catch unreachable is put in here
        return self.getCurrentLine().next() orelse unreachable;
    }
}

inline fn getCurrentLine(self: *CharacterBuffer) *Line {
    std.debug.assert(self.current_line < self.lines.len);
    return &self.lines[self.current_line];
}

inline fn getCurrentLineConst(self: *const CharacterBuffer) *const Line {
    std.debug.assert(self.current_line < self.lines.len);
    return &self.lines[self.current_line];
}

inline fn getCurrentCharacterBuf(self: *CharacterBuffer) *std.ArrayList(RenderChar) {
    std.debug.assert(self.current_line < self.render_chars.len);
    return &self.render_chars[self.current_line];
}

inline fn getCurrentCharacterBufConst(
    self: *const CharacterBuffer,
) *const std.ArrayList(RenderChar) {
    std.debug.assert(self.current_line < self.render_chars.len);
    return &self.render_chars[self.current_line];
}

/// Does 2 things kinda:
/// 1. Rotate the lines uffer
/// 2. Rotate the render_chars buffer
///
/// I dont move the current line as we want to remain in the middle of the paragraph when going down a line
///
/// The arguments are various parameters used to generate a newline.
fn scrollDownLine(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    try self.rotateLinesBuf(alloc, words, codepoint_limit);
    self.rotateRenderCharBuf();
}

/// Puts the current `render_chars` array list at the back of the buffer and clears it.
fn rotateLinesBuf(
    self: *CharacterBuffer,
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: u16,
) error{ OutOfMemory, EmptyLineNotAllowed }!void {
    // Generate a new line into the first arraylist
    var reused_words_arraylist = self.lines[0].words;

    const total_codepoints_with_spaces = try words.fillRandomLine(
        alloc,
        &reused_words_arraylist,
        codepoint_limit,
    );

    // Move the arraylist to the back of the buffer
    @memmove(self.lines[0 .. NUM_RENDER_LINES - 1], self.lines[1..NUM_RENDER_LINES]);
    self.lines[NUM_RENDER_LINES - 1] = try Line.init(
        reused_words_arraylist,
        total_codepoints_with_spaces,
    );
}

/// Puts the current `render_chars` array list at the back of the buffer and clears it.
fn rotateRenderCharBuf(self: *CharacterBuffer) void {
    var reused_words_arraylist = self.render_chars[0];
    reused_words_arraylist.clearRetainingCapacity();

    @memmove(self.render_chars[0 .. MAX_LINE_NO - 1], self.render_chars[1..MAX_LINE_NO]);
    self.render_chars[MAX_LINE_NO - 1] = reused_words_arraylist;
}
