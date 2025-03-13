const std = @import("std");

const Logger = struct {
    const Self = @This();
    const BufferedFileWriter = std.io.BufferedWriter(4096, std.fs.File.Writer);

    stdout: BufferedFileWriter = BufferedFileWriter{
        .unbuffered_writer = std.io.getStdOut().writer(),
    },
    stderr: BufferedFileWriter = BufferedFileWriter{
        .unbuffered_writer = std.io.getStdErr().writer(),
    },

    pub fn info(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.stdout.writer().print(format ++ "\n", args);
        try self.stdout.flush();
    }

    pub fn err(self: *Self, comptime format: []const u8, args: anytype) !void {
        try self.stderr.writer().print(format ++ "\n", args);
        try self.stderr.flush();
    }
};

pub var log: Logger = Logger{};
