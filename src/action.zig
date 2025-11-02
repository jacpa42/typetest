const std = @import("std");
const vaxis = @import("vaxis");

pub const InGameAction = union(enum) {
    none,
    /// Exits the game entirely
    quit,
    /// Returns to main menu
    return_to_menu,
    /// Creates a new random game
    new_random_game,
    /// Restarts the current game
    restart_current_game,
    /// Undoes the latest key press (if any)
    undo_key_press,
    /// Does a key press with the provided code
    key_press: u21,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const del = std.ascii.control_code.del;
        const esc = std.ascii.control_code.esc;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .quit;
        if (key.matches(esc, .{})) return .return_to_menu;
        if (key.matches('r', ctrl)) return .restart_current_game;
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
        const esc = std.ascii.control_code.esc;
        const up = vaxis.Key.up;
        const down = vaxis.Key.down;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl) or key.matches(esc, .{})) return .quit;
        if (key.matches(ret, .{})) return .select;

        if (key.matchesAny(&.{ 'k', up }, .{})) return .move_up;
        if (key.matchesAny(&.{ 'j', down }, .{})) return .move_down;

        return .none;
    }
};

/// Actions in the results screen
pub const ResultsAction = union(enum) {
    none,
    /// quit program
    quit,
    /// Returns to main menu
    return_to_menu,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .quit;
        if (key.matches('q', .{})) return .return_to_menu;

        return .none;
    }
};
