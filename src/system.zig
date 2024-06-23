const std = @import("std");

const Input = @import("input.zig").Input;

const math = @import("math.zig");
const V = math.V;
const M = math.M;

const PosFile = @import("file.zig").PosFile;
const MolFile = @import("file.zig").MolFile;
const XyzFile = @import("file.zig").XyzFile;
const VelFile = @import("file.zig").VelFile;

const xyzWriteFrame = @import("file/xyz_file.zig").writeFrame;
const velWriteFrame = @import("file/vel_file.zig").writeFrame;

const ForceField = @import("ff.zig").ForceField;
const NeighborList = @import("neighbor_list.zig").NeighborList;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const printErrorMsg = @import("exception.zig").printErrorMsg;

pub const Time = struct {
    current_step: u32 = 0,
    current_time: f32 = 0.0,
    dt: f32 = 0.0,

    const Self = @This();

    pub fn advance(self: *Self, steps: u32) void {
        self.current_step += steps;
        self.current_time = @intToFloat(f32, self.current_step) * self.dt;
    }
};

pub const Atoms = struct {
    allocator: *Allocator,
    indexes: []u32,
    positions: []V,
    velocities: []V,
    forces: []V,
    masses: []f32,
    charges: []f32,
    names: [][]u8,

    pub const Self = @This();

    fn order(context: void, lhs: u32, rhs: u32) std.math.Order {
        _ = context;
        return std.math.order(lhs, rhs);
    }

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

        // Check match between number pos and mol properties
        const n_pos_entries = pos_file.data.frames.items[0].indexes.items.len;
        const n_mol_entries = mol_file.data.properties.indexes.items.len;
        if (n_pos_entries > n_mol_entries) {
            printErrorMsg("The number of atoms in pos file is bigger than the number of properties in mol file\n", .{});
            return error.MissingProperties;
        } else if (n_pos_entries < n_mol_entries) {
            // warning
        }
        const n_atoms = n_pos_entries;

        // Allocate slices
        var indexes = try allocator.alloc(u32, n_atoms);
        var positions = try allocator.alloc(V, n_atoms);
        var velocities = try allocator.alloc(V, n_atoms);
        var forces = try allocator.alloc(V, n_atoms);
        var masses = try allocator.alloc(f32, n_atoms);
        var charges = try allocator.alloc(f32, n_atoms);
        var names = try allocator.alloc([]u8, n_atoms);

        // Copy information from pos file
        std.mem.copy(u32, indexes, pos_file.data.frames.items[0].indexes.items);
        std.mem.copy(V, positions, pos_file.data.frames.items[0].positions.items);

        // Copy information from mol file matching pos file order
        for (indexes) |index, i| {
            // Linear search of index in mol file
            const j = for (mol_file.data.properties.indexes.items) |mol_index, j| {
                if (index == mol_index) break j;
            } else {
                //error
                return error.NotFound;
            };
            // Set mass
            masses[i] = mol_file.data.properties.masses.items[j];
            // Set charge
            charges[i] = mol_file.data.properties.charges.items[j];
            // Set name
            const name_len = mol_file.data.properties.names.items[j].len;
            names[i] = try allocator.alloc(u8, name_len);
            std.mem.copy(u8, names[i], mol_file.data.properties.names.items[j]);
        }

        // Initialize velocities to 0
        std.mem.set(V, velocities, V.zeros());

        // Initialize forces to 0
        std.mem.set(V, forces, V.zeros());

        return Self{
            .allocator = allocator,
            .indexes = indexes,
            .positions = positions,
            .velocities = velocities,
            .forces = forces,
            .masses = masses,
            .charges = charges,
            .names = names,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.indexes);
        self.allocator.free(self.positions);
        self.allocator.free(self.velocities);
        self.allocator.free(self.forces);
        self.allocator.free(self.masses);
        self.allocator.free(self.charges);
        for (self.names) |name| self.allocator.free(name);
        self.allocator.free(self.names);
    }
};

