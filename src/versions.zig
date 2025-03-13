const std = @import("std");

const architecture = @import("./architecture.zig");
const download = @import("./download.zig");
const environment = @import("./environment.zig");
const install = @import("./install.zig");
const zls = @import("./zls.zig");

const log = &@import("./logger.zig").log;

pub const ZigVersion = struct {
    /// Only in "master" version.
    version: ?[]const u8,
    date: []const u8,
    docs: []const u8,
    /// Version 0.5.0 and below do not contain this.
    std_docs: ?[]const u8,
    /// "master" version does not contain this.
    notes: ?[]const u8,
    src: Install,
    binary: Install,

    allocator: std.mem.Allocator,
    json: std.json.Parsed(std.json.Value),

    pub fn init(allocator: std.mem.Allocator, version: []const u8) !ZigVersion {
        const json_string = try download.fetchZigVersions(allocator);
        // TODO: Freeing this might mess up things later down the line.
        defer allocator.free(json_string);

        const json = try std.json.parseFromSlice(std.json.Value, allocator, json_string, .{});
        errdefer json.deinit();

        const parsed_version = json.value.object.get(version) orelse {
            return error.UnknownVersion;
        };
        const src = parsed_version.object.get("src").?;
        const platform = parsed_version.object.get(architecture.json_platform).?;

        return ZigVersion{
            .version = if (parsed_version.object.get("version")) |v| v.string else null,
            .date = parsed_version.object.get("date").?.string,
            .docs = parsed_version.object.get("docs").?.string,
            .std_docs = if (parsed_version.object.get("stdDocs")) |sd| sd.string else null,
            .notes = if (parsed_version.object.get("notes")) |n| n.string else null,
            .src = .{
                .tarball = src.object.get("tarball").?.string,
                .shasum = src.object.get("shasum").?.string,
                .size = src.object.get("size").?.string,
            },
            .binary = .{
                .tarball = platform.object.get("tarball").?.string,
                .shasum = platform.object.get("shasum").?.string,
                .size = platform.object.get("size").?.string,
            },

            .allocator = allocator,
            .json = json,
        };
    }

    pub fn deinit(self: *ZigVersion) void {
        self.json.deinit();
    }
};

const Install = struct {
    tarball: []const u8,
    shasum: []const u8,
    size: []const u8,
};

pub const Version = struct {
    name: []const u8,
    has_zls: bool,
};

/// Get installed versions on file system.
/// The caller owns the returned memory.
fn getInstalledVersions(allocator: std.mem.Allocator) !std.ArrayList(Version) {
    var home_dir = try environment.getHomeDir();
    defer home_dir.close();

    var versions = std.ArrayList(Version).init(allocator);

    const versions_path = try std.fs.path.join(allocator, &[_][]const u8{ ".zig", "versions" });
    defer allocator.free(versions_path);

    var dir = home_dir.openDir(versions_path, .{ .iterate = true }) catch |err| blk: {
        switch (err) {
            error.FileNotFound => {
                break :blk try home_dir.makeOpenPath(versions_path, .{ .iterate = true });
            },
            else => {
                return error.InvalidPermissions;
            },
        }
    };
    defer dir.close();

    var it = dir.iterate();
    while (try it.next()) |file| {
        if (file.kind != .directory) {
            continue;
        }

        const zls_path = try std.fs.path.join(
            allocator,
            &[_][]const u8{ ".zig", "versions", file.name, "zls" },
        );
        defer allocator.free(zls_path);

        try versions.append(.{
            .name = file.name,
            .has_zls = environment.fileExists(home_dir, zls_path),
        });
    }

    return versions;
}

/// List installed Zig versions.
pub fn listInstalledVersions(allocator: std.mem.Allocator) !void {
    var versions = try getInstalledVersions(allocator);
    defer versions.deinit();

    try log.info("Installed versions:", .{});
    // TODO: Sort this output.
    // TODO: List current version.
    for (versions.items) |version| {
        try log.info("  - {s}{s}", .{ version.name, if (version.has_zls) " (with ZLS)" else "" });
    }
}

/// Check if a Zig version is installed.
pub fn isVersionInstalled(allocator: std.mem.Allocator, version: []const u8) !bool {
    var versions = try getInstalledVersions(allocator);
    defer versions.deinit();

    for (versions.items) |v| {
        if (std.mem.eql(u8, v.name, version)) {
            return true;
        }
    }

    return false;
}

/// Get the current version of Zig running local on system.
pub fn getLocalZigVersion(allocator: std.mem.Allocator) ![]const u8 {
    var child_process = std.process.Child.init(&[_][]const u8{ "zig", "version" }, allocator);
    child_process.stdin_behavior = .Close;
    child_process.stdout_behavior = .Pipe;
    child_process.stderr_behavior = .Close;

    try child_process.spawn();

    var buf: [100]u8 = undefined;
    const local_version = if (child_process.stdout) |stdout|
        try stdout.reader().readUntilDelimiterOrEof(&buf, '\n') orelse return error.EmptyVersion
    else
        return error.EmptyVersion;

    _ = try child_process.kill();

    return local_version;
}

