pub const types = @import("types.zig");

pub const StructureType = enum(u8) {
    material,
    custom,
};

pub const Definition = union(StructureType) {
    material: void,
    custom: type,

    pub fn get_type(comptime self: Definition) type {
        const T = switch (self) {
            .material => types.MaterialConfig,
            .custom => |t| t,
        };
        // The type must be a struct
        const type_info = @typeInfo(T);
        comptime assert(type_info == .@"struct");

        // All structures to use FSD must have a version constant
        comptime assert(@hasDecl(T, "version"));
        comptime assert(@TypeOf(T.version) == types.Version);

        const struct_info = type_info.@"struct";
        // All members must have a default value
        // TODO: Validate the fields have acceptable types
        inline for (struct_info.fields) |field| {
            comptime assert(field.default_value != null);
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

pub fn load(comptime s_type: Definition, file_path: []const u8, out_data: *s_type.get_type()) void {
    const parser = Parser{};
    _ = file_path;

    const T = s_type.get_type();

    const struct_info = @typeInfo(T).@"struct";
    var fields: [struct_info.fields.len - 1]Field = undefined;

    // TODO: Find all fields in the structure and nested structures.
    // TODO: Figure out a way to capture enum fields as strings

    out_data.* = .{};

    inline for (struct_info.fields[1..], 0..) |field, i| {
        const field_type = field.type;
        const field_info = @typeInfo(field_type);

        const dtype = dtype: switch (field_info) {
            .bool => .{ .base = .bool },
            .int, .float => .{ .base = comptime std.meta.stringToEnum(BaseType, @typeName(field_type)).? },
            .@"enum" => {},
            .@"struct" => {},
            .array => |array| {
                if (array.child == u8) {
                    break :dtype .{ .string = .{ .max_len = array.len, .is_static = true, .is_const = false } };
                }
                const child_info = @typeInfo(array.child);
                switch (child_info) {
                    .float => {
                        switch (array.len) {
                            2 => break :dtype .{ .base = .vec2s },
                            3 => break :dtype .{ .base = .vec3s },
                            4 => break :dtype .{ .base = .vec4s },
                            else => {},
                        }
                    },
                    .int => {},
                    .bool => {},
                    else => @compileError("Unsupported array type" ++ @typeName(field_type))
                }

                break .{ .static_array = .{
                    .base = comptime std.meta.stringToEnum(BaseType, @typeName(array.child)).?,
                    .num_elements = array.len,
                } };
            },
            inline else => @compileError("Invalid field type for struct.")
        };
        fields[i] = Field{ .name = field.name, .dtype = dtype, .data = @ptrCast(&@field(out_data, field.name)) };
        parser.push(.read_statement);
    }
}

fn get_recursive_field_len(structure_t: type) usize {
    comptime {
        const type_info = @typeInfo(structure_t);
        assert(type_info == .@"struct");
        const struct_info = type_info.@"struct";
        var structs: [1024]std.builtin.Type.Struct = undefined;
        var ptr: usize = 0;
        var count: usize = 0;
        structs[ptr] = struct_info;
        ptr += 1;
        while (ptr > 0) {
            const fields = structs[ptr - 1].fields;
            ptr -= 1;

            for (fields) |field| {
                assert(field.default_value != null);
                const field_info = @typeInfo(field.type);
                switch (field_info) {
                    .@"struct" => |info| {
                        structs[ptr] = info;
                        ptr += 1;
                    },
                    .bool, .int, .float, .@"enum", .array => {
                        count += 1;
                    },
                    else => {
                        @compileError("Invalid field encountered in structure");
                    }
                }
            }
        }
        return count;
    }
}

fn get_fields(structure_t: type, data: *structure_t) [get_recursive_field_len(structure_t)]Field {
    const count = get_recursive_field_len(structure_t);
    const type_info = @typeInfo(structure_t);
    assert(type_info == .@"struct");
    const struct_info = type_info.@"struct";

    // +1 here so that we can store the information about structure_t itself
    var fields: [count + 1]Field = undefined;
    var index = 0;

    const internal_data = struct {
        info: std.builtin.Type.Struct,
        field_pos: usize,
        field_access: [32][]const u8 = undefined,
        access_len: u8 = 0,

        const Self = @This();
    };
    const buffer: [1024]internal_data = undefined;
    var structs = std.ArrayListUnmanaged(internal_data).initBuffer(buffer);

    fields[0] = Field{
        .name = "root",
        .dtype = .{ .@"struct" = .{ .fields_start = 0, .fields_end = 0 } },
        .data = null,
    };
    structs.appendAssumeCapacity(.{
        .info = struct_info,
        .field_pos = 0,
    });

    inline while (index < count) {
        const current_struct = structs.orderedRemove(0);
        fields[current_struct.field_pos].dtype.@"struct".field_start = index;

        field_loop: for (current_struct.info.fields) |field| {
            const field_info = @typeInfo(field.type);
            const dtype: DType = dtype: switch (field_info) {
                .bool => .{ .base = .bool },
                .int, .float => .{ .base = comptime std.meta.stringToEnum(BaseType, @typeName(field.type)).? },
                .@"enum" => {},
                .@"struct" => |s| {
                    fields[index] = Field{
                        .name = field.name,
                        .dtype = .{ .@"struct" = .{ .fields_start = 0, .fields_end = 0 } },
                        .data = @ptrCast(&@field(data, field.name)),
                    };
                    structs.appendAssumeCapacity(internal_data{ .info = s, .field_pos = index });
                    index += 1;
                    continue :field_loop;
                },
                .array => |array| {
                    if (array.child == u8) {
                        break :dtype .{ .string = .{ .max_len = array.len, .is_static = true, .is_const = false } };
                    }
                    const child_info = @typeInfo(array.child);
                    switch (child_info) {
                        .float => {
                            switch (array.len) {
                                2 => break :dtype .{ .base = .vec2s },
                                3 => break :dtype .{ .base = .vec3s },
                                4 => break :dtype .{ .base = .vec4s },
                                else => {},
                            }
                        },
                        .int => {},
                        .bool => {},
                        else => @compileError("Unsupported array type" ++ @typeName(field.type))
                    }

                    break .{ .static_array = .{
                        .base = comptime std.meta.stringToEnum(BaseType, @typeName(array.child)).?,
                        .num_elements = array.len,
                    } };
                },
                inline else => @compileError("Invalid field type for struct.")
            };
            fields[index] = Field{ .name = field.name, .dtype = dtype, .data = @ptrCast(&@field(data, field.name)) };
            index += 1;
        }
        fields[current_struct.field_pos].dtype.@"struct".field_end = index;
    }
}

fn get_access_type(dtype: type, comptime field_stack: []const []const u8) type {
    comptime assert(field_stack.len > 0);
    var current_type = dtype;
    var info = @typeInfo(current_type);
    switch (info) {
        .pointer => {
            current_type = info.pointer.child;
            info = @typeInfo(current_type);
        },
        .@"struct" => {},
        else => @compileError("Unsupported type"),
    }
    comptime assert(info == .@"struct");
    comptime assert(@hasField(current_type, field_stack[0]));
    const name = field_stack[0];
    for (info.@"struct".fields) |field| {
        if (comptime std.mem.eql(u8, field.name, name)) {
            if (field_stack.len > 1) {
                return get_access_type(field.type, field_stack[1..]);
            } else {
                return field.type;
            }
        }
    }
}

fn get_nested(
    final_type: type,
    data_ptr: anytype,
    comptime field_stack: []const []const u8,
) *final_type {
    if (comptime field_stack.len > 1) {
        return get_nested(final_type, &@field(data_ptr, field_stack[0]), field_stack[1..]);
    } else {
        return &@field(data_ptr, field_stack[0]);
    }
}
const Parser = struct {};

const Field = struct {
    name: []const u8,
    dtype: DType,
    data: *anyopaque,
};

const DType = union(enum(u8)) {
    base: BaseType,
    texture: struct { len: u64 },
    array: struct { base: BaseType, len: u64 },
    @"enum": BaseType,
    @"struct": struct { field_start: u32, field_end: u32 },
};

const BaseType = enum(u8) {
    u8,
    u16,
    u32,
    u64,
    u128,
    i8,
    i16,
    i32,
    i64,
    i128,
    f16,
    f32,
    f64,
    f80,
    f128,
    bool,
    vec2s,
    vec3s,
    vec4s,
};

const std = @import("std");
const assert = std.debug.assert;

test Parser {
    const CustomStructure = struct {
        data: u8 = 0,
        data_2: struct { _x0: u8 = 0, _x2: u32 = 0 } = .{},
        pub const version: types.Version = types.Version.init(0, 0, 1);
    };
    std.debug.print("{d}\n", .{comptime get_recursive_field_len(CustomStructure)});
    var a = CustomStructure{};
    std.debug.print("{any}\n", .{@field(@field(a, "data_2"), "_x0")});
    // std.debug.print("{any}\n", .{get_nested(&a, &[_][]const u8{ "data_2", "_x0" })});
    const access = &[_][]const u8{ "data_2", "_x0" };
    const access_type = get_access_type(@TypeOf(&a), access);
    std.debug.print("{any}\n", .{get_nested(access_type, &a, access).*});
    // var fsd: FSD = undefined;
    // try fsd.init(std.testing.allocator);
    //
    // var material: types.MaterialConfig = undefined;
    // var start = std.time.Timer.start() catch unreachable;
    // const result = try fsd.load_fsd(.material, &material, "test.fsd");
    // const end = start.read();
    // std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});
    // std.debug.print("Resul: {s}\n", .{@tagName(result)});
    //
    // std.debug.print("Material: {any}\n", .{material});
    // std.debug.print("Data7: {s}\n", .{material.data7});
    // std.testing.allocator.free(material.data7);
}
