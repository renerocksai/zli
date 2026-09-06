const std = @import("std");
const assert = std.debug.assert;
const expectEqual = std.testing.expectEqual;
const expectEqualStrings = std.testing.expectEqualStrings;

const fatal = @import("./fatal.zig").fatal;
const strings = @import("./strings.zig");

/// Asserts the type of a given value is valid.
pub fn assert_valid_value_type(comptime T: type) void {
    comptime {
        if (T == []const u8 or T == [:0]const u8 or @typeInfo(T) == .int) {
            return;
        }

        if (@typeInfo(T) == .@"enum") {
            const info = @typeInfo(T).@"enum";
            assert(info.is_exhaustive);
            assert(info.fields.len >= 2);
            return;
        }

        @compileLog("unsupported type", T);
        unreachable;
    }
}

/// Parses the name of a CLI argument.
///
/// ```zig
/// assert(std.mem.eql(name("--path=data.yaml"), "path"));
/// assert(std.mem.eql(name("-p=data.yaml"), "path"));
/// assert(std.mem.eql(name("-v"), "v"));
/// ```
pub fn name(arg: []const u8) []const u8 {
    if (arg.len <= 1) return "";
    if (arg[0] != '-') return "";

    var from: usize = 1;
    var to: usize = arg.len;

    if (arg.len > 2 and arg[1] == '-') {
        from = 2;
    }

    if (std.mem.indexOf(u8, arg, "=")) |i| {
        to = i;
    }

    return arg[from..to];
}

test name {
    try expectEqualStrings("verbose", name("--verbose"));
    try expectEqualStrings("v", name("-v"));
    try expectEqualStrings("path", name("--path=path.yaml"));
    try expectEqualStrings("p", name("-p=path.yaml"));
    try expectEqualStrings("long-var", name("--long-var=hello"));
}

/// Extracts the value of a CLI argument and returns it as a string.
///
/// ```zig
/// assert(std.mem.eql(unparsed_value("--path=data.yaml"), "data.yaml"));
/// assert(std.mem.eql(unparsed_value("-n=5"), "5"));
/// ```
fn unparsed_value(arg: [:0]const u8) ?[:0]const u8 {
    if (strings.index_of(arg, "=")) |pos_of_equ| {
        const split_at = pos_of_equ + 1;
        return arg[split_at.. :0];
    }
    return null;
}

test unparsed_value {
    try expectEqualStrings("path.yaml", unparsed_value("--path=path.yaml").?);
    try expectEqualStrings("path.yaml", unparsed_value("-p=path.yaml").?);
    try expectEqualStrings("hello", unparsed_value("--long-var=hello").?);
    try expectEqualStrings("", unparsed_value("--path=").?);
    try expectEqual(null, unparsed_value("--path"));
}

/// Takes in an unparsed CLI argument and parses out its value.
///
/// ```zig
/// assert(std.mem.eql(parse_arg([]const u8, "--path=data.yaml"), "data.yaml"));
/// assert(parse_arg(u32, "-n=5") == @as(u32, 5));
/// ```
pub fn parse_arg(io: std.Io, comptime T: type, arg: [:0]const u8) T {
    const arg_name = name(arg);
    const val = unparsed_value(arg) orelse {
        if (T == bool) return true;
        fatal(io, "{s}: argument value required", .{arg_name});
    };
    return parse_value(io, T, arg_name, val);
}

/// Parses the unparsed value associated with the given argument name into the
/// specified type.
///
/// ```zig
/// assert(std.mem.eql(parse_value([]const u8, "path", "data.yaml"), "data.yaml"));
/// assert(parse_value(u32, "n", "5") == @as(u32, 5));
/// ```
pub fn parse_value(io: std.Io, comptime T: type, arg_name: []const u8, arg_value: [:0]const u8) T {
    const V = switch (@typeInfo(T)) {
        .optional => |optional| optional.child,
        else => T,
    };

    if (V == []const u8 or V == [:0]const u8) return arg_value;
    if (V == bool) {
        if (strings.eql(arg_value, "true")) return true;
        if (strings.eql(arg_value, "false")) return false;
        fatal(io, "{s}: expected true or false, but found '{s}'", .{ arg_name, arg_value });
    }
    if (arg_value.len == 0) fatal(io, "{s}: argument value must not be empty", .{arg_name});
    if (@typeInfo(V) == .int) return parse_value_int(io, V, arg_name, arg_value);
    if (@typeInfo(V) == .@"enum") return parse_value_enum(io, V, arg_name, arg_value);
    comptime unreachable;
}

/// Parses the unparsed integer value associated with the given argument name
/// into the specified integer type.
///
/// ```zig
/// assert(parse_value_int(u32, "n", "5") == @as(u32, 5));
/// ```
fn parse_value_int(io: std.Io, comptime T: type, arg_name: []const u8, val: []const u8) T {
    return std.fmt.parseInt(T, val, 10) catch |err| {
        switch (err) {
            error.Overflow => fatal(
                io,
                "{s}: value exceeds {d}-bit {s} integer: '{s}'",
                .{ arg_name, @typeInfo(T).int.bits, @tagName(@typeInfo(T).int.signedness), val },
            ),
            error.InvalidCharacter => fatal(
                io,
                "{s}: expected an integer value, but found '{s}' (invalid digit)",
                .{ arg_name, val },
            ),
        }
    };
}

test parse_value_int {
    const io = std.testing.io;
    try expectEqual(parse_value_int(io, u32, "test-int", "6"), @as(u32, 6));
    try expectEqual(parse_value_int(io, usize, "test-int", "12"), @as(usize, 12));
}

/// Parses the unparsed enum value associated with the given argument name into
/// the specified enum type.
///
/// ```zig
/// const E = enum {
///    ok,
///    not_ok,
/// };
///
/// assert(parse_value_enum(E, "test-enum", "ok"), .ok);
/// assert(parse_value_enum(E, "test-enum", "not_ok"), .not_ok);
/// ```
fn parse_value_enum(io: std.Io, comptime E: type, arg_name: []const u8, val: []const u8) E {
    comptime assert(@typeInfo(E).@"enum".is_exhaustive);

    return std.meta.stringToEnum(E, val) orelse fatal(
        io,
        "{s}: expected one of {s}, but found '{s}'",
        .{ arg_name, comptime strings.fields_to_string(E), val },
    );
}

test parse_value_enum {
    const E = enum {
        ok,
        not_ok,
    };

    const io = std.testing.io;
    try expectEqual(parse_value_enum(io, E, "test-enum", "ok"), .ok);
    try expectEqual(parse_value_enum(io, E, "test-enum", "not_ok"), .not_ok);
}
