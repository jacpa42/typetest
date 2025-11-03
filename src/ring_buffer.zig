pub fn RingBuffer(T: type, size: comptime_int) type {
    return struct {
        items: [size]T,
        write: usize = 0,

        pub fn fill(value: T) @This() {
            var this = @This(){
                .items = undefined,
                .write = 0,
            };

            @memset(&this.items, value);

            return this;
        }

        pub fn append(self: *@This(), value: T) void {
            self.items[self.write] = value;
            self.write = (self.write + 1) % size;
        }
    };
}
