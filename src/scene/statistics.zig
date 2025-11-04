const std = @import("std");
const vaxis = @import("vaxis");
const super = @import("../scene.zig");
const character_style = @import("../character_style.zig");
const layout = @import("window_layout.zig");
const now = @import("util.zig").now;

const REQUIRED_BUF_SIZE: usize = std.math.log10_int(@as(StatisticValue, std.math.maxInt(StatisticValue))) + 1;
const StatisticValue = u32;
pub const Statistic = struct {
    label: []const u8,
    value: StatisticValue,
};

/// Renders some integer type to the window
pub fn renderStatistics(
    COUNT: comptime_int,
    statistics: *const [COUNT]Statistic,
    data: super.RenderData,
) error{ WindowTooSmall, OutOfMemory }!void {
    const win = layout.runningStatisticsWindow(try layout.gameWindow(data.root_window));

    const child_win_width = win.width / COUNT;
    var x_off: u16 = 0;

    inline for (statistics) |stat| {
        defer x_off += child_win_width;

        const print_buf = try data.frame_print_buffer.addManyAsSlice(
            data.alloc,
            REQUIRED_BUF_SIZE,
        );

        const len = std.fmt.printInt(print_buf, stat.value, 10, .lower, .{});
        // pop off the last couple values we dont use
        data.frame_print_buffer.items.len -= (print_buf.len - len);

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
                .text = print_buf[0..len],
                .style = character_style.statistic_value,
            },
        }, .{});
    }
}
