const std = @import("std");
const assert = std.debug.assert;

/// Like `std.enums.EnumFieldStruct`, but for structs.
///
/// Returns a struct with a fields matching each field name of the provided
/// struct.
///
/// Each field is of type `Data` and has the provided default, which may be
/// undefined.
pub fn struct_field_struct(comptime S: type, comptime Data: type, comptime default: ?Data) type {
    assert(@typeInfo(S) == .@"struct");

    const names = @typeInfo(S).@"struct".field_names;
    const types: [names.len]type = @splat(Data);
    const attrs: [names.len]std.lang.Type.Struct.FieldAttributes = @splat(.{
        .default_value_ptr = if (default) |d| @as(?*const anyopaque, @ptrCast(&d)) else null,
        .@"comptime" = false,
        .@"align" = if (@sizeOf(Data) > 0) @alignOf(Data) else null,
    });

    return @Struct(.auto, null, names, &types, &attrs);
}
