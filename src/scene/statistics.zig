const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("../scene.zig");
const layout = @import("window_layout.zig");
const character_style = @import("../character_style.zig");
const now = @import("../time.zig").now;

const Statistic = struct { label: []const u8, value: f32 };

/// Renders some integer type to the window
pub fn renderStatistics(
    statistics: []const Statistic,
    win: vaxis.Window,
) void {
    const BUF_SIZE = 512;
    var buf: [BUF_SIZE]u8 = @splat(0);
    var render_buf: []u8 = &buf;

    const child_win_width = win.width / @as(u16, @intCast(statistics.len));

    var x_off: u16 = 0;
    for (statistics) |statistic| {
        const child_win = win.child(.{
            .x_off = x_off,
            .height = 1,
            .width = child_win_width,
        });
        x_off += child_win_width;

        const formatted_value = std.fmt.bufPrint(
            render_buf,
            "{d:.0}",
            .{statistic.value},
        ) catch {
            @panic("Failed to print statistic to buffer");
        };

        render_buf = render_buf[formatted_value.len..];

        const segments: []const vaxis.Segment = &.{
            .{
                .text = statistic.label,
                .style = character_style.statistic_label,
            },
            .{
                .text = formatted_value,
                .style = character_style.fps,
            },
        };

        _ = child_win.print(segments, .{ .col_offset = 0, .wrap = .none });
    }
}
