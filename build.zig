const std = @import("std");
const builtin = @import("builtin");

const min_zig_string = "0.13.0-dev.211+6a65561e3";
const version = std.SemanticVersion{ .major = 0, .minor = 2, .patch = 0 };

const targets: []const std.Target.Query = &.{
    .{ .cpu_arch = .aarch64, .os_tag = .macos },
    .{ .cpu_arch = .aarch64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .linux },
    .{ .cpu_arch = .x86_64, .os_tag = .macos },
    .{ .cpu_arch = .x86_64, .os_tag = .windows },
};

const Build = blk: {
    const current_zig = builtin.zig_version;
    const min_zig = std.SemanticVersion.parse(min_zig_string) catch unreachable;
    if (current_zig.order(min_zig) == .lt) {
        @compileError(std.fmt.comptimePrint("Your Zig version v{} does not meet the minimum build requirement of v{}", .{ current_zig, min_zig }));
    }
    break :blk std.Build;
};

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const options = b.addOptions();

    options.addOption([]const u8, "min_zig_string", min_zig_string);

    options.addOption(std.SemanticVersion, "zigver_version", version);
    const exe_options_module = options.createModule();

    const clap_dep = b.dependency("clap", .{ .target = target });
    const clap_mod = clap_dep.module("clap");

    const exe = b.addExecutable(.{
        .name = "zigver",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("clap", clap_mod);
    exe.root_module.addImport("options", exe_options_module);
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);

    const exe_unit_tests = b.addTest(.{
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    const run_exe_unit_tests = b.addRunArtifact(exe_unit_tests);
    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_exe_unit_tests.step);

    // Building targets for release.
    for (targets) |t| {
        const build_target = b.resolveTargetQuery(t);

        const build_clap_dep = b.dependency("clap", .{ .target = build_target });
        const build_clap_mod = build_clap_dep.module("clap");

        const build_exe = b.addExecutable(.{
            .name = "zigver",
            .root_source_file = b.path("src/main.zig"),
            .target = build_target,
            .optimize = optimize,
        });
        build_exe.root_module.addImport("clap", build_clap_mod);
        build_exe.root_module.addImport("options", exe_options_module);
        b.installArtifact(exe);

        const target_output = b.addInstallArtifact(exe, .{
            .dest_dir = .{
                .override = .{
                    .custom = try t.zigTriple(b.allocator),
                },
            },
        });

        b.getInstallStep().dependOn(&target_output.step);
    }
}
