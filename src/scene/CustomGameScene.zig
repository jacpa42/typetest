const std = @import("std");
const super = @import("../scene.zig");
const layout = @import("window_layout.zig");
const vaxis = @import("vaxis");
const util = @import("util.zig");
const style = @import("../character_style.zig");
const stat = @import("statistics.zig");

const CharacterBuffer = @import("../CharacterBuffer.zig");
const Words = @import("../words.zig").Words;
const TestResultsScene = @import("TestResultsScene.zig");

const CustomGameSelectionScene = @This();

pub const CustomGameType = union(enum) {
    /// The total time in seconds
    time: u32,
    /// The total number of words for the test
    word: u32,

    /// Returns the value stored by any game type
    pub fn inner(self: CustomGameType) u32 {
        return switch (self) {
            inline else => |value| value,
        };
    }
};

prompt: []const u8,
prompt_num_codepoints: u16,
custom_game_type: CustomGameType,

pub fn init(
    comptime prompt: []const u8,
    custom_game_type: CustomGameType,
) CustomGameSelectionScene {
    var num_codepoints: u16 = 0;
    var iter = std.unicode.Utf8View.initComptime(prompt).iterator();
    while (iter.nextCodepoint() != null) : (num_codepoints += 1) {}

    return CustomGameSelectionScene{
        .prompt = prompt,
        .prompt_num_codepoints = num_codepoints,
        .custom_game_type = custom_game_type,
    };
}

/// Clears screen and renders the current state.
pub fn render(
    self: *CustomGameSelectionScene,
    data: super.RenderInfo,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    const game_window = try layout.gameWindow(
        data.root_window,
        data.words.max_codepoints,
    );

    const value = self.custom_game_type.inner();
    const print_size: u16 = 1 + std.math.log10_int(@max(value, 1));

    const text_input_window = layout.textInputWindow(
        game_window,
        self.prompt_num_codepoints + print_size,
    );

    const formatted_buffer = try data.frame_print_buffer.addManyAsSliceBounded(print_size);
    const fmtbuf = std.fmt.bufPrint(formatted_buffer, "{d}", .{value}) catch unreachable;
    std.debug.assert(fmtbuf.len == formatted_buffer.len);

    const prompt_style = switch (self.custom_game_type) {
        .time => style.custom_time_game_prompt,
        .word => style.custom_word_game_prompt,
    };

    const segments: [2]vaxis.Segment = .{
        vaxis.Segment{
            .text = self.prompt,
            .style = prompt_style,
        },
        vaxis.Segment{
            .text = formatted_buffer,
        },
    };

    _ = text_input_window.print(&segments, .{ .wrap = .none });
}

/// The `InGameAction.undo` action handler
pub fn processUndo(self: *CustomGameSelectionScene) void {
    switch (self.custom_game_type) {
        .time => |*v| v.* /= 10,
        .word => |*v| v.* /= 10,
    }
}

/// The `InGameAction.undo` action handler
pub fn processUndoWord(self: *CustomGameSelectionScene) void {
    switch (self.custom_game_type) {
        .time => |*v| v.* = 10,
        .word => |*v| v.* = 10,
    }
}

/// The `InGameAction.key_press` action handler.
pub fn processKeyPress(
    self: *CustomGameSelectionScene,
    typed_codepoint: u21,
) void {
    if (typed_codepoint < '0' or typed_codepoint > '9') return;

    const digit: u32 = @intCast(typed_codepoint - '0');
    const parsed = (self.custom_game_type.inner() *| 10) +| digit;

    switch (self.custom_game_type) {
        .time => |*v| v.* = parsed,
        .word => |*v| v.* = parsed,
    }
}

pub const Action = union(enum) {
    none,
    /// Exits the game entirely
    quit,
    /// Returns to the previous menu
    goback,
    /// Starts the custom game
    select,
    /// Undoes the latest key press (if any)
    undo_key_press,
    /// Undoes the latest `word` (if any)
    ///
    /// The `word` is defined in the normal vim word definition (until a space not including the current one)
    undo_word,
    /// Does a key press with the provided code
    key_press: u21,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const ret = std.ascii.control_code.cr;
        const del = std.ascii.control_code.del;
        const esc = std.ascii.control_code.esc;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .quit;
        if (key.matches(del, .{})) return .undo_key_press;
        if (key.matches(esc, .{})) return .goback;
        if (key.matches(ret, .{})) return .select;
        if (key.matches('w', ctrl)) return .undo_word;
        if (key.text != null) return .{ .key_press = key.codepoint };

        return .none;
    }
};
