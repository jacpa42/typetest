const vaxis = @import("vaxis");

/// The style for characters which are yet to be typed
pub const untyped = vaxis.Style{ .dim = true };

/// The style for characters which have been correctly typed
pub const right = vaxis.Style{
    .fg = .{ .index = 10 },
    .italic = true,
};

/// The style for characters which have been incorrectly typed
pub const wrong = vaxis.Style{
    .bg = .{ .index = 1 },
    .bold = true,
};

/// Swaps the fg and bg styles
pub fn invert_fg_bg(style: vaxis.Style) vaxis.Style {
    var new_style = style;

    new_style.fg = style.bg;
    new_style.bg = style.fg;

    return new_style;
}

/// The style for rendering the "fps: " or "wpm: " etc
pub const statistic_label = vaxis.Style{
    .fg = .{ .index = 4 },
};

/// The style for rendering the actual fps value
pub const statistic_value = vaxis.Style{
    .italic = true,
    .fg = .{ .index = 1 },
};

pub const game_window_border = vaxis.Style{
    .fg = .{ .index = 1 },
};

pub const text_box_window_border = vaxis.Style{
    .fg = .{ .index = 4 },
};

/// The style for the cursor
pub const header_style1 = vaxis.Style{
    .fg = .{ .index = 1 },
};

/// The style for the cursor
pub const header_style2 = vaxis.Style{
    .dim = true,
    .fg = .{ .index = 1 },
};
