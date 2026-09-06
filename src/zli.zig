//! This library is a friendly refactor of TigerBeetle's `flags` module that adds
//! support for:
//!
//! -   subcommand specific help messages; and
//! -   short options (`-k=v`).
//!
//! ============================================================================
//!
//! To call this project anything other than a friendly refactor would be
//! disingenuous.
//!
//! Full credit belongs to TigerBeetle for the inspiration and most of the logic
//! used throughout this library. This library has adopted the same license as
//! the original. Thank you, and please see the links below to show your support
//! for TigerBeetle.
//!
//! -   Tigerbeetle:        https://tigerbeetle.com
//! -   Tigerbeetle Github: https://github.com/tigerbeetle/tigerbeetle
//! -   Tigerbeetle Flags:  https://github.com/tigerbeetle/tigerbeetle/blob/main/src/flags.zig
//! -   Tiger Style:        https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md
//!
//! ============================================================================
//!
//! Motivation:
//!
//! The principles advocated for in TigerBeetle's `Tiger Style` resonated strongly.
//! The interface that was defined for parsing CLI arguments in TigerBeetle's
//! `flags` module was exactly the API that I had been looking for. I greatly
//! appreciated their use of comptime and the design of their CLI guidelines.
//! However, I had a need for both subcommand specific help messages and short
//! options - this library aims to fill that need. In the spirit of the original
//! code, I have made this project public in case it may help others.
//!
//! Support:
//!
//! Like the original, this library aims to be an 80% solution. It supports:
//! -   Subcommands;
//! -   Manual help messages for each subcommand and a global help message;
//! -   Long and short options with attached or separate values; and
//! -   Positional arguments.
//!
//! It does not auto-generate help messages or support chaining short arguments
//! or delimiter separated values.
//!
//! It retains the original source's reliance on asserts / fatal errors.
//!
//! Please note that while much of the core logic of this library has been taken
//! from TigerBeetle's `flag` module, the testing and snapshots have not. This
//! library was created to solve a problem I was having for side projects, so
//! please use with this in mind.

const std = @import("std");
const ArgIterator = std.process.Args.Iterator;
const StructField = std.builtin.Type.StructField;
const assert = std.debug.assert;

const fatal = @import("./fatal.zig").fatal;
const structs = @import("./structs.zig");
const argx = @import("./arg.zig");
const strings = @import("./strings.zig");
const help = @import("./help.zig");

/// Parse CLI arguments for subcommands specified as Zig `struct` or `union(enum)`.
///
/// ```zig
/// const App = union(enum) {
///     view: struct {
///         number: usize = 5,
///
///         pub const aliases = .{ .number = "n" };
///         pub const help =
///             \\ Command: view
///             \\
///             \\ Usage:
///             \\
///             \\ app view [-n, --number=<amount>]
///             \\
///             \\ Options:
///             \\
///             \\ -h, --help   Displays this help message then exits
///             \\ -n, --number The number of items to view. Default: 5.
///         ;
///     },
///     add: struct {
///         positional: struct { item: []const u8 },
///
///         pub const help =
///             \\ Command: add
///             \\
///             \\ Usage:
///             \\
///             \\ app add <item>
///             \\
///             \\ Options:
///             \\
///             \\ -h, --help   Displays this help message then exits
///         ;
///     },
///
///     pub const help =
///         \\ Usage: app [command] [options]
///         \\
///         \\ Commands:
///         \\  view            View the last n items.
///         \\  add             Add a new item.
///         \\
///         \\ General Options:
///         \\  -h, --help      Displays this help message then exits
///     ;
/// };
/// ```
pub fn parse(io: std.Io, args: *ArgIterator, comptime CLIArgs: type) CLIArgs {
    return parse_iterator(io, args, CLIArgs);
}

/// Parse process arguments at startup using the caller's I/O and permanent arena.
/// Returned string fields borrow process arguments or `init.arena` storage.
/// Keep that storage alive until the last use of the parsed configuration.
/// This function does not free argument storage or create an I/O implementation.
/// Allocation errors return to the caller; help and syntax errors exit the process.
pub fn parseInit(init: std.process.Init, comptime CLIArgs: type) std.process.Args.ToSliceError!CLIArgs {
    var args: SliceIterator = .{ .values = try init.minimal.args.toSlice(init.arena.allocator()) };
    return parse_iterator(init.io, &args, CLIArgs);
}

const SliceIterator = struct {
    values: []const [:0]const u8,
    index: usize = 0,

    fn next(self: *SliceIterator) ?[:0]const u8 {
        if (self.index == self.values.len) return null;
        const value = self.values[self.index];
        self.index += 1;
        return value;
    }
};

