const std = @import("std");

const environment = @import("./environment.zig");
const install = @import("./install.zig");

const log = &@import("./logger.zig").log;

pub fn installZls(
    allocator: std.mem.Allocator,
    version: []const u8,
    home_dir: std.fs.Dir,
    zig_home_path: []const u8,
) !void {
    supported: {
        if (std.mem.eql(u8, version, "master")) break :supported;

        var version_it = std.mem.splitScalar(u8, version, '.');
        const major_str = version_it.next() orelse return error.UnsupportedZigVersionForZLS;
        const major = std.fmt.parseInt(usize, major_str, 10) catch return error.UnsupportedZigVersionForZLS;
        const minor_str = version_it.next() orelse return error.UnsupportedZigVersionForZLS;
        const minor = std.fmt.parseInt(usize, minor_str, 10) catch return error.UnsupportedZigVersionForZLS;

        // 0.11.0 and above support ZLS
        if (major == 0 and minor < 11) return error.UnsupportedZigVersionForZLS;
    }

    try log.info("Installing ZLS.", .{});
    cloneZls(allocator, zig_home_path) catch |err| switch (err) {
        error.ZLSAlreadyInstalled => {
            try log.info("ZLS already installed. Skipping clone.", .{});
        },
        else => {
            return err;
        },
    };

    const zls_install_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "zls" });
    defer allocator.free(zls_install_path);
    try checkoutZlsVersion(allocator, version, zls_install_path);

    const zls_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ zig_home_path, "versions", version, "zls" },
    );
    defer allocator.free(zls_path);
    if (!environment.fileExists(home_dir, zls_path)) {
        try log.info("Building ZLS...", .{});
        try buildZls(allocator, zls_install_path);
        try log.info("ZLS built.", .{});

        try moveZlsToPath(allocator, version, zig_home_path);
    } else {
        try log.info("ZLS already built. Skipping build.", .{});
    }
    try log.info("Installed ZLS.", .{});
}

/// Clone ZLS repo to disk.
pub fn cloneZls(allocator: std.mem.Allocator, path: []const u8) !void {
    var install_dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer install_dir.close();

    if (environment.dirExists(install_dir, "zls")) {
        return error.ZLSAlreadyInstalled;
    }

    try log.info("Cloning ZLS...", .{});
    const output = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "clone", "--recurse-submodules", "https://github.com/zigtools/zls.git" },
        .cwd_dir = install_dir,
    });
    defer allocator.free(output.stderr);
    defer allocator.free(output.stdout);

    if (output.term.Exited != 0) {
        return error.FailedToCloneZLS;
    }

    try log.info("ZLS cloned.", .{});
}

/// Checkout ZLS version.
pub fn checkoutZlsVersion(allocator: std.mem.Allocator, version: []const u8, path: []const u8) !void {
    var install_dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer install_dir.close();

    // Pull latest changes
    const pull_output = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "pull", ".", "master" },
        .cwd_dir = install_dir,
    });
    defer allocator.free(pull_output.stderr);
    defer allocator.free(pull_output.stdout);

    if (pull_output.term.Exited != 0) {
        return error.UnsupportedZigVersionForZLS;
    }

    // Checkout requested version
    const checkout_output = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "git", "checkout", version },
        .cwd_dir = install_dir,
    });
    defer allocator.free(checkout_output.stderr);
    defer allocator.free(checkout_output.stdout);

    if (checkout_output.term.Exited != 0) {
        return error.UnsupportedZigVersionForZLS;
    }
}

/// Build ZLS version.
pub fn buildZls(allocator: std.mem.Allocator, path: []const u8) !void {
    var install_dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer install_dir.close();

    const output = try std.process.Child.run(.{
        .allocator = allocator,
        .argv = &[_][]const u8{ "zig", "build", "-Doptimize=ReleaseSafe" },
        .cwd_dir = install_dir,
    });
    defer allocator.free(output.stderr);
    defer allocator.free(output.stdout);

    if (output.term.Exited != 0) {
        try log.err("{s}", .{output.stderr});
        return error.FailedToBuildZLS;
    }
}

/// Move ZLS version to Zig install path.
pub fn moveZlsToPath(allocator: std.mem.Allocator, version: []const u8, zig_home_path: []const u8) !void {
    var dir = std.fs.cwd().openDir(zig_home_path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer dir.close();

    const from = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "zls", "zig-out", "bin", "zls" });
    defer allocator.free(from);

    const to = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "versions", version, "zls" });
    defer allocator.free(to);

    try dir.rename(from, to);
}
