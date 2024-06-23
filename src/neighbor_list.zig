const std = @import("std");

const Input = @import("input.zig").Input;

const LennardJonesList = @import("neighbor_list/lj_list.zig").LennardJonesList;

const Allocator = std.mem.Allocator;

const V = @import("math/v.zig").V;

pub const NeighborList = struct {
    lj_list: LennardJonesList,

    const Self = @This();

    pub fn init(allocator: *Allocator, input: Input) !Self {
        return Self{
            .lj_list = try LennardJonesList.init(allocator, input),
        };
    }

    pub fn deinit(self: Self) void {
        self.lj_list.deinit();
    }

    pub fn update(self: *Self, r: []V, box: ?V) !void {
        try self.lj_list.update(r, box);
    }
};
