const std = @import("std");
const vaxis = @import("vaxis");

pub const InGameAction = union(enum) {
    none,
    /// Returns to main menu
    exit_game,
    /// Creates a new random game
    new_random_game,
    /// Undoes the latest key press (if any)
    undo_key_press,
    /// Does a key press with the provided code
    key_press: u21,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const del = std.ascii.control_code.del;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .exit_game;
        if (key.matches('n', ctrl)) return .new_random_game;
        if (key.matches(del, .{})) return .undo_key_press;
        if (key.text != null) return .{ .key_press = key.codepoint };

        return .none;
    }
};

pub const MenuAction = enum {
    none,
    /// Exit the program
    quit,
    /// Select the current menu option
    select,
    /// Move the selection up
    move_up,
    /// Move the selection down
    move_down,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const ret = std.ascii.control_code.cr;
        const up = vaxis.Key.up;
        const down = vaxis.Key.down;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .quit;
        if (key.matches(ret, .{})) return .select;

        if (key.matchesAny(&.{ 'k', up }, .{})) return .move_up;
        if (key.matchesAny(&.{ 'j', down }, .{})) return .move_down;

        return .none;
    }
};
