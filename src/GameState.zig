const std = @import("std");
const Words = @import("Words.zig");

cursor_col: u16 = 0,
cursor_row: u16 = 0,

mistake_counter: u32 = 0,

/// The words in our buffer. known to be utf8
iter: std.unicode.Utf8Iterator,

/// Randomly generates a new game from a seed
pub fn fromWords(
    alloc: std.mem.Allocator,
    words: *const Words,
    seed: u64,
    num_words: usize,
) error{OutOfMemory}!@This() {
    const word_count = words.wordCount();

    // We want a line of words which is the length of the test length
    var rng = std.Random.DefaultPrng.init(seed);
    var current_word_buf = std.ArrayList(u8).empty;
    errdefer current_word_buf.deinit(alloc);

    for (0..num_words) |_| {
        const idx =
            rng.random().intRangeLessThan(usize, 0, word_count);
        const next_word = words.getWordUnchecked(idx);

        try current_word_buf.ensureUnusedCapacity(alloc, next_word.len + 1);
        current_word_buf.appendSliceAssumeCapacity(next_word);
        current_word_buf.appendAssumeCapacity(' ');
    }

    const word_buf = try current_word_buf.toOwnedSlice(alloc);

    std.debug.assert(std.unicode.utf8ValidateSlice(word_buf));
    const view = std.unicode.Utf8View.initUnchecked(word_buf);

    return @This(){ .iter = view.iterator() };
}

/// Whether or not we have completed the game
pub fn gameComplete(self: *const @This()) bool {
    return self.iter.i == self.iter.bytes.len;
}

// the slice in the iterator is owned so we deinit it when we are done
pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.iter.bytes);
}

/// Moves the cursor forward 1 position in a square grid
pub fn nextCursorPosition(
    self: *@This(),
    windim: struct { x: u16, y: u16 },
) void {
    self.cursor_col +|= 1;

    if (self.cursor_col >= windim.x) {
        self.cursor_col = 0;
        self.cursor_row +|= 1;
        if (self.cursor_row >= windim.y) {
            self.cursor_col = windim.x -| 1;
            self.cursor_row = windim.y -| 1;
        }
    }
}

/// Moves the cursor back 1 position in a square grid
pub fn prevCursorPosition(
    self: *@This(),
    windim: struct { x: u16, y: u16 },
) void {
    if (self.cursor_col == 0) {
        if (self.cursor_row > 0) {
            self.cursor_row -= 1;
            self.cursor_col = windim.x - 1;
        }
    } else self.cursor_col -= 1;
}

/// Peeks at the next codepoint. Returns `null` iff at the end of the buffer
///
/// does not modify the internal position of the iterator
pub fn peekNextCodepoint(self: *@This()) ?[]const u8 {
    const next = self.iter.peek(1);
    return if (next.len > 0) next else null;
}

/// Returns the previous codepoint. Returns `null` iff at the start of the buffer
///
/// does not move cursor_col or cursor_row
pub fn peekPrevCodepoint(self: *@This()) ?[]const u8 {
    return peekPrevCodepointSlice(&self.iter);
}

/// Returns the next codepoint. Returns `null` iff at the end of the buffer
///
/// does not move cursor_col or cursor_row
pub fn nextCodepoint(self: *@This()) ?[]const u8 {
    return self.iter.nextCodepointSlice();
}

/// Returns the previous codepoint. Returns `null` iff at the start of the buffer
///
/// does not move cursor_col or cursor_row
pub fn prevCodepoint(self: *@This()) ?[]const u8 {
    return prevCodepointSlice(&self.iter);
}

fn prevCodepointSlice(iterator: *std.unicode.Utf8Iterator) ?[]const u8 {
    if (iterator.i == 0) return null;

    const end = iterator.i;

    while (true) {
        iterator.i -= 1;

        // The bytes right of the first byte have their first two bits set to 0b10. So we check for this.
        // Once this is no longer the case then we have reached the previous code point.
        // see https://en.wikipedia.org/wiki/UTF-8#Description

        if (iterator.i == 0 or (iterator.bytes[iterator.i] & 0xC0) != 0x80) {
            break;
        }
    }

    return iterator.bytes[iterator.i..end];
}

fn peekPrevCodepointSlice(iterator: *std.unicode.Utf8Iterator) ?[]const u8 {
    if (iterator.i == 0) return null;

    const end = iterator.i;
    defer iterator.i = end;

    while (true) {
        iterator.i -= 1;

        // The bytes right of the first byte have their first two bits set to 0b10. So we check for this.
        // Once this is no longer the case then we have reached the previous code point.
        // see https://en.wikipedia.org/wiki/UTF-8#Description

        if (iterator.i == 0 or (iterator.bytes[iterator.i] & 0xC0) != 0x80) {
            break;
        }
    }

    return iterator.bytes[iterator.i..end];
}

test "unicode shenanigans" {
    const cp_1 = "_";
    const cp_2 = "â";
    const cp_3 = "雨";
    const cp_4 = "🫡";

    const cp_1234: *const [1 + 2 + 3 + 4:0]u8 = cp_1 ++ cp_2 ++ cp_3 ++ cp_4;

    var utf8iter = std.unicode.Utf8View.initComptime(cp_1234).iterator();

    var nxt: ?[]const u8 = null;
    {
        nxt = utf8iter.nextCodepointSlice();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = utf8iter.nextCodepointSlice();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = utf8iter.nextCodepointSlice();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = utf8iter.nextCodepointSlice();
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = utf8iter.nextCodepointSlice();
        try std.testing.expect(nxt == null);
    }
    {
        nxt = prevCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = prevCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = prevCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = prevCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = prevCodepointSlice(&utf8iter);
        try std.testing.expect(nxt == null);
    }
}
