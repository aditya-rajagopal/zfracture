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

pub const FSDHeader = extern struct {
    time_stamp: u64,
    type: u32,
    version: Version,
    size: u16,
};

pub const StructureType = enum(u8) {
    material = 0,
    custom = 255,
};

pub const Definition = union(StructureType) {
    material: void,
    /// This is used for custom structures. Though I expect for now this is rarely to be used. Most artifacts that need
    /// this file type should mostly be internal structures
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

    /// This will compute the u32 unique identifier of the type that will be used in binaries
    pub fn get_type_id(comptime self: Definition) u32 {
        switch (self) {
            .material => return @intFromEnum(StructureType.material),
            .custom => |t| {
                const name = @typeName(t);
                return std.hash.Crc32.hash(name) +| 255;
            },
        }
    }

    pub fn get_struct_name(comptime self: Definition) []const u8 {
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
    vec4s = 18,
    string = 19,

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
            .vec2s => math.Vec2,
            .vec3s => math.Vec3,
            .vec4s => math.Vec4,
            .bool => bool,
            else => @compileError("Should not be accessing get_type on this BaseType"),
        };
    }
};

pub const MaterialConfig = struct {
    colour: math.Vec4 = .zeros,
    pub const version: Version = Version.init(0, 0, 1);
};

const math = @import("fr_math");
const std = @import("std");
const assert = std.debug.assert;
