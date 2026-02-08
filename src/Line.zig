const std = @import("std");
const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;

/// Guaranteed to have a non zero number of words (which are themselves non-empty)
const Line = @This();

/// Each word is assumed to be utf8. Each word is assumed be non-empty.
words: std.ArrayList(u8),

/// The total number of characters in the line including spaces
total_codepoints: u16,

/// Internal iterator over the current word
iter: std.unicode.Utf8Iterator,

/// Checks that we have some words in the words list. This guarantees that
/// the line contains some chars
///
/// param `word_array_list`: A non-empty array list of words.
/// param `total_codepoints`: the sum of the codepoints in the words array list (not including spaces)
pub fn init(
    word_array_list: std.ArrayList(u8),
    total_codepoints_with_spaces: u16,
) error{EmptyLineNotAllowed}!Line {
    if (word_array_list.items.len == 0) {
        return error.EmptyLineNotAllowed;
    }

    std.debug.assert(std.unicode.utf8ValidateSlice(word_array_list.items));
    std.debug.assert(total_codepoints_with_spaces == std.unicode.utf8CountCodepoints(word_array_list.items) catch unreachable);

    var view = std.unicode.Utf8View.initUnchecked(word_array_list.items);

    return Line{
        .words = word_array_list,
        .total_codepoints = total_codepoints_with_spaces,
        .iter = view.iterator(),
    };
}

pub fn deinit(
    self: *Line,
    alloc: std.mem.Allocator,
) void {
    self.words.deinit(alloc);
}

/// Returns the next codepoint. Returns `null` iff at the end of the buffer
///
/// If our line contains these words: `['hi','bro']` then our nextCodepoint would return
///
/// `'h', 'i', ' ', 'b', 'r', 'o', ' ', null`
///
/// Note: Does not error when _first_ called as the line cannot be empty when created
/// with `Line.init` method.
pub fn next(self: *Line) ?[]const u8 {
    return self.iter.nextCodepointSlice();
}

/// Peeks at the next codepoint. Returns `null` iff at the end of the line.
pub fn peekNext(self: *const Line) ?[]const u8 {
    var iter_copy = self.iter;
    return iter_copy.nextCodepointSlice();
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// does not move cursor_col or cursor_row
pub fn prev(self: *Line) ?[]const u8 {
    return prevCodepoint(&self.iter);
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// Does not modify the internal position of the iterator.
pub fn peekPrev(self: *const Line) ?[]const u8 {
    var iter_copy = self.iter;
    return prevCodepoint(&iter_copy);
}

// The bytes right of the first byte have their first two bits set to 0b10. So we check for this.
// Once this is no longer the case then we have reached the previous code point.
// see https://en.wikipedia.org/wiki/UTF-8#Description
fn prevCodepoint(it: *std.unicode.Utf8Iterator) ?[]const u8 {
    if (it.i == 0) return null;

    const end = it.i;
    it.i -= 1;

    while (it.i > 0 and it.bytes[it.i] & 0xC0 == 0x80) {
        it.i -= 1;
    }

    return it.bytes[it.i..end];
}

test "unicode shenanigans" {
    const cp_1 = "_";
    const cp_2 = "â";
    const cp_3 = "雨";
    const cp_4 = "🫡";

    const cp_1234: *const [1 + 2 + 3 + 4:0]u8 = cp_1 ++ cp_2 ++ cp_3 ++ cp_4;

    var line = Line.init(cp_1234);

    var nxt: ?[]const u8 = null;
    {
        nxt = line.nextCodepoint();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = line.nextCodepoint();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = line.nextCodepoint();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = line.nextCodepoint();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = line.nextCodepoint();
        try std.testing.expect(nxt == null);
    }
    {
        nxt = prev(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = prev(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = prev(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = prev(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = prev(&line);
        try std.testing.expect(nxt == null);
    }
}
