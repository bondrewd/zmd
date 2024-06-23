// Modules
const std = @import("std");
// Types
const ArgumentParser = @import("argument_parser.zig").ArgumentParser;

pub fn main() anyerror!void {
    // Get allocator
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Parse arguments
    const args = ArgumentParser.parseArgumentsAllocator(allocator) catch return;
    defer ArgumentParser.deinitArgs(args);

    // Perform MD
    var istep: usize = 1;
    while (istep <= 1000) : (istep += 1) {}
}
