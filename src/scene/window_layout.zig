const std = @import("std");
const vaxis = @import("vaxis");
const words = @import("../words.zig");
const character_styles = @import("../character_style.zig");
const CharacterBuffer = @import("../CharacterBuffer.zig");
const Window = vaxis.Window;
const Header = @import("header.zig").Header;
const MainMenu = @import("MenuScene.zig").MainMenu;

pub const BORDER_SIZE = 2;
pub const MIN_TEXT_BOX_HEIGHT = CharacterBuffer.NUM_RENDER_LINES + BORDER_SIZE;
pub const MIN_GAME_WINDOW_HEIGHT = MIN_TEXT_BOX_HEIGHT + BORDER_SIZE;

/// The child window where our entire game goes
pub fn gameWindow(
    root_window: Window,
    largest_word_size: u16,
) error{EmptyLineNotAllowed}!Window {
    var game_window_height = root_window.height * 4 / 5;
    var game_window_width = root_window.width * 4 / 5;

    const MIN_GAME_WINDOW_WIDTH = largest_word_size + BORDER_SIZE;

    if (game_window_height < MIN_GAME_WINDOW_HEIGHT or
        game_window_width < MIN_GAME_WINDOW_WIDTH)
    {
        game_window_height = root_window.height;
        game_window_width = root_window.width;

        if (game_window_height < MIN_GAME_WINDOW_HEIGHT or
            game_window_width < MIN_GAME_WINDOW_WIDTH)
        {
            return error.EmptyLineNotAllowed;
        }
    }

    return root_window.child(.{
        .x_off = (root_window.width - game_window_width) / 2,
        .y_off = (root_window.height - game_window_height) / 2,
        .width = game_window_width,
        .height = game_window_height,
        .border = .{
            .style = character_styles.game_window_border,
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

/// The child window where our entire game goes
pub fn textInputWindow(
    game_window: Window,
    user_input_size: u16,
) Window {
    const text_input_window_height = 1 + BORDER_SIZE;
    const text_input_window_width = @min(
        user_input_size + BORDER_SIZE,
        game_window.width -| BORDER_SIZE,
    );

    return game_window.child(.{
        .x_off = (game_window.width - text_input_window_width) / 2,
        .y_off = (game_window.height - text_input_window_height) / 2,
        .width = text_input_window_width,
        .height = text_input_window_height,
        .border = .{
            .style = character_styles.text_box_window_border,
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

/// Top chunk of the `root_window`
pub fn headerWindow(
    root_window: Window,
    header: Header,
) error{EmptyLineNotAllowed}!Window {
    const win_height = header.height();
    const win_width = header.width();

    if (win_height >= root_window.height or
        win_width >= root_window.width)
    {
        return error.EmptyLineNotAllowed;
    }

    const main_menu_height: u16 = comptime @typeInfo(MainMenu).@"enum".fields.len;
    const height_available = root_window.height -| main_menu_height;
    return root_window.child(.{
        .x_off = (root_window.width - win_width) / 2,
        .y_off = (root_window.height - height_available) / 2,
        .width = win_width,
        .height = win_height,
    });
}

pub fn menuListItems(
    comptime Menu: type,
    game_window: Window,
) Window {
    if (@typeInfo(Menu) != .@"enum") @compileError("Menu list item must be an enum");

    const list_items_height: u16 = comptime @intCast(@typeInfo(Menu).@"enum".fields.len);
    const list_items_width = game_window.width;
    return game_window.child(.{
        .x_off = (game_window.width -| list_items_width) / 2,
        .y_off = (game_window.height -| list_items_height) / 2,
        .width = list_items_width,
        .height = list_items_height,
    });
}

/// The child window where our text box input goes.
///
/// Middle chunk of the screen
pub fn resultsWindow(
    game_window: Window,
) Window {
    return game_window;
}

/// The child window where our text box input goes.
///
/// The bottom chunk of the window.
pub fn charBufWindow(
    game_window: Window,
) Window {
    const height = CharacterBuffer.NUM_RENDER_LINES + BORDER_SIZE;

    return game_window.child(.{
        .x_off = 0,
        .y_off = (game_window.height -| height) / 2,
        .width = game_window.width,
        .height = height,
        .border = .{
            .style = character_styles.text_box_window_border,
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

/// The child window where our text box input goes.
///
/// We split the top section of the window into `splits.len` parts.
pub fn runningStatisticsWindow(
    game_window: Window,
) Window {
    return game_window.child(.{
        .x_off = 0,
        .width = game_window.width,
        .height = 2,
        .border = .{ .where = .bottom },
    });
}