/// Switch active Zig version.
pub fn useVersion(allocator: std.mem.Allocator, version: []const u8) !void {
    const installed = try isVersionInstalled(allocator, version);
    if (installed == false) {
        return error.VersionNotFound;
    }

    try environment.createVersionSymLink(allocator, version);
    try log.info("Now using Zig {s}.", .{version});
}

/// Remove a local Zig version.
pub fn removeVersion(
    allocator: std.mem.Allocator,
    version: []const u8,
    force: bool,
) !void {
    // BUG: This won't catch if you're on master.
    const current_version = try getLocalZigVersion(allocator);
    if (std.mem.eql(u8, version, current_version) and force == false) {
        return error.VersionInUse;
    }

    const installed = try isVersionInstalled(allocator, version);
    if (installed == false) {
        return error.VersionNotFound;
    }

    var home_dir = try environment.getHomeDir();
    defer home_dir.close();

    var install_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const install_path_alloc = try std.fs.path.join(allocator, &[_][]const u8{ ".zig", "versions", version });
    defer allocator.free(install_path_alloc);
    const install_path = try home_dir.realpath(install_path_alloc, &install_path_buf);

    if (environment.fileExists(home_dir, install_path)) {
        try std.fs.deleteTreeAbsolute(install_path);
    }

    try log.info("Removed version {s}.", .{version});
}

/// Install a Zig version and switch to it.
pub fn installVersion(
    allocator: std.mem.Allocator,
    version: []const u8,
    force: bool,
    with_zls: bool,
) !void {
    var home_dir = try environment.getHomeDir();
    defer home_dir.close();

    var zig_home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig/", &zig_home_path_buf);

    const install_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "versions", version });
    defer allocator.free(install_path);

    var zig_version = try ZigVersion.init(allocator, version);
    defer zig_version.deinit();

    if (force == true) {
        try removeVersion(allocator, version, force);
    } else {
        if (environment.fileExists(home_dir, install_path)) {
            if (with_zls == true) {
                try installZls(allocator, version, home_dir, zig_home_path);
            }
            return error.VersionAlreadyInstalled;
        }

        blk: {
            if (zig_version.version) |cloud_version| {
                const local_version = getLocalZigVersion(allocator) catch break :blk;

                if (std.mem.eql(u8, local_version, cloud_version)) {
                    return error.AlreadyRunningLatest;
                }
            }
        }
    }

    try log.info("Installing Zig {s}...", .{zig_version.version orelse version});
    try install.installVersion(allocator, version, install_path, zig_version);
    try log.info("Zig {s} installed.", .{zig_version.version orelse version});

    if (with_zls == true) {
        try installZls(allocator, version, home_dir, zig_home_path);
    }
}

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
    zls.install_zls(allocator, zig_home_path) catch |err| switch (err) {
        error.ZLSAlreadyInstalled => {
            try log.info("ZLS already installed. Skipping clone.", .{});
        },
        else => {
            return err;
        },
    };

    const zls_install_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "zls" });
    defer allocator.free(zls_install_path);
    try zls.checkout_zls_version(allocator, version, zls_install_path);

    const zls_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ zig_home_path, "versions", version, "zls" },
    );
    defer allocator.free(zls_path);
    if (!environment.fileExists(home_dir, zls_path)) {
        try log.info("Building ZLS...", .{});
        try zls.build_zls(allocator, zls_install_path);
        try log.info("ZLS built.", .{});

        try zls.move_zls_to_path(allocator, version, zig_home_path);
    } else {
        try log.info("ZLS already built. Skipping build.", .{});
    }
    try log.info("Installed ZLS.", .{});
}

/// Update a Zig version.
pub fn updateVersion(allocator: std.mem.Allocator, force: bool) !void {
    // Switch to master.
    try environment.createVersionSymLink(allocator, "master");

    if (force == false) {
        var zig_version = try ZigVersion.init(allocator, "master");
        defer zig_version.deinit();

        if (zig_version.version) |cloud_version| {
            const local_version = try getLocalZigVersion(allocator);

            if (std.mem.eql(u8, local_version, cloud_version)) {
                return error.AlreadyRunningLatest;
            }
        }
    }

    var home_dir = try environment.getHomeDir();
    defer home_dir.close();
    var zig_home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig/", &zig_home_path_buf);
    const zls_path = try std.fs.path.join(
        allocator,
        &[_][]const u8{ zig_home_path, "versions", "master", "zls" },
    );
    defer allocator.free(zls_path);

    try installVersion(allocator, "master", true, environment.fileExists(home_dir, zls_path));
}
