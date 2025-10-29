const std = @import("std");
const clap = @import("clap");
const vaxis = @import("vaxis");
const vxfw = vaxis.vxfw;
const cli_args = @import("args.zig");
const scene = @import("scene.zig");
const action = @import("action.zig");

const now = @import("time.zig").now;
const parseArgs = cli_args.parseArgs;
const Args = cli_args.Args;

/// What frame of the game are we on
frame: u64 = 0,
/// Current scene of the game
current_scene: scene.Scene = .{ .menu = .{} },

pub fn render(
    self: *const @This(),
    win: vaxis.Window,
) void {
    switch (self.current_scene) {
        .menu => |menu_scene| menu_scene.render(win),
        .timegame => |*timegame| timegame.render(win),
    }
}

/// Returns whether we should quit
pub fn processKeyPress(
    self: *@This(),
    alloc: std.mem.Allocator,
    key: vaxis.Key,
    codepoint_limit: u16,
    args: *Args,
) error{OutOfMemory}!enum { redraw, should_quit } {
    const menuEvent = action.MenuAction.processKeydown;
    const gameEvent = action.InGameAction.processKeydown;

    switch (self.current_scene) {
        .menu => |*menu| switch (menuEvent(key)) {
            .none => {},
            .quit => return .should_quit,
            .move_up => menu.moveSelectionUp(),
            .move_down => menu.moveSelectionDown(),
            .select => {
                const test_duration_ns: u64 = switch (menu.selection) {
                    .Exit => return .should_quit,
                    .Time15 => 15 * 1e9,
                    .Time30 => 30 * 1e9,
                    .Time60 => 60 * 1e9,
                    .Time120 => 120 * 1e9,
                };

                self.current_scene = .{
                    .timegame = try .init(
                        alloc,
                        test_duration_ns,
                        codepoint_limit,
                        &args.words,
                    ),
                };
            },
        },
        .timegame => |*timegame| switch (gameEvent(key)) {
            .none => {},
            .exit_game => {
                timegame.deinit(alloc);
                self.current_scene = .{ .menu = .{} };
            },
            .new_random_game => {
                try timegame.newGame(
                    alloc,
                    timegame.test_duration_ns,
                    codepoint_limit,
                    &args.words,
                );
            },
            .undo_key_press => timegame.processUndo(),
            .key_press => |codepoint| {
                try timegame.processKeyPress(
                    alloc,
                    &args.words,
                    codepoint_limit,
                    codepoint,
                );
            },
        },
    }

    return .redraw;
}

pub fn deinit(self: *@This(), alloc: std.mem.Allocator) void {
    switch (self.current_scene) {
        .menu => {},
        .timegame => |*timegame| timegame.deinit(alloc),
    }
}
