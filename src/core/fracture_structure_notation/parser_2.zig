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
    @"invalid_fsd_missing_=",
    invalid_fsd_invalid_field_name,
    @"invalid_fsd_missing_:",
    invalid_fsd_incompatable_type,
    invalid_fsd_array_must_contain_length,
    invalid_fsd_array_child_type_mismatch,
    invalid_fsd_invalid_float,
    invalid_fsd_invalid_integer,
    invalid_fsd_array_too_long,
    invalid_fsd_missing_array_start,
} || std.fs.File.OpenError || std.fs.File.ReadError;

// NOTE: If the fsd file is larger than 16 pages use the alloc version of load
const MAX_BUFFER_PAGES = 16;
const MAX_BYTES = 4096 * MAX_BUFFER_PAGES;

threadlocal var buffer: [MAX_BYTES]u8 = undefined;

const Token = struct {
    tag: Tag,
    start: u16,
    end: u16,

    pub const Tag = enum(u8) {
        IDENTIFIER,
        INTEGER,
        FLOAT,
        @"\"",
        @".",
        @":",
        @"@",
        @"=",
        @"[",
        @"]",
        @"{",
        @"}",
    };
};

// std.zig.Tokenizer
const Tokenizer = struct {
    source: []const u8,
    ptr: usize,

    const State = enum(u8) {
        start,
    };
};

