const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("../scene.zig");
const words = @import("../words.zig");
const character_styles = @import("../character_style.zig");
const CharacterBuffer = @import("../CharacterBuffer.zig");

pub const BORDER_SIZE = 2;
pub const MIN_TEXT_BOX_HEIGHT = CharacterBuffer.NUM_RENDER_LINES + BORDER_SIZE;
pub const MIN_TEXT_BOX_WIDTH = words.MAX_WORD_SIZE + BORDER_SIZE;
pub const MIN_GAME_WINDOW_WIDTH = MIN_TEXT_BOX_WIDTH + BORDER_SIZE;
pub const MIN_GAME_WINDOW_HEIGHT = MIN_TEXT_BOX_HEIGHT + BORDER_SIZE;

/// The child window where our entire game goes
pub fn gameWindow(
    win: vaxis.Window,
) error{WindowTooSmall}!vaxis.Window {
    var game_window_height = win.height * 2 / 3;
    var game_window_width = win.width * 2 / 3;

    if (game_window_height < MIN_GAME_WINDOW_HEIGHT or
        game_window_width < MIN_GAME_WINDOW_WIDTH)
    {
        game_window_height = win.height;
        game_window_width = win.width;

        if (game_window_height < MIN_GAME_WINDOW_HEIGHT or
            game_window_width < MIN_GAME_WINDOW_WIDTH)
        {
            return error.WindowTooSmall;
        }
    }

    return win.child(.{
        .x_off = (win.width - game_window_width) / 2,
        .y_off = (win.height - game_window_height) / 2,
        .width = game_window_width,
        .height = game_window_height,
        .border = .{
            .style = character_styles.game_window_border,
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

pub fn menuListItems(
    game_window: vaxis.Window,
) vaxis.Window {
    const list_items_height = scene.MenuItem.COUNT;
    const list_items_width = game_window.width;
    return game_window.child(.{
        .x_off = (game_window.width - list_items_width) / 2,
        .y_off = (game_window.height - list_items_height) / 2,
        .width = list_items_width,
        .height = list_items_height,
    });
}

/// The child window where our text box input goes.
///
/// Middle chunk of the screen
pub fn resultsWindow(
    game_window: vaxis.Window,
) vaxis.Window {
    const height = CharacterBuffer.NUM_RENDER_LINES + 2;

    return game_window.child(.{
        .x_off = 0,
        .y_off = (game_window.height -| height) / 2,
        .width = game_window.width,
        .height = height,
        .border = .{
            .style = character_styles.game_window_border,
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

/// The child window where our text box input goes.
///
/// The bottom chunk of the window.
pub fn charBufWindow(
    game_window: vaxis.Window,
) vaxis.Window {
    const height = CharacterBuffer.NUM_RENDER_LINES + 2;

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
    game_window: vaxis.Window,
) vaxis.Window {
    return game_window.child(.{
        .x_off = 0,
        .width = game_window.width,
        .height = 2,
        .border = .{ .where = .bottom },
    });
}
