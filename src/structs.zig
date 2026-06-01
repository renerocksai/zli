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
    var names: [fields_in.len][:0]const u8 = undefined;
    var types: [fields_in.len]type = undefined;
    var attrs: [fields_in.len]StructField.Attributes = undefined;

    for (fields_in, 0..) |field_in, i| {
        names[i] = field_in.name;
        types[i] = Data;
        attrs[i] = .{
            .default_value_ptr = if (default) |d| @as(?*const anyopaque, @ptrCast(&d)) else null,
            .@"comptime" = false,
            .@"align" = if (@sizeOf(Data) > 0) @alignOf(Data) else null,
        };
    }

    return @Struct(.auto, null, &names, &types, &attrs);
}
