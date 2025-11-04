const std = @import("std");
const builtin = @import("builtin");
const State = @import("../State.zig");
const FrameTimings = State.FrameTimings;

/// The maximum size required to print an integer type `T`.
pub fn requiredBufSize(T: type) usize {
    return std.math.log10_int(@as(T, std.math.maxInt(T))) + 1;
}

pub fn now() std.time.Instant {
    const supported = comptime switch (builtin.os.tag) {
        .wasi => false,
        .uefi => false,
        else => true,
    };

    if (!supported) @compileError("Instants are not supported on this platform.");

    return std.time.Instant.now() catch unreachable;
}

pub fn wordsPerMinute(
    correct: u32,
    mistakes: u32,
    test_start: ?std.time.Instant,
) f32 {
    const start = test_start orelse return 0.0;
    return charactersPerSecond(correct, mistakes, start) * 60.0 / 5.0;
}

/// The number of characters per second the user is typeing
pub fn charactersPerSecond(
    correct: u32,
    mistakes: u32,
    test_start: std.time.Instant,
) f32 {
    const elapsed = @as(f32, @floatFromInt(now().since(test_start))) / 1e9;

    const total_chars = @as(f32, @floatFromInt(correct + mistakes));
    const accuracy = @as(f32, @floatFromInt(correct)) / @max(total_chars, 1.0);

    return (total_chars * accuracy) / @max(elapsed, 1.0);
}

/// The number of characters per second the user is typeing
pub fn framesPerSecond(frame_timings: *const FrameTimings) f32 {
    var average: f32 = 0.0;
    const count: f32 = comptime State.NUM_FRAME_TIMINGS;

    if (State.NUM_FRAME_TIMINGS == 0) @compileError("retard");

    inline for (frame_timings.items) |frame_time| {
        average += 1e9 / @as(f32, @floatFromInt(frame_time));
    }

    return average / count;
}
