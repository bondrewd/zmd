const std = @import("std");

const File = std.fs.File;
const Reader = File.Reader;
const Writer = File.Writer;

const V = @import("../math.zig").V;
const MdFile = @import("md_file.zig").MdFile;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const printErrorMsg = @import("../exception.zig").printErrorMsg;
const elementFromString = @import("../constant.zig").elementFromString;

pub const Frame = struct {
    n_atoms: u32,
    names: ArrayList([]u8),
    pos: ArrayList(V),

    const Self = @This();

    pub fn init(allocator: *Allocator) Self {
        return Self{
            .n_atoms = 0,
            .element = ArrayList([]u8).init(allocator),
            .pos = ArrayList(V).init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.names.items) |name| self.names.allocator.free(name);
        self.names.deinit();
        self.pos.deinit();
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
    // State
    const State = enum { NumberOfAtoms, Comment, Positions };
    var state: State = .NumberOfAtoms;

    // Local variables
    var buf: [1024]u8 = undefined;
    var frame: ?Frame = null;

    // Iterate over lines
    var line_id: usize = 0;
    while (r.readUntilDelimiterOrEof(&buf, '\n') catch return error.BadLine) |line| {
        // Update line number
        line_id += 1;

        // Skip empty lines
        if (state == .NumberOfAtoms and std.mem.trim(u8, line, " ").len == 0) continue;

        switch (state) {
            // Parse number of atoms
            .NumberOfAtoms => {
                // Init frame
                if (frame) |fr| data.frames.append(fr) catch return error.OutOfMemory;
                frame = Frame.init(allocator);

                // Parse number
                const n_atoms = std.mem.trim(u8, line, " ");
                frame.?.n_atoms = std.fmt.parseInt(u32, n_atoms, 10) catch {
                    printErrorMsg("Bad number of atoms value {s} in line {s}\n", .{ n_atoms, line });
                    return error.BadValue;
                };

                // Update state
                state = .Comment;
                continue;
            },
            // Ignore comment
            .Comment => {
                // Update state
                state = .Positions;
                continue;
            },
            // Parse positions
            .Positions => {
                // Tokenize line
                var tokens = std.mem.tokenize(u8, line, " ");

                // Parse element
                const name = if (tokens.next()) |token| token else {
                    printErrorMsg("Missing atom name at line #{d} -> {s}\n", .{ line_id, line });
                    return error.MissingValue;
                };
                frame.?.element.append(blk: {
                    var list = ArrayList(u8).init(allocator);
                    defer list.deinit();
                    list.appendSlice(name) catch return error.OutOfMemory;
                    break :blk list.toOwnedSlice();
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

                // Update state
                state = .NumberOfAtoms;
                frame.?.pos.append(.{ .x = x, .y = y, .z = z }) catch return error.OutOfMemory;
                continue;
            },
        }
    }

    if (frame) |fr| data.frames.append(fr) catch return error.OutOfMemory;
}

pub const WriteDataError = error{WriteLine};
pub fn writeFrame(frame: Frame, w: Writer) WriteDataError!void {
    // Print time
    w.print("{d}\n", .{frame.n_atoms}) catch return error.WriteLine;
    // Print comment
    w.print("\n", .{}) catch return error.WriteLine;
    // Print positions
    for (frame.element.items) |e, i| {
        w.print("{s:<12}  {d:>12.5}  {d:>12.5}  {d:>12.5}\n", .{
            e.toString(),
            frame.pos.items[i].x,
            frame.pos.items[i].y,
            frame.pos.items[i].z,
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

pub const XyzFile = MdFile(Data, ReadDataError, readData, WriteDataError, writeData);