fn parse_iterator(io: std.Io, args: anytype, comptime CLIArgs: type) CLIArgs {
    _ = args.next() orelse fatal(io, "executable name missing", .{});

    return switch (@typeInfo(CLIArgs)) {
        .@"union" => parse_commands(io, args, CLIArgs),
        .@"struct" => parse_args(io, args, CLIArgs),
        else => unreachable,
    };
}

fn parse_commands(io: std.Io, args: anytype, comptime Commands: type) Commands {
    comptime assert(@typeInfo(Commands) == .@"union");
    comptime assert(std.meta.fields(Commands).len > 1);

    const command = args.next() orelse fatal(
        io,
        "subcommand required: expected {s}",
        .{comptime strings.fields_to_string(Commands)},
    );

    if (help.requested_help(command)) {
        help.try_print_help(io, Commands);
    }

    inline for (comptime std.meta.fields(Commands)) |field| {
        const parsed_field = comptime strings.replace(field.name, "_", "-");
        if (strings.eql(command, parsed_field)) {
            return @unionInit(Commands, field.name, parse_args(io, args, field.type));
        }
    }

    fatal(io, "Invalid subcommand: \"{s}\". Expected: {s}.", .{
        command,
        comptime strings.fields_to_string(Commands),
    });
}

fn parse_args(io: std.Io, args: anytype, comptime Args: type) Args {
    if (Args == void) {
        if (args.next()) |arg| {
            fatal(io, "unexpected argument: '{s}'", .{arg});
        }
        return {};
    }

    comptime assert(@typeInfo(Args) == .@"struct");

    comptime var fields: [std.meta.fields(Args).len]StructField = undefined;
    comptime var field_count = 0;

    comptime var positional_fields: []const StructField = &.{};

    comptime for (std.meta.fields(Args)) |field| {
        if (strings.eql(field.name, "positional")) {
            assert(@typeInfo(field.type) == .@"struct");

            positional_fields = std.meta.fields(field.type);

            for (positional_fields) |positional_field| {
                switch (@typeInfo(positional_field.type)) {
                    .optional => |optional| {
                        // if no default: will be required
                        argx.assert_valid_value_type(optional.child);
                    },
                    else => argx.assert_valid_value_type(positional_field.type),
                }
            }
        } else {
            switch (@typeInfo(field.type)) {
                .bool => {
                    assert(structs.default_value(field).? == false); // boolean flags should have a default of false
                },
                .optional => |optional| {
                    assert(structs.default_value(field).? == null); // optional flags should have a default of null
                    argx.assert_valid_value_type(optional.child);
                },
                else => {
                    argx.assert_valid_value_type(field.type);
                },
            }

            fields[field_count] = field;
            field_count += 1;
        }
    };

    var result: Args = undefined;
    var counts: structs.struct_field_struct(Args, u32, 0) = .{};
    var parsed_positional = false;
    var options_ended = false;

    next_arg: while (args.next()) |arg| {
        if (!options_ended and strings.eql(arg, "--")) {
            options_ended = true;
            continue;
        }
        if (!options_ended and help.requested_help(arg)) {
            help.try_print_help(io, Args);
        }

        // A lone dash and negative numbers are positional values. Other values
        // starting with a dash require `--` before the positional arguments.
        const is_positional = options_ended or arg.len == 0 or arg[0] != '-' or
            arg.len == 1 or (arg.len > 1 and std.ascii.isDigit(arg[1]));
        if (is_positional and @hasField(Args, "positional")) {
            if (parsed_positional) {
                fatal(io, "Unknown positional argument: {s}", .{arg});
            }

            inline for (positional_fields, 0..) |field, idx| {
                if (counts.positional == idx) {
                    @field(result.positional, field.name) = argx.parse_value(io, field.type, field.name, arg);

                    counts.positional += 1;

                    if (counts.positional == positional_fields.len) {
                        parsed_positional = true;
                    }

                    continue :next_arg;
                }
            }
        }

        if (is_positional) fatal(io, "Unknown positional argument: {s}", .{arg});

        // arg is now known to not be positional, which means it must start
        // with a dash.
        const arg_name_cli = argx.name(arg);

        inline for (fields[0..field_count]) |field| {
            const arg_name_app = comptime strings.replace(field.name, "_", "-");

            if (strings.eql(arg_name_app, arg_name_cli)) {
                if (@field(counts, field.name) != 0) fatal(io, "{s}: duplicate argument", .{field.name});
                @field(counts, field.name) = 1;

                const value = parse_option(io, field.type, arg, args);
                @field(result, field.name) = value;

                continue :next_arg;
            }
        }

        if (@hasDecl(Args, "aliases")) {
            const aliases = comptime Args.aliases;

            inline for (std.meta.fields(@TypeOf(aliases))) |field| {
                const alias = @field(aliases, field.name);

                if (strings.eql(alias, arg_name_cli)) {
                    if (@field(counts, field.name) != 0) fatal(io, "{s}: duplicate argument", .{field.name});
                    @field(counts, field.name) = 1;
                    const field_type = @TypeOf(@field(result, field.name));

                    const value = parse_option(io, field_type, arg, args);
                    @field(result, field.name) = value;

                    continue :next_arg;
                }
            }
        }

        // If we are here, then the current CLI argument is unknown.
        fatal(io, "Unknown CLI argument: {s}\n", .{arg});
    }

    inline for (fields[0..field_count]) |field| {
        switch (@field(counts, field.name)) {
            0 => if (structs.default_value(field)) |default| {
                @field(result, field.name) = default;
            } else {
                fatal(io, "{s}: argument is required", .{field.name});
            },
            1 => {},
            else => fatal(io, "{s}: duplicate argument", .{field.name}),
        }
    }

    if (@hasField(Args, "positional")) {
        assert(counts.positional <= positional_fields.len);
        inline for (positional_fields, 0..) |field, idx| {
            if (idx >= counts.positional) {
                if (field.default_value_ptr != null) {
                    @field(result.positional, field.name) = field.defaultValue().?;
                } else {
                    fatal(io, "{s}: argument is required", .{field.name});
                }
            }
        }
    }

    return result;
}

