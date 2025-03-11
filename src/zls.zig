const std = @import("std");
const log = &@import("./log.zig").log;
const install = @import("./install.zig");
const environment = @import("./environment.zig");

/// Install a ZLS version.
pub fn install_zls(allocator: std.mem.Allocator, path: []const u8) !void {
    var install_dir = std.fs.cwd().openDir(path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer install_dir.close();

    if (environment.dirExists(install_dir, "zls")) {
        return error.ZLSAlreadyInstalled;
    }

    log.info("Cloning ZLS...", .{});
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

    log.info("ZLS cloned.", .{});
}

/// Checkout ZLS version.
pub fn checkout_zls_version(allocator: std.mem.Allocator, version: []const u8, path: []const u8) !void {
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
pub fn build_zls(allocator: std.mem.Allocator, path: []const u8) !void {
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
        log.err("{s}", .{output.stderr});
        return error.FailedToBuildZLS;
    }
}

/// Move ZLS version to Zig install path.
pub fn move_zls_to_path(allocator: std.mem.Allocator, version: []const u8, zig_home_path: []const u8) !void {
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
