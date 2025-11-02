const std = @import("std");
const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;

/// Guaranteed to have a non zero number of words (which are themselves non-empty)
const Line = @This();

/// Each word is assumed to be utf8. Each word is assumed be non-empty.
///
/// Note: See `Words.generateSentence`.
words: std.ArrayList(Word),

/// The total number of characters in the line including spaces
total_codepoints: u16,

/// The current word index in words
current_word: usize = 0,

/// Internal iterator over the current word
iter: std.unicode.Utf8Iterator,

/// Checks that we have some words in the words list. This guarantees that
/// the line contains some chars
///
/// param `word_array_list`: A non-empty array list of words.
/// param `total_codepoints`: the sum of the codepoints in the words array list (not including spaces)
pub fn init(
    word_array_list: std.ArrayList(Word),
    total_codepoints_with_spaces: u16,
) error{NoWords}!Line {
    if (total_codepoints_with_spaces <= word_array_list.items.len or
        word_array_list.items.len == 0)
    {
        return error.NoWords;
    }

    std.debug.assert(word_array_list.items[0].buf.len > 0);
    std.debug.assert(std.unicode.utf8ValidateSlice(word_array_list.items[0].buf));

    var view = std.unicode.Utf8View.initUnchecked(word_array_list.items[0].buf);

    return Line{
        .words = word_array_list,
        .total_codepoints = total_codepoints_with_spaces,
        .current_word = 0,
        .iter = view.iterator(),
    };
}

pub fn deinit(
    self: *Line,
    alloc: std.mem.Allocator,
) void {
    self.words.deinit(alloc);
}

/// Returns the text that remains to be consumed.
///
/// The first argument is the remaing characters in the current word.
/// The second are whole words remaining.
pub inline fn remainingWords(
    self: *const Line,
) struct { []const u8, [][]const u8 } {
    return .{
        self.iter.bytes[self.iter.i..],
        self.words[self.current_word + 1 ..],
    };
}

/// Returns the next codepoint. Returns `null` iff at the end of the buffer
///
/// If our line contains these words: `['hi','bro']` then our nextCodepoint would return
///
/// `'h', 'i', ' ', 'b', 'r', 'o', ' ', null`
///
/// Note: Does not error when _first_ called as the line cannot be empty when created
/// with `Line.init` method.
pub fn nextCodepoint(self: *Line) ?[]const u8 {
    if (self.iter.nextCodepointSlice()) |next| return next;

    // If we have already called this function past the last word, then return null
    if (self.current_word >= self.words.items.len) return null;

    self.current_word += 1;

    // If we just reached the last word then return a space
    if (self.current_word == self.words.items.len) return " ";

    self.iter = std.unicode.Utf8View.initUnchecked(
        self.words.items[self.current_word].buf,
    ).iterator();

    return " ";
}

/// Peeks at the next codepoint. Returns `null` iff at the end of the line.
pub fn peekNextCodepoint(self: *const Line) ?[]const u8 {
    var iter_copy = self.iter;
    if (iter_copy.nextCodepointSlice()) |next| return next;

    // If we have already gone past the last word, then return null, otherwise space
    return if (self.current_word >= self.words.items.len) null else " ";
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// does not move cursor_col or cursor_row
pub fn prevCodepoint(self: *Line) ?[]const u8 {
    if (Util.prevCodepoint(&self.iter)) |cp| return cp;

    if (self.current_word == 0) return null;
    self.current_word -= 1;

    // Put the iterator at the  end of the previous word
    self.iter = std.unicode.Utf8View.initUnchecked(self.words.items[self.current_word].buf).iterator();
    self.iter.i = self.iter.bytes.len;

    return " ";
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// Does not modify the internal position of the iterator.
pub fn peekPrevCodepoint(self: *const Line) ?[]const u8 {
    if (self.iter.i == 0) {
        return if (self.current_word == 0) null else " ";
    }

    return Util.peekPrevCodepoint(&self.iter);
}

const Util = struct {
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

    // The bytes right of the first byte have their first two bits set to 0b10. So we check for this.
    // Once this is no longer the case then we have reached the previous code point.
    // see https://en.wikipedia.org/wiki/UTF-8#Description
    //
    // Does not mutate the iterator but does require a non const pointer to not copy values unnecessarily.
    fn peekPrevCodepoint(it: *const std.unicode.Utf8Iterator) ?[]const u8 {
        if (it.i == 0) return null;

        var end = it.i;
        end -= 1;

        while (end > 0 and it.bytes[end] & 0xC0 == 0x80) {
            end -= 1;
        }

        return it.bytes[it.i..end];
    }
};

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
        nxt = prevCodepoint(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = prevCodepoint(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = prevCodepoint(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = prevCodepoint(&line);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = prevCodepoint(&line);
        try std.testing.expect(nxt == null);
    }
}
