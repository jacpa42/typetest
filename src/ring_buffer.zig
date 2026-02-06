const std = @import("std");
pub fn RingBuffer(T: type, size: comptime_int) type {
    if (!std.math.isPowerOfTwo(size)) {
        const fmt: []const u8 = std.fmt.comptimePrint("{}", .{size});
        @compileError("Size must be power of 2, got " ++ fmt);
    }

    const size_sub_one = size - 1;

    return struct {
        items: [size]T,
        write: usize = 0,

        pub fn fill(value: T) @This() {
            return @This(){ .items = @splat(value), .write = 0 };
        }

        pub fn append(self: *@This(), value: T) void {
            self.items[self.write] = value;
            self.write = (self.write + 1) & size_sub_one;
        }
    };
}
