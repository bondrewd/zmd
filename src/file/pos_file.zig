const std = @import("std");

const File = std.fs.File;
const Reader = File.Reader;
const Writer = File.Writer;

const V = @import("../math.zig").V;
const MdFile = @import("md_file.zig").MdFile;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const printErrorMsg = @import("../exception.zig").printErrorMsg;

pub const Frame = struct {
    indexes: ArrayList(u32),
    positions: ArrayList(V),
    time: f32,

    const Self = @This();

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .indexes = ArrayList(u32).init(allocator),
            .positions = ArrayList(V).init(allocator),
            .time = 0.0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.indexes.deinit();
        self.positions.deinit();
    }
};

pub const Data = struct {
    frames: ArrayList(Frame),

    const Self = @This();

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .frames = ArrayList(Frame).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.frames.items) |*frame| frame.deinit();
        self.frames.deinit();
    }
};

pub const ReadDataError = error{ BadLine, OutOfMemory, MissingValue, BadValue };
pub fn readData(data: *Data, r: Reader, allocator: *Allocator) ReadDataError!void {
    // Local variables
    var buf: [1024]u8 = undefined;
    var frame: ?Frame = null;

    // Iterate over lines
    var line_id: usize = 0;
    while (r.readUntilDelimiterOrEof(&buf, '\n') catch return error.BadLine) |line| {
        // Update line number
        line_id += 1;

        // Skip comments
        if (std.mem.startsWith(u8, line, "#")) continue;

        // Skip empty lines
        if (std.mem.trim(u8, line, " ").len == 0) continue;

        // Parse time line
        if (std.mem.startsWith(u8, line, "time")) {
            // Init frame
            if (frame) |fr| data.frames.append(fr) catch return error.OutOfMemory;
            frame = Frame.init(allocator);

            // Parse time
            const time = std.mem.trim(u8, line[4..], " ");
            frame.?.time = std.fmt.parseFloat(f32, time) catch {
                printErrorMsg("Bad time value {s} in line {s}\n", .{ time, line });
                return error.BadValue;
            };
            continue;
        }

        // Tokenize line
        var tokens = std.mem.tokenize(u8, line, " ");

        // Parse index
        frame.?.indexes.append(if (tokens.next()) |token| std.fmt.parseInt(u32, token, 10) catch {
            printErrorMsg("Bad index value {s} in line {s}\n", .{ token, line });
            return error.BadValue;
        } else {
            printErrorMsg("Missing index value at line #{d} -> {s}\n", .{ line_id, line });
            return error.MissingValue;
        }) catch return error.OutOfMemory;

        // Parse positions
        const x = if (tokens.next()) |token| std.fmt.parseFloat(f32, token) catch {
            printErrorMsg("Bad x position value {s} in line {s}\n", .{ token, line });
            return error.BadValue;
        } else {
            printErrorMsg("Missing x position value at line #{d} -> {s}\n", .{ line_id, line });
            return error.MissingValue;
        };

        const y = if (tokens.next()) |token| std.fmt.parseFloat(f32, token) catch {
            printErrorMsg("Bad x position value {s} in line {s}\n", .{ token, line });
            return error.BadValue;
        } else {
            printErrorMsg("Missing x position value at line #{d} -> {s}\n", .{ line_id, line });
            return error.MissingValue;
        };

        const z = if (tokens.next()) |token| std.fmt.parseFloat(f32, token) catch {
            printErrorMsg("Bad x position value {s} in line {s}\n", .{ token, line });
            return error.BadValue;
        } else {
            printErrorMsg("Missing x position value at line #{d} -> {s}\n", .{ line_id, line });
            return error.MissingValue;
        };

        frame.?.positions.append(.{ .x = x, .y = y, .z = z }) catch return error.OutOfMemory;
    }

    if (frame) |fr| data.frames.append(fr) catch return error.OutOfMemory;
}

pub const WriteDataError = error{WriteLine};
pub fn writeFrame(frame: Frame, w: Writer) WriteDataError!void {
    // Print time
    w.print("time {d:>12.3}\n", .{frame.time}) catch return error.WriteLine;
    // Print units
    w.print("#{s:>11}  {s:>12}  {s:>12}  {s:>12}\n", .{ "index", "x", "y", "z" }) catch return error.WriteLine;
    w.print("#{s:>11}  {s:>12}  {s:>12}  {s:>12}\n", .{ "-", "nm", "nm", "nm" }) catch return error.WriteLine;
    // Print positions
    for (frame.indexes.items) |index, i| {
        w.print("{d:>12}  {d:>12.5}  {d:>12.5}  {d:>12.5}\n", .{
            index,
            frame.positions.items[i].x,
            frame.positions.items[i].y,
            frame.positions.items[i].z,
        }) catch return error.WriteLine;
    }
}

pub fn writeData(data: *Data, w: Writer, _: *Allocator) WriteDataError!void {
    // Loop over frames
    for (data.frames.items) |frame| {
        // Print frame
        try writeFrame(frame, w);
        // Print new line
        w.print("\n", .{}) catch return error.WriteLine;
    }
}

pub const PosFile = MdFile(Data, ReadDataError, readData, WriteDataError, writeData);
