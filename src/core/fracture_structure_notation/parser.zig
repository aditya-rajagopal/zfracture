// TODO: Can this have constants that can be used
const MAX_STATES = 512;
pub const FSDParser = @This();

states: [MAX_STATES]States,
state_ptr: u32,
initialized: u8,
line_number: u32,
column_number: u32,
allocator: std.mem.Allocator,

pub const States = union(enum(u8)) {
    read_data,
    read_header,
    expect_struct_type,
    expect_version,
    read_statement,
    read_field,
    read_type,
    assert_equal,
    read_value,
    read_till: u8,
    end_parser,
};

pub const Result = enum(u8) {
    success,
    out_of_memory,
    invalid_fsd_incomplete,
    @"invalid_fsd_expected_@_at_start",
    invalid_fsd_missing_def,
    invalid_fsd_required_header,
    invalid_fsd_invalid_file_type,
    invalid_fsd_version,
    invalid_fsd_invalid_field_name,
    @"invalid_fsd_missing_=",
    @"invalid_fsd_missing_:",
    invalid_fsd_incompatable_type,
    @"invalid_fsd_missing_{",
    invalid_fsd_invalid_float,
    invalid_fsd_invalid_integer,
    invalid_fsd_insufficient_array_elements,
    invalid_fsd_string_too_long,
    @"invalid_fsd_invalid_sting_missing_\"",
};

pub fn init(self: *FSDParser, allocator: std.mem.Allocator) !void {
    self.state_ptr = 0;
    self.initialized = 1;
    self.line_number = 0;
    self.column_number = 0;
    self.allocator = allocator;
}

pub fn reset(self: *FSDParser) void {
    self.state_ptr = 0;
    self.initialized = 1;
    self.line_number = 0;
    self.column_number = 0;
}

const Field = struct {
    name: []const u8,
    dtype: DataType,
    data: *anyopaque,
    // extra_data: ?*anyopaque = null,
};

