const std = @import("std");
const options = @import("options");

const environment = @import("./environment.zig");
const install = @import("./install.zig");
const log = &@import("./log.zig").log;
const architecture = @import("./architecture.zig");
const download = @import("./download.zig");
const zls = @import("./zls.zig");

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
        const json_string = try download.fetch_zig_versions_json(allocator);
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

/// Zigver version.
pub fn get_zigver_version() void {
    log.info("Zigver: v{}", .{options.version});
}

/// Get installed versions on file system.
/// The caller owns the returned memory.
fn get_installed_versions(allocator: std.mem.Allocator) !std.ArrayList(Version) {
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

        const zls_path = try std.fs.path.join(allocator, &[_][]const u8{ ".zig", "versions", file.name, "zls" });
        defer allocator.free(zls_path);

        try versions.append(.{ .name = file.name, .has_zls = environment.fileExists(home_dir, zls_path) });
    }

    return versions;
}

/// List installed Zig versions.
pub fn list_installed_versions(allocator: std.mem.Allocator) !void {
    var versions = try get_installed_versions(allocator);
    defer versions.deinit();

    log.info("Installed versions:", .{});
    // TODO: Sort this output.
    // TODO: List current version.
    for (versions.items) |version| {
        log.info("  - {s}{s}", .{ version.name, if (version.has_zls) " (with ZLS)" else "" });
    }
}

/// Check if a Zig version is installed.
pub fn is_version_installed(allocator: std.mem.Allocator, version: []const u8) !bool {
    var versions = try get_installed_versions(allocator);
    defer versions.deinit();

    for (versions.items) |v| {
        if (std.mem.eql(u8, v.name, version)) {
            return true;
        }
    }

    return false;
}

/// Get the current version of Zig running local on system.
pub fn get_local_zig_version(allocator: std.mem.Allocator) ![]const u8 {
    var child_process = std.process.Child.init(&[_][]const u8{ "zig", "version" }, allocator);
    child_process.stdin_behavior = .Close;
    child_process.stdout_behavior = .Pipe;
    child_process.stderr_behavior = .Close;

    try child_process.spawn();

    var buf: [100]u8 = undefined;
    const local_version = if (child_process.stdout) |stdout| try stdout.reader().readUntilDelimiterOrEof(&buf, '\n') orelse return error.EmptyVersion else return error.EmptyVersion;

    _ = try child_process.kill();

    return local_version;
}

/// Switch active Zig version.
pub fn use_version(allocator: std.mem.Allocator, version: []const u8) !void {
    const installed = try is_version_installed(allocator, version);
    if (installed == false) {
        return error.VersionNotFound;
    }

    try environment.create_version_sym_link(allocator, version);
    log.info("Now using Zig {s}.", .{version});
}

/// Remove a local Zig version.
pub fn remove_version(allocator: std.mem.Allocator, version: []const u8, force: bool) !void {
    // BUG: This won't catch if you're on master.
    const current_version = try get_local_zig_version(allocator);
    if (std.mem.eql(u8, version, current_version) and force == false) {
        return error.VersionInUse;
    }

    const installed = try is_version_installed(allocator, version);
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

    log.info("Removed version {s}.", .{version});
}

/// Install a Zig version and switch to it.
pub fn install_version(allocator: std.mem.Allocator, version: []const u8, force: bool, with_zls: bool) !void {
    var home_dir = try environment.getHomeDir();
    defer home_dir.close();

    var zig_home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig/", &zig_home_path_buf);

    const install_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "versions", version });
    defer allocator.free(install_path);

    var zig_version = try ZigVersion.init(allocator, version);
    defer zig_version.deinit();

    if (force == true) {
        try remove_version(allocator, version, force);
    } else {
        if (environment.fileExists(home_dir, install_path)) {
            if (with_zls == true) {
                try install_zls(allocator, version, home_dir, zig_home_path);
            }
            return error.VersionAlreadyInstalled;
        }

        blk: {
            if (zig_version.version) |cloud_version| {
                const local_version = get_local_zig_version(allocator) catch break :blk;

                if (std.mem.eql(u8, local_version, cloud_version)) {
                    return error.AlreadyRunningLatest;
                }
            }
        }
    }

    log.info("Installing Zig {s}...", .{zig_version.version orelse version});
    try install.install_version(allocator, version, install_path, zig_version);
    log.info("Zig {s} installed.", .{zig_version.version orelse version});

    if (with_zls == true) {
        try install_zls(allocator, version, home_dir, zig_home_path);
    }
}

pub fn install_zls(allocator: std.mem.Allocator, version: []const u8, home_dir: std.fs.Dir, zig_home_path: []const u8) !void {
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

    log.info("Installing ZLS.", .{});
    zls.install_zls(allocator, zig_home_path) catch |err| switch (err) {
        error.ZLSAlreadyInstalled => {
            log.info("ZLS already installed. Skipping clone.", .{});
        },
        else => {
            return err;
        },
    };

    const zls_install_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "zls" });
    defer allocator.free(zls_install_path);
    try zls.checkout_zls_version(allocator, version, zls_install_path);

    const zls_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "versions", version, "zls" });
    defer allocator.free(zls_path);
    if (!environment.fileExists(home_dir, zls_path)) {
        log.info("Building ZLS...", .{});
        try zls.build_zls(allocator, zls_install_path);
        log.info("ZLS built.", .{});

        try zls.move_zls_to_path(allocator, version, zig_home_path);
    } else {
        log.info("ZLS already built. Skipping build.", .{});
    }
    log.info("Installed ZLS.", .{});
}

/// Update a Zig version.
pub fn update_version(allocator: std.mem.Allocator, force: bool) !void {
    // Switch to master.
    try environment.create_version_sym_link(allocator, "master");

    if (force == false) {
        var zig_version = try ZigVersion.init(allocator, "master");
        defer zig_version.deinit();

        if (zig_version.version) |cloud_version| {
            const local_version = try get_local_zig_version(allocator);

            if (std.mem.eql(u8, local_version, cloud_version)) {
                return error.AlreadyRunningLatest;
            }
        }
    }

    var home_dir = try environment.getHomeDir();
    defer home_dir.close();
    var zig_home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig/", &zig_home_path_buf);
    const zls_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "versions", "master", "zls" });
    defer allocator.free(zls_path);

    try install_version(allocator, "master", true, environment.fileExists(home_dir, zls_path));
}
