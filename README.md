# ZLI

This library is a friendly refactor of TigerBeetle's `flags` module that adds
support for:

-   subcommand specific help messages; and
-   short options (`-k=v`).

## TigerBeetle

To call this project anything other than a friendly refactor would be
disingenuous.

Full credit belongs to TigerBeetle for the inspiration and most of the logic
used throughout this library. This library has adopted the same license as the
original. Thank you to the original authors, and please see the links below to
show your support for TigerBeetle.

-   [Tigerbeetle](https://tigerbeetle.com)
-   [Tigerbeetle Github](https://github.com/tigerbeetle/tigerbeetle)
-   [Tigerbeetle Flags](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/flags.zig)
-   [Tiger Style](https://github.com/tigerbeetle/tigerbeetle/blob/main/docs/TIGER_STYLE.md)

## Motivation

The principles advocated for in TigerBeetle's `Tiger Style` resonated strongly.
The interface that was defined for parsing CLI arguments in TigerBeetle's `flags`
module was exactly the API that I had been looking for. I greatly appreciated
their use of comptime and the design of their CLI guidelines. However, I had a
need for both subcommand specific help messages and short options - this library
aims to fill that need. In the spirit of the original code, I have made this
project public in case it may help others.

## Support and Limitations

Like the original, this library aims to be an 80% solution. It supports:

-   Subcommands;
-   Manual help messages for each subcommand and a global help message;
-   Long (`--key=value` or `--key value`) and short (`-k=v` or `-k v`) options; and
-   Positional arguments.

It does not auto-generate help messages or support chained short arguments
or delimiter-separated values.

It retains the original source's reliance on asserts / fatal errors.

Please note that while much of the core logic of this library has been taken from
[Tigerbeetle](https://github.com/tigerbeetle/tigerbeetle/blob/main/src/flags.zig),
the testing and snapshots have not. This library was created to solve a problem
I was having for side projects, so please use with this in mind.

If you need a more comprehensive CLI parsing solution, please see any of these
fantastic projects from the Zig community:
-   [Hejsil/zig-clap](https://github.com/Hejsil/zig-clap) - Simple command line argument parsing library
-   [prajwalch/yazap](https://github.com/prajwalch/yazap) - The ultimate Zig library for seamless command line parsing. Effortlessly handles options, subcommands, and custom arguments with ease.
-   [MasterQ32/zig-args](https://github.com/MasterQ32/zig-args) - Simple-to-use argument parser with struct-based config

## Zig 0.16.0 and process initialization

Use exact [Zig 0.16.0](https://ziglang.org/download/). The convenient entry point
accepts the `std.process.Init` supplied to main:

```zig
const std = @import("std");
const zli = @import("zli");

const Options = struct {
    port: u16 = 8080,
    verbose: bool = false,
    label: []const u8 = "server",

    pub const aliases = .{ .port = "p", .verbose = "v" };
    pub const help =
        \\Usage: server [--port N] [--verbose] [--label TEXT]
        \\  -h, --help       Show this help
        \\  -p, --port N     Listen port (default: 8080)
        \\  -v, --verbose    Enable verbose output
    ;
};

pub fn main(init: std.process.Init) !void {
    const options = try zli.parseInit(init, Options);
    var buffer: [1024]u8 = undefined;
    var output = std.Io.File.stdout().writer(init.io, &buffer);
    try output.interface.print("{s}: port={d}, verbose={}\n", .{
        options.label, options.port, options.verbose,
    });
    try output.interface.flush();
}
```

`parseInit` uses `init.minimal.args`, `init.arena`, and `init.io`; it does not
create an I/O provider or a separate general-purpose allocator. Argument
normalization allocates from the process arena at startup where needed,
including Windows command-line decoding. Parsed string fields borrow that
storage and remain valid until the arena is reset or deinitialized. Do not
reset it while retaining parsed strings. Sentinel slices (`[:0]const u8`) keep
their terminating zero.

The existing `zli.parse(io, &iterator, Options)` entry point remains available.
With that entry point, the caller owns the argument iterator and must keep its
storage alive while using returned strings. On Windows, create the iterator
with `std.process.Args.Iterator.initAllocator`.

Both APIs print help and exit successfully for exact `-h`, `--help`, or the
legacy bare `help` token before `--`, and print
a diagnostic and exit with status 1 for invalid CLI input. `parseInit` can also
return an allocation error. This is a startup CLI API, not a recoverable parser
for requests or an embedded command interpreter. Help text is supplied by your
struct; it is not generated from field metadata.

### Option syntax

- `--port=8080`, `--port 8080`, `-p=8080`, and `-p 8080` are equivalent.
- Zig fields such as `max_body` become `--max-body`.
- A bare boolean flag means true; `--verbose=false` explicitly sets false.
  Boolean flags do not consume the following positional argument.
- `--` ends option and help recognition, so subsequent tokens are positional.
- Named values may start with `-`; bare `--` is reserved as the end marker.
  Use `--label=--` for that literal value. Empty values are valid for string fields.
- Repeated options and unknown options are errors. Numeric ranges follow the
  declared Zig type; enum values must match one of its tags.

## Installing

Pin a commit of this [Zig 0.16 fork](https://github.com/renerocksai/zli) with
`zig fetch --save=zli` and its archive URL. Add the dependency module to your
executable in `build.zig`:

```zig
const zli = b.dependency("zli", .{
    .target = target,
    .optimize = optimize,
});
exe.root_module.addImport("zli", zli.module("zli"));
```

## Runnable examples

- [args](example/args.zig): a typed struct with defaults, aliases, and flags.
- [simple](example/simple.zig): options, positional arguments, and subcommands.
- [subcommands](example/subcommands.zig): per-command state and help.

All use `pub fn main(init: std.process.Init) !void` and `try zli.parseInit`.

```sh
zig build verify -Doptimize=Debug
zig build verify -Doptimize=ReleaseSafe
./zig-out/bin/simple example --foo 42 --opt
./zig-out/bin/simple --help
```

`zig build test` executes tests. `verify` also compiles the examples, checks
formatting, and exercises the process argument path. `check` compiles target
binaries without running them. CI runs Debug and ReleaseSafe natively on
Linux, macOS, and Windows; cross-compilation alone is not runtime evidence.
