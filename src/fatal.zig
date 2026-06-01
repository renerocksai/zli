const std = @import("std");

/// Format and print an error message to stderr, then exit with an exit code of 1.
pub fn fatal(io: std.Io, comptime fmt_string: []const u8, args: anytype) noreturn {
    var stderr_buffer: [1024]u8 = undefined;
    var stderr_writer = std.Io.File.stderr().writer(io, &stderr_buffer);
    const writer = &stderr_writer.interface;
    writer.print("error: " ++ fmt_string ++ "\n", args) catch {};
    writer.flush() catch {};
    std.process.exit(1);
}
