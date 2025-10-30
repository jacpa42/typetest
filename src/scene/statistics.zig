const std = @import("std");
const vaxis = @import("vaxis");
const scene = @import("../scene.zig");
const now = @import("../time.zig").now;

pub const TimeGameStatistic = union(enum) {
    fps: f32,
    wpm: f32,
    mistake_counter: u32,
    time_left_seconds: f32,

    pub fn render(self: @This(), win: vaxis.Window) void {
        win.clear();

        var buf: [128]u8 = undefined;
        var segment: vaxis.Segment = .{ .text = "" };

        defer {
            const len = std.unicode.utf8CountCodepoints(segment.text) catch unreachable;
            const col_offset = (win.width -| @as(u16, @truncate(len))) / 2;

            _ = win.printSegment(segment, .{
                .col_offset = col_offset,
                .wrap = .none,
            });
        }

        switch (self) {
            .fps => |frames_per_second| {
                const fps: u32 = @intFromFloat(frames_per_second);
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "fps: {d}",
                    .{fps},
                ) catch unreachable;
            },
            .wpm => |words_per_minute| {
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "wpm: {d:4.2}",
                    .{words_per_minute},
                ) catch unreachable;
            },
            .mistake_counter => |mistake_counter| {
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "mistakes: {}",
                    .{mistake_counter},
                ) catch unreachable;
            },
            .time_left_seconds => |time_left_seconds| {
                // var time_left_seconds = @as(f32, @floatFromInt(self.test_duration_ns)) / 1e9;
                // if (data.test_start) |start| {
                //     const elapsed = @as(f32, @floatFromInt(now().since(start))) / 1e9;
                //     time_left_seconds = @max(0.0, time_left_seconds - elapsed);
                // }
                segment.text = std.fmt.bufPrint(
                    &buf,
                    "time left: {:.1}",
                    .{time_left_seconds},
                ) catch unreachable;
            },
        }
    }
};
