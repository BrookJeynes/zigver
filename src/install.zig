const std = @import("std");
const environment = @import("./environment.zig");
const versions = @import("./versions.zig");

/// Install a Zig version.
pub fn installVersion(allocator: std.mem.Allocator, version: []const u8, path: []const u8, zig_version: versions.ZigVersion) !void {
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

    try environment.unpackTar(allocator, install_dir, req.reader());
    try environment.createVersionSymLink(allocator, version);
}
