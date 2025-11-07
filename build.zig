const std = @import("std");
const zon = @import("./build.zig.zon");

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const version = zon.version;

    const typetest = b.addModule("typetest", .{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    addDependencies(b, typetest, target, optimize);
    addRunStep(b, typetest);

    const release = b.step("release", "Create release builds of typetest");
    const git_version = getGitVersion(b);
    if (git_version == .tag) {
        if (std.mem.eql(u8, version, git_version.tag[1..])) {
            setupReleaseStep(b, release);
        } else {
            release.dependOn(&b.addFail(b.fmt(
                "error: git tag does not match zon package version (zon: '{s}', git: '{s}')",
                .{ version, git_version.tag[1..] },
            )).step);
        }
    } else {
        release.dependOn(&b.addFail(
            "error: git tag missing, cannot make release builds",
        ).step);
    }
}

fn addDependencies(
    b: *std.Build,
    typetest: *std.Build.Module,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
) void {
    const dependancies: [2][]const u8 = .{ "clap", "vaxis" };
    for (dependancies) |name| {
        const dependancy = b.dependency(name, .{
            .target = target,
            .optimize = optimize,
        });
        typetest.addImport(name, dependancy.module(name));
    }
}

fn addRunStep(
    b: *std.Build,
    typetest: *std.Build.Module,
) void {
    const exe = b.addExecutable(.{
        .name = "typetest",
        .root_module = typetest,
    });
    const bin = b.addRunArtifact(exe);
    const run_step = b.step("run", "Execute program");
    run_step.dependOn(&bin.step);

    // add cmdline args
    if (b.args) |args| bin.addArgs(args);

    const mod_tests = b.addTest(.{ .root_module = typetest });
    const run_mod_tests = b.addRunArtifact(mod_tests);
    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&run_mod_tests.step);

    // Install the executable in build dir
    b.installArtifact(exe);
}

fn setupCheckStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    folders: *std.Build.Dependency,
    lsp: *std.Build.Dependency,
) *std.Build.Step {
    const check = b.step("check", "Check if the SuperHTML CLI compiles");
    const super_cli_check = b.addExecutable(.{
        .name = "superhtml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        }),
    });

    super_cli_check.root_module.addImport("superhtml", superhtml);
    super_cli_check.root_module.addImport(
        "known_folders",
        folders.module("known-folders"),
    );
    super_cli_check.root_module.addImport("lsp", lsp.module("lsp"));
    super_cli_check.root_module.addOptions("build_options", options);

    check.dependOn(&super_cli_check.step);
    return check;
}
fn setupTestStep(
    b: *std.Build,
    superhtml: *std.Build.Module,
    check: *std.Build.Step,
) void {
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(check);

    const unit_tests = b.addTest(.{
        .root_module = superhtml,
        .filters = b.args orelse &.{},
    });

    const run_unit_tests = b.addRunArtifact(unit_tests);
    test_step.dependOn(&run_unit_tests.step);
}

fn setupCliTool(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    folders: *std.Build.Dependency,
    lsp: *std.Build.Dependency,
) void {
    const super_cli = b.addExecutable(.{
        .name = "superhtml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .single_threaded = true,
        }),
    });

    super_cli.root_module.addImport("superhtml", superhtml);
    super_cli.root_module.addImport(
        "known_folders",
        folders.module("known-folders"),
    );
    super_cli.root_module.addImport("lsp", lsp.module("lsp"));
    super_cli.root_module.addOptions("build_options", options);

    const run_exe = b.addRunArtifact(super_cli);
    if (b.args) |args| run_exe.addArgs(args);
    const run_exe_step = b.step("run", "Run the SuperHTML CLI");
    run_exe_step.dependOn(&run_exe.step);

    b.installArtifact(super_cli);
}

fn setupWasmStep(
    b: *std.Build,
    optimize: std.builtin.OptimizeMode,
    options: *std.Build.Step.Options,
    superhtml: *std.Build.Module,
    lsp: *std.Build.Dependency,
) void {
    const wasm = b.step("wasm", "Generate a WASM build of the SuperHTML LSP for VSCode");
    const super_wasm_lsp = b.addExecutable(.{
        .name = "superhtml",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/wasm.zig"),
            .target = b.resolveTargetQuery(.{
                .cpu_arch = .wasm32,
                .os_tag = .wasi,
            }),
            .optimize = optimize,
            .single_threaded = true,
            .link_libc = false,
        }),
    });

    super_wasm_lsp.root_module.addImport("superhtml", superhtml);
    super_wasm_lsp.root_module.addImport("lsp", lsp.module("lsp"));
    super_wasm_lsp.root_module.addOptions("build_options", options);

    const target_output = b.addInstallArtifact(super_wasm_lsp, .{
        .dest_dir = .{ .override = .{ .custom = "" } },
    });
    wasm.dependOn(&target_output.step);
}

