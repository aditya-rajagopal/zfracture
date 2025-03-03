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

const MAX_ITERATIONS = 4096;

pub const LoadError = error{
    fsd_too_many_iterations,
    invalid_fsd_incomplete,
    invalid_fsd_missing_def,
    @"invalid_fsd_expected_@_at_start",
    invalid_fsd_invalid_file_type,
    invalid_fsd_version,
    fsd_major_version_mismatch,
    fsd_minor_version_mismatch,
    fsd_patch_version_mismatch,
} || std.fs.File.OpenError || std.fs.File.ReadError;

pub fn load(comptime s_type: Definition, file_path: []const u8, out_data: *s_type.get_type()) LoadError!void {
    const T = s_type.get_type();

    // TODO: Figure out a way to capture enum fields as strings

    out_data.* = .{};
    const fields = comptime get_fields(T);
    var out_fields = fill_pointers(T, &fields, out_data);

    const struct_name = comptime blk: {
        const type_name = @typeName(T);
        var iter = std.mem.splitBackwardsScalar(u8, type_name, '.');
        break :blk iter.first();
    };

    var field_buffer: [32][]Field = undefined;
    var field_stack = std.ArrayListUnmanaged([]Field).initBuffer(&field_buffer);

    const root_struct = out_fields[0].dtype.@"struct";
    const root_fields = out_fields[root_struct.fields_start..root_struct.fields_end];
    field_stack.appendAssumeCapacity(root_fields);

    const file = try std.fs.cwd().openFile(file_path, .{});
    const reader = file.reader();
    defer file.close();

    var parser_stack_buffer: [1024]ParserState = undefined;
    var parser_stack = std.ArrayListUnmanaged(ParserState).initBuffer(&parser_stack_buffer);

    parser_stack.appendAssumeCapacity(.end_parsing);
    parser_stack.appendNTimesAssumeCapacity(.read_statement, out_fields.len - 1);
    parser_stack.appendAssumeCapacity(.read_header);

    var buffer: [4096]u8 = undefined;
    var data: []const u8 = undefined;
    data.len = 0;

    parser_stack.appendAssumeCapacity(.read_data);
    var column_number: u32 = 0;
    var line_number: u32 = 0;
    var read_head: u32 = 0;

    // TODO: Make this return a result object instead of an error along with info about the error
    for (0..MAX_ITERATIONS) |_| {
        switch (parser_stack.getLast()) {
            .read_data => {
                var len: usize = 0;
                if (data.len == 0) {
                    len = try reader.read(&buffer);
                } else {
                    std.mem.copyForwards(u8, &buffer, data);
                    len = try reader.read(buffer[data.len..]);
                }
                if (len == 0) {
                    return LoadError.invalid_fsd_incomplete;
                }
                len += data.len;
                data = buffer[0..len];
                _ = parser_stack.pop();
            },
            .read_header => {
                assert(data.len >= 5);
                if (data[0] != '@') {
                    return LoadError.@"invalid_fsd_expected_@_at_start";
                }

                const def: [4]u8 = .{ 'd', 'e', 'f', ' ' };

                if (@as(u32, @bitCast(data[1..5].*)) != @as(u32, @bitCast(def))) {
                    return LoadError.invalid_fsd_missing_def;
                }
                data = data[5..];
                column_number = 5;

                // Expect the string to be the type of the structure
                search: while (read_head < data.len) : (read_head += 1) {
                    if (data[read_head] == ' ') {
                        break :search;
                    }
                } else {
                    column_number += read_head;
                    return LoadError.invalid_fsd_incomplete;
                }

                if (!std.mem.eql(u8, data[0..read_head], struct_name)) {
                    return LoadError.invalid_fsd_invalid_file_type;
                }
                data = data[read_head + 1 ..];
                column_number += @truncate(read_head + 1);
                read_head = 0;

                // Read the version
                search: while (read_head < data.len) : (read_head += 1) {
                    if (data[read_head] == '\n') {
                        break :search;
                    }
                } else {
                    column_number += read_head;
                    return LoadError.invalid_fsd_incomplete;
                }

                var i: u32 = 0;

                const version: types.Version = T.version;

                while (i < read_head) : (i += 1) {
                    if (data[i] == '.') {
                        const major = std.fmt.parseInt(u4, data[0..i], 10) catch {
                            return LoadError.invalid_fsd_version;
                        };
                        if (version.major != major) {
                            return LoadError.fsd_major_version_mismatch;
                        }
                        break;
                    }
                }

                data = data[i + 1 ..];
                read_head -= i + 1;
                column_number += @truncate(i + 1);
                i = 0;

                while (i < read_head) : (i += 1) {
                    if (data[i] == '.') {
                        const minor = std.fmt.parseInt(u4, data[0..i], 10) catch {
                            return LoadError.invalid_fsd_version;
                        };
                        if (version.minor != minor) {
                            return LoadError.fsd_minor_version_mismatch;
                        }
                        break;
                    }
                }
                read_head -= i + 1;
                data = data[i + 1 ..];
                column_number += @truncate(i + 1);

                const patch = std.fmt.parseInt(u16, data[0 .. read_head - 1], 10) catch {
                    return LoadError.invalid_fsd_version;
                };
                if (version.patch != patch) {
                    return LoadError.fsd_patch_version_mismatch;
                }
                data = data[read_head + 1 ..];
                read_head = 0;
                line_number += 1;

                _ = parser_stack.pop();
                break;
            },
            .end_parsing => break,
            else => {}
        }
    } else {
        return LoadError.fsd_too_many_iterations;
    }
}

