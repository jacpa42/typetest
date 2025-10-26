const std = @import("std");
const Words = @import("Words.zig");

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

// the slice in the iterator is owned so we deinit it when we are done
pub fn deinit(self: *const @This(), alloc: std.mem.Allocator) void {
    alloc.free(self.iter.bytes);
}

/// Returns the next codepoint. Returns `null` iff at the end of the buffer
pub fn next(self: *@This()) ?[]const u8 {
    return self.iter.nextCodepointSlice();
}

/// Returns the previous codepoint. Returns `null` iff at the start of the buffer
pub fn prev(self: *@This()) ?[]const u8 {
    return previousCodepointSlice(&self.iter);
}

fn previousCodepointSlice(iterator: *std.unicode.Utf8Iterator) ?[]const u8 {
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
        nxt = previousCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_4));

        nxt = previousCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_3));

        nxt = previousCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_2));

        nxt = previousCodepointSlice(&utf8iter);
        try std.testing.expect(std.mem.eql(u8, nxt.?, cp_1));

        nxt = previousCodepointSlice(&utf8iter);
        try std.testing.expect(nxt == null);
    }
}
