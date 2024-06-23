const ansi = @import("ansi-zig/src/ansi.zig");

// Ansi formats and colors
pub const reset = ansi.reset;
pub const bold = ansi.bold_on;
pub const red = ansi.fg_light_red;
pub const blue = ansi.fg_light_blue;
pub const yellow = ansi.fg_light_yellow;
