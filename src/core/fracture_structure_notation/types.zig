pub const Version = packed struct(u32) {
    major: u4 = 0,
    minor: u12 = 0,
    patch: u16 = 0,

    pub fn init(major: u4, minor: u12, patch: u16) Version {
        return Version{
            .major = major,
            .minor = minor,
            .patch = patch,
        };
    }
};

pub const StructureType = enum(u8) {
    material,
    custom,
};

pub const Definition = union(StructureType) {
    material: void,
    custom: type,

    pub fn get_type(comptime self: Definition) type {
        const T = switch (self) {
            .material => MaterialConfig,
            .custom => |t| t,
        };
        // The type must be a struct
        const type_info = @typeInfo(T);
        comptime assert(type_info == .@"struct");

        // All structures to use FSD must have a version constant
        comptime assert(@hasDecl(T, "version"));
        comptime assert(@TypeOf(T.version) == Version);

        const struct_info = type_info.@"struct";
        // All members must have a default value
        // TODO: Validate the fields have acceptable types
        inline for (struct_info.fields) |field| {
            comptime assert(field.defaultValue() != null);
        }

        return T;
    }

    pub fn get_struct_name(comptime self: StructureType) []const u8 {
        comptime {
            switch (self) {
                .material => return "material",
                .custom => |t| {
                    const name = @typeName(t);
                    var iter = std.mem.splitBackwardsScalar(u8, name, '.');
                    return iter.first();
                }
            }
        }
    }
};

pub const DType = union(enum(u8)) {
    base: BaseType,
    texture: struct { len: u64 },
    array: ArrayInfo,
    @"enum": BaseType,
    @"struct": StructInfo,

    const StructInfo = struct { fields_start: u32, fields_end: u32 };
    const ArrayInfo = struct {
        base: BaseType,
        len: u32,
        parsed_len: u32 = 0,
        current_len: u32 = 0,
    };
};

pub const BaseType = enum(u8) {
    u8 = 0,
    u16 = 1,
    u32 = 2,
    u64 = 3,
    u128 = 4,
    i8 = 5,
    i16 = 6,
    i32 = 7,
    i64 = 8,
    i128 = 9,
    f16 = 10,
    f32 = 11,
    f64 = 12,
    f80 = 13,
    f128 = 14,
    bool = 15,
    vec2s = 16,
    vec3s = 17,
    vec4s = 19,
    string = 20,

    pub fn get_type(comptime self: BaseType) type {
        return switch (self) {
            .u8 => u8,
            .u16 => u16,
            .u32 => u32,
            .u64 => u64,
            .u128 => u128,
            .i8 => i8,
            .i16 => i16,
            .i32 => i32,
            .i64 => i64,
            .i128 => i128,
            .f16 => f16,
            .f32 => f32,
            .f64 => f64,
            .f80 => f80,
            .f128 => f128,
            .bool => bool,
            else => @compileError("Should not be accessing get_type on this BaseType"),
        };
    }
};

pub const MaterialConfig = struct {
    data: u8 = 0,
    data2: i8 = 0,
    data3: f32 = 0,
    data4: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 },
    data5: [6]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0, 0.0, 0.0 },
    data6: [32]u8 = std.mem.zeroes([32]u8),
    // data7: [16]u8 = undefined,
    // data5: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    // data6: [2]f32 = [_]f32{ 0.0, 0.0 },
    // data7: [16]u8 = undefined,
    //
    // @data2: i8 = -10
    // @data3: f32 = 1.523425
    // @data4: vec3s = {1.23, 2522.2523, 5}
    // @data5: vec4s = {1.23, 2522.2523, 5, 32.2352}
    // @data6: vec2s = {1.23, 2522.2523}
    // @data7: string = "test_string"

    pub const version: Version = Version.init(0, 0, 1);
};

const std = @import("std");
const assert = std.debug.assert;
