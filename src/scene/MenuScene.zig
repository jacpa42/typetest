const std = @import("std");
const vaxis = @import("vaxis");
const super = @import("../scene.zig");
const layout = @import("window_layout.zig");

const MenuScene = @This();

selection: SuperMenu = .{ .main_menu = .default },

/// Clears screen and renders the current state
pub fn render(
    self: *const MenuScene,
    data: super.RenderData,
) error{WindowTooSmall}!void {
    const main_window = try layout.gameWindow(data.root_window);

    switch (self.selection) {
        .main_menu => |menu| renderMenu(MainMenu, menu, main_window),
        .time_game_menu => |menu| renderMenu(TimeGameMenu, menu, main_window),
        .word_game_menu => |menu| renderMenu(WordGameMenu, menu, main_window),
    }
}

pub fn moveSelection(
    self: *MenuScene,
    comptime dir: Direction,
) void {
    switch (self.selection) {
        .main_menu => |*sel| sel.* = moveInnnerSelection(MainMenu, sel.*, dir),
        .time_game_menu => |*sel| sel.* = moveInnnerSelection(TimeGameMenu, sel.*, dir),
        .word_game_menu => |*sel| sel.* = moveInnnerSelection(WordGameMenu, sel.*, dir),
    }
}

fn renderMenu(
    comptime Menu: type,
    selection: Menu,
    game_window: vaxis.Window,
) void {
    const info = @typeInfo(Menu).@"enum";
    const COUNT = info.fields.len;

    const SegmentWithOffset = struct { seg: vaxis.Segment, num_codepoints: u16 };
    var menu_item_segment_offsets: [COUNT]SegmentWithOffset = comptime blk: {
        var segments: [COUNT]SegmentWithOffset = undefined;
        for (0.., &segments) |idx, *seg| {
            const menu_item: Menu = @enumFromInt(idx);
            const text = menu_item.displayName();
            seg.seg = .{
                .text = text,
                .style = .{},
            };

            seg.num_codepoints = std.unicode.utf8CountCodepoints(text) catch
                @compileError("display name is not utf8 encoded");
        }
        break :blk segments;
    };

    const list_item_window = layout.menuListItems(Menu, game_window);

    menu_item_segment_offsets[@intFromEnum(selection)].seg.style = .{
        .bg = .{ .index = 1 },
    };

    for (menu_item_segment_offsets, 0..) |segment_offset, row| {
        std.debug.assert(list_item_window.width >= segment_offset.num_codepoints);

        const opts = vaxis.Window.PrintOptions{
            .row_offset = @truncate(row),
            .col_offset = (list_item_window.width -| segment_offset.num_codepoints) / 2,
            .wrap = .none,
        };

        _ = list_item_window.printSegment(segment_offset.seg, opts);
    }
}

fn moveInnnerSelection(
    Menu: type,
    selection: Menu,
    comptime dir: Direction,
) @TypeOf(selection) {
    if (@typeInfo(Menu) != .@"enum") @compileError("cannot move non enum selection");

    const count = comptime @typeInfo(Menu).@"enum".fields.len;
    if (count == 0) @compileError("menu enum cannot be empty");

    const delta = comptime switch (dir) {
        .up => count - 1,
        .down => 1,
    };

    return @enumFromInt((@intFromEnum(selection) + delta) % count);
}

pub const Direction = enum { up, down };

pub const SuperMenu = union(enum) {
    main_menu: MainMenu,
    time_game_menu: TimeGameMenu,
    word_game_menu: WordGameMenu,
};

pub const MainMenu = enum {
    time,
    word,
    exit,

    pub const default: MainMenu = @enumFromInt(0);

    pub fn displayName(self: MainMenu) []const u8 {
        return switch (self) {
            .exit => "quit",
            .time => "time",
            .word => "words",
        };
    }
};

pub const TimeGameMenu = enum {
    time15,
    time30,
    time60,
    time120,

    pub const default: TimeGameMenu = @enumFromInt(0);

    pub fn displayName(self: TimeGameMenu) []const u8 {
        return switch (self) {
            .time15 => "  15s",
            .time30 => "  30s",
            .time60 => "  60s",
            .time120 => " 120s",
        };
    }
};

pub const WordGameMenu = enum {
    words10,
    words25,
    words50,
    words100,

    pub const default: WordGameMenu = @enumFromInt(0);

    pub fn displayName(self: WordGameMenu) []const u8 {
        return switch (self) {
            .words10 => "󰼭  10",
            .words25 => "󰼭  25",
            .words50 => "󰼭  50",
            .words100 => "󰼭 100",
        };
    }
};
