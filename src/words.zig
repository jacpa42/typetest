const std = @import("std");

pub const MAX_WORD_SIZE = 64;

/// default seed for WordRng
const DEFAULT_SEED = 0;

pub const WordsParseError =
    error{ OutOfMemory, InvalidUtf8 } ||
    std.fs.File.OpenError || std.Io.Reader.LimitedAllocError;

/// A slice of utf8 and the number of codepoints. Memory for the buf pre-allocated elsewhere.
pub const Word = struct {
    /// The characters of the word. Memory is allocated elsewhere.
    buf: []const u8,
    /// The number of utf8 codepoints in the grapheme
    num_codepoints: u16,
};

/// A bunch of `Word` structs in an array with a nifty way to generate random words.
pub const Words = struct {
    /// Raw bytes of the user input words
    word_buf: []const u8,

    /// Pieces of buf which are:
    /// 1. Length in range 1..MAX_WORD_SIZE
    /// 2. utf8
    /// 3. Contain no newline characters.
    ///
    /// If the user provides unprintable characters for the terminal then the words might contain said characters.
    words: []const Word,

    /// rng type used to generate new words
    rng: WordRng,

    /// The maximum number of codepoints in a word
    max_codepoints: u16,

    pub fn reseed(self: *@This(), seed: u64) void {
        switch (self.rng) {
            .sequential => |*idx| idx.* = seed,
            .random => |*rng| rng.seed(seed),
        }
    }

    /// Gets the current seed from the rng
    pub fn getSeed(self: *@This(), seed: u64) void {
        switch (self.rng) {
            .sequential => |*idx| idx.* = seed,
            .random => |*rng| rng.seed(seed),
        }
    }

    /// Uses the internal rng to get a new word
    pub fn randomWord(self: *@This()) Word {
        return self.words[self.rng.generate(self.words.len)];
    }

    /// Clears the array list and fills it with words until the codepoint_limit would be exceeded by adding more words (and spaces).
    ///
    /// The allocator is in case we need to resize the array.
    ///
    /// returns: the number of codepoints which this line has ___including spaces___
    pub fn fillRandomLine(
        self: *@This(),
        alloc: std.mem.Allocator,
        array_list: *std.ArrayList(u8),
        codepoint_limit: u16,
    ) error{ OutOfMemory, EmptyLineNotAllowed }!u16 {
        array_list.clearRetainingCapacity();

        var next_word = self.randomWord();
        var total_codepoints: u16 = 0;

        while (total_codepoints + next_word.num_codepoints < codepoint_limit) {
            try array_list.appendSlice(alloc, next_word.buf);
            try array_list.append(alloc, ' ');

            total_codepoints += next_word.num_codepoints + 1; // plus 1 for space
            next_word = self.randomWord();
        }

        if (array_list.items.len == 0) return error.EmptyLineNotAllowed;

        return total_codepoints;
    }

    pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
        alloc.free(self.word_buf);
        alloc.free(self.words);
        self.* = undefined;
    }

    /// Parses the word_buf into some new words.
    ///
    /// Stores the word_buf for deinit
    pub fn init(
        alloc: std.mem.Allocator,
        rng: WordRng,
        make_lower_case: bool,
        word_buf: []const u8,
    ) error{ OutOfMemory, InvalidUtf8, EmptyFile }!@This() {
        var largest_word: u16 = 0;
        var words = try std.ArrayList(Word).initCapacity(alloc, 0);
        errdefer words.deinit(alloc);

        var word_iterator = std.mem.splitAny(u8, word_buf, " \n\r\t");
        word_iter: while (word_iterator.next()) |word_bytes| {
            const view = try std.unicode.Utf8View.init(word_bytes);

            var utf8_iter = view.iterator();
            var num_codepoints: u16 = 0;
            while (utf8_iter.nextCodepointSlice()) |slice| : (num_codepoints += 1) {
                if (num_codepoints > MAX_WORD_SIZE) continue :word_iter;

                if (make_lower_case and slice.len == 1) {
                    // This is a bit sus :)
                    @constCast(&slice[0]).* = std.ascii.toLower(slice[0]);
                }
            }
            if (num_codepoints == 0) continue :word_iter;

            largest_word = @max(largest_word, num_codepoints);
            try words.append(alloc, .{
                .buf = word_bytes,
                .num_codepoints = num_codepoints,
            });
        }

        if (words.items.len == 0) return error.EmptyFile;

        return @This(){
            .words = try words.toOwnedSlice(alloc),
            .rng = rng,
            .word_buf = word_buf,
            .max_codepoints = largest_word,
        };
    }

    test "Words parsing: empty input" {
        const alloc = std.testing.allocator;
        const input: [][:0]const u8 = &.{
            "",
            "\n",
            "\n" * 2,
            "\n" * 100,
            "\n" * 2552,
        };

        for (input) |empty_lines| {
            var empty_words = try init(alloc, false, empty_lines, 1000000);
            std.debug.assert(empty_words.words.len == 0);
            for (0..1000) |_| {
                std.debug.assert(empty_words.randomWord().len == 0);
            }
        }
    }

    test "Words parsing: happy path" {
        const alloc = std.testing.allocator;
        const input: [][:0]const u8 = &.{
            "",
            "\n",
            "\n" * 2,
            "\n" * 100,
            "\n" * 2552,
        };

        for (input) |empty_lines| {
            var empty_words = try init(alloc, false, empty_lines, 1000000);
            defer empty_words.deinit(alloc);
            std.debug.assert(empty_words.words.len == 0);
            for (0..1000) |_| {
                std.debug.assert(empty_words.randomWord().len == 0);
            }
        }
    }
};

pub const RngMode = enum { sequential, random };

/// A union struct which allows generating a `random` word from the wordbuf.
pub const WordRng = union(RngMode) {
    /// NOTE: the value is the current index of the word
    sequential: usize,
    random: std.Random.DefaultPrng,

    /// Generates an index in the range provided
    fn generate(self: *WordRng, max: usize) usize {
        switch (self.*) {
            .sequential => |*idx| {
                var new_idx = idx.* +% 1;
                defer idx.* = new_idx;
                if (new_idx >= max) new_idx = 0;
                return new_idx;
            },
            .random => |*rng| return rng.*.random().intRangeLessThan(usize, 0, max),
        }
    }
};
