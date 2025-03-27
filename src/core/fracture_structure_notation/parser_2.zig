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
    @"invalid_version_missing.",
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

    const keywords = std.StaticStringMap(Tag).initComptime(.{
        .{ "u8", .u8 },
        .{ "u16", .u16 },
        .{ "u32", .u32 },
        .{ "u64", .u64 },
        .{ "u128", .u128 },
        .{ "i8", .i8 },
        .{ "i16", .i16 },
        .{ "i32", .i32 },
        .{ "i64", .i64 },
        .{ "i128", .i128 },
        .{ "f16", .f16 },
        .{ "f32", .f32 },
        .{ "f64", .f64 },
        .{ "f80", .f80 },
        .{ "f128", .f128 },
        .{ "bool", .bool },
        .{ "vec2s", .vec2s },
        .{ "vec3s", .vec3s },
        .{ "vec4s", .vec4s },
        .{ "Texture", .texture },
        .{ "def", .def },
        .{ "true", .true },
        .{ "false", .false },
    });

    pub const Tag = enum(u8) {
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
        indentifier,
        number_literal,
        string_literal,
        @"\"",
        @".",
        @",",
        @":",
        @"@",
        @"=",
        @"[",
        @"]",
        @"{",
        @"}",
        texture,
        def,
        invalid,
        eof,
        true,
        false,
    };

    pub fn base_type(self: Token) ?BaseType {
        const int: u8 = @intFromEnum(self.tag);
        if (int <= 19) {
            return @enumFromInt(int);
        } else {
            return null;
        }
    }

    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }
};

