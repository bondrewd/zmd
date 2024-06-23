const std = @import("std");
const fmt = std.fmt;
const mem = std.mem;
const printErrorMsg = @import("exception.zig").printErrorMsg;

const ArrayList = std.ArrayList;
const Allocator = std.mem.Allocator;
const TypeInfo = std.builtin.TypeInfo;
const StructField = TypeInfo.StructField;
const Declaration = TypeInfo.Declaration;

pub const InputFileParserConfiguration = struct {
    line_buffer_size: usize = 1024,
    separator: []const u8 = " ",
    section_opening: []const u8 = "[",
    section_closing: []const u8 = "]",
    comment_character: []const u8 = "#",
};

pub const InputFileParserEntry = struct {
    name: []const u8,
    entry_type: type = bool,
    section: []const u8,
    default_value: ?union { int: comptime_int, float: comptime_float, string: []const u8, boolean: bool } = null,
};

pub fn InputFileParser(comptime config: InputFileParserConfiguration, comptime entries: anytype) type {
    return struct {
        const Self = @This();

        pub const InputFileParserResult = blk: {
            // Struct fields
            var fields: [entries.len]StructField = undefined;
            inline for (entries) |entry, i| {
                // Validate entry
                fields[i] = .{
                    .name = entry.name,
                    .field_type = entry.entry_type,
                    .default_value = null,
                    .is_comptime = false,
                    .alignment = @alignOf(entry.entry_type),
                };
            }

            // Struct declarations
            var decls: [0]Declaration = .{};

            break :blk @Type(TypeInfo{ .Struct = .{
                .layout = .Auto,
                .fields = &fields,
                .decls = &decls,
                .is_tuple = false,
            } });
        };

        pub fn parse(allocator: *Allocator, input_file_name: []const u8) !InputFileParserResult {
            var f = std.fs.cwd().openFile(input_file_name, .{ .read = true }) catch {
                printErrorMsg("Can't open file {s}\n", .{input_file_name});
                return error.OpenFailed;
            };

            // Initialize input parser result
            var parsed_entries: InputFileParserResult = undefined;
            inline for (entries) |entry| @field(parsed_entries, entry.name) = undefined;

            // Initialize input parser flags
            var entry_found = [_]bool{false} ** entries.len;

            // Go to the start of the file
            try f.seekTo(0);

            // Get reader
            const r = f.reader();

            // Line buffer
            var buf: [config.line_buffer_size]u8 = undefined;

            // Section name
            var current_section: [config.line_buffer_size]u8 = undefined;

            while (try r.readUntilDelimiterOrEof(&buf, '\n')) |line| {
                // Skip comments
                if (mem.startsWith(u8, line, config.comment_character)) continue;

                // Skip empty lines
                if (mem.trim(u8, line, " ").len == 0) continue;

                // Check for section
                if (mem.startsWith(u8, line, config.section_opening)) {
                    const closing_symbol = mem.indexOf(u8, line, config.section_closing);
                    if (closing_symbol) |index| {
                        mem.set(u8, &current_section, ' ');
                        mem.copy(u8, &current_section, line[1..index]);
                        continue;
                    } else {
                        printErrorMsg("Missing ']' character in section name -> {s}\n", .{line});
                        return error.MissingValue;
                    }
                }

                // Replace separator
                if (!mem.eql(u8, config.separator, " ")) {
                    const sep_idx = mem.indexOf(u8, line, config.separator);
                    if (sep_idx) |idx| {
                        line[idx] = ' ';
                    } else {
                        printErrorMsg("Missing separator " ++ config.separator ++ " -> {s}\n", .{line});
                        return error.MissingValue;
                    }
                }

                // Parse arguments
                var tokens = mem.tokenize(u8, line, " ");

                // Get key
                const key = if (tokens.next()) |token| token else {
                    printErrorMsg("Missing key value in input file -> {s}\n", .{line});
                    return error.MissingValue;
                };

                // Get value
                const rest = tokens.rest();
                const val = if (std.mem.indexOf(u8, rest, config.comment_character)) |index| rest[0..index] else rest;
                const val_trim = std.mem.trim(u8, val, " ");

                // Look for the corresponding input
                inline for (entries) |entry, i| {
                    const current_section_trim = mem.trim(u8, &current_section, " ");
                    var in_section = mem.eql(u8, current_section_trim, entry.section);
                    var in_entry = mem.eql(u8, key, entry.name);
                    if (in_section and in_entry) {
                        entry_found[i] = true;
                        switch (@typeInfo(entry.entry_type)) {
                            .Int => @field(parsed_entries, entry.name) = try fmt.parseInt(entry.entry_type, val_trim, 10),
                            .Float => @field(parsed_entries, entry.name) = try fmt.parseFloat(entry.entry_type, val_trim),
                            .Pointer => {
                                @field(parsed_entries, entry.name) = try allocator.alloc(u8, val_trim.len);
                                mem.copy(u8, @field(parsed_entries, entry.name), val_trim);
                            },
                            .Bool => @field(parsed_entries, entry.name) = blk: {
                                var buffer: [config.line_buffer_size]u8 = undefined;
                                var val_up = std.ascii.upperString(&buffer, val_trim);
                                if (mem.eql(u8, val_up, "ON") or mem.eql(u8, val_up, "YES") or mem.eql(u8, val_up, "TRUE")) break :blk true;
                                if (mem.eql(u8, val_up, "OFF") or mem.eql(u8, val_up, "NO") or mem.eql(u8, val_up, "FALSE")) break :blk false;
                                printErrorMsg("Bad value for entry " ++ entry.name ++ " -> {s}\n", .{val_trim});
                                return error.BadValue;
                            },
                            else => unreachable,
                        }
                    }
                }
            }

            inline for (entries) |entry, i| {
                if (!entry_found[i]) {
                    if (entry.default_value) |default| {
                        switch (@typeInfo(entry.entry_type)) {
                            .Int => @field(parsed_entries, entry.name) = default.int,
                            .Float => @field(parsed_entries, entry.name) = default.float,
                            .Pointer => std.mem.copy(u8, @field(parsed_entries, entry.name), default.string),
                            .Bool => @field(parsed_entries, entry.name) = default.boolean,
                            else => unreachable,
                        }
                    } else {
                        printErrorMsg("Missing value for " ++ entry.name ++ "\n", .{});
                        return error.MissingValue;
                    }
                }
            }

            return parsed_entries;
        }

        pub fn deinitInput(allocator: *Allocator, parsed_entries: InputFileParserResult) void {
            inline for (entries) |entry| {
                switch (@typeInfo(entry.entry_type)) {
                    .Pointer => allocator.free(@field(parsed_entries, entry.name)),
                    else => {},
                }
            }
        }
    };
}

