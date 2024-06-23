const std = @import("std");

const Input = @import("input.zig").Input;

const Allocator = std.mem.Allocator;

const LennardJones = @import("ff/lennard_jones.zig").LennardJones;

pub const ForceField = struct {
    allocator: *Allocator,
    lennard_jones: LennardJones,

    pub const Self = @This();

    pub fn init(allocator: *Allocator, input: Input) !Self {
        return Self{
            .allocator = allocator,
            .lennard_jones = try LennardJones.init(allocator, input),
        };
    }

    pub fn deinit(self: Self) void {
        self.lennard_jones.deinit();
    }
};
