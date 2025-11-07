const std = @import("std");
const builtin = @import("builtin");
const State = @import("../State.zig");
const FrameTimings = State.FrameTimings;

/// Allocating a buffer of at least this size should not error when we try to print a float or int to it.
pub const REQUIRED_NUM_BUF_SIZE: usize = 64;

pub fn now() std.time.Instant {
    const supported = comptime switch (builtin.os.tag) {
        .wasi => false,
        .uefi => false,
        else => true,
    };

    if (!supported) @compileError("Instants are not supported on this platform.");

    return std.time.Instant.now() catch unreachable;
}

pub fn accuracy(correct: u32, incorrect: u32) f32 {
    return 100.0 * @as(f32, @floatFromInt(correct)) / @as(f32, @floatFromInt(correct + incorrect));
}

pub fn wordsPerMinute(
    correct: u32,
    test_start: ?std.time.Instant,
) f32 {
    const start = test_start orelse return 0.0;
    return charactersPerSecond(correct, start) * 12.0;
}

/// The number of characters per second the user is typeing
pub fn charactersPerSecond(
    correct: u32,
    test_start: std.time.Instant,
) f32 {
    // We dont start recording wpm or cps until this time as otherwise the wpm is insane
    const wpm_normalization_period_seconds = 0.5;

    const elapsed = @as(f32, @floatFromInt(now().since(test_start))) / 1e9;
    return @as(f32, @floatFromInt(correct)) / @max(elapsed, wpm_normalization_period_seconds);
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
