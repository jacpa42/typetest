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
        gpa: std.mem.Allocator,
        rng: WordRng,
        make_lower_case: bool,
        word_buf: []const u8,
    ) error{ OutOfMemory, InvalidUtf8, EmptyFile }!@This() {
        var largest_word: u16 = 0;
        var words = std.ArrayList(Word).empty;
        errdefer words.deinit(gpa);

        var utf8iter = blk: {
            const view = try std.unicode.Utf8View.init(word_buf);
            break :blk view.iterator();
        };
        var num_codepoints: u16 = 0;
        var next_word_start: usize = 0;
        const mask = @as(u8, @intFromBool(make_lower_case)) << 5;

        while (utf8iter.nextCodepointSlice()) |slice| {
            if (slice.len > 1) {
                num_codepoints += 1;
                continue;
            }

            std.debug.assert(slice.len == 1);

            const vt = std.ascii.control_code.vt;
            const ff = std.ascii.control_code.ff;
            switch (slice[0]) {
                ' ', '\t', '\n', '\r', vt, ff => {
                    const buf = word_buf[next_word_start .. utf8iter.i - 1];
                    if (0 < buf.len and num_codepoints < MAX_WORD_SIZE) {
                        largest_word = @max(largest_word, num_codepoints);
                        try words.append(gpa, .{
                            .buf = buf,
                            .num_codepoints = num_codepoints,
                        });
                    }

                    next_word_start = utf8iter.i;
                    num_codepoints = 0;
                },
                'A'...'Z' => {
                    // This is a bit sus :)
                    @constCast(&slice[0]).* = slice[0] | mask;
                    num_codepoints += 1;
                },
                else => num_codepoints += 1,
            }
        }

        if (words.items.len == 0) return error.EmptyFile;

        return @This(){
            .words = try words.toOwnedSlice(gpa),
            .rng = rng,
            .word_buf = word_buf,
            .max_codepoints = largest_word,
        };
    }

    test "Words parsing: empty input" {
        const alloc = std.testing.allocator;
        const input: [5][:0]const u8 = .{
            "",
            "\n",
            "\n" ** 2,
            "\n" ** 100,
            "\n" ** 2552,
        };

        for (0.., input) |input_idx, empty_lines| {
            const words = init(alloc, .{ .sequential = 0 }, false, empty_lines) catch |e| {
                try std.testing.expectEqual(error.EmptyFile, e);
                continue;
            };
            std.debug.print("\n----\n", .{});
            std.debug.print("Found {} words at input {}:\n", .{ words.words.len, input_idx });
            for (words.words) |w| {
                std.debug.print("---{any}---\n", .{w.buf});
            }
            @panic("Empty input was mishandled");
        }
    }

    /// see http://www.rikai.com/library/kanjitables/kanji_codes.unicode.shtml
    fn randomJapaneseCharacter(rng: *std.Random) u21 {
        const ranges = [_][2]u21{
            .{ 0x3000, 0x303f }, //    Japanese-style punctuation
            .{ 0x3040, 0x309f }, //    Hiragana
            .{ 0x30a0, 0x30ff }, //    Katakana
            .{ 0xff00, 0xffef }, //    Full-width roman characters and half-width katakana
            .{ 0x4e00, 0x9faf }, //    CJK unifed ideographs - Common and uncommon kanji
            .{ 0x3400, 0x4dbf }, //    CJK unified ideographs Extension A - Rare kanji
        };
        const idx = rng.intRangeLessThan(usize, 0, ranges.len);
        const range = ranges[idx];

        return rng.intRangeLessThan(u21, range[0], range[1]);
    }

    /// see https://character-table.netlify.app/english/
    fn randomEnglishCharacter(rng: *std.Random) u21 {
        const ranges = [_][2]u21{
            .{ 0x20, 0x5F },
            .{ 0x61, 0x7A },
            .{ 0x7C, 0x7C + 1 },
            .{ 0xA0, 0xA0 + 1 },
            .{ 0xA7, 0xA7 + 1 },
            .{ 0xA9, 0xA9 + 1 },
            .{ 0x2010, 0x2011 },
            .{ 0x2013, 0x2014 },
            .{ 0x2018, 0x2019 },
            .{ 0x201C, 0x201D },
            .{ 0x2020, 0x2021 },
            .{ 0x2026, 0x2026 + 1 },
            .{ 0x2030, 0x2030 + 1 },
            .{ 0x2032, 0x2033 },
            .{ 0x20AC, 0x20AC + 1 },
        };
        const idx = rng.intRangeLessThan(usize, 0, ranges.len);
        const range = ranges[idx];

        return rng.intRangeLessThan(u21, range[0], range[1]);
    }

    test "Words parsing: happy path" {
        const gpa = std.testing.allocator;
        const max_letters = 10_000;

        for (0..10) |seed| {
            var default_prng = std.Random.DefaultPrng.init(@intCast(seed));
            var rng = default_prng.random();

            var word_list = std.ArrayList(u8).empty;
            // NOTE: errdefer as this buffer is taken by the Words object
            errdefer word_list.deinit(gpa);
            for (0..rng.intRangeLessThan(usize, 1, max_letters)) |_| {
                if (rng.weightedIndex(u8, &.{ 2, 8 }) == 0) {
                    const idx = rng.intRangeLessThan(u8, 0, std.ascii.whitespace.len);
                    try word_list.append(gpa, std.ascii.whitespace[idx]);
                } else {
                    const next_char_list = [_]u21{ randomEnglishCharacter(&rng), randomJapaneseCharacter(&rng) };
                    const char = next_char_list[rng.intRangeLessThan(usize, 0, next_char_list.len)];

                    var buf: [4]u8 = @splat(0);
                    const len = try std.unicode.utf8Encode(char, &buf);

                    try word_list.appendSlice(gpa, buf[0..len]);
                }
            }

            var happy_words = try init(
                gpa,
                .{ .sequential = 0 },
                rng.boolean(),
                try word_list.toOwnedSlice(gpa),
            );
            defer happy_words.deinit(gpa);

            for (happy_words.words) |word| {
                try std.testing.expect(word.num_codepoints < MAX_WORD_SIZE);
            }
        }
    }

    test "Words parsing: lower casing stuff" {
        const gpa = std.testing.allocator;
        const max_letters = 10_000;

        for (0..10) |seed| {
            var default_prng = std.Random.DefaultPrng.init(@intCast(seed));
            var rng = default_prng.random();

            var word_list = std.ArrayList(u8).empty;
            // NOTE: errdefer as this buffer is taken by the Words object
            errdefer word_list.deinit(gpa);
            for (0..rng.intRangeLessThan(usize, 1, max_letters)) |_| {
                if (rng.weightedIndex(u8, &.{ 2, 8 }) == 0) {
                    const idx = rng.intRangeLessThan(u8, 0, std.ascii.whitespace.len);
                    try word_list.append(gpa, std.ascii.whitespace[idx]);
                } else {
                    const next_char_list = [_]u21{ randomEnglishCharacter(&rng), randomJapaneseCharacter(&rng) };
                    const char = next_char_list[rng.intRangeLessThan(usize, 0, next_char_list.len)];

                    var buf: [4]u8 = @splat(0);
                    const len = try std.unicode.utf8Encode(char, &buf);

                    try word_list.appendSlice(gpa, buf[0..len]);
                }
            }

            var happy_words = try init(
                gpa,
                .{ .sequential = 0 },
                true,
                try word_list.toOwnedSlice(gpa),
            );
            defer happy_words.deinit(gpa);

            for (happy_words.words) |word| {
                try std.testing.expect(word.num_codepoints < MAX_WORD_SIZE);
                const view = try std.unicode.Utf8View.init(word.buf);
                var iter = view.iterator();

                while (iter.nextCodepointSlice()) |cp| {
                    if (cp.len == 1) {
                        switch (cp[0]) {
                            'A'...'Z' => @panic("Found capital word!!"),
                            else => continue,
                        }
                    }
                }
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
