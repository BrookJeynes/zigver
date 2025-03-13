const std = @import("std");

const clap = @import("clap");
const options = @import("options");

const versions = @import("./versions.zig");

const log = &@import("./logger.zig").log;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help             Display this help and exit.
        \\-l, --list             List installed Zig versions.
        \\-v, --version          Get the version of Zigver.
        \\-i, --install <str>    Install a version of Zig. Use `latest` or `master` for nightly builds. Use the --with-zls flag to install ZLS alongside the desired Zig version.
        \\-u, --use <str>        Use an installed version of Zig.
        \\-r, --remove <str>     Remove a version of Zig.
        \\    --update           Update Zig version. Only applicable when running latest. Will update ZLS if installed.
        \\
        \\-f, --force            Force an install/uninstall.
        \\    --with-zls         Install the corresponding ZLS LSP version. Only supports Zig versions 0.11.0 and above.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = allocator,
    }) catch {
        try log.err("Invalid argument. Use the `--help` flag to see available arguments.", .{});
        std.posix.exit(1);
    };
    defer res.deinit();

    const force = res.args.force != 0;
    const with_zls = res.args.@"with-zls" != 0;

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    } else if (res.args.list != 0) {
        versions.listInstalledVersions(allocator) catch |err| switch (err) {
            error.InvalidPermissions => try log.err("Unable to install due to permissions.", .{}),
            else => try log.err("Unable to list out installed versions - {}.", .{err}),
        };
    } else if (res.args.version != 0) {
        try log.info("Zigver: v{}", .{options.version});
    } else if (res.args.install) |version| {
        const ver = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.installVersion(allocator, ver, force, with_zls) catch |err| switch (err) {
            error.UnknownVersion => try log.err("Could not find requested version.", .{}),
            error.AlreadyRunningLatest => try log.info("Already running latest {s} release. Use the `--force` flag to force an install.", .{version}),
            error.VersionAlreadyInstalled => try log.info("Already running latest {s} release. Use the `--force` flag to force an install.", .{version}),
            error.InvalidPermissions => try log.err("Unable to install due to permissions.", .{}),
            error.UnsupportedZigVersionForZLS => try log.err("ZLS is not supported for requested version.", .{}),
            error.FailedToCloneZLS => try log.err("Failed to clone ZLS repository.", .{}),
            error.FailedToBuildZLS => try log.err("Failed to build ZLS.", .{}),
            else => try log.err("Unable to install version - {}.", .{err}),
        };
    } else if (res.args.use) |version| {
        const ver = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.useVersion(allocator, ver) catch |err| switch (err) {
            error.VersionNotFound => try log.err("The requested version is not installed.", .{}),
            error.InvalidPermissions => try log.err("Unable to use due to permissions.", .{}),
            else => try log.err("Unable to use version - {}.", .{err}),
        };
    } else if (res.args.remove) |version| {
        const ver = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.removeVersion(allocator, ver, force) catch |err| switch (err) {
            error.VersionInUse => try log.err("Unable to remove a version in-use. Use the `--force` flag to force an uninstall.", .{}),
            error.VersionNotFound => try log.err("The requested version is not installed.", .{}),
            error.InvalidPermissions => try log.err("Unable to uninstall due to permissions.", .{}),
            error.EmptyVersion => try log.err("Zig is not detected on the system.", .{}),
            else => try log.err("Unable to uninstall version - {}.", .{err}),
        };
    } else if (res.args.update != 0) {
        versions.updateVersion(allocator, force) catch |err| switch (err) {
            error.InvalidPermissions => try log.err("Unable to uninstall due to permissions.", .{}),
            error.AlreadyRunningLatest => try log.info("Already running latest release. Use the `--force` flag to force an update.", .{}),
            error.EmptyVersion => try log.err("Zig is not detected on the system.", .{}),
            error.UnsupportedZigVersionForZLS => try log.err("ZLS is not supported for requested version.", .{}),
            error.FailedToCloneZLS => try log.err("Failed to clone ZLS repository.", .{}),
            error.FailedToBuildZLS => try log.err("Failed to build ZLS.", .{}),
            else => try log.err("Unable to update version - {}.", .{err}),
        };
    }
}
