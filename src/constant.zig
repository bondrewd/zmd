const std = @import("std");

// Boltzmann constant (kJ/mol-K)
pub const kb = 0.008314463;

// Elements
pub const Element = enum {
    H,
    He,
    O,
    C,
    S,
    P,
    Ar,

    const Self = @This();

    pub fn toString(self: Self) []const u8 {
        return switch (self) {
            .H => "H",
            .He => "He",
            .O => "O",
            .C => "C",
            .S => "S",
            .P => "P",
            .Ar => "Ar",
        };
    }
};

pub fn elementFromString(str: []const u8) !Element {
    if (std.mem.eql(u8, str, "H")) {
        return .H;
    } else if (std.mem.eql(u8, str, "He")) {
        return .He;
    } else if (std.mem.eql(u8, str, "O")) {
        return .O;
    } else if (std.mem.eql(u8, str, "C")) {
        return .C;
    } else if (std.mem.eql(u8, str, "S")) {
        return .S;
    } else if (std.mem.eql(u8, str, "P")) {
        return .P;
    } else if (std.mem.eql(u8, str, "Ar")) {
        return .Ar;
    } else {
        return error.UnknownElement;
    }
}
