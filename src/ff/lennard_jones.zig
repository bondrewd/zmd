const std = @import("std");

const Input = @import("../input.zig").Input;

const math = @import("../math.zig");
const V = math.V;
const M = math.M;

const MolFile = @import("../file.zig").MolFile;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;

const printErrorMsg = @import("../exception.zig").printErrorMsg;

pub const LennardJones = struct {
    allocator: *Allocator,
    indexes: []u32,
    e: []f32,
    s: []f32,
    e_sqrt: []f32,
    s_half: []f32,

    pub const Self = @This();

    pub fn init(allocator: *Allocator, input: Input) !Self {
        // Read mol file
        var mol_file = MolFile.init(allocator);
        defer mol_file.deinit();
        try mol_file.openFile(input.in_mol_file, .{});
        defer mol_file.close();
        try mol_file.readData();

        // Allocate slices
        const n = mol_file.data.lennard_jones.indexes.items.len;
        var indexes = try allocator.alloc(u32, n);
        var e = try allocator.alloc(f32, n);
        var s = try allocator.alloc(f32, n);
        var e_sqrt = try allocator.alloc(f32, n);
        var s_half = try allocator.alloc(f32, n);

        // Copy information from pos file
        std.mem.copy(u32, indexes, mol_file.data.lennard_jones.indexes.items);
        std.mem.copy(f32, e, mol_file.data.lennard_jones.e.items);
        std.mem.copy(f32, s, mol_file.data.lennard_jones.s.items);

        // Bubble sort e and s based on index
        var i: usize = 0;
        var j: usize = 0;
        while (i < indexes.len - 1) : (i += 1) {
            while (j < indexes.len - i - 1) : (j += 1) {
                if (indexes[j] > indexes[j + 1]) {
                    std.mem.swap(u32, &indexes[j], &indexes[j + 1]);
                    std.mem.swap(f32, &e[j], &e[j + 1]);
                    std.mem.swap(f32, &s[j], &s[j + 1]);
                }
            }
        }

        // Preprocess parameters
        i = 0;
        while (i < indexes.len) : (i += 1) {
            e_sqrt[i] = std.math.sqrt(e[i]);
            s_half[i] = 0.5 * s[i];
        }

        return Self{
            .allocator = allocator,
            .indexes = indexes,
            .e = e,
            .s = s,
            .e_sqrt = e_sqrt,
            .s_half = s_half,
        };
    }

    pub fn deinit(self: Self) void {
        self.allocator.free(self.indexes);
        self.allocator.free(self.e);
        self.allocator.free(self.s);
        self.allocator.free(self.e_sqrt);
        self.allocator.free(self.s_half);
    }

    pub fn force(self: Self, i: u32, j: u32, ri: V, rj: V, fi: *V, fj: *V, virial: *M, box: ?V) void {
        // Epsilon
        const ei = self.e_sqrt[i];
        const ej = self.e_sqrt[j];
        const e = ei * ej;
        // Sigma
        const si = self.s_half[i];
        const sj = self.s_half[j];
        const s = si + sj;
        const s2 = s * s;
        // Cutoff
        const cutoff2 = 6.25 * s2;

        var rij = math.v.sub(ri, rj);
        if (box) |b| rij = math.wrap(rij, b);
        const rij2 = math.v.dot(rij, rij);

        if (rij2 < cutoff2) {
            const c2 = s2 / rij2;
            const c4 = c2 * c2;
            const c8 = c4 * c4;
            const c14 = c8 * c4 * c2;

            const f = 48.0 * e * (c14 - 0.5 * c8) / s2;
            const fij = math.v.scale(rij, f);

            fi.* = math.v.add(fi.*, fij);
            fj.* = math.v.sub(fj.*, fij);

            virial.* = math.m.add(virial.*, math.v.direct(rij, fij));
        }
    }

    pub fn energy(self: Self, i: u32, j: u32, ri: V, rj: V, ene: *f32, box: ?V) void {
        // Epsilon
        const ei = self.e_sqrt[i];
        const ej = self.e_sqrt[j];
        const e = ei * ej;
        // Sigma
        const si = self.s_half[i];
        const sj = self.s_half[j];
        const s = si + sj;
        const s2 = s * s;
        // Cutoff
        const cutoff2 = 6.25 * s2;

        var rij = math.v.sub(ri, rj);
        if (box) |b| rij = math.wrap(rij, b);
        const rij2 = math.v.dot(rij, rij);

        if (rij2 < cutoff2) {
            const c2 = s2 / rij2;
            const c4 = c2 * c2;
            const c6 = c4 * c2;
            const c12 = c6 * c6;

            ene.* += 4.0 * e * (c12 - c6);
        }
    }
};

const testing = std.testing;
const dummyInput = @import("../input.zig").dummyInput;

