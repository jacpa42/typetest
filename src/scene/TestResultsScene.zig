const std = @import("std");
const vaxis = @import("vaxis");
const layout = @import("window_layout.zig");
const character_style = @import("../character_style.zig");
const super = @import("../scene.zig");
const util = @import("util.zig");
const stat = @import("statistics.zig");

average_wpm: f32,
peak_wpm: f32,
average_accuracy: f32,
test_duration_seconds: f32,

/// Clears screen and renders the current state.
pub fn render(
    self: *const @This(),
    data: super.RenderInfo,
) error{ EmptyLineNotAllowed, OutOfMemory }!void {
    const game_window = try layout.gameWindow(
        data.root_window,
        data.words.max_codepoints,
    );
    const middle_box = layout.resultsWindow(game_window);

    const statistics: [4]stat.Statistic = .{
        .{ .label = "average words per minute: ", .value = self.average_wpm },
        .{ .label = "peak words per minute: ", .value = self.peak_wpm },
        .{ .label = "accuracy: ", .value = self.average_accuracy },
        .{ .label = "test duration: ", .value = self.test_duration_seconds },
    };

    var row = (middle_box.height -| @as(u16, @truncate(statistics.len))) / 2;

    for (&statistics) |statistic| {
        defer row += 1;

        const buf = try data.frame_print_buffer.addManyAsSliceBounded(util.REQUIRED_NUM_BUF_SIZE);

        const print_buf =
            std.fmt.bufPrint(buf, "{d:.2}", .{statistic.value}) catch return error.OutOfMemory;

        // pop off the last couple values we dont use
        data.frame_print_buffer.items.len -= (buf.len - print_buf.len);

        std.debug.assert(std.unicode.utf8ValidateSlice(statistic.label));
        const label_len = std.unicode.utf8CountCodepoints(statistic.label) catch unreachable;

        _ = middle_box.print(&.{
            vaxis.Segment{
                .text = statistic.label,
                .style = character_style.statistic_label,
            },
            vaxis.Segment{
                .text = print_buf,
                .style = character_style.statistic_value,
            },
        }, .{
            .col_offset = (middle_box.width -| @as(u16, @truncate(label_len + print_buf.len))) / 2,
            .row_offset = row,
        });
    }
}

/// Actions in the results screen
pub const Action = enum {
    none,
    /// quit program
    quit,
    /// Returns to main menu
    return_to_menu,

    /// Process the event from vaxis and optionally emit an action to process
    pub fn processKeydown(key: vaxis.Key) @This() {
        const esc = std.ascii.control_code.esc;
        const cr = std.ascii.control_code.cr;
        const ctrl = vaxis.Key.Modifiers{ .ctrl = true };

        if (key.matches('c', ctrl)) return .quit;
        if (key.matchesAny(&.{ esc, cr }, .{})) return .return_to_menu;

        return .none;
    }
};
