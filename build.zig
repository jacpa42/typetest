const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const mod = b.addModule("typetest", .{
        .root_source_file = b.path("typetest.zig"),
        .target = target,
        .optimize = optimize,
    });

    const exe = b.addExecutable(.{ .name = "typetest", .root_module = mod });
    // Install the executable in build dir
    b.installArtifact(exe);

    const clap = b.dependency("clap", .{});
    exe.root_module.addImport("clap", clap.module("clap"));

    const bin = b.addRunArtifact(exe);
    const run_step = b.step("run", "Execute program");
    run_step.dependOn(&bin.step);

    // add cmdline args
    if (b.args) |args| bin.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = mod });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);
}
