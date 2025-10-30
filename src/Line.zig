const std = @import("std");

const Words = @import("words.zig").Words;
const Word = @import("words.zig").Word;

/// Each word is assumed to be utf8. Each word is assumed be non-empty.
///
/// Note: See `Words.generateSentence`.
words: std.ArrayList(Word) = .empty,

/// The total number of characters in the line
num_codepoints: usize,

/// The current word index in words
current_word: usize = 0,

/// Internal iterator over the current word
iter: std.unicode.Utf8Iterator = .{ .bytes = "", .i = 0 },

pub fn initUnchecked(word_array_list: std.ArrayList(Word)) @This() {
    if (word_array_list.items.len > 0) {
        var num_codepoints = word_array_list.items.len - 1;

        for (word_array_list.items) |word| {
            std.debug.assert(std.unicode.utf8ValidateSlice(word.buf));
            num_codepoints += word.num_codepoints;
        }

        var view = std.unicode.Utf8View.initUnchecked(word_array_list.items[0].buf);
        return @This(){
            .words = word_array_list,
            .num_codepoints = num_codepoints,
            .current_word = 0,
            .iter = view.iterator(),
        };
    } else {
        return @This(){
            .words = .empty,
            .num_codepoints = 0,
            .current_word = 0,
            .iter = .{ .bytes = "", .i = 0 },
        };
    }
}

pub inline fn getCurrentWord(self: *const @This()) Word {
    return self.words.items[self.current_word];
}

/// Returns the text that remains to be consumed.
///
/// The first argument is the remaing characters in the current word.
/// The second are whole words remaining.
pub inline fn remainingWords(
    self: *const @This(),
) struct { []const u8, [][]const u8 } {
    return .{
        self.iter.bytes[self.iter.i..],
        self.words[self.current_word + 1 ..],
    };
}

/// Returns the next codepoint. Returns `null` iff at the end of the buffer
///
/// does not move cursor_col or cursor_row
pub fn nextCodepoint(self: *@This()) ?[]const u8 {
    if (self.iter.nextCodepointSlice()) |next| return next;

    self.current_word += 1;
    if (self.current_word >= self.words.items.len) return null;

    self.iter = std.unicode.Utf8View.initUnchecked(self.words.items[self.current_word].buf).iterator();

    return " ";
}

/// Peeks at the next codepoint. Returns `null` iff at the end of the line.
///
/// Does not modify the internal position of the iterator.
pub fn peekNextCodepoint(self: *@This()) ?[]const u8 {
    const next = self.iter.peek(1);
    if (next.len > 0) return next;

    const prev_current_word = self.current_word;
    defer self.current_word = prev_current_word;

    self.current_word += 1;

    return if (self.current_word >= self.words.items.len) null else " ";
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// does not move cursor_col or cursor_row
pub fn prevCodepoint(self: *@This()) ?[]const u8 {
    if (self.iter.i == 0) {
        if (self.current_word == 0) return null;

        self.current_word -= 1;

        // Put the iterator at the  end of the previous word
        self.iter = std.unicode.Utf8View.initUnchecked(self.words.items[self.current_word].buf).iterator();
        self.iter.i = self.iter.bytes.len;

        return " ";
    }

    return Util.prevCodepoint(&self.iter);
}

/// Returns the previous codepoint. Returns `null` iff at the start of the line.
///
/// Does not modify the internal position of the iterator.
pub fn peekPrevCodepoint(self: *@This()) ?[]const u8 {
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
    fn peekPrevCodepoint(it: *std.unicode.Utf8Iterator) ?[]const u8 {
        if (it.i == 0) return null;

        const end = it.i;
        defer it.i = end;
        it.i -= 1;

        while (it.i > 0 and it.bytes[it.i] & 0xC0 == 0x80) {
            it.i -= 1;
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

    var line = @This().initUnchecked(cp_1234);

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
