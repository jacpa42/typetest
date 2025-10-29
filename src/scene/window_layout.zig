const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("../scene.zig");

/// The child window where our entire game goes
pub fn gameWindow(win: vaxis.Window) vaxis.Window {
    const height = win.height * 2 / 3;
    const width = win.width * 2 / 3;
    return win.child(.{
        .x_off = (win.width - width) / 2,
        .y_off = (win.height - height) / 2,
        .width = width,
        .height = height,
    });
}

/// The child window where our text box input goes.
///
/// The bottom chunk of the window.
pub fn textWindow(game_window: vaxis.Window) vaxis.Window {
    const height = scene.NUM_RENDER_LINES + 2;

    return game_window.child(.{
        .x_off = 0,
        .y_off = game_window.height -| height,
        .width = game_window.width,
        .height = height,
        .border = .{
            .style = .{},
            .where = .all,
            .glyphs = .single_rounded,
        },
    });
}

/// The child window where our text box input goes.
///
/// We split the top section of the window into `splits.len` parts.
pub fn runningStatisticsWindows(
    game_window: vaxis.Window,
    splits: []vaxis.Window,
) void {
    std.debug.assert(splits.len > 0);

    const top_section_height = 2;
    const widget_width = game_window.width / splits.len;
    const widget_height = 1;

    const top_section = game_window.child(.{
        .x_off = 0,
        .y_off = 0,
        .width = game_window.width,
        .height = top_section_height,
        .border = .{
            .style = .{},
            .where = .bottom,
            .glyphs = .single_square,
        },
    });

    var idx = 0;
    var x_off = 0;
    while (x_off < top_section.width - widget_width) {
        defer {
            idx += 1;
            x_off += widget_width;
        }

        std.debug.assert(idx < splits.len);

        splits[idx] = top_section.child(.{
            .width = widget_width,
            .height = widget_height,
        });
    }
}
