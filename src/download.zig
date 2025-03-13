const std = @import("std");

/// Fetch JSON specifying Zig versions.
/// The caller owns the returned memory.
pub fn fetchVersions(allocator: std.mem.Allocator) ![]const u8 {
    var body = std.ArrayList(u8).init(allocator);
    defer body.deinit();

    var client = std.http.Client{ .allocator = allocator };
    defer client.deinit();

    const fetch_options = std.http.Client.FetchOptions{
        .location = std.http.Client.FetchOptions.Location{
            .url = "https://ziglang.org/download/index.json",
        },
        .response_storage = .{ .dynamic = &body },
        .max_append_size = 100 * 1024 * 1024,
    };

    _ = try client.fetch(fetch_options);

    return body.toOwnedSlice();
}
