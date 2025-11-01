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

/// The style for the cursor
pub const cursor = vaxis.Style{
    .italic = true,
    .fg = .{ .index = 0 },
    .bg = .{ .index = 15 },
};
