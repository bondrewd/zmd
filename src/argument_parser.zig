// Modules
const argparse = @import("argparse");
// Types
const AppOption = argparse.AppOption;
const AppPositional = argparse.AppPositional;

pub const ArgumentParser = argparse.ArgumentParser(.{
    .app_name = "zmd",
    .app_description =
    \\Molecular dynamics written in zig.
    ,
    .app_version = .{ .major = 0, .minor = 1, .patch = 0 },
}, &.{}, &.{
    AppPositional{
        .name = "input",
        .metavar = "INPUT",
        .description = "Input control file",
    },
});

pub const ParserResult = ArgumentParser.ParserResult;
