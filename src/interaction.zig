const std = @import("std");

const math = @import("math.zig");
const V = math.V;
const M = math.M;

const Pair = @import("neighbor_list.zig").Pair;
const System = @import("system.zig").System;

pub fn lennardJonesForceInteraction(system: *System, t_f: []V, t_virial: *M, t_id: usize) void {
    // Calculate pairs to work with
    const n_pairs = system.neighbor_list.pairs.len;
    const n_pairs_per_thread = (n_pairs + system.n_threads - 1) / system.n_threads;
    const lo = t_id * n_pairs_per_thread;
    const hi = std.math.min((t_id + 1) * n_pairs_per_thread, n_pairs);
    if (lo > hi) return;

    // Loop over neighbors
    for (system.neighbor_list.pairs[lo..hi]) |pair| {
        const i = pair.i;
        const j = pair.j;

        const ri = system.r.items[i];
        const ei = system.ff.lennard_jones_parameters[i].e;
        const si = system.ff.lennard_jones_parameters[i].s;

        const rj = system.r.items[j];
        const ej = system.ff.lennard_jones_parameters[j].e;
        const sj = system.ff.lennard_jones_parameters[j].s;

        const e = std.math.sqrt(ei * ej);
        const s = (si + sj) / 2.0;
        const s2 = s * s;
        const cut_off2 = 6.25 * s2;

        var rij = math.v.sub(ri, rj);
        if (system.use_pbc) rij = math.wrap(rij, system.region);
        const rij2 = math.v.dot(rij, rij);

        if (rij2 < cut_off2) {
            const c2 = s2 / rij2;
            const c4 = c2 * c2;
            const c8 = c4 * c4;
            const c14 = c8 * c4 * c2;

            const f = 48.0 * e * (c14 - 0.5 * c8) / s2;
            const force = math.v.scale(rij, f);

            t_f[i] = math.v.add(t_f[i], force);
            t_f[j] = math.v.sub(t_f[j], force);

            const rijf = math.v.direct(rij, force);
            t_virial.* = math.m.add(t_virial.*, rijf);
        }
    }
}

pub fn lennardJonesEnergyInteraction(system: *System) void {
    // Loop over neighbors
    for (system.neighbor_list.pairs) |pair| {
        const i = pair.i;
        const j = pair.j;

        const ri = system.r.items[i];
        const ei = system.ff.lennard_jones_parameters[i].e;
        const si = system.ff.lennard_jones_parameters[i].s;

        const rj = system.r.items[j];
        const ej = system.ff.lennard_jones_parameters[j].e;
        const sj = system.ff.lennard_jones_parameters[j].s;

        const e = std.math.sqrt(ei * ej);
        const s = (si + sj) / 2.0;
        const s2 = s * s;
        const cut_off2 = 6.25 * s2;

        var rij = math.v.sub(ri, rj);
        if (system.use_pbc) rij = math.wrap(rij, system.region);
        const rij2 = math.v.dot(rij, rij);

        if (rij2 < cut_off2) {
            const c2 = s2 / rij2;
            const c4 = c2 * c2;
            const c6 = c4 * c2;
            const c12 = c6 * c6;

            const energy = 4.0 * e * (c12 - c6);

            system.energy.potential += energy;
        }
    }
}