pub const System = struct {
    allocator: *Allocator,
    ff: ForceField,
    neighbor_list: NeighborList,
    atoms: Atoms,
    time: Time,

    const Self = @This();

    pub fn init(allocator: *Allocator, input: Input) !Self {
        return Self{
            .allocator = allocator,
            .ff = try ForceField.init(allocator, input),
            .neighbor_list = try NeighborList.init(allocator, input),
            .atoms = try Atoms.init(allocator, input),
            .time = Time{},
        };
    }

    pub fn deinit(self: Self) void {
        self.ff.deinit();
        self.neighbor_list.deinit();
        self.atoms.deinit();
    }

    pub fn step(self: *Self) !void {
        self.time.advance(1);
    }
};

const testing = std.testing;
const dummyInput = @import("input.zig").dummyInput;

test "Time basic usage" {
    var time = Time{ .current_step = 10, .current_time = 5.0, .dt = 0.2 };

    time.advance(1);

    try testing.expect(time.current_step == 11);
    try testing.expect(time.current_time == 2.2);
    try testing.expect(time.dt == 0.2);

    time.advance(5);

    try testing.expect(time.current_step == 16);
    try testing.expect(time.current_time == 3.2);
    try testing.expect(time.dt == 0.2);
}

test "Atoms basic usage 1" {
    var in_pos_file = ArrayList(u8).init(testing.allocator);
    defer in_pos_file.deinit();
    try in_pos_file.appendSlice("test/unit/atoms_basic_usage_01.pos");
    var in_pos_file_name = in_pos_file.items;

    var in_mol_file = ArrayList(u8).init(testing.allocator);
    defer in_mol_file.deinit();
    try in_mol_file.appendSlice("test/unit/atoms_basic_usage_01.mol");
    var in_mol_file_name = in_mol_file.items;

    var input = dummyInput();
    input.in_pos_file = in_pos_file_name;
    input.in_mol_file = in_mol_file_name;

    var atoms = try Atoms.init(testing.allocator, input);
    defer atoms.deinit();

    // Check indexes
    try testing.expect(atoms.indexes.len == 3);
    try testing.expect(atoms.indexes[0] == 1);
    try testing.expect(atoms.indexes[1] == 2);
    try testing.expect(atoms.indexes[2] == 3);

    // Check positions
    try testing.expect(atoms.positions.len == 3);
    try testing.expect(atoms.positions[0].x == -0.5);
    try testing.expect(atoms.positions[0].y == 0.0);
    try testing.expect(atoms.positions[0].z == 0.0);

    try testing.expect(atoms.positions[1].x == 0.0);
    try testing.expect(atoms.positions[1].y == 0.0);
    try testing.expect(atoms.positions[1].z == 0.0);

    try testing.expect(atoms.positions[2].x == 0.5);
    try testing.expect(atoms.positions[2].y == 0.0);
    try testing.expect(atoms.positions[2].z == 0.0);

    // Check velocities
    try testing.expect(atoms.velocities.len == 3);
    try testing.expect(atoms.velocities[0].x == 0.0);
    try testing.expect(atoms.velocities[0].y == 0.0);
    try testing.expect(atoms.velocities[0].z == 0.0);

    try testing.expect(atoms.velocities[1].x == 0.0);
    try testing.expect(atoms.velocities[1].y == 0.0);
    try testing.expect(atoms.velocities[1].z == 0.0);

    try testing.expect(atoms.velocities[2].x == 0.0);
    try testing.expect(atoms.velocities[2].y == 0.0);
    try testing.expect(atoms.velocities[2].z == 0.0);

    // Check forces
    try testing.expect(atoms.forces.len == 3);
    try testing.expect(atoms.forces[0].x == 0.0);
    try testing.expect(atoms.forces[0].y == 0.0);
    try testing.expect(atoms.forces[0].z == 0.0);

    try testing.expect(atoms.forces[1].x == 0.0);
    try testing.expect(atoms.forces[1].y == 0.0);
    try testing.expect(atoms.forces[1].z == 0.0);

    try testing.expect(atoms.forces[2].x == 0.0);
    try testing.expect(atoms.forces[2].y == 0.0);
    try testing.expect(atoms.forces[2].z == 0.0);

    // Check masses
    try testing.expect(atoms.masses.len == 3);
    try testing.expect(atoms.masses[0] == 1.0);
    try testing.expect(atoms.masses[1] == 2.0);
    try testing.expect(atoms.masses[2] == 3.0);

    // Check charges
    try testing.expect(atoms.charges.len == 3);
    try testing.expect(atoms.charges[0] == -0.5);
    try testing.expect(atoms.charges[1] == 0.0);
    try testing.expect(atoms.charges[2] == 0.5);

    // Check charges
    try testing.expect(atoms.names.len == 3);
    try testing.expect(std.mem.eql(u8, atoms.names[0], "A1"));
    try testing.expect(std.mem.eql(u8, atoms.names[1], "B2"));
    try testing.expect(std.mem.eql(u8, atoms.names[2], "C3"));
}

