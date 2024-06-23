const std = @import("std");

const ArrayList = std.ArrayList;

const math = @import("math.zig");
const V = math.V;
const M = math.M;

const kb = @import("constant.zig").kb;
const Element = @import("constant.zig").Element;
const Real = @import("config.zig").Real;
const TsFile = @import("file.zig").TsFile;
const XyzFile = @import("file.zig").XyzFile;
const xyzWriteFrame = @import("file/xyz_file.zig").writeFrame;
const PosFile = @import("file.zig").PosFile;
const MolFile = @import("file.zig").MolFile;
const VelFile = @import("file.zig").VelFile;
const velWriteFrame = @import("file/vel_file.zig").writeFrame;
const ForceField = @import("ff.zig").ForceField;
const Integrator = @import("integrator.zig").Integrator;
const Input = @import("input.zig").MdInputFileParserResult;
const NeighborList = @import("neighbor_list.zig").NeighborList;
const stopWithErrorMsg = @import("exception.zig").stopWithErrorMsg;

const LennardJonesParameters = @import("ff.zig").LennardJonesParameters;
const lennardJonesForceInteraction = @import("interaction.zig").lennardJonesForceInteraction;
const lennardJonesEnergyInteraction = @import("interaction.zig").lennardJonesEnergyInteraction;

const Reporter = @import("reporter.zig").Reporter;

