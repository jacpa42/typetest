const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;

const parseArgs = @import("src/args.zig").parseArgs;
const GameState = @import("src/GameState.zig");

const Event = union(enum) {
    key_press: vaxis.Key,
    winsize: vaxis.Winsize,
};

const Styles = struct {
    const untyped = vaxis.Style{
        .dim = true,
    };
    const typed_right = vaxis.Style{
        .fg = .{ .index = 10 },
        .italic = true,
    };
    const typed_wrong = vaxis.Style{
        .fg = .{ .index = 9 },
        .bold = true,
    };
    const cursor = vaxis.Style{
        .italic = true,
        .fg = .{ .index = 0 },
        .bg = .{ .index = 15 },
    };
};

const GameAction = union(enum) {
    undo,
    key_press: u21,
};
const MenuAction = enum {
    exit,
    restart_game,
    new_game,
};

/// Action abstraction layer for the program. Each action has an effect in the scene and we can map keycodes to actions
const Action = union(enum) {
    none,
    menu: MenuAction,
    game: GameAction,
};

/// Process the event from vaxis and optionally emit an action to process
fn processKeydown(key: vaxis.Key) Action {
    const del = std.ascii.control_code.del;

    if (key.matches('c', .{ .ctrl = true })) {
        return Action{ .menu = .exit };
    } else if (key.matches('r', .{ .ctrl = true })) {
        return Action{ .menu = .restart_game };
    } else if (key.matches('n', .{ .ctrl = true })) {
        return Action{ .menu = .new_game };
    } else if (key.matches(del, .{})) {
        return Action{ .game = .undo };
    } else if (key.text != null) {
        return Action{ .game = .{ .key_press = key.codepoint } };
    }

    return Action.none;
}

/// Setups the draw window for the game
fn newGameWindow(
    window: *const vaxis.Window,
    state: *const GameState,
) vaxis.Window {
    // Clear the entire space because we are drawing in immediate mode.
    // vaxis double buffers the screen. This new frame will be compared to
    // the old and only updated cells will be drawn
    // win.clear();

    const box_width = (window.width * 2) / 3;
    const box_height = (window.height * 2) / 3;

    // Create a bordered child window
    const child = window.child(.{
        .x_off = (window.width - box_width) / 2,
        .y_off = (window.height - box_height) / 2,
        .width = box_width,
        .height = box_height,
        .border = .{ .where = .all, .style = .{} },
    });

    const segment = vaxis.Segment{
        .text = state.iter.bytes,
        .style = Styles.untyped,
    };
    _ = child.printSegment(segment, .{});

    return child;
}

fn handleUndo(
    game_window: *vaxis.Window,
    state: *GameState,
) void {
    // update the current cell to untyped and update the previous cell to cursor
    if (state.peekNextCodepoint()) |char| {
        game_window.writeCell(
            state.cursor_col,
            state.cursor_row,
            .{
                .char = .{ .width = 0, .grapheme = char },
                .style = Styles.untyped,
            },
        );

        state.prevCursorPosition(.{
            .x = game_window.width,
            .y = game_window.height,
        });

        if (state.prevCodepoint()) |next_char| {
            game_window.writeCell(
                state.cursor_col,
                state.cursor_row,
                .{
                    .char = .{ .width = 0, .grapheme = next_char },
                    .style = Styles.cursor,
                },
            );
        }
    }
}

/// On keypress we need to determine the cell draw style if it was correct or not and then draw
fn handleKeyPress(
    game_window: *vaxis.Window,
    state: *GameState,
    codepoint: u21,
) void {
    if (state.nextCodepoint()) |char| {
        if (state.test_start == null) {
            state.test_start = std.time.Instant.now() catch unreachable;
        }
        const decoded = std.unicode.utf8Decode(char) catch unreachable;
        var style: vaxis.Style = undefined;

        if (codepoint == decoded) {
            style = Styles.typed_right;
            state.correct_counter += 1;
        } else {
            style = Styles.typed_wrong;
            state.mistake_counter += 1;
        }

        game_window.writeCell(
            state.cursor_col,
            state.cursor_row,
            .{
                .char = .{ .width = 0, .grapheme = char },
                .style = style,
            },
        );

        state.nextCursorPosition(.{
            .x = game_window.width,
            .y = game_window.height,
        });

        if (state.peekNextCodepoint()) |next_char| {
            game_window.writeCell(state.cursor_col, state.cursor_row, .{
                .char = .{ .width = 0, .grapheme = next_char },
                .style = Styles.cursor,
            });
        }
    }
}

