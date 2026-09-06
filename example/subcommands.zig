const std = @import("std");
const zli = @import("zli");

const Writer = std.Io.Writer;

const View = struct {
    number: usize = 5,
    data_path: []const u8 = "./data/data.json",
    pub const aliases = .{
        .number = "n",
        .data_path = "p",
    };

    pub const help =
        \\ Command: view
        \\
        \\ Usage:
        \\
        \\ app view [-n, --number=<amount>] [-p, --data-path=<path>]
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -n, --number             The number of items to view.
        \\                          Default: 5.
        \\
        \\ -p, --data-path=<path>   The relative path to the data file.
        \\                          Default: ./data/data.json
    ;
};

const ViewAll = struct {
    data_path: []const u8 = "./data/data.json",

    pub const aliases = .{
        .data_path = "p",
    };

    pub const help =
        \\ Command: view-all
        \\
        \\ Usage:
        \\
        \\ app view-all [-p, --data-path=<path>]
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits.
        \\
        \\ -p, --data-path=<path>   The relative path to the data file.
        \\                          Default: ./data/data.json
    ;
};

const Add = struct {
    data_path: []const u8 = "./data/data.json",
    positional: struct {
        item: []const u8,
    },

    pub const aliases = .{
        .data_path = "p",
    };

    pub const help =
        \\ Command: add
        \\
        \\ Usage:
        \\
        \\ app add [-p, --data-path=<path>] <item>
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits
        \\
        \\ -p, --data-path=<path>   The relative path to the data file.
        \\                          Default: ./data/data.json
    ;
};

const Delete = struct {
    data_path: []const u8 = "./data/data.json",
    positional: struct {
        item: []const u8,
    },

    pub const aliases = .{
        .data_path = "p",
    };

    pub const help =
        \\ Command: delete
        \\
        \\ Usage:
        \\
        \\ app delete [-p, --data-path=<path>] <item>
        \\
        \\ Options:
        \\
        \\ -h, --help               Displays this help message then exits
        \\
        \\ -p, --data-path=<path>   The relative path to the data file.
        \\                          Default: ./data/data.json
    ;
};

const App = union(enum) {
    view: View,
    view_all: ViewAll,
    add: Add,
    delete: Delete,

    pub const help =
        \\ Usage: app [command] [options]
        \\
        \\ Commands:
        \\  view            View the last n items.
        \\  view-all        View all items.
        \\  add             Add a new item.
        \\  delete          Delete an item.
        \\
        \\ General Options:
        \\  -h, --help      Displays this help message then exits
    ;
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    var stdout_buffer: [1024]u8 = undefined;
    var stdout_writer = std.Io.File.stdout().writer(io, &stdout_buffer);
    const writer = &stdout_writer.interface;

    const result = try zli.parseInit(init, App);

    switch (result) {
        .view => |values| {
            try view(writer, values);
        },
        .view_all => |values| {
            try view_all(writer, values);
        },
        .add => |values| {
            try add(writer, values);
        },
        .delete => |values| {
            try delete(writer, values);
        },
    }
}

fn view(writer: *Writer, values: View) !void {
    try writer.print("View", .{});
    try writer.print("\tPath: {s}\n", .{values.data_path});
    try writer.print("\tNumber: {d}\n", .{values.number});
    try writer.flush();
}

fn view_all(writer: *Writer, values: ViewAll) !void {
    try writer.print("View All", .{});
    try writer.print("\tPath: {s}\n", .{values.data_path});
    try writer.flush();
}

fn add(writer: *Writer, values: Add) !void {
    try writer.print("Add Command:\n", .{});
    try writer.print("\tPath: {s}\n", .{values.data_path});
    try writer.print("\tPositional: {s}\n", .{values.positional.item});
    try writer.flush();
}

fn delete(writer: *Writer, values: Delete) !void {
    try writer.print("Delete Command:\n", .{});
    try writer.print("\tPath: {s}\n", .{values.data_path});
    try writer.print("\tPositional: {s}\n", .{values.positional.item});
    try writer.flush();
}
