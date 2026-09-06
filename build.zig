const std = @import("std");

pub fn build(b: *std.Build) void {
    if (!std.mem.eql(u8, @import("builtin").zig_version_string, std.mem.trim(u8, @embedFile(".zig-version"), " \r\n")))
        @panic("Use exactly the Zig release in .zig-version");
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const module = b.addModule("zli", .{
        .root_source_file = b.path("src/zli.zig"),
        .target = target,
        .optimize = optimize,
    });

    const main_tests = b.addTest(.{
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/test.zig"),
            .optimize = optimize,
            .target = target,
        }),
    });

    const test_step = b.step("test", "Run library tests");
    test_step.dependOn(&b.addRunArtifact(main_tests).step);
    const check = b.step("check", "Compile tests and examples without running target executables");
    check.dependOn(&main_tests.step);
    const verify = b.step("verify", "Run tests, compile examples and check formatting");
    verify.dependOn(test_step);
    verify.dependOn(&b.addFmt(.{ .paths = &.{ "build.zig", "build.zig.zon", "src", "example" }, .check = true }).step);

    const fixture = b.addExecutable(.{
        .name = "zli-parser-fixture",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/parser_fixture.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "zli", .module = module }},
        }),
    });
    check.dependOn(&fixture.step);
    const process_tests = b.addSystemCommand(&.{ "python3", "tests/cli.py" });
    process_tests.addArtifactArg(fixture);
    verify.dependOn(&process_tests.step);

    const examples_step = b.step("examples", "Build and install all examples");

    verify.dependOn(examples_step);

    inline for (.{ "subcommands", "args", "simple" }) |name| {
        const example = b.addExecutable(.{
            .name = name,
            .root_module = b.createModule(.{
                .root_source_file = b.path(b.fmt("example/{s}.zig", .{name})),
                .target = target,
                .optimize = optimize,
            }),
        });
        const install_example = b.addInstallArtifact(example, .{});
        example.root_module.addImport("zli", module);
        examples_step.dependOn(&example.step);
        check.dependOn(&example.step);
        examples_step.dependOn(&install_example.step);
    }
}