pub const System = struct {
    // Configuration
    allocator: *std.mem.Allocator = undefined,
    rng: std.rand.DefaultPrng = undefined,
    threads: []std.Thread = undefined,
    n_threads: usize = undefined,
    // System atom properties
    id: ArrayList(u32) = undefined,
    r: ArrayList(V) = undefined,
    v: ArrayList(V) = undefined,
    f: ArrayList(V) = undefined,
    m: ArrayList(Real) = undefined,
    q: ArrayList(Real) = undefined,
    e: ArrayList(Element) = undefined,
    // Integration variables
    ff: ForceField = undefined,
    current_step: u64 = undefined,
    integrator: Integrator = undefined,
    neighbor_list: NeighborList = undefined,
    neighbor_list_update_step: u64 = undefined,
    // System properties
    virial: M = undefined,
    pressure: M = undefined,
    temperature: Real = undefined,
    energy: struct { kinetic: Real, potential: Real } = undefined,
    // System box
    region: V = undefined,
    use_pbc: bool = undefined,
    // Output files
    reporter: Reporter = undefined,
    ts_file: TsFile = undefined,
    ts_file_out: u64 = undefined,
    xyz_file: XyzFile = undefined,
    xyz_file_out: u64 = undefined,
    vel_file: VelFile = undefined,
    vel_file_out: u64 = undefined,

    const Self = @This();

    pub fn init(allocator: *std.mem.Allocator, _: Input) !Self {
        // Declare system
        var system = System{};

        // Set allocator
        system.allocator = allocator;

        // Init threads
        system.n_threads = input.n_threads;
        system.threads = try allocator.alloc(std.Thread, system.n_threads);

        // Set current step
        system.current_step = 0;

        // Set region
        const bc = std.mem.trim(u8, input.boundary_type, " ");
        if (std.mem.eql(u8, bc, "PBC")) {
            system.region = .{ .x = input.region_x, .y = input.region_y, .z = input.region_z };
            system.use_pbc = true;
        } else {
            system.region = V.zeros();
            system.use_pbc = false;
        }

        // Parse pos file
        var pos_file_name = std.mem.trim(u8, input.in_pos_file, " ");
        var pos_file = PosFile.init(allocator);
        defer pos_file.deinit();
        try pos_file.openFile(pos_file_name, .{});
        try pos_file.readData();

        // Initialize ids and positions
        var id_slice = pos_file.data.frames.items[0].indexes.toOwnedSlice();
        system.id = ArrayList(u32).fromOwnedSlice(allocator, id_slice);

        var r_slice = pos_file.data.frames.items[0].positions.toOwnedSlice();
        system.r = ArrayList(V).fromOwnedSlice(allocator, r_slice);

        // Initialize forces and velocities arrays
        system.v = try ArrayList(V).initCapacity(allocator, system.r.items.len);
        for (system.r.items) |_| try system.v.append(V.zeros());
        system.f = try ArrayList(V).initCapacity(allocator, system.r.items.len);
        for (system.r.items) |_| try system.f.append(V.zeros());

        // Wrap system
        system.wrap();

        // Parse mol file
        var mol_file_name = std.mem.trim(u8, input.in_mol_file, " ");
        var mol_file = MolFile.init(allocator);
        defer mol_file.deinit();
        try mol_file.openFile(mol_file_name, .{});
        try mol_file.readData();

        // Initialize mass and charge
        var m_slice = mol_file.data.properties.mass.toOwnedSlice();
        system.m = ArrayList(f64).fromOwnedSlice(allocator, m_slice);

        var q_slice = mol_file.data.properties.charge.toOwnedSlice();
        system.q = ArrayList(f64).fromOwnedSlice(allocator, q_slice);

        // Initialize virial
        system.virial = math.M.zeros();

        // Initialize pressure
        system.pressure = math.M.zeros();

        // Initialize force field
        var force_interactions = std.ArrayList(fn (*System, []V, *M, usize) void).init(allocator);
        defer force_interactions.deinit();
        var energy_interactions = std.ArrayList(fn (*System) void).init(allocator);
        defer energy_interactions.deinit();

        var neighbor_list_cutoff: Real = 0.0;

        // --> Lennard-Jones interaction
        if (mol_file.data.lennard_jones.id.items.len > 0) {
            var lj_parameters = ArrayList(LennardJonesParameters).init(allocator);
            defer lj_parameters.deinit();
            for (mol_file.data.lennard_jones.id.items) |id, i| {
                try lj_parameters.append(.{
                    .id = id,
                    .e = mol_file.data.lennard_jones.e.items[i],
                    .s = mol_file.data.lennard_jones.s.items[i],
                });
            }
            system.ff.lennard_jones_parameters = lj_parameters.toOwnedSlice();
            try force_interactions.append(lennardJonesForceInteraction);
            try energy_interactions.append(lennardJonesEnergyInteraction);
            // Cutoff for neighbor list
            for (system.ff.lennard_jones_parameters) |para| {
                const cutoff = 2.5 * para.s + 0.3 * para.s;
                if (neighbor_list_cutoff < cutoff) neighbor_list_cutoff = cutoff;
            }
        }

        system.ff.force_interactions = force_interactions.toOwnedSlice();
        system.ff.energy_interactions = energy_interactions.toOwnedSlice();

        // Initialize neighbor list
        system.neighbor_list = NeighborList.init(allocator, neighbor_list_cutoff);
        system.neighbor_list_update_step = input.neighbor_list_step;
        try system.neighbor_list.update(&system);

        // Set rng
        var seed = if (input.rng_seed > 0) input.rng_seed else blk: {
            var s: u64 = undefined;
            try std.os.getrandom(std.mem.asBytes(&s));
            break :blk s;
        };
        system.rng = std.rand.DefaultPrng.init(seed);

        // Initialize velocities
        system.initVelocities(input.temperature);

        // Initialize forces
        system.calculateForceInteractions();

        // Initialize energies
        system.calculateEnergyInteractions();
        system.calculateKineticEnergy();

        // Initialize temperature
        system.calculateTemperature();

        // Initialize pressure
        system.calculatePressure();

        // Initialize integrator
        system.integrator = Integrator.init(input);

        // TS output file
        if (input.out_ts_step > 0) {
            var ts_file_name = std.mem.trim(u8, input.out_ts_file, " ");
            var ts_file = TsFile.init(allocator);
            try ts_file.createFile(ts_file_name, .{});
            try ts_file.printDataHeader();
            try ts_file.printDataFromSystem(&system);
            system.ts_file = ts_file;
            system.ts_file_out = input.out_ts_step;
        }

        // TODO: temporal fix until mol file is refactored
        system.e = try ArrayList(Element).initCapacity(allocator, system.r.items.len);
        for (system.r.items) |_| try system.e.append(.Ar);

        // Reporter
        system.reporter = Reporter.init(allocator, &system);

        // XYZ probe
        if (input.out_xyz_step > 0) {
            var xyz_file_name = std.mem.trim(u8, input.out_xyz_file, " ");
            try system.reporter.addProbe(xyz_file_name, .xyz, input.out_xyz_step);
        }

        // Vel probe
        if (input.out_vel_step > 0) {
            var vel_file_name = std.mem.trim(u8, input.out_vel_file, " ");
            try system.reporter.addProbe(vel_file_name, .vel, input.out_vel_step);
        }

        // Report
        try system.reporter.report();

        return system;
    }

    pub fn deinit(_: *Self) void {
        self.id.deinit();
        self.r.deinit();
        self.v.deinit();
        self.f.deinit();
        self.m.deinit();
        self.q.deinit();
        self.e.deinit();
        self.allocator.free(self.ff.force_interactions);
        self.allocator.free(self.ff.energy_interactions);
        self.allocator.free(self.neighbor_list.pairs);
        self.vel_file.deinit();
        self.xyz_file.deinit();
        self.allocator.free(self.threads);
        self.reporter.deinit();
    }

    pub fn initVelocities(self: *Self, temperature: Real) void {
        // Get rng
        const rng = &self.rng.random;

        // Initialize with random velocities
        var i: usize = 0;
        while (i < self.v.items.len) : (i += 1) {

            // Sigma
            const s = std.math.sqrt(kb * temperature / self.m.items[i]);

            // Alpha
            const a = .{
                .x = std.math.sqrt(-2.0 * std.math.ln(rng.float(Real))),
                .y = std.math.sqrt(-2.0 * std.math.ln(rng.float(Real))),
                .z = std.math.sqrt(-2.0 * std.math.ln(rng.float(Real))),
            };

            // Beta
            const b = .{
                .x = @cos(2.0 * std.math.pi * rng.float(Real)),
                .y = @cos(2.0 * std.math.pi * rng.float(Real)),
                .z = @cos(2.0 * std.math.pi * rng.float(Real)),
            };

            // Assign random velocity
            const ab = math.v.mul(a, b);
            self.v.items[i] = math.v.scale(ab, s);
        }

        // Calculate scaling factor
        var factor: Real = 0;
        for (self.v.items) |v, j| factor += self.m.items[j] * math.v.dot(v, v);
        factor = 3.0 * @intToFloat(Real, self.v.items.len) * kb * temperature / factor;
        factor = std.math.sqrt(factor);

        // Scale velocities
        i = 0;
        while (i < self.v.items.len) : (i += 1) self.v.items[i] = math.v.scale(self.v.items[i], factor);
    }

    fn calculateForceInteractionsThread(system: *Self, t_f: []V, t_virial: *M, t_id: usize) void {
        // Calculate forces
        for (system.ff.force_interactions) |f| f(system, t_f, t_virial, t_id);
    }

    pub fn calculateForceInteractions(self: *Self) void {
        // Reset forces
        var i: usize = 0;
        while (i < self.f.items.len) : (i += 1) self.f.items[i] = V.zeros();

        // Reset virial
        self.virial = math.M.zeros();

        // Allocate local thread variables
        var t_f = self.allocator.alloc(V, self.n_threads * self.f.items.len) catch {
            stopWithErrorMsg("Could not allocate t_f array", .{});
            unreachable;
        };
        defer self.allocator.free(t_f);

        var t_virial = self.allocator.alloc(M, self.n_threads) catch {
            stopWithErrorMsg("Could not allocate t_virial array", .{});
            unreachable;
        };
        defer self.allocator.free(t_virial);

        // Initialize local thread variables
        i = 0;
        while (i < self.n_threads * self.f.items.len) : (i += 1) t_f[i] = V.zeros();
        i = 0;
        while (i < self.n_threads) : (i += 1) t_virial[i] = M.zeros();

        // Calculate forces
        i = 0;
        while (i < self.n_threads) : (i += 1) self.threads[i] = std.Thread.spawn(.{}, calculateForceInteractionsThread, .{
            self,
            t_f[i * self.f.items.len .. (i + 1) * self.f.items.len],
            &t_virial[i],
            i,
        }) catch {
            stopWithErrorMsg("Could not spawn #{d} thread for force calculation", .{i});
            unreachable;
        };
        i = 0;
        while (i < self.n_threads) : (i += 1) self.threads[i].join();

        // Reduce local thread variables
        i = 0;
        while (i < self.n_threads) : (i += 1) {
            for (self.f.items) |*f, j| f.* = math.v.add(f.*, t_f[i * self.f.items.len + j]);
            self.virial = math.m.add(self.virial, t_virial[i]);
        }
    }

    pub fn calculateEnergyInteractions(self: *Self) void {
        // Reset energy
        self.energy.potential = 0;

        // Calculate energy
        for (self.ff.energy_interactions) |f| f(self);
    }

    pub fn calculateKineticEnergy(self: *Self) void {
        var energy: Real = 0.0;

        var i: usize = 0;
        while (i < self.v.items.len) : (i += 1) {
            energy += self.m.items[i] * math.v.dot(self.v.items[i], self.v.items[i]);
        }

        self.energy.kinetic = 0.5 * energy;
    }

    pub fn calculateTemperature(self: *Self) void {
        self.calculateKineticEnergy();
        const dof = 3.0 * @intToFloat(Real, self.r.items.len);
        self.temperature = 2.0 * self.energy.kinetic / (dof * kb);
    }

    pub fn calculatePressure(self: *Self) void {
        // Calculate velocity tensor
        var v_tensor = math.M.zeros();
        var i: usize = 0;
        while (i < self.v.items.len) : (i += 1) {
            const v = self.v.items[i];
            const m = self.m.items[i];
            const vv = math.v.direct(v, v);
            const vvm = math.m.scale(vv, m);
            v_tensor = math.m.add(v_tensor, vvm);
        }

        // Calculate pressure
        const vol = self.region.x * self.region.y * self.region.z;
        const tmp = math.m.add(v_tensor, self.virial);
        const p = math.m.scale(tmp, 1.0 / vol);
        self.pressure = math.m.add(self.pressure, p);
    }

    pub fn wrap(self: *Self) void {
        var i: usize = 0;
        while (i < self.r.items.len) : (i += 1) {
            self.r.items[i] = math.wrap(self.r.items[i], self.region);
        }
    }

    pub fn step(self: *Self) !void {
        // Update step counter
        self.current_step += 1;

        // Update neighbor list
        if (self.current_step % self.neighbor_list_update_step == 0) try self.neighbor_list.update(self);

        // Integrate equations of motion
        self.integrator.evolveSystem(self);

        // Wrap system
        if (self.use_pbc) self.wrap();

        // Write ts file
        if (self.ts_file_out > 0 and self.current_step % self.ts_file_out == 0) {
            // Calculate properties
            self.calculateEnergyInteractions();
            self.calculateKineticEnergy();
            self.calculateTemperature();
            self.calculatePressure();
            // Report properties
            try self.ts_file.printDataFromSystem(self);
        }

        // Report
        try self.reporter.report();
    }
};