pub const InputParser = InputFileParser(.{ .separator = "=" }, [_]InputFileParserEntry{
    .{
        .name = "in_mol_file",
        .entry_type = []u8,
        .section = "INPUT",
    },
    .{
        .name = "in_pos_file",
        .entry_type = []u8,
        .section = "INPUT",
    },
    .{
        .name = "out_ts_file",
        .entry_type = []u8,
        .section = "OUTPUT",
        .default_value = .{ .string = "out.ts" },
    },
    .{
        .name = "out_ts_period",
        .entry_type = u32,
        .section = "OUTPUT",
        .default_value = .{ .int = 0 },
    },
    .{
        .name = "out_xyz_file",
        .entry_type = []u8,
        .section = "OUTPUT",
        .default_value = .{ .string = "out.xyz" },
    },
    .{
        .name = "out_xyz_period",
        .entry_type = u32,
        .section = "OUTPUT",
        .default_value = .{ .int = 0 },
    },
    .{
        .name = "out_vel_file",
        .entry_type = []u8,
        .section = "OUTPUT",
        .default_value = .{ .string = "out.vel" },
    },
    .{
        .name = "out_vel_period",
        .entry_type = u32,
        .section = "OUTPUT",
        .default_value = .{ .int = 0 },
    },
    .{
        .name = "n_threads",
        .entry_type = usize,
        .section = "PARALLEL",
        .default_value = .{ .int = 1 },
    },
    .{
        .name = "integrator",
        .entry_type = []u8,
        .section = "DYNAMICS",
    },
    .{
        .name = "n_steps",
        .entry_type = u32,
        .section = "DYNAMICS",
    },
    .{
        .name = "time_step",
        .entry_type = f32,
        .section = "DYNAMICS",
    },
    .{
        .name = "ensemble",
        .entry_type = []u8,
        .section = "DYNAMICS",
    },
    .{
        .name = "rng_seed",
        .entry_type = u32,
        .section = "DYNAMICS",
    },
    .{
        .name = "temperature",
        .entry_type = f32,
        .section = "DYNAMICS",
    },
    .{
        .name = "neighbor_list_period",
        .entry_type = u32,
        .section = "DYNAMICS",
    },
    .{
        .name = "boundary_type",
        .entry_type = []u8,
        .section = "BOUNDARY",
    },
    .{
        .name = "box_x_size",
        .entry_type = f32,
        .section = "BOUNDARY",
    },
    .{
        .name = "box_y_size",
        .entry_type = f32,
        .section = "BOUNDARY",
    },
    .{
        .name = "box_z_size",
        .entry_type = f32,
        .section = "BOUNDARY",
    },
});

