const std = @import("std");

pub const WordsParseError =
    error{ OutOfMemory, InvalidUtf8, EmptyFile } ||
    std.fs.File.OpenError ||
    std.Io.Reader.LimitedAllocError;

/// Allocated slice of mem. utf8
word_buf: []const u8,
/// Indices of newline characters in `word_buf`
newlines: []const usize,

/// Returns a buf of space seperated randomly selected words (`Xoshiro256`)
pub fn generateRandomWords(
    self: *const @This(),
    alloc: std.mem.Allocator,
    seed: u64,
    count: usize,
) error{OutOfMemory}![]const u8 {
    // We want a line of words which is the length of the test length
    var rng = std.Random.DefaultPrng.init(seed);
    var current_word_buf = std.ArrayList(u8).empty;
    defer current_word_buf.deinit(alloc);

    for (0..count) |_| {
        const idx =
            rng.random().intRangeLessThan(usize, 0, self.wordCount());
        const next_word = self.getWordUnchecked(idx);

        try current_word_buf.ensureUnusedCapacity(alloc, next_word.len + 1);
        current_word_buf.appendSliceAssumeCapacity(next_word);
        current_word_buf.appendAssumeCapacity(' ');
    }

    return try current_word_buf.toOwnedSlice(alloc);
}

/// Returns a (utf8) word from the wordbuf at the index
pub fn getWordUnchecked(self: *const @This(), idx: usize) []const u8 {
    std.debug.assert(idx + 1 < self.newlines.len);

    const start = self.newlines[idx] + 1;
    const end = self.newlines[idx + 1];

    if (start >= end) return "";

    return self.word_buf[start..end];
}

/// the total number of words
pub fn wordCount(self: *const @This()) usize {
    std.debug.assert(self.newlines.len > 0);
    return self.newlines.len - 1;
}

pub fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
    gpa.free(self.word_buf);
    gpa.free(self.newlines);
}

pub fn parseFromFile(
    gpa: std.mem.Allocator,
    file: std.fs.File,
    max_words: usize,
) WordsParseError!@This() {
    const KIB = 1024;
    var buf: [KIB]u8 = undefined;
    var file_reader = file.reader(&buf);

    const word_buf = try file_reader.interface.allocRemaining(
        gpa,
        .limited(KIB * KIB * KIB),
    );
    errdefer gpa.free(word_buf);

    var newlines_array_list = try std.ArrayList(usize).initCapacity(gpa, max_words);
    errdefer newlines_array_list.deinit(gpa);

    var utf8_iter = (try std.unicode.Utf8View.init(word_buf)).iterator();
    var idx: usize = 0;

    // Insert an artificial newline at the beginning to not skip first word
    newlines_array_list.appendAssumeCapacity(0);

    while (utf8_iter.nextCodepointSlice()) |cp_slice| {
        // Check for newline character
        if (cp_slice[0] == '\n') try newlines_array_list.append(gpa, idx);
        idx += cp_slice.len;
    }

    if (newlines_array_list.items.len == 1) return error.EmptyFile;
    newlines_array_list.appendAssumeCapacity(word_buf.len);

    const newlines = try newlines_array_list.toOwnedSlice(gpa);

    return @This(){ .word_buf = word_buf, .newlines = newlines };
}

/// If `stdin` is not piped then try use the path var
pub fn parseFromPath(
    gpa: std.mem.Allocator,
    path: ?[]const u8,
    max_words: usize,
) (error{MissingInputFile} || WordsParseError)!@This() {
    if (!std.fs.File.stdin().isTty()) {
        return try parseFromFile(gpa, std.fs.File.stdin(), max_words);
    }

    const wordfile = try std.fs.cwd().openFile(path orelse return error.MissingInputFile, .{});
    defer wordfile.close();

    return try parseFromFile(gpa, wordfile, max_words);
}
