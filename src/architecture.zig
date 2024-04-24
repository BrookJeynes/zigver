const builtin = @import("builtin");

const arch = switch (builtin.cpu.arch) {
    .x86_64 => "x86_64",
    .aarch64 => "aarch64",
    else => @compileError("Unsupported CPU Architecture"),
};

const os = switch (builtin.os.tag) {
    .windows => "windows",
    .linux => "linux",
    .macos => "macos",
    else => @compileError("Unsupported OS"),
};

pub const url_platform = os ++ "-" ++ arch;
pub const json_platform = arch ++ "-" ++ os;
pub const archive_ext = if (builtin.os.tag == .windows) "zip" else "tar.xz";
