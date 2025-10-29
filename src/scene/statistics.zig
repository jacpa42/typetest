const std = @import("std");
const vaxis = @import("vaxis");

pub const TimeStatWindow = enum {
    wpm,
    mistake_counter,
    time_left,

    pub const COUNT: comptime_int = @typeInfo(@This()).@"enum".fields.len;
};
