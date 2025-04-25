const std = @import("std");
const assert = std.debug.assert;

const math = @import("fr_math");

const types = @import("types.zig");
const DType = types.DType;
const BaseType = types.BaseType;

pub const Field = struct {
    name: []const u8,
    dtype: DType,
    data: ?*anyopaque,
};

fn get_recursive_field_len(T: type) usize {
    comptime {
        const type_info = @typeInfo(T);
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
                assert(field.defaultValue() != null);
                const field_info = @typeInfo(field.type);
                switch (field_info) {
                    .@"struct" => |info| {
                        if (field.type == math.Vec2 or field.type == math.Vec3 or field.type == math.Vec4) {
                            count += 1;
                            continue;
                        }
                        structs[ptr] = info;
                        count += 1;
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

pub fn get_fields(T: type) [get_recursive_field_len(T) + 1]Field {
    @setEvalBranchQuota(100000);
    comptime {
        const count = get_recursive_field_len(T);
        const type_info = @typeInfo(T);
        assert(type_info == .@"struct");
        const struct_info = type_info.@"struct";

        // +1 here so that we can store the information about structure_t itself
        var fields: [count + 1]Field = undefined;
        var index = 1;

        const internal_data = struct {
            info: std.builtin.Type.Struct,
            field_pos: usize,
        };
        var internal_buffer: [1024]internal_data = undefined;
        var structs = std.ArrayListUnmanaged(internal_data).initBuffer(&internal_buffer);

        fields[0] = Field{
            .name = "root",
            .dtype = .{ .@"struct" = .{ .fields_start = 0, .fields_end = 0 } },
            .data = null,
        };
        structs.appendAssumeCapacity(.{
            .info = struct_info,
            .field_pos = 0,
        });

        // TODO: Should there be 2 loops one for comptime stuff and one for dealing with pointers

        while (index < count + 1) {
            const current_struct = structs.orderedRemove(0);
            fields[current_struct.field_pos].dtype.@"struct".fields_start = index;

            field_loop: for (current_struct.info.fields) |field| {
                const field_info = @typeInfo(field.type);
                const dtype: DType = dtype: switch (field_info) {
                    .bool => .{ .base = .bool },
                    .int, .float => .{ .base = std.meta.stringToEnum(BaseType, @typeName(field.type)).? },
                    .@"enum" => {},
                    .@"struct" => |s| {
                        if (field.type == math.Vec2) {
                            break :dtype .{ .base = .vec2s };
                        }
                        if (field.type == math.Vec3) {
                            break :dtype .{ .base = .vec3s };
                        }
                        if (field.type == math.Vec4) {
                            break :dtype .{ .base = .vec4s };
                        }
                        fields[index] = Field{
                            .name = field.name,
                            .dtype = .{ .@"struct" = .{ .fields_start = 0, .fields_end = 0 } },
                            .data = null,
                        };
                        structs.appendAssumeCapacity(internal_data{ .info = s, .field_pos = index });
                        index += 1;
                        continue :field_loop;
                    },
                    .array => |array| {
                        const child_info = @typeInfo(array.child);
                        switch (child_info) {
                            .float => {
                                // switch (array.len) {
                                //     2 => break :dtype .{ .base = .vec2s },
                                //     3 => break :dtype .{ .base = .vec3s },
                                //     4 => break :dtype .{ .base = .vec4s },
                                //     else => {},
                                // }
                            },
                            .int => {},
                            .bool => {},
                            else => @compileError("Unsupported array type" ++ @typeName(field.type))
                        }
                        //TODO: Deal with array of structs
                        break :dtype .{ .array = .{
                            .base = std.meta.stringToEnum(BaseType, @typeName(array.child)).?,
                            .len = array.len,
                        } };
                    },
                    inline else => @compileError("Invalid field type for struct.")
                };
                fields[index] = Field{ .name = field.name, .dtype = dtype, .data = null };
                index += 1;
            }
            fields[current_struct.field_pos].dtype.@"struct".fields_end = index;
        }
        return fields;
    }
}

pub fn fill_pointers(
    T: type,
    comptime fields: []const Field,
    data: *T,
) [get_recursive_field_len(T) + 1]Field {
    const count = comptime get_recursive_field_len(T);
    comptime assert(fields.len == count + 1);
    comptime assert(std.mem.eql(u8, fields[0].name, "root"));

    const tracking_t = struct {
        prev_index: u16,
        index_end: u16,
    };
    comptime var internal_buffer: [32]tracking_t = undefined;
    comptime var struct_stack = std.ArrayListUnmanaged(tracking_t).initBuffer(&internal_buffer);
    comptime var index: usize = 1;

    var out_fields: [count + 1]Field = undefined;
    out_fields[0] = fields[0];

    inline for (0..count) |_| {
        switch (fields[index].dtype) {
            .base, .array => {
                const local_stack = comptime blk: {
                    var ret_fields: [struct_stack.items.len + 1][]const u8 = undefined;
                    for (struct_stack.items, 0..) |item, i| {
                        ret_fields[i] = fields[item.prev_index].name;
                    }
                    ret_fields[struct_stack.items.len] = fields[index].name;
                    break :blk ret_fields;
                };
                out_fields[index] = fields[index];
                const access_t = get_access_type(T, &local_stack);
                const ptr = get_nested_field_ptr(access_t, data, &local_stack);
                out_fields[index].data = @ptrCast(ptr);
            },
            .@"struct" => |s| {
                comptime struct_stack.appendAssumeCapacity(tracking_t{ .prev_index = index, .index_end = s.fields_end });
                out_fields[index] = fields[index];
                index = s.fields_start;
                continue;
            },
            else => {
                @compileError("Not implemented");
            },
        }
        index += 1;
        if (comptime struct_stack.items.len > 0) {
            if (index == struct_stack.items[struct_stack.items.len - 1].index_end) {
                const finished_struct = comptime struct_stack.pop();
                index = finished_struct.prev_index + 1;
            }
        }
    }
    return out_fields;
}

// test fill_pointers {
//     // TODO: Finish this test
//     const CustomStructure = struct {
//         data: u8 = 0,
//         data_2: struct { _x0: u8 = 0, _x2: [3]u32 = [_]u32{0} ** 3 } = .{},
//         pub const version: types.Version = types.Version.init(0, 0, 1);
//     };
//     var a = CustomStructure{};
//     const fields = comptime get_fields(CustomStructure);
//     const out_fields = fill_pointers(CustomStructure, &fields, &a);
//     // for (out_fields) |field| {
//     //     std.debug.print("\t{any}\n", .{field});
//     // }
//     const val_ptr: *[3]u32 = @alignCast(@ptrCast(out_fields[4].data.?));
//     val_ptr[0] = 69;
//     try std.testing.expectEqual(a.data_2._x2[0], 69);
//
//     // std.debug.print("{d}\n", .{comptime get_recursive_field_len(CustomStructure)});
// }

pub fn get_access_type(dtype: type, comptime field_stack: []const []const u8) type {
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

pub fn get_nested_field_ptr(
    final_type: type,
    data_ptr: anytype,
    comptime field_stack: []const []const u8,
) *final_type {
    if (comptime field_stack.len > 1) {
        return get_nested_field_ptr(final_type, &@field(data_ptr, field_stack[0]), field_stack[1..]);
    } else {
        return &@field(data_ptr, field_stack[0]);
    }
}