pub const Input = InputParser.InputFileParserResult;

const testing = std.testing;

pub fn dummyInput() Input {
    return Input{
        .in_mol_file = undefined,
        .in_pos_file = undefined,
        .out_ts_file = undefined,
        .out_ts_period = 0,
        .out_xyz_file = undefined,
        .out_xyz_period = 0,
        .out_vel_file = undefined,
        .out_vel_period = 0,
        .n_threads = 0,
        .integrator = undefined,
        .n_steps = 0,
        .time_step = 0,
        .ensemble = undefined,
        .rng_seed = 0,
        .temperature = 0,
        .neighbor_list_period = 0,
        .boundary_type = undefined,
        .box_x_size = 0,
        .box_y_size = 0,
        .box_z_size = 0,
    };
}

test "Input parser basic usage 1" {
    const input = try InputParser.parse(testing.allocator, "test/unit/input_parser_basic_usage_01.inp");
    defer InputParser.deinitInput(testing.allocator, input);

    // Check INPUT section
    try testing.expect(std.mem.eql(u8, input.in_mol_file, "in.mol"));
    try testing.expect(std.mem.eql(u8, input.in_pos_file, "in.pos"));

    // Check OUTPUT section
    try testing.expect(std.mem.eql(u8, input.out_ts_file, "out.ts"));
    try testing.expect(input.out_ts_period == 1);
    try testing.expect(std.mem.eql(u8, input.out_xyz_file, "out.xyz"));
    try testing.expect(input.out_xyz_period == 1);
    try testing.expect(std.mem.eql(u8, input.out_vel_file, "out.vel"));
    try testing.expect(input.out_vel_period == 1);

    // Check PARALLEL section
    try testing.expect(input.n_threads == 1);

    // Check DYNAMICS section
    try testing.expect(std.mem.eql(u8, input.integrator, "foo"));
    try testing.expect(input.n_steps == 1);
    try testing.expect(input.time_step == 1.0);
    try testing.expect(std.mem.eql(u8, input.ensemble, "foo"));
    try testing.expect(input.rng_seed == 1);
    try testing.expect(input.temperature == 1.0);
    try testing.expect(input.neighbor_list_period == 1);

    // Check BOUNDARY section
    try testing.expect(std.mem.eql(u8, input.boundary_type, "foo"));
    try testing.expect(input.box_x_size == 1.0);
    try testing.expect(input.box_y_size == 1.0);
    try testing.expect(input.box_z_size == 1.0);
}
