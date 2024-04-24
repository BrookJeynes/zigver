const std = @import("std");
const builtin = @import("builtin");

const log = &@import("./log.zig").log;

pub fn getHomeDir() !std.fs.Dir {
    switch (builtin.os.tag) {
        .linux, .macos => {
            return std.fs.openDirAbsolute(std.posix.getenv("HOME") orelse {
                log.err("Could not find install directory, $HOME environment variable is not set", .{});
                return error.MissingHomeEnvironmentVariable;
            }, .{ .iterate = true });
        },
        .windows => {
            return std.fs.openDirAbsolute(std.process.getenvW("USERPROFILE") orelse {
                log.err("Could not find install directory, %USERPROFILE% environment variable is not set", .{});
                return error.MissingHomeEnvironmentVariable;
            }, .{ .iterate = true });
        },
        else => @compileError("Unsupported OS"),
    }
}

pub fn fileExists(path: []const u8) bool {
    const result = blk: {
        _ = std.fs.cwd().openFile(path, .{}) catch |err| {
            switch (err) {
                error.FileNotFound => break :blk false,
                else => break :blk true,
            }
        };
        break :blk true;
    };
    return result;
}

pub fn create_version_sym_link(allocator: std.mem.Allocator, version: []const u8) !void {
    var home_dir = try getHomeDir();
    defer home_dir.close();

    var zig_home_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const zig_home_path = try home_dir.realpath(".zig/", &zig_home_path_buf);

    const install_path_alloc = try std.fs.path.join(allocator, &[_][]const u8{ ".zig/versions/", version });
    defer allocator.free(install_path_alloc);
    var install_path_buf: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const install_path = try home_dir.realpath(install_path_alloc, &install_path_buf);

    const sym_link_path = try std.fs.path.join(allocator, &[_][]const u8{ zig_home_path, "current" });
    defer allocator.free(sym_link_path);

    var global_folder = try home_dir.openDir(".zig/", .{ .iterate = true });
    defer global_folder.close();

    try create_sym_link(global_folder, install_path, sym_link_path, .{ .is_directory = true });
}

fn create_sym_link(dir: std.fs.Dir, target_path: []const u8, sym_link_path: []const u8, flags: std.fs.Dir.SymLinkFlags) !void {
    if (fileExists(sym_link_path)) {
        try std.fs.cwd().deleteTree(sym_link_path);
    }
    try dir.symLink(target_path, sym_link_path, flags);
}

pub fn unpack_tar(allocator: std.mem.Allocator, dir: std.fs.Dir, reader: anytype) !void {
    var decompressed = try std.compress.xz.decompress(allocator, reader);
    defer decompressed.deinit();
    try std.tar.pipeToFileSystem(dir, decompressed.reader(), .{ .mode_mode = .executable_bit_only, .strip_components = 1 });
}
