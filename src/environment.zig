const std = @import("std");
const builtin = @import("builtin");

const log = &@import("logger.zig").log;

pub fn getHomeDir() !std.fs.Dir {
    return std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
        try log.err("Could not find install directory, $HOME environment variable is not set", .{});
        return error.MissingHomeEnvironmentVariable;
    }, .{ .iterate = true });
}

pub fn fileExists(dir: std.fs.Dir, path: []const u8) bool {
    const result = blk: {
        _ = dir.openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => break :blk false,
                else => {
                    break :blk true;
                },
            }
        };
        break :blk true;
    };
    return result;
}

pub fn dirExists(dir: std.fs.Dir, path: []const u8) bool {
    const result = blk: {
        _ = dir.openDir(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => break :blk false,
                else => {
                    break :blk true;
                },
            }
        };
        break :blk true;
    };
    return result;
}

pub fn createVersionSymLink(
    allocator: std.mem.Allocator,
    version: []const u8,
) !void {
    var home_dir = try getHomeDir();
    defer home_dir.close();

    var zig_home_path_buf: [std.fs.max_path_bytes]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig", &zig_home_path_buf);

    const install_path = try std.fs.path.join(allocator, &[_][]const u8{
        zig_home_path,
        "versions",
        version,
    });
    defer allocator.free(install_path);

    var global_folder = try home_dir.openDir(".zig", .{ .iterate = true });
    defer global_folder.close();

    // TODO: Symbolic links won't be detected if they're broken.
    if (fileExists(global_folder, "current")) {
        try global_folder.deleteTree("current");
    }

    try global_folder.symLink(
        install_path,
        "current",
        .{ .is_directory = true },
    );
}

pub fn unpackTar(
    allocator: std.mem.Allocator,
    dir: std.fs.Dir,
    reader: anytype,
) !void {
    var decompressed = try std.compress.xz.decompress(allocator, reader);
    defer decompressed.deinit();
    try std.tar.pipeToFileSystem(dir, decompressed.reader(), .{
        .mode_mode = .executable_bit_only,
        .strip_components = 1,
    });
}
