const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("../scene.zig");
const character_style = @import("../character_style.zig");
const now = @import("../time.zig").now;

/// Renders some integer type to the window
pub fn renderStatistic(
    label: [:0]const u8,
    value: anytype,
    win: vaxis.Window,
) void {
    const BUF_SIZE = 32;
    var buf: [BUF_SIZE]u8 = undefined;

    const bufend = std.fmt.printInt(&buf, value, 10, .lower, .{});

    const segments: []const vaxis.Segment = &.{
        .{
            .text = label,
            .style = character_style.statistic_label,
        },
        .{
            .text = buf[0..bufend],
            .style = character_style.fps,
        },
    };

    _ = win.print(segments, .{ .wrap = .none });
}
