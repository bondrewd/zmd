const std = @import("std");

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const System = @import("system.zig").System;

const PosFile = @import("file.zig").PosFile;
const VelFile = @import("file.zig").VelFile;
const XyzFile = @import("file.zig").XyzFile;
//const CsvFile = @import("file.zig").CsvFile;

const posWriteFrame = @import("file.zig").posWriteFrame;
const xyzWriteFrame = @import("file.zig").xyzWriteFrame;
const velWriteFrame = @import("file.zig").velWriteFrame;
//const csvWriteFrame = @import("file.zig").csvWriteFrame;

pub const FileType = enum {
    pos,
    vel,
    xyz,
    //csv,
};

pub const MdFile = union(enum) {
    pos_file: PosFile,
    vel_file: VelFile,
    xyz_file: XyzFile,
};

pub const Reporter = struct {
    allocator: *Allocator,
    system: *System,
    md_files: ArrayList(MdFile),
    output_freqs: ArrayList(u32),

    const Self = @This();

    pub fn init(allocator: *Allocator, system: *System) Self {
        return .{
            .allocator = allocator,
            .system = system,
            .md_files = ArrayList(MdFile).init(allocator),
            .output_freqs = ArrayList(u32).init(allocator),
        };
    }

    pub fn deinit(self: Self) void {
        var i: usize = 0;
        while (i < self.md_files.items.len) : (i += 1) {
            switch (self.md_files.items[i]) {
                .pos_file => |*file| file.deinit(),
                .xyz_file => |*file| file.deinit(),
                .vel_file => |*file| file.deinit(),
            }
        }
        self.md_files.deinit();
        self.output_freqs.deinit();
    }

    pub fn addProbe(self: *Self, file_name: []const u8, file_type: FileType, freq: u32) !void {
        // Create file
        var md_file = switch (file_type) {
            .pos => blk: {
                var pos_file = PosFile.init(self.allocator);
                try pos_file.createFile(file_name, .{});
                break :blk MdFile{ .pos_file = pos_file };
            },
            .xyz => blk: {
                var xyz_file = XyzFile.init(self.allocator);
                try xyz_file.createFile(file_name, .{});
                break :blk MdFile{ .xyz_file = xyz_file };
            },
            .vel => blk: {
                var vel_file = VelFile.init(self.allocator);
                try vel_file.createFile(file_name, .{});
                break :blk MdFile{ .vel_file = vel_file };
            },
        };
        // Add probe
        try self.md_files.append(md_file);
        try self.output_freqs.append(freq);
    }

    pub fn report(self: Self) !void {
        const step = self.system.current_step;
        for (self.md_files.items) |file, i| {
            const freq = self.output_freqs.items[i];
            if (step > 0 and step % freq != 0) continue;

            switch (file) {
                .pos_file => |f| try posWriteFrame(
                    .{
                        .indexes = self.system.id,
                        .positions = self.system.r,
                        .time = @intToFloat(f32, step) * self.system.integrator.dt,
                    },
                    f.file.writer(),
                ),
                .xyz_file => |f| try xyzWriteFrame(
                    .{
                        .n_atoms = @intCast(u32, self.system.id.items.len),
                        .element = self.system.e,
                        .pos = self.system.r,
                    },
                    f.file.writer(),
                ),
                .vel_file => |f| try velWriteFrame(
                    .{
                        .id = self.system.id,
                        .vel = self.system.v,
                        .time = @intToFloat(f32, step) * self.system.integrator.dt,
                    },
                    f.file.writer(),
                ),
            }
        }
    }
};
