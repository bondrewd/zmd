const std = @import("std");
const red = @import("ansi.zig").red;
const bold = @import("ansi.zig").bold;
const reset = @import("ansi.zig").reset;
const yellow = @import("ansi.zig").yellow;

pub fn printWarningMsg(comptime warning_msg: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.writeAll(bold ++ yellow ++ "WARNING: " ++ reset) catch unreachable;
    stderr.print(warning_msg, args) catch unreachable;
}

pub fn printErrorMsg(comptime error_msg: []const u8, args: anytype) void {
    const stderr = std.io.getStdErr().writer();
    stderr.writeAll(bold ++ red ++ "ERROR: " ++ reset) catch unreachable;
    stderr.print(error_msg, args) catch unreachable;
}

pub fn stopWithErrorMsg(comptime error_msg: []const u8, args: anytype) void {
    printErrorMsg(error_msg, args) catch unreachable;
    std.os.exit(0);
}
