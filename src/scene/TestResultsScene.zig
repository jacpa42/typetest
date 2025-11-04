const std = @import("std");
const vaxis = @import("vaxis");
const layout = @import("window_layout.zig");
const character_style = @import("../character_style.zig");
const super = @import("../scene.zig");
const util = @import("util.zig");

average_wpm: f32,

/// Clears screen and renders the current state.
pub fn render(
    self: *const @This(),
    data: super.RenderData,
) error{ WindowTooSmall, OutOfMemory }!void {
    const game_window = try layout.gameWindow(data.root_window);
    const middle_box = layout.resultsWindow(game_window);

    const col_offset = (middle_box.width -| @as(u16, @truncate(10))) / 2;

    const print_buf = try data.frame_print_buffer.addManyAsSlice(
        data.alloc,
        util.requiredBufSize(u32),
    );

    const len = std.fmt.printInt(print_buf, @as(u32, @intFromFloat(self.average_wpm)), 10, .lower, .{});
    // pop off the last couple values we dont use
    data.frame_print_buffer.items.len -= (print_buf.len - len);

    _ = middle_box.print(&.{
        vaxis.Segment{
            .text = "average wpm: ",
            .style = character_style.statistic_label,
        },
        vaxis.Segment{
            .text = print_buf[0..len],
            .style = character_style.statistic_value,
        },
    }, .{ .col_offset = col_offset });
}
