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
    invalid_fsd_incomplete,
    @"invalid_fsd_expected_@_at_start",
    invalid_fsd_required_header,
    invalid_fsd_invalid_file_type,
    invalid_fsd_version,
    invalid_fsd_invalid_field_name,
    @"invalid_fsd_missing_=",
    @"invalid_fsd_missing_:",
    invalid_fsd_incompatable_type,
};

pub fn init(self: *FSDParser, allocator: std.mem.Allocator) !void {
    self.state_ptr = 0;
    self.initialized = 1;
    self.line_number = 0;
    self.column_number = 0;
    self.allocator = allocator;
}

pub fn parse(self: *FSDParser, comptime file_type: DefinitionTypes, out_data: *file_type.get_struct(), file_name: []const u8) !Result {
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

    const Field = struct {
        name: []const u8,
        dtype: DataType,
        data: *anyopaque,
    };

    var fields: [struct_info.fields.len - 1]Field = undefined;
    inline for (struct_info.fields[1..], 0..) |field, i| {
        const field_type = field.type;
        const field_info = @typeInfo(field_type);
        std.debug.print("Field name: {s}", .{@typeName(field_type)});

        const dtype = switch (field_info) {
            .bool => .{ .base = .bool },
            .int, .float => .{ .base = comptime std.meta.stringToEnum(BaseTypes, @typeName(field_type)).? },
            .array => |array| .{ .static_array = .{
                .base = comptime std.meta.stringToEnum(BaseTypes, @typeName(array.child)).?,
                .num_elements = array.len,
            } },
            .pointer => |pointer| {
                comptime assert(pointer.size == .Slice);
                break .{ .dynamic_array = comptime std.meta.stringToEnum(BaseTypes, @typeName(pointer.child)).? };
            },
            inline else => @compileError("Invalid field type for struct.")
        };
        fields[i] = Field{ .name = field.name, .dtype = dtype, .data = @ptrCast(&@field(out_data, field.name)) };
        self.push(.read_statement);
    }
    std.debug.print("Fields: {any}\n", .{fields});

    self.push(.read_header);
    self.push(.read_data);

    var buffer: [4096]u8 = undefined;
    var data: []const u8 = undefined;
    data.len = 0;

    var index: usize = 0;
    var field_number: usize = 0;

    // TODO: while loop might be better here but this is cool. See if this needs to be replaced
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
                break :blk Result.invalid_fsd_required_header;
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
            std.debug.print("Data: {s}\n", .{data});
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
                else => unreachable,
            }
            data = data[index + 1 ..];
            self.column_number += @truncate(index + 1);
            index = 0;
            self.pop();
            continue :blk self.states[self.state_ptr - 1];
        },
        .read_value => {
            std.debug.print("value: \"{s}\"\n", .{data[0 .. index - 1]});
            switch (fields[field_number].dtype) {
                .base => |b| {
                    switch (b) {
                        .u8 => {
                            const ptr: *u8 = @ptrCast(fields[field_number].data);
                            ptr.* = std.fmt.parseInt(u8, data[0 .. index - 1], 10) catch {
                                break :blk Result.invalid_fsd_version;
                            };
                        },
                        else => unreachable
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

    std.debug.print("Result: {s}\n", .{@tagName(result)});

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
};

pub const DataType = union(enum(u8)) {
    Texture,
    base: BaseTypes,
    static_array: struct { num_elements: usize, base: BaseTypes },
    dynamic_array: struct { base: BaseTypes },
};

test FSDParser {
    var parser: FSDParser = undefined;
    try parser.init(std.testing.allocator);

    var material: MaterialConfig = undefined;
    _ = try parser.parse(.material, &material, "test.fsd");
    std.debug.print("Material: {any}\n", .{material});
}

const std = @import("std");
const assert = std.debug.assert;