test "Lennard Jones basic usage 1" {
    var in_mol_file = ArrayList(u8).init(testing.allocator);
    defer in_mol_file.deinit();
    try in_mol_file.appendSlice("test/unit/lj_basic_usage_01.mol");
    var in_mol_file_name = in_mol_file.items;

    var input = dummyInput();
    input.in_mol_file = in_mol_file_name;

    var lj = try LennardJones.init(testing.allocator, input);
    defer lj.deinit();

    // Check LJ indexes
    try testing.expect(lj.indexes.len == 3);
    try testing.expect(lj.indexes[0] == 1);
    try testing.expect(lj.indexes[1] == 2);
    try testing.expect(lj.indexes[2] == 3);

    // Check LJ e
    try testing.expect(lj.e.len == 3);
    try testing.expect(lj.e[0] == 0.1);
    try testing.expect(lj.e[1] == 0.2);
    try testing.expect(lj.e[2] == 0.3);

    // Check LJ s
    try testing.expect(lj.s.len == 3);
    try testing.expect(lj.s[0] == 0.1);
    try testing.expect(lj.s[1] == 0.2);
    try testing.expect(lj.s[2] == 0.3);

    // Check LJ e_sqrt
    try testing.expect(lj.e_sqrt.len == 3);
    try testing.expect(lj.e_sqrt[0] == std.math.sqrt(0.1));
    try testing.expect(lj.e_sqrt[1] == std.math.sqrt(0.2));
    try testing.expect(lj.e_sqrt[2] == std.math.sqrt(0.3));

    // Check LJ s
    try testing.expect(lj.s_half.len == 3);
    try testing.expect(lj.s_half[0] == 0.5 * 0.1);
    try testing.expect(lj.s_half[1] == 0.5 * 0.2);
    try testing.expect(lj.s_half[2] == 0.5 * 0.3);
}

test "Lennard Jones basic usage 2" {
    var in_mol_file = ArrayList(u8).init(testing.allocator);
    defer in_mol_file.deinit();
    try in_mol_file.appendSlice("test/unit/lj_basic_usage_02.mol");
    var in_mol_file_name = in_mol_file.items;

    var input = dummyInput();
    input.in_mol_file = in_mol_file_name;

    var lj = try LennardJones.init(testing.allocator, input);
    defer lj.deinit();

    // Initialize variables
    const ri = V{ .x = 0.0, .y = 0.0, .z = 0.0 };
    const rj = V{ .x = 2.0, .y = 0.0, .z = 0.0 };
    const rij = math.v.sub(ri, rj);
    const r = math.v.norm(rij);

    var i: usize = 0;
    var j: usize = 0;
    var fi = V.zeros();
    var fj = V.zeros();
    var virial = M.zeros();
    var eij = lj.e_sqrt[i] * lj.e_sqrt[j];
    var sij = lj.s_half[i] + lj.s_half[j];
    var c8 = std.math.pow(f32, sij / r, 8);
    var c14 = std.math.pow(f32, sij / r, 14);
    var f = 48.0 * eij * (c14 - 0.5 * c8) / (sij * sij);
    var fij = math.v.scale(rij, f);

    lj.force(@intCast(u32, i), @intCast(u32, j), ri, rj, &fi, &fj, &virial, null);
    try math.v.expectApproxEqAbs(fi, fij, std.math.epsilon(f32));
    try math.v.expectApproxEqAbs(fj, math.v.scale(fij, -1), std.math.epsilon(f32));
    try math.m.expectApproxEqAbs(virial, math.v.direct(rij, fij), std.math.epsilon(f32));

    i = 1;
    j = 1;
    fi = V.zeros();
    fj = V.zeros();
    virial = M.zeros();
    eij = lj.e_sqrt[i] * lj.e_sqrt[j];
    sij = lj.s_half[i] + lj.s_half[j];
    c8 = std.math.pow(f32, sij / r, 8);
    c14 = std.math.pow(f32, sij / r, 14);
    f = 48.0 * eij * (c14 - 0.5 * c8) / (sij * sij);
    fij = math.v.scale(rij, f);

    lj.force(@intCast(u32, i), @intCast(u32, j), ri, rj, &fi, &fj, &virial, null);
    try math.v.expectApproxEqAbs(fi, fij, std.math.epsilon(f32));
    try math.v.expectApproxEqAbs(fj, math.v.scale(fij, -1), std.math.epsilon(f32));
    try math.m.expectApproxEqAbs(virial, math.v.direct(rij, fij), std.math.epsilon(f32));

    i = 2;
    j = 2;
    fi = V.zeros();
    fj = V.zeros();
    virial = M.zeros();
    eij = lj.e_sqrt[i] * lj.e_sqrt[j];
    sij = lj.s_half[i] + lj.s_half[j];
    c8 = std.math.pow(f32, sij / r, 8);
    c14 = std.math.pow(f32, sij / r, 14);
    f = 48.0 * eij * (c14 - 0.5 * c8) / (sij * sij);
    fij = math.v.scale(rij, f);

    lj.force(@intCast(u32, i), @intCast(u32, j), ri, rj, &fi, &fj, &virial, null);
    try math.v.expectApproxEqAbs(fi, fij, std.math.epsilon(f32));
    try math.v.expectApproxEqAbs(fj, math.v.scale(fij, -1), std.math.epsilon(f32));
    try math.m.expectApproxEqAbs(virial, math.v.direct(rij, fij), std.math.epsilon(f32));
}
