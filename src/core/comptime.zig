const field = @import("fracture_structure_notation/field.zig");

pub const get_nested_field_ptr = field.get_nested_field_ptr;
pub const get_access_type = field.get_access_type;

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

test get_nested_field_ptr {
    const InternalStruct = struct { _x0: u16 = 69, _x2: u32 = 420 };
    const CustomStructure = struct {
        data: u16 = 666,
        data_2: InternalStruct = .{},
    };
    var a = CustomStructure{};

    const access = &[_][]const u8{ "data_2", "_x0" };
    const access_type = get_access_type(@TypeOf(&a), access);
    try testing.expectEqual(access_type, u16);
    const value_ptr = get_nested_field_ptr(access_type, &a, access);
    try testing.expectEqual(value_ptr.*, 69);
    a.data_2._x0 = 420;
    try testing.expectEqual(value_ptr.*, 420);

    const access_2 = &[_][]const u8{"data_2"};
    const access_type_2 = get_access_type(@TypeOf(&a), access_2);
    try testing.expectEqual(access_type_2, InternalStruct);
    const value_ptr_2 = get_nested_field_ptr(access_type_2, &a, access_2);
    try testing.expectEqual(value_ptr_2.*, InternalStruct{ ._x0 = 420, ._x2 = 420 });
    value_ptr_2._x0 = 69;
    try testing.expectEqual(value_ptr_2.*, InternalStruct{ ._x0 = 69, ._x2 = 420 });
    try testing.expectEqual(value_ptr.*, 69);
}

const std = @import("std");
const assert = std.debug.assert;
const testing = std.testing;
