const std = @import("std");
const vaxis = @import("vaxis");
const super = @import("../scene.zig");
const character_style = @import("../character_style.zig");
const layout = @import("window_layout.zig");
const util = @import("util.zig");

const StatisticValue = f32;
pub const Statistic = struct {
    label: []const u8,
    value: StatisticValue,
};

/// Renders some integer type to the window
pub fn renderStatistics(
    game_window: vaxis.Window,
    statistics: []const Statistic,
    data: super.RenderData,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    const win = layout.runningStatisticsWindow(game_window);

    const child_win_width = win.width / @as(u16, @intCast(statistics.len));
    var x_off: u16 = 0;

    for (statistics) |stat| {
        defer x_off += child_win_width;

        const buf = try data.frame_print_buffer.addManyAsSliceBounded(
            util.REQUIRED_NUM_BUF_SIZE,
        );

        const print_buf = std.fmt.bufPrint(buf, "{d:.0}", .{stat.value}) catch return error.OutOfMemory;
        // pop off the last couple values we dont use
        data.frame_print_buffer.items.len -= (buf.len - print_buf.len);

        const statistic_win = win.child(.{
            .height = win.height,
            .width = child_win_width,
            .x_off = x_off,
        });

        _ = statistic_win.print(&.{
            vaxis.Segment{
                .text = stat.label,
                .style = character_style.statistic_label,
            },
            vaxis.Segment{
                .text = print_buf,
                .style = character_style.statistic_value,
            },
        }, .{});
    }
}