const ParserState = enum(u8) {
    read_data,
    read_statement,
    read_header,
    end_parsing,
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
                assert(field.default_value != null);
                const field_info = @typeInfo(field.type);
                switch (field_info) {
                    .@"struct" => |info| {
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

fn get_fields(T: type) [get_recursive_field_len(T) + 1]Field {
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
        var buffer: [1024]internal_data = undefined;
        var structs = std.ArrayListUnmanaged(internal_data).initBuffer(&buffer);

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

fn fill_pointers(
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
    comptime var buffer: [32]tracking_t = undefined;
    comptime var struct_stack = std.ArrayListUnmanaged(tracking_t).initBuffer(&buffer);
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
                const access_t = comp.get_access_type(T, &local_stack);
                const ptr = comp.get_nested(access_t, data, &local_stack);
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

// const comp = @import("../comptime.zig");
const comp = struct {
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

    pub fn get_nested(
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
};

const Parser = struct {};

const Field = struct {
    name: []const u8,
    dtype: DType,
    data: ?*anyopaque,
};

const DType = union(enum(u8)) {
    base: BaseType,
    texture: struct { len: u64 },
    array: ArrayInfo,
    @"enum": BaseType,
    @"struct": StructInfo,

    const StructInfo = struct { fields_start: u32, fields_end: u32 };
    const ArrayInfo = struct { base: BaseType, len: u64 };
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
    // const CustomStructure = struct {
    //     data: u8 = 0,
    //     data_2: struct { _x0: u8 = 0, _x2: [3]u32 = [_]u32{0} ** 3 } = .{},
    //     pub const version: types.Version = types.Version.init(0, 0, 1);
    // };
    // var a = CustomStructure{};
    // const fields = comptime get_fields(CustomStructure);
    // const out_fields = fill_pointers(CustomStructure, &fields, &a);
    // for (out_fields) |field| {
    //     std.debug.print("\t{any}\n", .{field});
    // }
    // const val_ptr: *[3]u32 = @alignCast(@ptrCast(out_fields[4].data.?));
    // val_ptr[0] = 69;
    // try std.testing.expectEqual(a.data_2._x2[0], 69);

    // std.debug.print("{d}\n", .{comptime get_recursive_field_len(CustomStructure)});
    // var fsd: FSD = undefined;
    // try fsd.init(std.testing.allocator);

    var material: types.MaterialConfig = undefined;
    var start = std.time.Timer.start() catch unreachable;
    try load(.material, "test.fsd", &material);
    const end = start.read();
    std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});

    std.debug.print("Material: {any}\n", .{material});
}