fn parse_option(io: std.Io, comptime T: type, arg: [:0]const u8, args: anytype) T {
    if (T == bool or std.mem.indexOfScalar(u8, arg, '=') != null) {
        return argx.parse_arg(io, T, arg);
    }
    const arg_name = argx.name(arg);
    const value = args.next() orelse fatal(io, "{s}: argument value required", .{arg_name});
    if (strings.eql(value, "--")) fatal(io, "{s}: argument value required before --", .{arg_name});
    return argx.parse_value(io, T, arg_name, value);
}

test "attached and separate values preserve defaults aliases enums and optional fields" {
    const Options = struct {
        port: u16 = 8080,
        duration_ms: u32 = 100,
        execution: enum { @"inline", workers } = .workers,
        workers: ?u16 = null,
        pub const aliases = .{ .port = "p", .duration_ms = "d" };
    };
    var attached: SliceIterator = .{ .values = &.{ "app", "-p=9000", "--duration-ms=25", "--execution=inline", "--workers=2" } };
    var separate: SliceIterator = .{ .values = &.{ "app", "--port", "9000", "-d", "25", "--execution", "inline", "--workers", "2" } };
    const expected: Options = .{ .port = 9000, .duration_ms = 25, .execution = .@"inline", .workers = 2 };
    try std.testing.expectEqualDeep(expected, parse_iterator(std.testing.io, &attached, Options));
    try std.testing.expectEqualDeep(expected, parse_iterator(std.testing.io, &separate, Options));
    var empty: SliceIterator = .{ .values = &.{"app"} };
    try std.testing.expectEqualDeep(Options{}, parse_iterator(std.testing.io, &empty, Options));
}

test "boolean options do not consume following positional values" {
    const Options = struct {
        verbose: bool = false,
        positional: struct { value: []const u8 },
        pub const aliases = .{ .verbose = "v" };
    };
    var bare: SliceIterator = .{ .values = &.{ "app", "-v", "false" } };
    const present = parse_iterator(std.testing.io, &bare, Options);
    try std.testing.expect(present.verbose);
    try std.testing.expectEqualStrings("false", present.positional.value);
    var explicit: SliceIterator = .{ .values = &.{ "app", "--verbose=false", "true" } };
    const disabled = parse_iterator(std.testing.io, &explicit, Options);
    try std.testing.expect(!disabled.verbose);
    try std.testing.expectEqualStrings("true", disabled.positional.value);
}

