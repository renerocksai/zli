const std = @import("std");
const expect = std.testing.expect;

const strings = @import("./strings.zig");

const help_strings = [_][]const u8{ "--help", "-h", "help" };

/// Determines if a given option name matches a request for help.
pub fn requested_help(option_name: []const u8) bool {
    for (help_strings) |h| {
        if (strings.eql(h, option_name)) {
            return true;
        }
    }

    return false;
}

test requested_help {
    for (help_strings) |str| {
        try expect(requested_help(str) == true);
    }

    for ([_][]const u8{ "bad", "", "-", "--", "h", "he", "hel", "--hel", "--help=1", "-hello" }) |str| {
        try expect(!requested_help(str));
    }
}

/// If a container contains a help message, will print.
pub fn try_print_help(io: std.Io, comptime T: type) void {
    if (@hasDecl(T, "help")) {
        var stdout_buffer: [1024]u8 = undefined;
        var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
        const writer = &stdout_writer.interface;
        writer.writeAll(T.help) catch std.process.exit(1);
        writer.flush() catch std.process.exit(1);
        std.process.exit(0);
    }
}
