const std = @import("std");

const KIB = 1024;
const MIB = KIB * KIB;

const MAX_FILE_SIZE = 50 * MIB;
const MAX_WORD_SIZE = KIB / 2;

pub const WordsParseError =
    error{
        /// classic oom
        OutOfMemory,
        /// Found a character which is not valid utf8
        InvalidUtf8,
        /// The file provided is too big
        EmptyFile,
        /// There is a word in the file which is too large
        WordsTooBig,
    } ||
    std.fs.File.OpenError ||
    std.Io.Reader.LimitedAllocError;

/// Allocated slice of mem. utf8
word_buf: []const u8,
/// Indices of newline characters in `word_buf`
newlines: []const usize,

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
    var buf: [KIB]u8 = undefined;
    var file_reader = file.reader(&buf);

    const word_buf = try file_reader.interface.allocRemaining(
        gpa,
        .limited(MAX_FILE_SIZE),
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
        if (cp_slice[0] == '\n') {
            const previous_idx = newlines_array_list.items[newlines_array_list.items.len - 1];
            if (idx > MAX_WORD_SIZE + previous_idx) return error.WordsTooBig;
            try newlines_array_list.append(gpa, idx);
        }
        idx += cp_slice.len;
    }

    if (newlines_array_list.items.len <= 1) {
        return error.EmptyFile;
    } else {
        const previous_idx = newlines_array_list.items[newlines_array_list.items.len - 1];
        if (word_buf.len > MAX_WORD_SIZE + previous_idx) return error.WordsTooBig;
    }
    try newlines_array_list.append(gpa, word_buf.len);

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
