const std = @import("std");

const fs = std.fs;
const cwd = fs.cwd;

const File = std.fs.File;
const Reader = File.Reader;
const Writer = File.Writer;
const OpenFlags = File.OpenFlags;
const CreateFlags = File.CreateFlags;

const Allocator = std.mem.Allocator;

pub fn MdFile(
    comptime Data: type,
    comptime ReadDataError: type,
    comptime readDataFn: fn (data: *Data, r: Reader, allocator: *Allocator) ReadDataError!void,
    comptime WriteDataError: type,
    comptime writeDataFn: fn (data: *Data, w: Writer, allocator: *Allocator) WriteDataError!void,
) type {
    return struct {
        data: Data,
        allocator: *Allocator,
        file: File = undefined,

        const Self = @This();

        pub fn init(allocator: *Allocator) Self {
            return Self{
                .data = Data.init(allocator),
                .allocator = allocator,
            };
        }

        pub fn deinit(self: *Self) void {
            self.data.deinit();
        }

        pub fn close(self: *Self) void {
            self.file.close();
        }

        pub fn readData(self: *Self) ReadDataError!void {
            try readDataFn(&self.data, self.file.reader(), self.allocator);
        }

        pub fn writeData(self: *Self) WriteDataError!void {
            try writeDataFn(&self.data, self.file.writer(), self.allocator);
        }

        pub fn openFile(self: *Self, file_name: []const u8, flags: OpenFlags) !void {
            self.file = try cwd().openFile(file_name, flags);
        }

        pub fn createFile(self: *Self, file_name: []const u8, flags: CreateFlags) !void {
            self.file = try cwd().createFile(file_name, flags);
        }
    };
}
