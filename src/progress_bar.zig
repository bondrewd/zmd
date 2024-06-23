const std = @import("std");

pub const ProgressBar = struct {
    writer: std.fs.File.Writer,
    fill: []const u8,
    r_sep: []const u8,
    l_sep: []const u8,
    blocks: []const []const u8,
    length: u32,
    min: usize,
    max: usize,

    const Self = @This();

    const ProgressBarConfig = struct {
        fill: ?[]const u8 = null,
        r_sep: ?[]const u8 = null,
        l_sep: ?[]const u8 = null,
        blocks: ?[]const []const u8 = null,
        length: ?u8 = null,
        min: usize,
        max: usize,
    };

    pub fn initStdOut(config: ProgressBarConfig) !Self {
        var stdout = std.io.getStdOut().writer();
        return init(stdout, config);
    }

    pub fn init(w: std.fs.File.Writer, config: ProgressBarConfig) Self {
        return .{
            .writer = w,
            .fill = config.fill orelse " ",
            .r_sep = config.r_sep orelse "|",
            .l_sep = config.r_sep orelse "|",
            .blocks = config.blocks orelse &[_][]const u8{ " ", "▏", "▎", "▍", "▌", "▋", "▊", "▉", "█" },
            .length = config.length orelse 25,
            .min = config.min,
            .max = config.max,
        };
    }

    pub fn displayProgressAllocator(self: Self, step: usize, allocator: *std.mem.Allocator) !void {
        var s = step;
        s = if (s > self.min) s else self.min;
        s = if (s < self.max) s else self.max;

        const n = @intToFloat(f32, self.blocks.len - 1);
        const p = @intToFloat(f32, s - self.min + 1) / @intToFloat(f32, self.max - self.min + 1);
        const l = p * @intToFloat(f32, self.length);
        const x = @floatToInt(u32, @floor(l));
        const y = @floatToInt(u32, @floor(n * (l - @intToFloat(f32, x))));

        // Output string
        var bar = std.ArrayList(u8).init(allocator);
        defer bar.deinit();
        var w = bar.writer();

        // Carriage return
        try w.writeByte('\r');
        // Write left part
        try w.writeAll(self.l_sep);
        // Write middle part
        var i: usize = 0;
        while (i < self.length) : (i += 1) {
            if (i < x) {
                try w.writeAll(self.blocks[self.blocks.len - 1]);
            } else if (i == x) {
                try w.writeAll(self.blocks[y]);
            } else {
                try w.writeAll(self.fill);
            }
        }
        // Write right part
        try w.writeAll(self.r_sep);
        // Write percentage
        try w.print(" {d:6.2}%", .{p * 100});
        // Print new line
        if (s == self.max) try w.writeByte('\n');
        // Flush string
        try self.writer.writeAll(bar.items);
    }

    pub fn displayProgress(self: Self, step: usize) !void {
        var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
        defer arena.deinit();
        var allocator = &arena.allocator;
        try self.displayProgressAllocator(step, allocator);
    }
};
