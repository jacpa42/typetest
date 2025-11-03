const std = @import("std");
const layout = @import("window_layout.zig");
const super = @import("../scene.zig");

average_wpm: f32,

/// Clears screen and renders the current state.
pub fn render(
    self: *const @This(),
    data: super.RenderData,
) error{WindowTooSmall}!void {
    const game_window = try layout.gameWindow(data.root_window);

    // as we add more stats here we need to change how they are rendered

    const middle_box_width = game_window.width / 2;
    const middle_box_height = game_window.height / 2;
    const middle_box = game_window.child(.{
        .width = middle_box_width,
        .height = middle_box_height,
        .x_off = (game_window.width - middle_box_width) / 2,
        .y_off = (game_window.height - middle_box_height) / 2,
        .border = .{ .where = .all },
    });

    var buf: [256]u8 = undefined;

    const print_buf = std.fmt.bufPrint(
        &buf,
        "average wpm: {d:4.2}",
        .{self.average_wpm},
    ) catch std.process.exit(1);

    // const col_offset = (middle_box_width -| @as(u16, @truncate(print_buf.len))) / 2;
    const col_offset = 0;
    _ = middle_box.printSegment(
        .{ .text = print_buf },
        .{ .col_offset = col_offset },
    );
}
