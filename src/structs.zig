const std = @import("std");
const StructField = std.builtin.Type.StructField;
const assert = std.debug.assert;

/// This is essentially `field.default_value_ptr`, but with a useful type instead of
/// `?*const anyopaque`.
pub fn default_value(comptime field: StructField) ?field.type {
    var out: ?field.type = null;

    if (field.default_value_ptr) |default_opaque| {
        out = @as(*const field.type, @ptrCast(@alignCast(default_opaque))).*;
    }

    return out;
}

/// Like `std.enums.EnumFieldStruct`, but for structs.
///
/// Returns a struct with a fields matching each field name of the provided
/// struct.
///
/// Each field is of type `Data` and has the provided default, which may be
/// undefined.
pub fn struct_field_struct(comptime S: type, comptime Data: type, comptime default: ?Data) type {
    assert(@typeInfo(S) == .@"struct");

    const fields_in = @typeInfo(S).@"struct".fields;
    var fields_out: [fields_in.len]StructField = undefined;

    for (&fields_out, fields_in) |*field_out, field_in| {
        field_out.* = .{
            .name = field_in.name,
            .type = Data,
            .default_value_ptr = if (default) |d| @as(?*const anyopaque, @ptrCast(&d)) else null,
            .is_comptime = false,
            .alignment = if (@sizeOf(Data) > 0) @alignOf(Data) else 0,
        };
    }

    return @Type(.{ .@"struct" = .{
        .layout = .auto,
        .fields = &fields_out,
        .decls = &.{},
        .is_tuple = false,
    } });
}
