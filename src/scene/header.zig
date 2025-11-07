const std = @import("std");
const vaxis = @import("vaxis");
const character_style = @import("../character_style.zig");
const super = @import("../scene.zig");

const newline = '\n';

/// A bunch of ascii art headers sorted from least wide to most wide
///
/// You must call the `comptimeChecks` method to make sure that I haven't fucked shit up
pub const Header = enum {
    rebel,
    shadow,
    bloody,
    fire,
    paga,
    calvin,
    templar,

    /// Prints the header in the center of the window
    pub fn render(
        self: Header,
        window: vaxis.Window,
        frame_counter: u64,
        animate_cycle_len: u64,
    ) void {
        const col_offset = (window.width -| self.width()) / 2;
        var row_offset: u16 = (window.height -| self.height()) / 2;

        var iter = std.mem.splitScalar(u8, self.art(), newline);

        const split_after = (self.width() * (frame_counter % animate_cycle_len)) / animate_cycle_len;
        std.debug.assert(split_after < self.width());

        while (iter.next()) |line| {
            defer row_offset += 1;

            var idx: usize = 0;
            std.debug.assert(std.unicode.utf8ValidateSlice(line));
            var utf8_iter = std.unicode.Utf8View.initUnchecked(line).iterator();
            find_split: while (utf8_iter.nextCodepointSlice() != null) : (idx += 1) {
                if (idx > split_after) break :find_split;
            }

            _ = window.print(&.{
                .{
                    .text = line[0..utf8_iter.i],
                    .style = character_style.header_style1,
                },
                .{
                    .text = line[utf8_iter.i..],
                    .style = character_style.header_style2,
                },
            }, .{
                .wrap = .none,
                .row_offset = row_offset,
                .col_offset = col_offset,
            });
        }
    }

    pub fn art(self: Header) []const u8 {
        return switch (self) {
            .rebel =>
            \\ ███████████ █████ █████ ███████████  ██████████ ███████████ ██████████  █████████  ███████████
            \\▒█▒▒▒███▒▒▒█▒▒███ ▒▒███ ▒▒███▒▒▒▒▒███▒▒███▒▒▒▒▒█▒█▒▒▒███▒▒▒█▒▒███▒▒▒▒▒█ ███▒▒▒▒▒███▒█▒▒▒███▒▒▒█
            \\▒   ▒███  ▒  ▒▒███ ███   ▒███    ▒███ ▒███  █ ▒ ▒   ▒███  ▒  ▒███  █ ▒ ▒███    ▒▒▒ ▒   ▒███  ▒ 
            \\    ▒███      ▒▒█████    ▒██████████  ▒██████       ▒███     ▒██████   ▒▒█████████     ▒███    
            \\    ▒███       ▒▒███     ▒███▒▒▒▒▒▒   ▒███▒▒█       ▒███     ▒███▒▒█    ▒▒▒▒▒▒▒▒███    ▒███    
            \\    ▒███        ▒███     ▒███         ▒███ ▒   █    ▒███     ▒███ ▒   █ ███    ▒███    ▒███    
            \\    █████       █████    █████        ██████████    █████    ██████████▒▒█████████     █████   
            \\   ▒▒▒▒▒       ▒▒▒▒▒    ▒▒▒▒▒        ▒▒▒▒▒▒▒▒▒▒    ▒▒▒▒▒    ▒▒▒▒▒▒▒▒▒▒  ▒▒▒▒▒▒▒▒▒     ▒▒▒▒▒    
            ,

            .shadow =>
            \\████████╗██╗   ██╗██████╗ ███████╗████████╗███████╗███████╗████████╗
            \\╚══██╔══╝╚██╗ ██╔╝██╔══██╗██╔════╝╚══██╔══╝██╔════╝██╔════╝╚══██╔══╝
            \\   ██║    ╚████╔╝ ██████╔╝█████╗     ██║   █████╗  ███████╗   ██║   
            \\   ██║     ╚██╔╝  ██╔═══╝ ██╔══╝     ██║   ██╔══╝  ╚════██║   ██║   
            \\   ██║      ██║   ██║     ███████╗   ██║   ███████╗███████║   ██║   
            \\   ╚═╝      ╚═╝   ╚═╝     ╚══════╝   ╚═╝   ╚══════╝╚══════╝   ╚═╝   
            ,

            .bloody =>
            \\▄▄▄█████▓▓██   ██▓ ██▓███  ▓█████▄▄▄█████▓▓█████   ██████ ▄▄▄█████▓
            \\▓  ██▒ ▓▒ ▒██  ██▒▓██░  ██▒▓█   ▀▓  ██▒ ▓▒▓█   ▀ ▒██    ▒ ▓  ██▒ ▓▒
            \\▒ ▓██░ ▒░  ▒██ ██░▓██░ ██▓▒▒███  ▒ ▓██░ ▒░▒███   ░ ▓██▄   ▒ ▓██░ ▒░
            \\░ ▓██▓ ░   ░ ▐██▓░▒██▄█▓▒ ▒▒▓█  ▄░ ▓██▓ ░ ▒▓█  ▄   ▒   ██▒░ ▓██▓ ░ 
            \\  ▒██▒ ░   ░ ██▒▓░▒██▒ ░  ░░▒████▒ ▒██▒ ░ ░▒████▒▒██████▒▒  ▒██▒ ░ 
            \\  ▒ ░░      ██▒▒▒ ▒▓▒░ ░  ░░░ ▒░ ░ ▒ ░░   ░░ ▒░ ░▒ ▒▓▒ ▒ ░  ▒ ░░   
            \\    ░     ▓██ ░▒░ ░▒ ░      ░ ░  ░   ░     ░ ░  ░░ ░▒  ░ ░    ░    
            \\  ░       ▒ ▒ ░░  ░░          ░    ░         ░   ░  ░  ░    ░      
            \\          ░ ░                 ░  ░           ░  ░      ░           
            \\          ░ ░                                                      
            ,

            .fire =>
            \\            )  (                     (           
            \\  *   )  ( /(  )\ )       *   )      )\ )  *   ) 
            \\` )  /(  )\())(()/( (   ` )  /( (   (()/(` )  /( 
            \\ ( )(_))((_)\  /(_)))\   ( )(_)))\   /(_))( )(_))
            \\(_(_())__ ((_)(_)) ((_) (_(_())((_) (_)) (_(_()) 
            \\|_   _|\ \ / /| _ \| __||_   _|| __|/ __||_   _| 
            \\  | |   \ V / |  _/| _|   | |  | _| \__ \  | |   
            \\  |_|    |_|  |_|  |___|  |_|  |___||___/  |_|   
            ,

            .paga =>
            \\░▀█▀░█░█░█▀█░█▀▀░▀█▀░█▀▀░█▀▀░▀█▀
            \\░░█░░░█░░█▀▀░█▀▀░░█░░█▀▀░▀▀█░░█░
            \\░░▀░░░▀░░▀░░░▀▀▀░░▀░░▀▀▀░▀▀▀░░▀░
            ,

            .calvin =>
            \\╔╦╗╦ ╦╔═╗╔═╗╔╦╗╔═╗╔═╗╔╦╗
            \\ ║ ╚╦╝╠═╝║╣  ║ ║╣ ╚═╗ ║ 
            \\ ╩  ╩ ╩  ╚═╝ ╩ ╚═╝╚═╝ ╩ 
            ,

            .templar =>
            \\┏┳┓┓┏┏┓┏┓┏┳┓┏┓┏┓┏┳┓
            \\ ┃ ┗┫┃┃┣  ┃ ┣ ┗┓ ┃ 
            \\ ┻ ┗┛┣┛┗┛ ┻ ┗┛┗┛ ┻ 
            ,
        };
    }

    /// The width of the art
    pub fn width(self: Header) u16 {
        return switch (self) {
            inline else => |header| comptime strWidth(header.art()),
        };
    }

    /// The height of the art
    pub fn height(self: Header) u16 {
        return switch (self) {
            inline else => |header| comptime strHeight(header.art()),
        };
    }

    pub fn comptimeChecks() void {
        comptime inWidthOrder();

        inline for (0..@typeInfo(Header).@"enum".fields.len) |i| {
            const header: Header = comptime @enumFromInt(i);
            comptime {
                if (!allLinesEqualLength(header.art())) {
                    @compileError("malformed string input for " ++ @typeInfo(Header).@"enum".fields[i].name);
                }
            }
        }
    }
};

const view = std.unicode.Utf8View.initComptime;

/// Checks that they are in order biggest to smallest
fn inWidthOrder() void {
    const fields = @typeInfo(Header).@"enum".fields;
    const COUNT = fields.len;
    if (COUNT <= 1) return true;

    var current: usize = 0;

    while (current < COUNT - 1) {
        const next = current + 1;
        defer current = next;

        if (@as(Header, @enumFromInt(next)).width() >
            @as(Header, @enumFromInt(current)).width())
        {
            @compileError("The width of " ++ fields[next].name ++ " is greater than " ++ fields[current].name ++ " which is illegal.");
        }
    }
}

fn strWidth(comptime str: []const u8) u16 {
    var iter = view(str).iterator();
    var len = 0;

    @setEvalBranchQuota(100_000);
    while (iter.nextCodepointSlice()) |slice| : (len += 1) {
        if (slice[0] == newline) return len;
    }

    return len;
}

fn strHeight(str: []const u8) u16 {
    var iter = std.mem.splitScalar(u8, str, newline);
    var height = 0;

    @setEvalBranchQuota(10000);
    while (iter.next() != null) : (height += 1) {}
    return height;
}

fn allLinesEqualLength(comptime str: []const u8) bool {
    var iter = std.mem.splitScalar(u8, str, newline);
    var line_len: ?usize = null;

    @setEvalBranchQuota(15000);
    while (iter.next()) |line| {
        var len = 0;
        var utf8_iter = view(line).iterator();
        while (utf8_iter.nextCodepointSlice() != null) : (len += 1) {}

        if (line_len) |prev_line_len| {
            if (prev_line_len != len) return false;
        } else {
            line_len = len;
        }
    }

    return true;
}
