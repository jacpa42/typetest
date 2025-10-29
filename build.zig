const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("typetest", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const dependancies: [2][]const u8 = .{ "clap", "vaxis" };
    for (dependancies) |name| {
        const dependancy = b.dependency(name, .{
            .target = target,
            .optimize = optimize,
        });
        mod.addImport(name, dependancy.module(name));
    }

    const exe = b.addExecutable(.{
        .name = "typetest",
        .root_module = mod,
    });

    const bin = b.addRunArtifact(exe);
    const run_step = b.step("run", "Execute program");
    run_step.dependOn(&bin.step);

    // add cmdline args
    if (b.args) |args| bin.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Install the executable in build dir
    b.installArtifact(exe);
}
