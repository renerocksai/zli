const std = @import("std");
const zli = @import("zli");

const Options = struct {
    port: u16 = 8080,
    duration_ms: u32 = 100,
    execution: enum { @"inline", workers } = .workers,
    workers: ?u16 = null,
    count: i32 = 0,
    verbose: bool = false,
    text: []const u8 = "default",
    sentinel: [:0]const u8 = "sentinel-default",
    optional: ?[:0]const u8 = null,
    positional: struct { first: ?[]const u8 = null, second: ?[:0]const u8 = null },

    pub const aliases = .{ .port = "p", .duration_ms = "d", .verbose = "v", .text = "t", .count = "c" };
    pub const help = "VALUES HELP\n";
};

const Commands = union(enum) {
    values: Options,
    required: struct { number: u8 },
    no_help: struct {},
    empty,

    pub const help = "GLOBAL HELP\n";
};

/// The wrapper switch exercises the unchanged public iterator API.
/// Every other invocation enters through parseInit with the real process Init.
pub fn main(init: std.process.Init) !void {
    const legacy = blk: {
        var probe = try init.minimal.args.iterateAllocator(init.gpa);
        defer probe.deinit();
        _ = probe.next();
        break :blk if (probe.next()) |arg| std.mem.eql(u8, arg, "--legacy-iterator") else false;
    };

    if (legacy) {
        var iterator = try init.minimal.args.iterateAllocator(init.gpa);
        defer iterator.deinit();
        // parse discards the wrapper switch in place of the executable name.
        _ = iterator.next();
        const result = zli.parse(init.io, &iterator, Commands);
        try write_result(init, result);
    } else {
        const result = try zli.parseInit(init, Commands);
        try write_result(init, result);
    }
}

fn write_result(init: std.process.Init, result: Commands) !void {
    // Reusing permanent storage after parsing must not overwrite argument data.
    const scratch = try init.arena.allocator().alloc(u8, 4096);
    @memset(scratch, 0xa5);

    var buffer: [1024]u8 = undefined;
    var stdout = std.Io.File.stdout().writer(init.io, &buffer);
    const writer = &stdout.interface;
    switch (result) {
        .values => |value| {
            std.debug.assert(value.sentinel[value.sentinel.len] == 0);
            if (value.optional) |text| std.debug.assert(text[text.len] == 0);
            if (value.positional.second) |text| std.debug.assert(text[text.len] == 0);
            try std.json.Stringify.value(value, .{}, writer);
        },
        .required => |value| try std.json.Stringify.value(value, .{}, writer),
        .no_help, .empty => try writer.writeAll("{}"),
    }
    try writer.writeByte('\n');
    try writer.flush();
}
