/// Creates a distinct type of a given type by storing it inside a struct and creating a type constant tag.
/// Passing the same type and different tags will create different types. However passing the same type and tag will
/// return the same type.
/// This does add some overhead to syntax since you will have to explicitly call .val on everything.
pub fn Distinct(T: type, tag: @Type(.enum_literal)) type {
    return struct {
        val: T,
        pub const name = @tagName(tag);
    };
}

test Distinct {
    const Idx1 = Distinct(u64, .idx1);
    const Idx2 = Distinct(u64, .idx2);
    const Idx3 = Distinct(u64, .idx1);

    const test_struct = struct {
        a: u64,
        b: u64,
    };
    const vec4 = @Vector(4, f32);
    const quat = Distinct(vec4, .quaternion);
    const Vec4 = Distinct(vec4, .quaternion);

    const test1 = Distinct(test_struct, .test1);
    const test2 = Distinct(test_struct, .test2);

    try std.testing.expect(Vec4 == quat);
    try std.testing.expect(test1 != test2);

    try std.testing.expect(Idx1 != Idx2);
    try std.testing.expect(Idx1 == Idx3);
    try std.testing.expect(@sizeOf(Idx1) == 8);
}

/// Helper function to merge enums together. The passed enums should not have common tag names else it will
/// cause an error when compiling.
/// The backing_int_type provided must be an unsigned integer and should be able to accomodate the combined enums.
pub fn MergeEnums(comptime enums: []const type, comptime backing_int_type: type) type {
    const int_type_info = @typeInfo(backing_int_type);
    if (int_type_info != .int and int_type_info.Int.signedness != .unsigned) {
        @compileError("Expected an unsigned integer as backing_int_type got " ++ @typeName(backing_int_type));
    }

    // Calculate how many fields we will need in the new enum
    comptime var total: usize = 0;
    inline for (enums) |element| {
        const field_type_info = @typeInfo(element);
        switch (field_type_info) {
            .@"enum" => |e| {
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
        inline for (field_type_info.@"enum".fields) |f| {
            enum_fields[i].name = f.name;
            enum_fields[i].value = i;
            i += 1;
        }
    }
    var enum_type: std.builtin.Type.Enum = undefined;

    enum_type.fields = &enum_fields;
    enum_type.tag_type = backing_int_type;
    enum_type.decls = &[0]std.builtin.Type.Declaration{};
    enum_type.is_exhaustive = false;

    return @Type(std.builtin.Type{ .@"enum" = enum_type });
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
    try testing.expect(enum_info == .@"enum");
    try testing.expect(!enum_info.@"enum".is_exhaustive);
    try testing.expect(enum_info.@"enum".tag_type == u8);
    try testing.expect(enum_info.@"enum".fields.len == 6);
}

const std = @import("std");
const testing = std.testing;