/// Updates the current frame with the new action
fn processGameAction(
    game_window: *vaxis.Window,
    state: *GameState,
    action: GameAction,
) void {
    switch (action) {
        .undo => handleUndo(game_window, state),
        .key_press => |codepoint| handleKeyPress(game_window, state, codepoint),
    }
}

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

    var args = try parseArgs(alloc);
    defer args.deinit(alloc);

    var game_state = GameState{};
    try game_state.newGame(
        alloc,
        &args.words,
        args.seed,
        args.word_count,
    );
    defer game_state.deinit(alloc);

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

    // vx.window() returns the root window. This window is the size of the
    // terminal and can spawn child windows as logical areas. Child windows
    // cannot draw outside of their bounds
    var win = vx.window();

    var game_window = newGameWindow(&win, &game_state);

    while (true) {
        // nextEvent blocks until an event is in the queue
        const event = loop.nextEvent();
        var action: Action = .none;

        // Exhaustive switching ftw. Vaxis will send events if your Event enum
        // has the fields for those events (ie "key_press", "winsize")
        switch (event) {
            .key_press => |key| action = processKeydown(key),
            .winsize => |ws| {
                try vx.resize(alloc, tty.writer(), ws);
                win = vx.window();
                game_window = newGameWindow(&win, &game_state);
            },
        }

        switch (action) {
            .none => {},
            .menu => |menu_action| switch (menu_action) {
                .exit => break,
                .new_game => {
                    args.seed = @bitCast(std.time.microTimestamp());

                    try game_state.newGame(
                        alloc,
                        &args.words,
                        args.seed,
                        args.word_count,
                    );

                    win.clear();
                },
                .restart_game => {
                    try game_state.newGame(
                        alloc,
                        &args.words,
                        args.seed,
                        args.word_count,
                    );

                    win.clear();
                },
            },
            .game => |game_action| processGameAction(&game_window, &game_state, game_action),
        }

        if (game_state.gameComplete()) break;

        if (game_state.wordsPerMinute()) |wpm| {
            // place the wpm window above and to the left of the main game window
            const height = 3;
            const width = 10; // 5 for wpm: and 3 for wpm and 2 for border
            var wpm_window = win.child(.{
                .x_off = game_window.x_off,
                .y_off = game_window.y_off -| height,
                .width = width,
                .height = height,
                .border = .{ .where = .all, .style = .{} },
            });

            var wpm_buf: [width]u8 = undefined;
            const seg = vaxis.Segment{
                .text = try std.fmt.bufPrint(&wpm_buf, "wpm: {}", .{wpm}),
            };
            _ = wpm_window.printSegment(seg, .{});
        }

        // Render the screen. Using a buffered writer will offer much better
        // performance, but is not required
        try vx.render(tty.writer());
    }

    // Print score and what not
    {
        // Clear the entire space because we are drawing in immediate mode.
        // vaxis double buffers the screen. This new frame will be compared to
        // the old and only updated cells will be drawn
        // win.clear();
        win.clear();

        const box_width = (win.width) / 2;
        const box_height = (win.height) / 2;

        // Create a bordered child window
        // Create some children for the stuff
        const child = win.child(.{
            .x_off = (win.width - box_width) / 2,
            .y_off = (win.height - box_height) / 2,
            .width = box_width,
            .height = box_height,
            .border = .{ .where = .all, .style = .{} },
        });

        const mistakes = child.child(.{
            .x_off = 0,
            .y_off = 0,
            .width = box_width / 2,
            .height = box_height / 2,
            .border = .{ .where = .all, .style = .{} },
        });

        var buf: [512]u8 = undefined;
        const score_buf = try std.fmt.bufPrint(&buf, "{}", .{game_state.mistake_counter});
        const wpm_buf = try std.fmt.bufPrint(buf[score_buf.len..], "{}", .{game_state.wordsPerMinute() orelse 0});

        const segments = &.{
            vaxis.Segment{
                .text = "total mistakes: ",
                .style = .{
                    .fg = .{ .index = 9 },
                    .bold = true,
                },
            },
            vaxis.Segment{ .text = score_buf },
            vaxis.Segment{ .text = "\n" },
            vaxis.Segment{
                .text = "average wpm: ",
                .style = .{
                    .fg = .{ .index = 10 },
                    .bold = true,
                    .italic = true,
                },
            },
            vaxis.Segment{ .text = wpm_buf },
        };
        _ = mistakes.print(segments, .{});
    }

    try vx.render(tty.writer());

    // Wait a bit for user input then exit
    _ = loop.nextEvent();
}
