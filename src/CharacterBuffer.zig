const std = @import("std");
const vaxis = @import("vaxis");
const Line = @import("Line.zig");
const character_style = @import("character_style.zig");
const Words = @import("words.zig").Words;
const now = @import("time.zig").now;

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
pub const MAX_CURRENT_LINE = (NUM_RENDER_LINES / 2) + (NUM_RENDER_LINES % 2);

const RenderChar = struct {
    /// The codepoint slice which was supposed to have been typed
    true_codepoint_slice: []const u8,
    /// A character style indicating the result of the keypress to the user
    style: character_style,
};

// todo: I want to scroll only when I reach MAX_CURRENT_LINE. I will need to
// rework the way in which the game is processed and rendered :(
//
/// A buffer which holds the sentences. Note that each line is allocated using the `alloc` field.
lines: [NUM_RENDER_LINES]Line,

/// An array of all the characters which have been pressed thus far
render_chars: [MAX_CURRENT_LINE]std.ArrayList(RenderChar) = @splat(.empty),

/// The current line the user is writing to
current_line: usize = 0,

/// The `InGameAction.undo` action handler.
///
/// Essentially want to pop the latest character if we can.
pub fn processUndo(self: *@This()) void {
    _ = self;
}

/// Does 2 things kinda:
/// 1. Rotate the lines uffer
/// 2. Rotate the render_chars buffer
///
/// I dont move the current line as we want to remain in the middle of the paragraph when going down a line
///
/// The arguments are various parameters used to generate a newline.
fn scrollDownLine(
    self: *@This(),
    alloc: std.mem.Allocator,
    words: *Words,
    codepoint_limit: usize,
) void {
    // 1. Rotate the lines buffer
    {
        // Generate a new line into the first arraylist
        var reused_words_arraylist = self.lines[0].words;
        try words.fillRandomLine(
            alloc,
            &reused_words_arraylist,
            codepoint_limit,
        );

        // Move the arraylist to the back of the buffer
        @memmove(self.lines[0 .. NUM_RENDER_LINES - 1], self.lines[1..NUM_RENDER_LINES]);
        self.lines[NUM_RENDER_LINES - 1] = Line.initUnchecked(reused_words_arraylist);
    }

    // 2. Rotate the render_chars buffer
    {
        var reused_words_arraylist = self.render_chars[0];
        reused_words_arraylist.clearRetainingCapacity();

        @memmove(self.render_chars[0 .. MAX_CURRENT_LINE - 1], self.render_chars[1..MAX_CURRENT_LINE]);
        self.render_chars[MAX_CURRENT_LINE - 1] = reused_words_arraylist;
        // Note: I dont really care that this arraylist wont get used right away. its not that big a deal.
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
    _ = self;
    _ = alloc;
    _ = words;
    _ = codepoint_limit;
    _ = codepoint;
}
