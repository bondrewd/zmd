const std = @import("std");

const math = @import("math.zig");
const V = math.V;
const add = math.v.add;
const scale = math.v.scale;

const System = @import("system.zig").System;
const Input = @import("input.zig").MdInputFileParserResult;
const stopWithErrorMsg = @import("exception.zig").stopWithErrorMsg;

pub const Integrator = struct {
    dt: f32 = undefined,
    evolveSystem: fn (*System) void = undefined,

    const Self = @This();

    pub fn init(input: Input) Self {
        // Declare integrator
        var integrator = Integrator{};

        // Set time step
        integrator.dt = input.time_step;

        // Get integrator name
        const name = std.mem.trim(u8, input.integrator, " ");

        // Parse integrator name
        if (std.mem.eql(u8, "LEAP", name)) {
            integrator.evolveSystem = leapFrog;
        } else {
            stopWithErrorMsg("Unknown integrator -> {s}", .{name});
            unreachable;
        }

        return integrator;
    }
};

pub fn leapFrog(system: *System) void {
    // Time step
    const dt = system.integrator.dt;

    // First part
    var i: usize = 0;
    while (i < system.r.items.len) : (i += 1) {
        // v(t + dt/2) = v(t) + f(t) * dt/2m
        system.v.items[i] = add(system.v.items[i], scale(system.f.items[i], 0.5 * dt / system.m.items[i]));
        // x(t + dt) = x(t) + v(t + dt/2) * dt
        system.r.items[i] = add(system.r.items[i], scale(system.v.items[i], dt));
    }

    // Update forces
    // f(t + dt) = -dU(t + dt)/dt
    system.calculateForceInteractions();

    // Second part
    i = 0;
    while (i < system.r.items.len) : (i += 1) {
        // v(t + dt) = v(t + dt/2) + f(t + dt) * dt/2m
        system.v.items[i] = add(system.v.items[i], scale(system.f.items[i], 0.5 * dt / system.m.items[i]));
    }
}
