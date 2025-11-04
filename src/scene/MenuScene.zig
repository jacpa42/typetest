const std = @import("std");
const vaxis = @import("vaxis");
const super = @import("../scene.zig");
const layout = @import("window_layout.zig");
const Header = @import("header.zig").Header;

const MenuScene = @This();

selection: SuperMenu = .{ .main_menu = .default },

/// Clears screen and renders the current state
pub fn render(
    self: *const MenuScene,
    data: super.RenderData,
) error{EmptyLineNotAllowed}!void {
    comptime Header.comptimeChecks();

    switch (self.selection) {
        .main_menu => |main_menu| {
            for (0..@typeInfo(Header).@"enum".fields.len) |i| {
                const largest_header: Header = @enumFromInt(i);

                const title_menu = layout.headerWindow(
                    data.root_window,
                    largest_header,
                ) catch continue;

                largest_header.render(
                    title_menu,
                    data.frame_counter,
                    data.animation_duration,
                );

                const main_menu_window = data.root_window.child(.{
                    .width = data.root_window.width,
                    .height = data.root_window.height -| title_menu.height,
                    .y_off = title_menu.height,
                });

                return renderMenu(MainMenu, main_menu, main_menu_window);
            }

            renderMenu(
                MainMenu,
                main_menu,
                try layout.gameWindow(
                    data.root_window,
                    data.words.max_codepoints,
                ),
            );
        },
        .time_game_menu => |time_game_menu| renderMenu(
            TimeGameMenu,
            time_game_menu,
            try layout.gameWindow(
                data.root_window,
                data.words.max_codepoints,
            ),
        ),
        .word_game_menu => |word_game_menu| renderMenu(
            WordGameMenu,
            word_game_menu,
            try layout.gameWindow(
                data.root_window,
                data.words.max_codepoints,
            ),
        ),
    }
}

pub fn moveSelection(
    self: *MenuScene,
    comptime dir: Direction,
) void {
    switch (self.selection) {
        .main_menu => |*sel| sel.* = moveInnerSelection(MainMenu, sel.*, dir),
        .time_game_menu => |*sel| sel.* = moveInnerSelection(TimeGameMenu, sel.*, dir),
        .word_game_menu => |*sel| sel.* = moveInnerSelection(WordGameMenu, sel.*, dir),
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

    for (menu_item_segment_offsets, 0..) |segment_offset, row_offset| {
        std.debug.assert(list_item_window.width >= segment_offset.num_codepoints);

        const opts = vaxis.Window.PrintOptions{
            .row_offset = @truncate(row_offset),
            .col_offset = (list_item_window.width -| segment_offset.num_codepoints) / 2,
            .wrap = .none,
        };

        _ = list_item_window.printSegment(segment_offset.seg, opts);
    }
}

pub const Direction = enum { up, down };

fn moveInnerSelection(
    InnerMenu: type,
    selection: InnerMenu,
    comptime dir: Direction,
) InnerMenu {
    if (@typeInfo(InnerMenu) != .@"enum") @compileError("cannot move non enum selection");

    const COUNT = @typeInfo(InnerMenu).@"enum".fields.len;
    std.debug.assert(COUNT > 0);
    const delta = comptime switch (dir) {
        .up => COUNT - 1,
        .down => 1,
    };

    const value: usize = (@as(u32, @intFromEnum(selection)) + delta) % COUNT;
    std.debug.assert(value < COUNT);
    return @enumFromInt(value);
}

pub const SuperMenu = union(enum) {
    main_menu: MainMenu,
    time_game_menu: TimeGameMenu,
    word_game_menu: WordGameMenu,
};

pub const MainMenu = enum {
    time,
    word,

    pub const default: MainMenu = @enumFromInt(0);

    pub fn displayName(self: MainMenu) []const u8 {
        return switch (self) {
            .time => "time",
            .word => "word",
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
