const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const parseArgs = @import("src/args.zig").parseArgs;

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
    focus_in,
};

/// Action abstraction layer for the program. Each action has an effect in the scene and we can map keycodes to actions
const Action = union(enum) {
    none,
    undo,
    // The codepoint of a keypress
    key_press: u21,
};

pub fn main() !void {
    var gpa = std.heap.DebugAllocator(.{}){};
    const alloc = gpa.allocator();
    defer {
        switch (gpa.deinit()) {
            .ok => {},
            .leak => {
                std.debug.print("memory leak somewhere buddy :)\n", .{});
            },
        }
    }

    const args = try parseArgs(alloc);
    defer args.deinit(alloc);

    const words_for_test = try args.words.generateRandomWords(
        alloc,
        args.seed,
        args.word_count,
    );
    defer alloc.free(words_for_test);

    // Init tty
    var buffer: [1024]u8 = undefined;
    var tty = try vaxis.Tty.init(&buffer);
    defer tty.deinit();

    // Initialize Vaxis
    var vx = try vaxis.init(alloc, .{});
    // Deinit takes an optional allocator. If your program is exiting, you can
    // choose to pass a null allocator to save some exit time.
    defer vx.deinit(alloc, tty.writer());

    // The event loop requires an intrusive init. We create an instance with
    // stable pointers to Vaxis and our TTY, then init the instance. Doing so
    // installs a signal handler for SIGWINCH on posix TTYs
    //
    // This event loop is thread safe. It reads the tty in a separate thread
    var loop: vaxis.Loop(Event) = .{ .tty = &tty, .vaxis = &vx };
    try loop.init();

    // Start the read loop. This puts the terminal in raw mode and begins
    // reading user input
    try loop.start();
    defer loop.stop();

    // Optionally enter the alternate screen
    try vx.enterAltScreen(tty.writer());

    // Sends queries to terminal to detect certain features. This should always
    // be called after entering the alt screen, if you are using the alt screen
    try vx.queryTerminal(tty.writer(), 1 * std.time.ns_per_s);

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();

        // Exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| {
                if (key.matches('c', .{ .ctrl = true })) {
                    break;
                } else if (key.matches('l', .{ .ctrl = true })) {
                    vx.queueRefresh();
                } else {
                    // todo: print the key on screen :)
                }
            },

            // winsize events are sent to the application to ensure that all
            // resizes occur in the main thread. This lets us avoid expensive
            // locks on the screen. All applications must handle this event
            // unless they aren't using a screen (IE only detecting features)
            //
            // The allocations are because we keep a copy of each cell to
            // optimize renders. When resize is called, we allocated two slices:
            // one for the screen, and one for our buffered screen. Each cell in
            // the buffered screen contains an ArrayList(u8) to be able to store
            // the grapheme for that cell. Each cell is initialized with a size
            // of 1, which is sufficient for all of ASCII. Anything requiring
            // more than one byte will incur an allocation on the first render
            // after it is drawn. Thereafter, it will not allocate unless the
            // screen is resized
            .winsize => |ws| try vx.resize(alloc, tty.writer(), ws),
            else => {},
        }

        // vx.window() returns the root window. This window is the size of the
        // terminal and can spawn child windows as logical areas. Child windows
        // cannot draw outside of their bounds
        const win = vx.window();

        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        win.clear();

        // Create a style
        const style: vaxis.Style = .{};

        const box_width = win.width / 2;
        const box_height = win.height / 2;

        // Create a bordered child window
        const child = win.child(.{
            .x_off = (win.width - box_width) / 2,
            .y_off = (win.height - box_height) / 2,
            .width = box_width,
            .height = box_height,
            .border = .{
                .where = .all,
                .style = style,
            },
        });

        // todo: Each time the user presses a key we need to render if they typed that correctly.
        // We dont need to store what the user is typing. We only care about the current letter and how to move backward / foreward.

        child.writeCell(1, 0, .{
            .char = .{ .width = 1, .grapheme = "🫡" },
            .style = .{ .bg = .{ .index = 0 } },
        });

        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());
    }
}
