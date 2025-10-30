const std = @import("std");

const KIB = 1024;
const MAX_WORD_SIZE = KIB / 2;

pub const WordsParseError =
    error{ OutOfMemory, InvalidUtf8 } ||
    std.fs.File.OpenError || std.Io.Reader.LimitedAllocError;

/// A slice of utf8 and the number of codepoints. Memory for the buf pre-allocated elsewhere.
pub const Word = struct {
    /// The characters of the word. Memory is allocated elsewhere.
    buf: []const u8,
    /// The number of utf8 codepoints in the grapheme
    num_codepoints: usize,
};

/// A bunch of `Word` structs in an array with a nifty way to generate random words.
pub const Words = struct {
    /// Pieces of buf which are:
    /// 1. Length in range 1..MAX_WORD_SIZE
    /// 2. utf8
    /// 3. Contain no newline characters.
    ///
    /// If the user provides unprintable characters for the terminal then the words might contain said characters.
    words: []const Word,

    /// rng type used to generate new words
    rng: WordRng = .{ .sequential = 0 },

    pub fn reseed(self: *@This(), seed: u64) void {
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
    pub fn fillRandomLine(
        self: *@This(),
        alloc: std.mem.Allocator,
        array_list: *std.ArrayList(Word),
        codepoint_limit: usize,
    ) error{OutOfMemory}!void {
        array_list.clearRetainingCapacity();
        var remaining_codepoints = codepoint_limit;

        var next_word = self.randomWord();
        var num_spaces: usize = 0;
        while (remaining_codepoints >= next_word.num_codepoints + num_spaces) {
            num_spaces = array_list.items.len;

            try array_list.append(alloc, next_word);

            remaining_codepoints -= next_word.num_codepoints;
            next_word = self.randomWord();
        }
    }

    pub fn deinit(self: *@This(), gpa: std.mem.Allocator) void {
        gpa.free(self.words);
        self.* = undefined;
    }

    /// Parses the word_buf into some new words.
    pub fn init(
        gpa: std.mem.Allocator,
        word_buf: []const u8,
        max_words: usize,
    ) error{ OutOfMemory, InvalidUtf8 }!@This() {
        var words = try std.ArrayList(Word).initCapacity(gpa, max_words + 1);
        errdefer words.deinit(gpa);

        var utf8_iter = (try std.unicode.Utf8View.init(word_buf)).iterator();
        var grapheme_size: usize = 0;
        var byte_index: usize = 0;
        var word_start: usize = 0;
        while (utf8_iter.nextCodepointSlice()) |codepoint_slice| {
            // Check for newline character
            if (codepoint_slice[0] == '\n') {
                const word = Word{
                    .buf = word_buf[word_start..byte_index],
                    .num_codepoints = grapheme_size,
                };

                std.debug.assert(std.unicode.utf8CountCodepoints(word.buf) catch unreachable == word.num_codepoints);

                // Include words who are not too big or small

                if (0 < word.buf.len and word.buf.len < MAX_WORD_SIZE) {
                    try words.append(gpa, word);
                }

                byte_index += 1;
                word_start = byte_index;
                grapheme_size = 0;
            } else {
                byte_index += codepoint_slice.len;
                grapheme_size += 1;
            }
        }

        // Add the final word
        {
            const word = Word{
                .buf = word_buf[word_start..byte_index],
                .num_codepoints = grapheme_size,
            };

            std.debug.assert(std.unicode.utf8CountCodepoints(word.buf) catch unreachable == word.num_codepoints);

            // Include words who are not too big or small
            if (0 < word.buf.len and word.buf.len < MAX_WORD_SIZE) {
                try words.append(gpa, word);
            }
        }

        return @This(){ .words = try words.toOwnedSlice(gpa) };
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
            var empty_words = try init(alloc, empty_lines, 1000000);
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
            var empty_words = try init(alloc, empty_lines, 1000000);
            defer empty_words.deinit(alloc);
            std.debug.assert(empty_words.words.len == 0);
            for (0..1000) |_| {
                std.debug.assert(empty_words.randomWord().len == 0);
            }
        }
    }
};

/// A union struct which allows generating a `random` word from the wordbuf.
const WordRng = union(enum) {
    sequential: u64,
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
