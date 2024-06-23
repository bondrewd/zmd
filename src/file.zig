pub const PosFile = @import("file/pos_file.zig").PosFile;
pub const MolFile = @import("file/mol_file.zig").MolFile;
pub const VelFile = @import("file/vel_file.zig").VelFile;
pub const XyzFile = @import("file/xyz_file.zig").XyzFile;
//pub const CsvFile = @import("file/csv_file.zig").CsvFile;
pub const TsFile = @import("file/ts_file.zig").TsFile;

pub const posWriteFrame = @import("file/pos_file.zig").writeFrame;
pub const xyzWriteFrame = @import("file/xyz_file.zig").writeFrame;
pub const velWriteFrame = @import("file/vel_file.zig").writeFrame;