test "Atoms basic usage 2" {
    var in_pos_file = ArrayList(u8).init(testing.allocator);
    defer in_pos_file.deinit();
    try in_pos_file.appendSlice("test/unit/atoms_basic_usage_02.pos");
    var in_pos_file_name = in_pos_file.items;

    var in_mol_file = ArrayList(u8).init(testing.allocator);
    defer in_mol_file.deinit();
    try in_mol_file.appendSlice("test/unit/atoms_basic_usage_02.mol");
    var in_mol_file_name = in_mol_file.items;

    var input = dummyInput();
    input.in_pos_file = in_pos_file_name;
    input.in_mol_file = in_mol_file_name;

    var atoms = try Atoms.init(testing.allocator, input);
    defer atoms.deinit();

    // Check indexes
    try testing.expect(atoms.indexes.len == 3);
    try testing.expect(atoms.indexes[0] == 20);
    try testing.expect(atoms.indexes[1] == 1);
    try testing.expect(atoms.indexes[2] == 123);

    // Check positions
    try testing.expect(atoms.positions.len == 3);
    try testing.expect(atoms.positions[0].x == -0.5);
    try testing.expect(atoms.positions[0].y == 0.0);
    try testing.expect(atoms.positions[0].z == 0.0);

    try testing.expect(atoms.positions[1].x == 0.0);
    try testing.expect(atoms.positions[1].y == 0.0);
    try testing.expect(atoms.positions[1].z == 0.0);

    try testing.expect(atoms.positions[2].x == 0.5);
    try testing.expect(atoms.positions[2].y == 0.0);
    try testing.expect(atoms.positions[2].z == 0.0);

    // Check velocities
    try testing.expect(atoms.velocities.len == 3);
    try testing.expect(atoms.velocities[0].x == 0.0);
    try testing.expect(atoms.velocities[0].y == 0.0);
    try testing.expect(atoms.velocities[0].z == 0.0);

    try testing.expect(atoms.velocities[1].x == 0.0);
    try testing.expect(atoms.velocities[1].y == 0.0);
    try testing.expect(atoms.velocities[1].z == 0.0);

    try testing.expect(atoms.velocities[2].x == 0.0);
    try testing.expect(atoms.velocities[2].y == 0.0);
    try testing.expect(atoms.velocities[2].z == 0.0);

    // Check forces
    try testing.expect(atoms.forces.len == 3);
    try testing.expect(atoms.forces[0].x == 0.0);
    try testing.expect(atoms.forces[0].y == 0.0);
    try testing.expect(atoms.forces[0].z == 0.0);

    try testing.expect(atoms.forces[1].x == 0.0);
    try testing.expect(atoms.forces[1].y == 0.0);
    try testing.expect(atoms.forces[1].z == 0.0);

    try testing.expect(atoms.forces[2].x == 0.0);
    try testing.expect(atoms.forces[2].y == 0.0);
    try testing.expect(atoms.forces[2].z == 0.0);

    // Check masses
    try testing.expect(atoms.masses.len == 3);
    try testing.expect(atoms.masses[0] == 2.0);
    try testing.expect(atoms.masses[1] == 3.0);
    try testing.expect(atoms.masses[2] == 1.0);

    // Check charges
    try testing.expect(atoms.charges.len == 3);
    try testing.expect(atoms.charges[0] == 0.0);
    try testing.expect(atoms.charges[1] == 0.5);
    try testing.expect(atoms.charges[2] == -0.5);

    // Check charges
    try testing.expect(atoms.names.len == 3);
    try testing.expect(std.mem.eql(u8, atoms.names[0], "B2"));
    try testing.expect(std.mem.eql(u8, atoms.names[1], "C3"));
    try testing.expect(std.mem.eql(u8, atoms.names[2], "A1"));
}
