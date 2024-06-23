pub const v = @import("math/v.zig");
pub const V = v.V;
pub const m = @import("math/m.zig");
pub const M = m.M;

// Wrap vector inside box
pub fn wrap(vec: V, box: V) V {
    return .{
        .x = if (vec.x > 0.5 * box.x) vec.x - box.x else if (vec.x < -0.5 * box.x) vec.x + box.x else vec.x,
        .y = if (vec.y > 0.5 * box.y) vec.y - box.y else if (vec.y < -0.5 * box.y) vec.y + box.y else vec.y,
        .z = if (vec.z > 0.5 * box.z) vec.z - box.z else if (vec.z < -0.5 * box.z) vec.z + box.z else vec.z,
    };
}