// std.zig.Tokenizer
const Tokenizer = struct {
    source: [:0]const u8,
    ptr: u16,

    const State = enum(u8) {
        start,
        integer_literal,
        float_literal,
        identifier_literal,
        string_literal,
        string_literal_backslash,
        invalid,
        comment,
    };

    pub fn init(data: [:0]const u8) Tokenizer {
        return .{
            .source = data,
            .ptr = 0,
        };
    }

    pub fn next(self: *Tokenizer) Token {
        var result = Token{
            .tag = .invalid,
            .start = self.ptr,
            .end = undefined,
        };

        state_machine: switch (State.start) {
            .start => {
                switch (self.source[self.ptr]) {
                    0 => {
                        if (self.ptr == self.source.len) {
                            return .{
                                .tag = .eof,
                                .start = self.ptr,
                                .end = self.ptr,
                            };
                        } else {
                            continue :state_machine .invalid;
                        }
                    },
                    '0'...'9', '-' => {
                        self.ptr += 1;
                        result.tag = .number_literal;
                        continue :state_machine .integer_literal;
                    },
                    ' ', '\n', '\t', '\r' => {
                        self.ptr += 1;
                        result.start = self.ptr;
                        continue :state_machine .start;
                    },
                    'a'...'z', 'A'...'Z', '_' => {
                        result.tag = .indentifier;
                        continue :state_machine .identifier_literal;
                    },
                    '"' => {
                        result.tag = .string_literal;
                        continue :state_machine .string_literal;
                    },
                    '@' => {
                        self.ptr += 1;
                        result.tag = .@"@";
                    },
                    '=' => {
                        self.ptr += 1;
                        result.tag = .@"=";
                    },
                    '[' => {
                        self.ptr += 1;
                        result.tag = .@"[";
                    },
                    ']' => {
                        self.ptr += 1;
                        result.tag = .@"]";
                    },
                    '{' => {
                        self.ptr += 1;
                        result.tag = .@"{";
                    },
                    '}' => {
                        self.ptr += 1;
                        result.tag = .@"}";
                    },
                    '.' => {
                        self.ptr += 1;
                        result.tag = .@".";
                    },
                    ',' => {
                        self.ptr += 1;
                        result.tag = .@",";
                    },
                    ':' => {
                        self.ptr += 1;
                        result.tag = .@":";
                    },
                    '/' => continue :state_machine .comment,
                    else => continue :state_machine .invalid,
                }
            },
            .identifier_literal => {
                self.ptr += 1;
                switch (self.source[self.ptr]) {
                    'a'...'z', 'A'...'Z', '_', '0'...'9' => continue :state_machine .identifier_literal,
                    else => {
                        const ident = self.source[result.start..self.ptr];
                        if (Token.getKeyword(ident)) |tag| {
                            result.tag = tag;
                        }
                    },
                }
            },
            .integer_literal => {
                switch (self.source[self.ptr]) {
                    '.' => {
                        self.ptr += 1;
                        continue :state_machine .float_literal;
                    },
                    // TODO(adi): Get binary and hex numbers to work
                    '_', '0'...'9' => {
                        self.ptr += 1;
                        continue :state_machine .integer_literal;
                    },
                    else => {},
                }
            },
            .float_literal => {
                switch (self.source[self.ptr]) {
                    '_', '0'...'9' => {
                        self.ptr += 1;
                        continue :state_machine .float_literal;
                    },
                    else => {},
                }
            },
            .string_literal => {
                self.ptr += 1;
                switch (self.source[self.ptr]) {
                    0 => {
                        if (self.ptr != self.source.len) {
                            continue :state_machine .invalid;
                        } else {
                            result.tag = .invalid;
                        }
                    },
                    '\n' => result.tag = .invalid,
                    '"' => self.ptr += 1,
                    '\\' => continue :state_machine .string_literal_backslash,
                    0x01...0x09, 0x0b...0x1f, 0x7f => {
                        continue :state_machine .invalid;
                    },
                    else => continue :state_machine .string_literal,
                }
            },
            .string_literal_backslash => {
                self.ptr += 1;
                switch (self.source[self.ptr]) {
                    0, '\n' => result.tag = .invalid,
                    else => continue :state_machine .string_literal,
                }
            },
            .comment => {},
            .invalid => {
                std.debug.print("INVALID: position: {d}[{d}], data: {d}\n", .{ self.ptr, self.source.len, self.source[self.ptr..] });
            },
        }

        result.end = self.ptr;
        return result;
    }
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
    buffer[length_file] = 0;

    const data: [:0]const u8 = buffer[0..length_file :0];

    var field_current: u32 = 1;

    // TODO: Make this return a result object instead of an error along with info about the error
    // TODO: Allow arrays of arrays
    // TODO: Allow comments
    // TODO: Should there be a token buffer that we fill up and then parse that way? That might not work with buffered
    // input. Should we just load the entire file into memeory? I dont like that because i dont want there to be allocations here
    // But maybe that is fine in debug builds? If I were to do it i would do it in read_data. Just fill in a buffer of
    // 1024 tokens. Usually that should cover most files.
    //
    var tokenizer: Tokenizer = .init(data);

    var next_token: Token = undefined;

    // next_token = tokenizer.next();
    // var i: u32 = 0;
    // std.debug.print("TOKENS: {s}\n", .{file_path});
    // while (next_token.tag != .invalid and next_token.tag != .eof) {
    //     std.debug.print("\t{d}. {s}: {s}\n", .{ i, @tagName(next_token.tag), data[next_token.start..next_token.end] });
    //     next_token = tokenizer.next();
    //     i += 1;
    // }
    // tokenizer.ptr = 0;

    const result: ?LoadError = blk: {
        { // NOTE: Parse header
            next_token = tokenizer.next();
            assert(next_token.tag == .@"@");

            next_token = tokenizer.next();
            assert(next_token.tag == .def);

            next_token = tokenizer.next();
            if (next_token.tag != .indentifier and !std.mem.eql(u8, data[next_token.start..next_token.end], struct_name)) {
                break :blk LoadError.invalid_fsd_invalid_file_type;
            }

            next_token = tokenizer.next();
            if (next_token.tag != .number_literal and
                std.fmt.parseInt(u4, data[next_token.start..next_token.end], 10) catch {
                    break :blk LoadError.invalid_fsd_version;
                } != T.version.major)
            {
                break :blk LoadError.fsd_major_version_mismatch;
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@":");

            next_token = tokenizer.next();
            if (next_token.tag != .number_literal and
                std.fmt.parseInt(u12, data[next_token.start..next_token.end], 10) catch {
                    break :blk LoadError.invalid_fsd_version;
                } != T.version.minor)
            {
                break :blk LoadError.fsd_minor_version_mismatch;
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@":");

            next_token = tokenizer.next();
            if (next_token.tag != .number_literal and
                std.fmt.parseInt(u16, data[next_token.start..next_token.end], 10) catch {
                    break :blk LoadError.invalid_fsd_version;
                } != T.version.minor)
            {
                break :blk LoadError.fsd_patch_version_mismatch;
            }
        }

        // NOTE: Parse statements
        inline for (0..out_fields.len - 1) |_| {
            next_token = tokenizer.next();
            assert(next_token.tag == .@"@");

            next_token = tokenizer.next();
            if (!std.mem.eql(u8, out_fields[field_current].name, data[next_token.start..next_token.end])) {
                break :blk LoadError.invalid_fsd_invalid_field_name;
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@":");

            next_token = tokenizer.next();
            switch (out_fields[field_current].dtype) {
                .base => |b| {
                    if (b != next_token.base_type()) {
                        break :blk LoadError.invalid_fsd_incompatable_type;
                    }
                },
                .array => |*arr_info| {
                    next_token = tokenizer.next();
                    assert(next_token.tag == .@"[");

                    next_token = tokenizer.next();
                    if (next_token.tag != .number_literal) {
                        break :blk LoadError.invalid_fsd_array_must_contain_length;
                    }

                    const len = std.fmt.parseUnsigned(u32, data[next_token.start..next_token.end], 10) catch {
                        break :blk LoadError.invalid_fsd_invalid_integer;
                    };

                    if (len > arr_info.len) {
                        break :blk LoadError.invalid_fsd_array_too_long;
                    }
                    arr_info.parsed_len = len;

                    next_token = tokenizer.next();
                    assert(next_token.tag == .@"]");

                    next_token = tokenizer.next();
                    if (arr_info.base != next_token.base_type()) {
                        break :blk LoadError.invalid_fsd_array_child_type_mismatch;
                    }
                },
                .@"struct" => std.debug.panic("NOT IMPLEMENTED", .{}),
                .texture => std.debug.panic("NOT IMPLEMENTED", .{}),
                .@"enum" => std.debug.panic("NOT IMPLEMENTED", .{}),
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@"=");

            next_token = tokenizer.next();
            switch (out_fields[field_current].dtype) {
                .base => |b| {
                    switch (b) {
                        .vec2s, .vec3s, .vec4s => {
                            assert(next_token.tag == .@"[");
                            const vector: [*]f32 = @ptrCast(@alignCast(out_fields[field_current].data.?));
                            var pos: usize = 0;
                            for (0..4) |_| {
                                next_token = tokenizer.next();
                                assert(next_token.tag == .number_literal);
                                vector[pos] = std.fmt.parseFloat(f32, data[next_token.start..next_token.end]) catch {
                                    return LoadError.invalid_fsd_invalid_float;
                                };
                                next_token = tokenizer.next();
                                if (next_token.tag == .@"]") {
                                    break;
                                }
                                assert(next_token.tag == .@",");
                                pos += 1;
                            }
                            // NOTE: If you provide more numbers than 4 this assert will get triggered
                            assert(next_token.tag == .@"]");
                        },
                        else => {
                            assert(next_token.tag == .number_literal);
                            try parse_number_literal(b, data[next_token.start..next_token.end], out_fields[field_current].data.?);
                        },
                    }
                },
                .array => unreachable,
                else => {},
            }

            field_current += 1;
        }

        break :blk null;
    };

    next_token = tokenizer.next();
    assert(next_token.tag == .eof);

    if (result) |err| {
        std.debug.print(
            "Error: {s} at field: {d}\n",
            .{ @errorName(err), field_current },
        );
    }

    // TODO(adi): write binary format to disc here
}

fn parse_number_literal(base_type: BaseType, noalias payload: []const u8, noalias out_data: *anyopaque) LoadError!void {
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
            unreachable;
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
    for (0..iterations) |_| {
        try load(.material, "test.fsd", &material);
    }
    const end = start.read() / iterations;
    std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});

    std.debug.print("Material: {any}\n", .{material});
}