pub fn load_fsd(
    self: *FSDParser,
    comptime file_type: DefinitionTypes,
    out_data: *file_type.get_struct(),
    file_name: []const u8,
) !Result {
    assert(self.initialized > 0);

    const file = try std.fs.cwd().openFile(file_name, .{});
    const reader = file.reader();
    defer file.close();

    const T = file_type.get_struct();
    const type_info = @typeInfo(T);
    comptime assert(type_info == .@"struct");
    const struct_info = type_info.@"struct";
    inline for (struct_info.fields) |field| {
        comptime assert(field.default_value != null);
    }

    out_data.* = .{};

    self.push(.end_parser);

    var fields: [struct_info.fields.len - 1]Field = undefined;
    inline for (struct_info.fields[1..], 0..) |field, i| {
        const field_type = field.type;
        const field_info = @typeInfo(field_type);

        const dtype = dtype: switch (field_info) {
            .bool => .{ .base = .bool },
            .int, .float => .{ .base = comptime std.meta.stringToEnum(BaseTypes, @typeName(field_type)).? },
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
                    .base = comptime std.meta.stringToEnum(BaseTypes, @typeName(array.child)).?,
                    .num_elements = array.len,
                } };
            },
            .pointer => |pointer| {
                comptime assert(pointer.size == .Slice);
                fields[i].name = field.name;
                fields[i].data = @ptrCast(&@field(out_data, field.name));
                if (pointer.child == u8) {
                    fields[i].dtype = .{ .string = .{ .max_len = undefined, .is_static = false, .is_const = pointer.is_const } };
                } else {
                    fields[i].dtype = .{ .dynamic_array = comptime std.meta.stringToEnum(BaseTypes, @typeName(pointer.child)).? };
                }
                self.push(.read_statement);
                continue;
            },
            inline else => @compileError("Invalid field type for struct.")
        };
        fields[i] = Field{ .name = field.name, .dtype = dtype, .data = @ptrCast(&@field(out_data, field.name)) };
        self.push(.read_statement);
    }

    self.push(.read_header);
    self.push(.read_data);

    var buffer: [4096]u8 = undefined;
    var data: []const u8 = undefined;
    data.len = 0;

    var index: usize = 0;
    var field_number: usize = 0;

    // TODO: while loop might be better here but this is cool. See if this needs to be replaced
    // TODO: Should this be in a seperate function?
    // TODO: Convert to loop with a max states limit. Prevent infinite loops somehow
    const result: Result = blk: switch (self.states[self.state_ptr - 1]) {
        .read_data => {
            var len: usize = 0;
            if (data.len == 0) {
                len = try reader.read(&buffer);
            } else {
                std.mem.copyForwards(u8, &buffer, data);
                len = try reader.read(buffer[data.len..]);
            }
            if (len == 0) {
                break :blk Result.invalid_fsd_incomplete;
            }
            len += data.len;
            data = buffer[0..len];
            self.pop();

            continue :blk self.states[self.state_ptr - 1];
        },
        .read_header => {
            assert(data.len >= 5);
            if (data[0] != '@') {
                break :blk Result.@"invalid_fsd_expected_@_at_start";
            }

            const def: [4]u8 = .{ 'd', 'e', 'f', ' ' };

            if (@as(u32, @bitCast(data[1..5].*)) != @as(u32, @bitCast(def))) {
                break :blk Result.invalid_fsd_missing_def;
            }
            data = data[5..];
            self.column_number = 4;
            self.pop();
            self.push(.expect_version);
            self.push(.{ .read_till = '\n' });
            self.push(.expect_struct_type);
            self.push(.{ .read_till = ' ' });
            continue :blk self.states[self.state_ptr - 1];
        },
        .expect_struct_type => {
            if (!std.mem.eql(u8, data[0..index], @tagName(file_type))) {
                break :blk Result.invalid_fsd_invalid_file_type;
            }
            data = data[index + 1 ..];
            self.column_number += @truncate(index + 1);
            index = 0;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .expect_version => {
            // TODO: Instead of storing the version in the outdata outdata default should have a version that needs
            // to match with the version in the file atleast till the minor level.
            var i: usize = 0;
            while (i < index) : (i += 1) {
                if (data[i] == '.') {
                    out_data.version.major = std.fmt.parseInt(u4, data[0..i], 10) catch {
                        break :blk Result.invalid_fsd_version;
                    };

                    break;
                }
            } else {
                break :blk Result.invalid_fsd_version;
            }
            data = data[i + 1 ..];
            index -= i + 1;
            self.column_number += @truncate(i + 1);
            i = 0;
            while (i < index) : (i += 1) {
                if (data[i] == '.') {
                    out_data.version.minor = std.fmt.parseInt(u12, data[0..i], 10) catch {
                        break :blk Result.invalid_fsd_version;
                    };
                    break;
                }
            } else {
                break :blk Result.invalid_fsd_version;
            }

            index -= i + 1;
            data = data[i + 1 ..];
            self.column_number += @truncate(i + 1);
            out_data.version.patch = std.fmt.parseInt(u16, data[0 .. index - 1], 10) catch {
                break :blk Result.invalid_fsd_version;
            };
            data = data[index + 1 ..];
            index = 0;
            self.line_number += 1;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_till => |delimiter| {
            while (index < data.len) : (index += 1) {
                if (data[index] == delimiter) {
                    self.pop();
                    continue :blk self.states[self.state_ptr - 1];
                }
            }
            self.push(.read_data);
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_statement => {
            if (data.len == 0) {
                self.push(.read_data);
                continue :blk self.states[self.state_ptr - 1];
            }
            if (data[0] != '@') {
                break :blk Result.@"invalid_fsd_expected_@_at_start";
            }
            data = data[1..];
            self.pop();
            self.push(.read_value);
            self.push(.{ .read_till = '\n' });
            self.push(.assert_equal);
            self.push(.{ .read_till = ' ' });
            self.push(.read_type);
            self.push(.{ .read_till = ' ' });
            self.push(.read_field);
            self.push(.{ .read_till = ' ' });
            continue :blk self.states[self.state_ptr - 1];
        },
        .assert_equal => {
            assert(index == 1);
            if (data[0] != '=') {
                break :blk Result.@"invalid_fsd_missing_=";
            }
            data = data[2..];
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_field => {
            assert(index > 2);
            if (!std.mem.eql(u8, fields[field_number].name, data[0 .. index - 1])) {
                break :blk Result.invalid_fsd_invalid_field_name;
            }

            if (data[index - 1] != ':') {
                break :blk Result.@"invalid_fsd_missing_:";
            }
            data = data[index + 1 ..];
            self.column_number += @truncate(index + 1);
            index = 0;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_type => {
            switch (fields[field_number].dtype) {
                .base => |b| {
                    if (!std.mem.eql(u8, @tagName(b), data[0..index])) {
                        break :blk Result.invalid_fsd_incompatable_type;
                    }
                },
                .string => |*str_info| str_blk: {
                    if (std.mem.eql(u8, "string", data[0..index])) {
                        break :str_blk;
                    }
                    if (data[0] == '[') {
                        var pos: usize = 1;
                        self.column_number += 1;
                        while (pos < index) : (pos += 1) {
                            if (data[pos] == ']') {
                                if (pos == 1) {} else {
                                    const len = std.fmt.parseUnsigned(usize, data[1..pos], 10) catch {
                                        break :blk Result.invalid_fsd_invalid_integer;
                                    };
                                    if (len > str_info.max_len) {
                                        break :blk Result.invalid_fsd_string_too_long;
                                    }
                                    str_info.max_len = @truncate(len);
                                }
                                self.column_number += @truncate(pos - 1);
                                if (!std.mem.eql(u8, "u8", data[pos + 1 .. index])) {
                                    break;
                                }
                                self.column_number += 2;
                                break :str_blk;
                            }
                        }
                    }
                    break :blk Result.invalid_fsd_incompatable_type;
                },
                else => unreachable,
            }
            data = data[index + 1 ..];
            self.column_number += @truncate(index + 1);
            index = 0;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_value => {
            switch (fields[field_number].dtype) {
                .base => |b| {
                    switch (b) {
                        .u8 => {
                            const ptr: *u8 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseUnsigned(u8, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .u16 => {
                            const ptr: *u16 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseUnsigned(u16, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .u32 => {
                            const ptr: *u32 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseUnsigned(u32, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .u64 => {
                            const ptr: *u64 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseUnsigned(u64, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .i8 => {
                            const ptr: *i8 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseInt(i8, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .i16 => {
                            const ptr: *i16 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseInt(i16, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .i32 => {
                            const ptr: *i32 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseInt(i32, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .i64 => {
                            const ptr: *i64 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseInt(i64, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_invalid_integer;
                            };
                        },
                        .f32 => {
                            const ptr: *f32 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseFloat(f32, data[0 .. index - 1]) catch {
                                break :blk Result.invalid_fsd_invalid_float;
                            };
                        },
                        .f64 => {
                            const ptr: *f64 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.* = std.fmt.parseFloat(f64, data[0 .. index - 1]) catch {
                                break :blk Result.invalid_fsd_invalid_float;
                            };
                        },
                        .vec2s, .vec3s, .vec4s => |t| {
                            // TODO: This is not robust. Can make this faster.
                            if (data[0] != '{') {
                                break :blk Result.@"invalid_fsd_missing_{";
                            }
                            var start: usize = 1;
                            while (data[start] == ' ') {
                                start += 1;
                            }

                            const ptr: [*]f32 = @ptrCast(@alignCast(fields[field_number].data));

                            var pos: usize = start;
                            var num: usize = 0;
                            const max_num: usize = switch (t) {
                                .vec2s => 2,
                                .vec3s => 3,
                                .vec4s => 4,
                                else => unreachable,
                            };

                            while (num < max_num and pos < index - 1) {
                                if (data[pos] == ',') {
                                    ptr[num] = std.fmt.parseFloat(f32, data[start..pos]) catch {
                                        break :blk Result.invalid_fsd_invalid_float;
                                    };

                                    pos += 1;
                                    while (data[pos] == ' ') {
                                        pos += 1;
                                    }
                                    num += 1;
                                    start = pos;
                                    continue;
                                }
                                if (data[pos] == '}') {
                                    var local_pos: usize = pos;
                                    while (data[pos - 1] == ' ') {
                                        local_pos -= 1;
                                    }
                                    ptr[num] = std.fmt.parseFloat(f32, data[start..local_pos]) catch {
                                        break :blk Result.invalid_fsd_invalid_float;
                                    };
                                    num += 1;
                                    break;
                                }
                                pos += 1;
                            }

                            if (num != max_num) {
                                break :blk Result.invalid_fsd_insufficient_array_elements;
                            }

                            if (data[pos] != '}') {
                                break :blk Result.@"invalid_fsd_missing_{";
                            }
                        },
                        else => unreachable
                    }
                },
                .string => |str_info| {
                    if (data[0] != '"') {
                        break :blk Result.@"invalid_fsd_invalid_sting_missing_\"";
                    }
                    var pos: usize = 1;
                    while (pos < index - 2) : (pos += 1) {
                        if (data[pos] == '"') {
                            break;
                        }
                        // TODO: Deal with " in string
                        // if (data[pos] == '\\' and pos < index - 3 and data[pos + 1] == '"') {
                        //     pos += 1;
                        // }
                    }
                    if (data[pos] != '"') {
                        break :blk Result.@"invalid_fsd_invalid_sting_missing_\"";
                    }
                    const string = data[1..pos];

                    if (str_info.is_static) {
                        if (string.len > str_info.max_len) {
                            break :blk Result.invalid_fsd_string_too_long;
                        }
                        const ptr: [*]u8 = @ptrCast(@alignCast(fields[field_number].data));
                        @memset(ptr[string.len..str_info.max_len], 0);
                        @memcpy(ptr[0..string.len], string);
                    } else {
                        // TODO: Should this come from a static allocation? Or should there be no dynamic allocations
                        // at all
                        const out_string = self.allocator.dupe(u8, string) catch {
                            break :blk Result.out_of_memory;
                        };
                        if (str_info.is_const) {
                            const ptr: *[]const u8 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.ptr = out_string.ptr;
                            ptr.len = out_string.len;
                        } else {
                            const ptr: *[]u8 = @ptrCast(@alignCast(fields[field_number].data));
                            ptr.ptr = out_string.ptr;
                            ptr.len = out_string.len;
                        }
                    }
                },
                else => unreachable,
            }
            data = data[index + 1 ..];
            self.column_number = 0;
            self.line_number += 1;
            index = 0;
            field_number += 1;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .end_parser => {
            break :blk .success;
        },
    };

    return result;
}

inline fn push(self: *FSDParser, state: States) void {
    assert(self.state_ptr < MAX_STATES);
    self.states[self.state_ptr] = state;
    self.state_ptr += 1;
}

inline fn pop(self: *FSDParser) void {
    assert(self.state_ptr > 0);
    self.state_ptr -= 1;
}

pub fn parse_custom(comptime expected_struct_type: type) !expected_struct_type {
    expected_struct_type{};
}

pub const DefinitionTypes = enum(u8) {
    material,
    custom,

    pub fn get_struct(comptime self: DefinitionTypes) type {
        return switch (self) {
            .material => MaterialConfig,
            inline else => @compileError("Unsupported type. Use parse_custom"),
        };
    }
};

pub const MaterialConfig = struct {
    version: Version = .{},
    data: u8 = 0,
    data2: i8 = 0,
    data3: f32 = 0,
    data4: [3]f32 = [_]f32{ 0.0, 0.0, 0.0 },
    data5: [4]f32 = [_]f32{ 0.0, 0.0, 0.0, 0.0 },
    data6: [2]f32 = [_]f32{ 0.0, 0.0 },
    data7: [16]u8 = undefined,
};

pub const Version = packed struct(u32) {
    major: u4 = 0,
    minor: u12 = 0,
    patch: u16 = 0,
};

pub const BaseTypes = enum(u8) {
    u8,
    u16,
    u32,
    u64,
    i8,
    i16,
    i32,
    i64,
    f32,
    f64,
    bool,
    vec2s,
    vec3s,
    vec4s,
};

pub const DataType = union(enum(u8)) {
    Texture,
    base: BaseTypes,
    static_array: struct { base: BaseTypes, num_elements: u32 },
    dynamic_array: BaseTypes,
    string: struct { max_len: u32, is_static: bool, is_const: bool },
};

test FSDParser {
    var parser: FSDParser = undefined;
    try parser.init(std.testing.allocator);

    var material: MaterialConfig = undefined;
    var start = std.time.Timer.start() catch unreachable;
    const result = try parser.load_fsd(.material, &material, "test.fsd");
    const end = start.read();
    std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});
    std.debug.print("Resul: {s}\n", .{@tagName(result)});

    std.debug.print("Material: {any}\n", .{material});
    // std.testing.allocator.free(material.data7);
}

const std = @import("std");
const assert = std.debug.assert;