fn setupFetchLanguageSubtagRegistryStep(
    b: *std.Build,
    target: std.Build.ResolvedTarget,
) void {
    const step = b.step(
        "fetch-language-subtag-registry",
        "Fetch the IANA language subtag registry",
    );
    const fetcher = b.addExecutable(.{
        .name = "language-subtag-fetcher",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/html/language_tag/fetch.zig"),
            .target = target,
        }),
    });
    const fetch = b.addRunArtifact(fetcher);
    fetch.has_side_effects = true;
    fetch.addFileArg(b.path("src/html/language_tag/registry.txt"));
    step.dependOn(&fetch.step);
}

fn setupReleaseStep(
    b: *std.Build,
    release_step: *std.Build.Step,
) void {
    const targets: []const std.Target.Query = &.{
        .{ .cpu_arch = .aarch64, .os_tag = .macos },
        .{ .cpu_arch = .aarch64, .os_tag = .linux },
        .{ .cpu_arch = .x86_64, .os_tag = .macos },
        .{ .cpu_arch = .x86_64, .os_tag = .linux, .abi = .musl },
        .{ .cpu_arch = .x86_64, .os_tag = .windows },
        .{ .cpu_arch = .aarch64, .os_tag = .windows },
    };

    for (targets) |t| {
        const target = b.resolveTargetQuery(t);
        const optimize = std.builtin.OptimizeMode.ReleaseFast;
        const tt_root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
        });
        addDependencies(b, tt_root_module, target, optimize);

        const tt_exe_release = b.addExecutable(.{
            .name = "typetest",
            .root_module = tt_root_module,
        });

        switch (t.os_tag.?) {
            .macos, .windows => {
                const archive_name = b.fmt("{s}.zip", .{
                    t.zigTriple(b.allocator) catch unreachable,
                });

                const zip = b.addSystemCommand(&.{
                    "zip",
                    "-9",
                    // "-dd",
                    "-q",
                    "-j",
                });
                const archive = zip.addOutputFileArg(archive_name);
                zip.addDirectoryArg(tt_exe_release.getEmittedBin());
                _ = zip.captureStdOut();

                release_step.dependOn(&b.addInstallFileWithDir(
                    archive,
                    .{ .custom = "releases" },
                    archive_name,
                ).step);
            },
            else => {
                const archive_name = b.fmt("{s}.tar.xz", .{
                    t.zigTriple(b.allocator) catch unreachable,
                });

                const tar = b.addSystemCommand(&.{
                    "tar",
                    "-cJf",
                });

                const archive = tar.addOutputFileArg(archive_name);
                tar.addArg("-C");

                tar.addDirectoryArg(tt_exe_release.getEmittedBinDirectory());
                tar.addArg("typetest");
                _ = tar.captureStdOut();

                release_step.dependOn(&b.addInstallFileWithDir(
                    archive,
                    .{ .custom = "releases" },
                    archive_name,
                ).step);
            },
        }
    }
}

const Version = union(Kind) {
    tag: []const u8,
    commit: []const u8,
    // not in a git repo
    unknown,

    pub const Kind = enum { tag, commit, unknown };

    pub fn string(v: Version) []const u8 {
        return switch (v) {
            .tag, .commit => |tc| tc,
            .unknown => "unknown",
        };
    }
};
fn getGitVersion(b: *std.Build) Version {
    const git_path = b.findProgram(&.{"git"}, &.{}) catch return .unknown;
    var out: u8 = undefined;
    const git_describe = std.mem.trim(
        u8,
        b.runAllowFail(&[_][]const u8{
            git_path,            "-C",
            b.build_root.path.?, "describe",
            "--match",           "*.*.*",
            "--tags",
        }, &out, .Ignore) catch return .unknown,
        " \n\r",
    );

    switch (std.mem.count(u8, git_describe, "-")) {
        0 => return .{ .tag = git_describe },
        2 => {
            // Untagged development build (e.g. 0.8.0-684-gbbe2cca1a).
            var it = std.mem.splitScalar(u8, git_describe, '-');
            const tagged_ancestor = it.next() orelse unreachable;
            const commit_height = it.next() orelse unreachable;
            const commit_id = it.next() orelse unreachable;

            // Check that the commit hash is prefixed with a 'g'
            // (it's a Git convention)
            if (commit_id.len < 1 or commit_id[0] != 'g') {
                std.debug.panic("Unexpected `git describe` output: {s}\n", .{git_describe});
            }

            // The version is reformatted in accordance with
            // the https://semver.org specification.
            return .{
                .commit = b.fmt("{s}-dev.{s}+{s}", .{
                    tagged_ancestor,
                    commit_height,
                    commit_id[1..],
                }),
            };
        },
        else => std.debug.panic(
            "Unexpected `git describe` output: {s}\n",
            .{git_describe},
        ),
    }
}
