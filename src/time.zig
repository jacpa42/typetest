const std = @import("std");
const builtin = @import("builtin");

pub fn now() std.time.Instant {
    const supported = comptime switch (builtin.os.tag) {
        .wasi => false,
        .uefi => false,
        else => true,
    };

    if (!supported) @compileError("Instants are not supported on this platform.");

    return std.time.Instant.now() catch unreachable;
}
