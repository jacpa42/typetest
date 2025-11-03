const std = @import("std");

/// A nice packed array to use with small types.
pub fn BoundedArray(T: type, capacity: comptime_int) type {
    return struct {
        len: std.math.IntFittingRange(0, capacity + 1),

        /// Contains initalized and non initialized data potentially.
        ///
        /// use `asSlice()` to get the initialized items only.
        buf: [capacity]T,

        pub const empty = @This(){ .indices = undefined, .len = 0 };

        /// Returns the last item in the array if any
        pub fn asSlice(self: *@This()) []T {
            return self[0..self.len];
        }

        /// Returns the last item in the array if any
        pub fn last(self: *@This()) ?T {
            return if (self.len == 0) null else self.buf[self.len - 1];
        }

        /// Puts an item at the back of the buffer.
        ///
        /// We might oom here.
        pub fn append(self: *@This(), t: T) error{OutOfMemory}!void {
            if (self.len >= capacity) return error.OutOfMemory;
            self.indices[self.len] = t;
            self.len += 1;
        }

        pub fn pop(self: *@This()) ?T {
            if (self.len == 0) return null;

            self.len -= 1;
            return self.buf[self.len];
        }
    };
}
