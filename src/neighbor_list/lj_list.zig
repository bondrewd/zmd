const std = @import("std");

const Input = @import("../input.zig").Input;

const math = @import("../math.zig");
const V = math.V;

const PosFile = @import("../file.zig").PosFile;
const MolFile = @import("../file.zig").MolFile;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

pub const Pair = struct {
    i_atom: usize,
    j_atom: usize,
    i_lj: usize,
    j_lj: usize,
};

pub const LennardJonesList = struct {
    allocator: *Allocator,
    list: []Pair,
    lj_index_from_atom_index: []?usize,
    cutoff: f32,
    update_period: u32,

    const Self = @This();

    pub fn init(allocator: *Allocator, input: Input) !Self {
        // Read position file first frame
        var pos_file = PosFile.init(allocator);
        defer pos_file.deinit();
        try pos_file.openFile(input.in_pos_file, .{});
        defer pos_file.close();
        try pos_file.readData();

        // Read mol file
        var mol_file = MolFile.init(allocator);
        defer mol_file.deinit();
        try mol_file.openFile(input.in_mol_file, .{});
        defer mol_file.close();
        try mol_file.readData();

        // Allocate array
        const n_atoms = pos_file.data.frames.items[0].indexes.items.len;
        var lj_index_from_atom_index = try allocator.alloc(?usize, n_atoms);

        // Initialize array
        std.mem.set(?usize, lj_index_from_atom_index, null);
        for (pos_file.data.frames.items[0].indexes.items) |pos_index, i| {
            for (mol_file.data.properties.indexes.items) |mol_index, j| {
                if (pos_index == mol_index) {
                    lj_index_from_atom_index[i] = j;
                    break;
                }
            }
        }

        // Calculate max sigma value
        var s_max: f32 = 0.0;
        for (mol_file.data.lennard_jones.s.items) |sigma| s_max = if (sigma > s_max) sigma else s_max;

        return Self{
            .allocator = allocator,
            .list = try allocator.alloc(Pair, 0),
            .lj_index_from_atom_index = lj_index_from_atom_index,
            .cutoff = 3.0 * s_max,
            .update_period = input.neighbor_list_period,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.list);
        self.allocator.free(self.lj_index_from_atom_index);
    }

    pub fn update(self: *Self, r: []V, box: ?V) !void {
        // Deinit current list
        self.allocator.free(self.list);
        // Declare list for saving pairs
        var list = std.ArrayList(Pair).init(self.allocator);
        defer list.deinit();

        // Square of cutoff distance
        const cutoff2 = self.cutoff * self.cutoff;

        var i: usize = 0;
        while (i < system.r.items.len) : (i += 1) {
            const ri = r[i];

            var j: usize = i + 1;
            while (j < system.r.items.len) : (j += 1) {
                const rj = r[j];

                var rij = math.v.sub(ri, rj);
                if (box) |b| rij = math.wrap(rij, b);
                const rij2 = math.v.dot(rij, rij);

                if (rij2 < cutoff2) try pairs.append(.{
                    .i_atom = i,
                    .j_atom = j,
                    .i_lj = self.lj_index_from_atom_index(i),
                    .j_lj = self.lj_index_from_atom_index(j),
                });
            }
        }

        // Save neighbor list
        self.list = list.toOwnedSlice();
    }
};
