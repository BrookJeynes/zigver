const std = @import("std");
const clap = @import("clap");

const versions = @import("./versions.zig");
const log = &@import("./log.zig").log;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    log.init();

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
        log.err("Invalid argument. Use the `--help` flag to see available arguments.", .{});
        std.posix.exit(1);
    };
    defer res.deinit();

    const force = res.args.force != 0;
    const with_zls = res.args.@"with-zls" != 0;

    if (res.args.help != 0) {
        return clap.help(std.io.getStdErr().writer(), clap.Help, &params, .{});
    } else if (res.args.list != 0) {
        versions.list_installed_versions(allocator) catch |err| switch (err) {
            error.InvalidPermissions => log.err("Unable to install due to permissions.", .{}),
            else => log.err("Unable to list out installed versions - {}.", .{err}),
        };
    } else if (res.args.version != 0) {
        versions.get_zigver_version();
    } else if (res.args.install) |version| {
        const v = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.install_version(allocator, v, force, with_zls) catch |err| switch (err) {
            error.UnknownVersion => log.err("Could not find requested version.", .{}),
            error.AlreadyRunningLatest => log.info("Already running latest {s} release. Use the `--force` flag to force an install.", .{version}),
            error.VersionAlreadyInstalled => log.info("Already running latest {s} release. Use the `--force` flag to force an install.", .{version}),
            error.InvalidPermissions => log.err("Unable to install due to permissions.", .{}),
            error.UnsupportedZigVersionForZLS => log.err("ZLS is not supported for requested version.", .{}),
            error.FailedToCloneZLS => log.err("Failed to clone ZLS repository.", .{}),
            error.FailedToBuildZLS => log.err("Failed to build ZLS.", .{}),
            else => log.err("Unable to install version - {}.", .{err}),
        };
    } else if (res.args.use) |version| {
        const v = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.use_version(allocator, v) catch |err| switch (err) {
            error.VersionNotFound => log.err("The requested version is not installed.", .{}),
            error.InvalidPermissions => log.err("Unable to use due to permissions.", .{}),
            else => log.err("Unable to use version - {}.", .{err}),
        };
    } else if (res.args.remove) |version| {
        const v = if (std.mem.eql(u8, version, "latest")) "master" else version;

        versions.remove_version(allocator, v, force) catch |err| switch (err) {
            error.VersionInUse => log.err("Unable to remove a version in-use. Use the `--force` flag to force an uninstall.", .{}),
            error.VersionNotFound => log.err("The requested version is not installed.", .{}),
            error.InvalidPermissions => log.err("Unable to uninstall due to permissions.", .{}),
            error.EmptyVersion => log.err("Zig is not detected on the system.", .{}),
            else => log.err("Unable to uninstall version - {}.", .{err}),
        };
    } else if (res.args.update != 0) {
        versions.update_version(allocator, force) catch |err| switch (err) {
            error.InvalidPermissions => log.err("Unable to uninstall due to permissions.", .{}),
            error.AlreadyRunningLatest => log.info("Already running latest release. Use the `--force` flag to force an update.", .{}),
            error.EmptyVersion => log.err("Zig is not detected on the system.", .{}),
            error.UnsupportedZigVersionForZLS => log.err("ZLS is not supported for requested version.", .{}),
            error.FailedToCloneZLS => log.err("Failed to clone ZLS repository.", .{}),
            error.FailedToBuildZLS => log.err("Failed to build ZLS.", .{}),
            else => log.err("Unable to update version - {}.", .{err}),
        };
    }
}
