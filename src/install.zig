const std = @import("std");

const environment = @import("./environment.zig");
const versions = @import("./versions.zig");
const log = &@import("./log.zig").log;

/// Install a Zig version.
pub fn install_version(allocator: std.mem.Allocator, version: []const u8, path: []const u8, zig_version: versions.ZigVersion) !void {
    // Initialise install dir.
    var install_dir = std.fs.cwd().makeOpenPath(path, .{}) catch {
        return error.InvalidPermissions;
    };
    defer install_dir.close();

    // Fetch tar.
    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    var headerBuffer: [256 * 1024]u8 = undefined;
    const uri = std.Uri.parse(zig_version.binary.tarball) catch unreachable;

    var req = try client.open(.GET, uri, .{ .server_header_buffer = &headerBuffer });
    defer req.deinit();

    try req.send();
    try req.wait();

    // unpack tar
    try environment.unpack_tar(allocator, install_dir, req.reader());

    // Create symbolic link
    try environment.create_version_sym_link(allocator, version);
}
