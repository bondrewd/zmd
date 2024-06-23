const std = @import("std");
const System = @import("../system.zig").System;
const Input = @import("../input.zig").MdInputFileParserResult;
const stopWithErrorMsg = @import("../exception.zig").stopWithErrorMsg;

const TsFileData = struct {};

pub const TsFile = struct {
    allocator: *std.mem.Allocator = undefined,
    writer: ?std.fs.File.Writer = undefined,
    reader: ?std.fs.File.Reader = undefined,
    file: ?std.fs.File = undefined,
    data: TsFileData = undefined,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator) Self {
        return Self{
            .allocator = allocator,
            .data = .{},
        };
    }

    pub fn deinit(_: Self) void {}

    pub fn openFile(self: *Self, file_name: []const u8, flags: std.fs.File.OpenFlags) !void {
        var file = try std.fs.cwd().openFile(file_name, flags);
        self.file = file;
        if (flags.read) self.reader = file.reader();
        if (flags.write) self.writer = file.writer();
    }

    pub fn createFile(self: *Self, file_name: []const u8, flags: std.fs.File.CreateFlags) !void {
        var file = try std.fs.cwd().createFile(file_name, flags);
        self.file = file;
        if (flags.read) self.reader = file.reader();
        self.writer = file.writer();
    }

    pub fn printDataHeader(self: Self) !void {
        // Get writer
        var w = if (self.writer) |w| w else {
            stopWithErrorMsg("Can't print ts file before open or create one", .{});
            unreachable;
        };

        // Print header
        try w.print("#{s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12} {s:>12}\n", .{
            "step",
            "time",
            "temperature",
            "kinetic",
            "potential",
            "total",
            "pressure",
            "px",
            "py",
            "pz",
        });
    }

    pub fn printDataFromSystem(self: Self, system: *System) !void {
        // Get writer
        var w = if (self.writer) |w| w else {
            stopWithErrorMsg("Can't print ts file before open or create one", .{});
            unreachable;
        };

        // Print data
        try w.print(" {d:>12} {d:>12.3} {d:>12.5} {e:>12.5} {e:>12.5} {e:>12.5} {e:>12.5} {e:>12.5} {e:>12.5} {e:>12.5}\n", .{
            system.current_step,
            @intToFloat(f32, system.current_step) * system.integrator.dt,
            system.temperature,
            system.energy.kinetic,
            system.energy.potential,
            system.energy.kinetic + system.energy.potential,
            (system.pressure.xx + system.pressure.yy + system.pressure.zz) / 3.0,
            system.pressure.xx,
            system.pressure.yy,
            system.pressure.zz,
        });
    }
};