pub fn load(comptime s_type: Definition, noalias file_path: []const u8, noalias out_data: *s_type.get_type()) LoadError!void {
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
    const length_file = try reader.read(&buffer);
    defer file.close();
    assert(length_file < MAX_BYTES);

    var parser_stack_buffer: [1024]ParserState = undefined;
    var parser_stack = std.ArrayListUnmanaged(ParserState).initBuffer(&parser_stack_buffer);

    parser_stack.appendAssumeCapacity(.end_parsing);
    parser_stack.appendNTimesAssumeCapacity(.read_statement, out_fields.len - 1);
    parser_stack.appendAssumeCapacity(.read_header);

    var data: []const u8 = buffer[0..length_file];

    var column_number: u32 = 0;
    var line_number: u32 = 0;

    var read_head: u32 = 0;
    var field_current: u32 = 1;

    // TODO: Make this return a result object instead of an error along with info about the error
    // TODO: Allow arrays of arrays
    // TODO: Allow comments
    // TODO: Should there be a token buffer that we fill up and then parse that way? That might not work with buffered
    // input. Should we just load the entire file into memeory? I dont like that because i dont want there to be allocations here
    // But maybe that is fine in debug builds? If I were to do it i would do it in read_data. Just fill in a buffer of
    // 1024 tokens. Usually that should cover most files.

    const result: ?LoadError = loop: switch (parser_stack.getLast()) {
        .read_header => {
            assert(data.len >= 5);
            if (data[0] != '@') {
                break :loop LoadError.@"invalid_fsd_expected_@_at_start";
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
                break :loop LoadError.invalid_fsd_incomplete;
            }

            if (!std.mem.eql(u8, data[0..read_head], struct_name)) {
                break :loop LoadError.invalid_fsd_invalid_file_type;
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
                break :loop LoadError.invalid_fsd_incomplete;
            }

            var i: u32 = 0;

            const version: types.Version = T.version;

            while (i < read_head and data[i] != '.') : (i += 1) {}

            const major = std.fmt.parseInt(u4, data[0..i], 10) catch {
                break :loop LoadError.invalid_fsd_version;
            };
            if (version.major != major) {
                break :loop LoadError.fsd_major_version_mismatch;
            }

            data = data[i + 1 ..];
            read_head -= i + 1;
            column_number += @truncate(i + 1);
            i = 0;

            while (i < read_head and data[i] != '.') : (i += 1) {}

            const minor = std.fmt.parseInt(u4, data[0..i], 10) catch {
                return LoadError.invalid_fsd_version;
            };
            if (version.minor != minor) {
                return LoadError.fsd_minor_version_mismatch;
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
            continue :loop .read_statement;
        },
        .read_statement => {
            assert(data.len > 2);
            if (data[0] != '@') {
                break :loop LoadError.@"invalid_fsd_expected_@_at_start";
            }
            data = data[1..];
            column_number += 1;
            _ = parser_stack.pop();
            parser_stack.appendAssumeCapacity(.end_statement);
            parser_stack.appendAssumeCapacity(.read_till_next_line);
            parser_stack.appendAssumeCapacity(.parse_value);
            parser_stack.appendAssumeCapacity(.read_value);
            parser_stack.appendAssumeCapacity(.assert_equal);
            parser_stack.appendAssumeCapacity(.read_next_token);
            parser_stack.appendAssumeCapacity(.read_type);
            parser_stack.appendAssumeCapacity(.read_next_token);
            parser_stack.appendAssumeCapacity(.read_field);
            parser_stack.appendAssumeCapacity(.read_next_token);
            continue :loop .read_next_token;
        },
        .read_next_token => {
            // NOTE: Before reading next token remove all white space
            if (data[read_head] == ' ' or data[read_head] == '\t') {
                consuming: while (read_head < data.len) : (read_head += 1) {
                    if (data[read_head] == ' ' or data[read_head] == '\t') {
                        continue :consuming;
                    } else {
                        data = data[read_head..];
                        read_head = 0;
                        break :consuming;
                    }
                } else {
                    break :loop LoadError.invalid_fsd_incomplete;
                }
            } else {}

            search: while (read_head < data.len) : (read_head += 1) {
                if (data[read_head] != ' ' and data[read_head] != '\n' and data[read_head] != '\t' and data[read_head] != '\r') {
                    continue :search;
                } else {
                    _ = parser_stack.pop();
                    continue :loop parser_stack.getLast();
                }
            } else {
                break :loop LoadError.invalid_fsd_incomplete;
            }
        },
        .read_till_next_line => {
            while (read_head < data.len) : (read_head += 1) {
                if (data[read_head] == '\n') {
                    _ = parser_stack.pop();
                    data = data[read_head + 1 ..];
                    line_number += 1;
                    column_number = 0;
                    continue :loop .end_statement;
                }
            }

            break :loop LoadError.invalid_fsd_incomplete;
        },
        .assert_equal => {
            assert(read_head == 1);
            if (data[0] != '=') {
                break :loop LoadError.@"invalid_fsd_missing_=";
            }
            data = data[2..];
            read_head = 0;
            _ = parser_stack.pop();
            continue :loop .read_next_token;
        },
        .read_field => {
            assert(read_head >= 2);
            if (!std.mem.eql(u8, out_fields[field_current].name, data[0 .. read_head - 1])) {
                break :loop LoadError.invalid_fsd_invalid_field_name;
            }
            if (data[read_head - 1] != ':') {
                break :loop LoadError.@"invalid_fsd_missing_:";
            }
            data = data[read_head + 1 ..];
            column_number += @truncate(read_head + 1);
            read_head = 0;
            _ = parser_stack.pop();
            continue :loop .read_next_token;
        },
        .read_type => {
            assert(read_head >= 2);
            switch (out_fields[field_current].dtype) {
                .base => |b| {
                    if (!std.mem.eql(u8, @tagName(b), data[0..read_head])) {
                        break :loop LoadError.invalid_fsd_incompatable_type;
                    }
                },
                .array => |*arr_info| {
                    if (data[0] == '[') {
                        var pos: usize = 1;
                        column_number += 1;

                        while (pos < read_head and data[pos] != ']') : (pos += 1) {}

                        if (pos == 1) {
                            break :loop LoadError.invalid_fsd_array_must_contain_length;
                        }

                        const len = std.fmt.parseUnsigned(u32, data[1..pos], 10) catch {
                            break :loop LoadError.invalid_fsd_invalid_integer;
                        };
                        if (len > arr_info.len) {
                            break :loop LoadError.invalid_fsd_array_too_long;
                        }
                        arr_info.parsed_len = len;

                        column_number += @truncate(pos - 1);
                        const type_name: []const u8 = @tagName(arr_info.base);
                        if (!std.mem.eql(u8, type_name, data[pos + 1 .. read_head])) {
                            break :loop LoadError.invalid_fsd_array_child_type_mismatch;
                        }
                        column_number += @truncate(type_name.len);
                    } else {
                        break :loop LoadError.invalid_fsd_incompatable_type;
                    }
                },
                .@"struct" => std.debug.panic("NOT IMPLEMENTED", .{}),
                .texture => std.debug.panic("NOT IMPLEMENTED", .{}),
                .@"enum" => std.debug.panic("NOT IMPLEMENTED", .{}),
            }
            data = data[read_head + 1 ..];
            column_number += @truncate(read_head + 1);
            read_head = 0;
            _ = parser_stack.pop();
            continue :loop .read_next_token;
        },
        .read_value => {
            // TODO: allow _ in numbers
            switch (out_fields[field_current].dtype) {
                .base => {
                    _ = parser_stack.pop();
                    parser_stack.appendAssumeCapacity(.read_next_token);
                    continue :loop .read_next_token;
                },
                .array => {
                    search: while (read_head < data.len) : (read_head += 1) {
                        // NOTE: consume all the spaces before array start. Array must start on teh same line
                        if (data[read_head] != ' ' and data[read_head] != '\t') {
                            continue :search;
                        } else if (data[read_head] == '[') {
                            // NOTE: Only if you have a character after the [ character can you slice and continue
                            // else go read some more data. This is to handle if [ is the last character in the buffer
                            _ = parser_stack.pop();
                            if (read_head < data.len - 1) {
                                data = data[read_head + 1 ..];
                                read_head = 0;
                                parser_stack.appendAssumeCapacity(.parse_array);
                                continue :loop .parse_array;
                            } else {
                                break :loop LoadError.invalid_fsd_incomplete;
                            }
                        } else {
                            break :loop LoadError.invalid_fsd_missing_array_start;
                        }
                    } else {
                        break :loop LoadError.invalid_fsd_incomplete;
                    }
                },
                else => @panic("NOT IMPLEMENTED"),
            }
            unreachable;
        },
        .parse_value => {
            switch (out_fields[field_current].dtype) {
                .base => |b| try parse_base_types(b, data[0..read_head], out_fields[field_current].data.?),
                .array => unreachable,
                else => {},
            }
            data = data[read_head..];
            column_number += @truncate(read_head + 1);
            read_head = 0;
            _ = parser_stack.pop();
            continue :loop .read_till_next_line;
        },
        .read_array_element => {
            // NOTE: Eat the white spaces
            if (data[read_head] == ' ' or data[read_head] == '\t' or data[read_head] == '\r' or data[read_head] == '\n') {
                consuming: while (read_head < data.len) : (read_head += 1) {
                    if (data[read_head] == ' ' or data[read_head] == '\t') {
                        continue :consuming;
                    } else {
                        data = data[read_head..];
                        read_head = 0;
                        break :consuming;
                    }
                } else {
                    break :loop LoadError.invalid_fsd_incomplete;
                }
            } else {}

            search: while (read_head < data.len) : (read_head += 1) {
                if (data[read_head] != ' ' and data[read_head] != ']') {
                    continue :search;
                } else {
                    _ = parser_stack.pop();
                    continue :loop parser_stack.getLast();
                }
            } else {
                break :loop LoadError.invalid_fsd_incomplete;
            }
        },
        .parse_array => {
            const array_info = &out_fields[field_current].dtype.array;
            assert(array_info.len > 0);

            _ = parser_stack.pop();
            continue :loop .read_till_next_line;
        },
        .end_statement => {
            field_current += 1;
            _ = parser_stack.pop();
            if (parser_stack.getLast() == .read_statement) {
                continue :loop .read_statement;
            } else {
                continue :loop .end_parsing;
            }
        },
        .end_parsing => break :loop null,
    };

    if (result) |err| {
        std.debug.print(
            "Error: {s} at field: {d}, line: {d}, column: {d}\n",
            .{ @errorName(err), field_current, line_number, column_number },
        );
        std.debug.print("Data: {s}", .{data});
    }

    // TODO(adi): write binary format to disc here
}

fn parser_array(array_data: *DType.ArrayInfo, data: []const u8, noalias out_data: *anyopaque) LoadError!void {
    _ = data;
    _ = out_data;
    _ = array_data;
}

fn parse_base_types(base_type: BaseType, noalias payload: []const u8, noalias out_data: *anyopaque) LoadError!void {
    switch (base_type) {
        .u8 => {
            const ptr: *u8 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseUnsigned(u8, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .u16 => {
            const ptr: *u16 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseUnsigned(u16, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .u32 => {
            const ptr: *u32 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseUnsigned(u32, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .u64 => {
            const ptr: *u64 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseUnsigned(u64, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .i8 => {
            const ptr: *i8 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseInt(i8, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .i16 => {
            const ptr: *i16 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseInt(i16, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .i32 => {
            const ptr: *i32 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseInt(i32, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .i64 => {
            const ptr: *i64 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseInt(i64, payload, 10) catch {
                return LoadError.invalid_fsd_invalid_integer;
            };
        },
        .f32 => {
            const ptr: *f32 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseFloat(f32, payload) catch {
                return LoadError.invalid_fsd_invalid_float;
            };
        },
        .f64 => {
            const ptr: *f64 = @ptrCast(@alignCast(out_data));
            ptr.* = std.fmt.parseFloat(f64, payload) catch {
                return LoadError.invalid_fsd_invalid_float;
            };
        },
        .vec2s, .vec3s, .vec4s => {
            // TODO: Call array parsing
        },
        else => unreachable,
    }
}

const ParserState = enum(u8) {
    read_statement,
    read_header,
    read_till_next_line,
    read_next_token,
    read_type,
    read_field,
    read_value,
    read_array_element,
    parse_value,
    parse_array,
    assert_equal,
    end_statement,
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
                assert(field.defaultValue() != null);
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
    const ArrayInfo = struct { base: BaseType, len: u32, parsed_len: u32, current_len: u32 };
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
    const iterations = 100000;
    // var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    // const allocator = arena.allocator();
    // defer arena.deinit();
    for (0..iterations) |_| {
        try load(.material, "test.fsd", &material);
        // const file = try std.fs.cwd().openFile("test.zon", .{});
        // defer file.close();
        // const source = try file.readToEndAllocOptions(allocator, 10240, null, 1, 0);
        // // const source = try file.readToEndAlloc(allocator, 1024);
        // material = try std.zon.parse.fromSlice(types.MaterialConfig, allocator, source, null, .{ .free_on_error = false });
        // _ = arena.reset(.retain_capacity);
    }
    const end = start.read() / iterations;
    std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});

    std.debug.print("Material: {any}\n", .{material});
}
