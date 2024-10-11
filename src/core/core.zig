pub const logging = @import("logging.zig");
pub const asserts = @import("asserts.zig");

pub fn MergeEnums(comptime enums: []const type, comptime backing_int_type: type) type {
    const int_type_info = @typeInfo(backing_int_type);
    if (int_type_info != .Int and int_type_info.Int.signedness != .unsigned) {
        @compileError("Expected an unsigned integer as backing_int_type got " ++ @typeName(backing_int_type));
    }

    // Calculate how many fields we will need in the new enum
    comptime var total: usize = 0;
    inline for (enums) |element| {
        const field_type_info = @typeInfo(element);
        switch (field_type_info) {
            .Enum => |e| {
                if (!e.is_exhaustive) {
                    @compileError("Recieved an exhaustive enum. This function does not support them");
                }
                total += e.fields.len;
            },
            else => {
                @compileError("Expected member of tuple to be enum got " ++ @typeName(element));
            },
        }
    }

    comptime std.debug.assert(total < std.math.maxInt(backing_int_type));

    comptime var enum_fields: [total]std.builtin.Type.EnumField = undefined;

    var i: usize = 0;
    inline for (enums) |element| {
        const field_type_info = @typeInfo(element);
        switch (field_type_info) {
            .Enum => |e| {
                inline for (e.fields) |f| {
                    enum_fields[i].name = f.name;
                    enum_fields[i].value = i;
                    i += 1;
                }
            },
            else => {
                @compileError("Expected member of tuple to be enum got " ++ @typeName(element));
            },
        }
    }
    var enum_type: std.builtin.Type.Enum = undefined;

    enum_type.fields = &enum_fields;
    enum_type.tag_type = backing_int_type;
    enum_type.decls = &[0]std.builtin.Type.Declaration{};
    enum_type.is_exhaustive = false;

    return @Type(std.builtin.Type{ .Enum = enum_type });
}

test MergeEnums {
    const enum1 = enum {
        a,
        b,
    };
    const enum2 = enum {
        c,
        d,
    };
    const enum3 = enum {
        e,
        f,
    };

    const enum_out = MergeEnums(&[_]type{ enum1, enum2, enum3 }, u8);
    const enum_info = @typeInfo(enum_out);
    try testing.expect(enum_info == .Enum);
    try testing.expect(!enum_info.Enum.is_exhaustive);
    try testing.expect(enum_info.Enum.tag_type == u8);
    try testing.expect(enum_info.Enum.fields.len == 6);
}

test {
    testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
const testing = std.testing;