test "strings retain original sentinel slices including empty values" {
    const Options = struct {
        text: []const u8,
        sentinel: [:0]const u8,
        optional: ?[:0]const u8 = null,
        positional: struct { empty: [:0]const u8 },
    };
    const sentinel: [:0]const u8 = "--sentinel=retained";
    const optional: [:0]const u8 = "another value";
    var args: SliceIterator = .{ .values = &.{ "app", "--text=", sentinel, "--optional", optional, "" } };
    const result = parse_iterator(std.testing.io, &args, Options);
    try std.testing.expectEqualStrings("", result.text);
    try std.testing.expectEqualStrings("retained", result.sentinel);
    try std.testing.expect(result.sentinel.ptr == sentinel.ptr + "--sentinel=".len);
    try std.testing.expect(result.optional.?.ptr == optional.ptr);
    try std.testing.expectEqual(@as(u8, 0), result.sentinel[result.sentinel.len]);
    try std.testing.expectEqualStrings("", result.positional.empty);
    try std.testing.expectEqual(@as(u8, 0), result.positional.empty[0]);
}

test "negative values and end of options preserve positional tokens" {
    const Numbers = struct { number: i16 = 0, positional: struct { value: i16 } };
    var negative: SliceIterator = .{ .values = &.{ "app", "--number", "-12", "-4" } };
    try std.testing.expectEqualDeep(Numbers{ .number = -12, .positional = .{ .value = -4 } }, parse_iterator(std.testing.io, &negative, Numbers));

    const Strings = struct {
        positional: struct { first: []const u8, second: []const u8, third: []const u8 },
        pub const help = "must not print";
    };
    var ended: SliceIterator = .{ .values = &.{ "app", "--", "--help", "--", "-file" } };
    const result = parse_iterator(std.testing.io, &ended, Strings);
    try std.testing.expectEqualStrings("--help", result.positional.first);
    try std.testing.expectEqualStrings("--", result.positional.second);
    try std.testing.expectEqualStrings("-file", result.positional.third);
}

test "subcommands fill optional positional defaults" {
    const Commands = union(enum) {
        list_items: struct { positional: struct { first: []const u8, second: ?[]const u8 = null, third: u8 = 7 } },
        empty,
    };
    var args: SliceIterator = .{ .values = &.{ "app", "list-items", "item" } };
    const result = parse_iterator(std.testing.io, &args, Commands);
    try std.testing.expectEqualStrings("item", result.list_items.positional.first);
    try std.testing.expectEqual(@as(?[]const u8, null), result.list_items.positional.second);
    try std.testing.expectEqual(@as(u8, 7), result.list_items.positional.third);
}

fn test_process_args() std.process.Args {
    return switch (@import("builtin").os.tag) {
        .windows => .{ .vector = std.unicode.utf8ToUtf16LeStringLiteral("app --text=retained --sentinel=sentinel") },
        .wasi => unreachable,
        else => .{ .vector = &.{ "app", "--text=retained", "--sentinel=sentinel" } },
    };
}

test "parseInit retains borrowed strings after returning and legacy iterator agrees" {
    if (@import("builtin").os.tag == .wasi) return error.SkipZigTest;
    const Options = struct { text: []const u8, sentinel: [:0]const u8 };
    var arena: std.heap.ArenaAllocator = .init(std.testing.allocator);
    defer arena.deinit();
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    const init: std.process.Init = .{
        .minimal = .{ .args = test_process_args(), .environ = .empty },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environ,
        .preopens = .empty,
    };
    const result = try parseInit(init, Options);
    const scratch = try arena.allocator().alloc(u8, 4096);
    @memset(scratch, 0xa5);
    try std.testing.expectEqualStrings("retained", result.text);
    try std.testing.expectEqualStrings("sentinel", result.sentinel);
    try std.testing.expectEqual(@as(u8, 0), result.sentinel[result.sentinel.len]);

    var iterator = try test_process_args().iterateAllocator(std.testing.allocator);
    defer iterator.deinit();
    try std.testing.expectEqualDeep(result, parse(std.testing.io, &iterator, Options));
}

test "parseInit returns arena allocation failure" {
    if (@import("builtin").os.tag == .wasi) return error.SkipZigTest;
    var failing: std.testing.FailingAllocator = .init(std.testing.allocator, .{ .fail_index = 0 });
    var arena: std.heap.ArenaAllocator = .init(failing.allocator());
    defer arena.deinit();
    var environ: std.process.Environ.Map = .init(std.testing.allocator);
    defer environ.deinit();
    const init: std.process.Init = .{
        .minimal = .{ .args = test_process_args(), .environ = .empty },
        .arena = &arena,
        .gpa = std.testing.allocator,
        .io = std.testing.io,
        .environ_map = &environ,
        .preopens = .empty,
    };
    try std.testing.expectError(error.OutOfMemory, parseInit(init, struct { text: []const u8, sentinel: [:0]const u8 }));
}
