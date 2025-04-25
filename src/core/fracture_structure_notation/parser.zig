const std = @import("std");
const assert = std.debug.assert;

const field = @import("field.zig");
const token = @import("tokenizer.zig");
const Tokenizer = token.Tokenizer;
const Token = token.Token;
const types = @import("types.zig");
const Definition = types.Definition;
const BaseType = types.BaseType;

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
    string_too_long,
} || std.fs.File.OpenError || std.fs.File.ReadError;

// NOTE: If the fsd file is larger than 16 pages use the alloc version of load
const MAX_BUFFER_PAGES = 16;
const MAX_BYTES = 4096 * MAX_BUFFER_PAGES;

threadlocal var buffer: [MAX_BYTES]u8 = undefined;

const DEBUG_TOKENS: bool = false;

// TODO: Change LoadError to be a union type that has some payload and this function returns a success code
// TODO: Allow arrays of arrays
// TODO: This needs a logger
pub fn parse_fsd(comptime s_type: Definition, noalias file_path: []const u8, noalias out_data: *s_type.get_type()) LoadError!void {
    const T: type = s_type.get_type();

    // TODO: Make a binary of the file if it does not exist. If the binary file does exist then make check if
    // the binary needs to be regenerated. If it does regenerate it, else just read the binary file.
    // In Release and Dist builds make this only read the bianry file and ignore the rest

    // TODO: Should this be reset alread? what happens in the case of failures
    out_data.* = .{};
    // TODO: Figure out a way to capture enum fields as strings
    const fields = comptime field.get_fields(T);
    const out_fields = field.fill_pointers(T, &fields, out_data);

    const struct_name = comptime s_type.get_struct_name();
    // var field_buffer: [32][]field.Field = undefined;
    // var field_stack = std.ArrayListUnmanaged([]field.Field).initBuffer(&field_buffer);

    // const root_struct = out_fields[0].dtype.@"struct";
    // const root_fields = out_fields[root_struct.fields_start..root_struct.fields_end];
    // field_stack.appendAssumeCapacity(root_fields);

    const file = try std.fs.cwd().openFile(file_path, .{});
    const reader = file.reader();
    const length_file = try reader.read(&buffer);
    defer file.close();

    assert(length_file < MAX_BYTES);
    buffer[length_file] = 0;

    const data: [:0]const u8 = buffer[0..length_file :0];

    var tokenizer: Tokenizer = .init(data);
    var next_token: Token = undefined;

    if (comptime DEBUG_TOKENS) {
        next_token = tokenizer.next();
        var i: u32 = 0;
        std.debug.print("TOKENS: {s}\n", .{file_path});
        while (next_token.tag != .invalid and next_token.tag != .eof) {
            std.debug.print("\t{d}. {s}: {s}\n", .{ i, @tagName(next_token.tag), data[next_token.start..next_token.end] });
            next_token = tokenizer.next();
            i += 1;
        }
        tokenizer.ptr = 0;
    }

    // TODO: Tokenize the entire thing first?
    // TODO: Convert asserts into errors and skip parsing. Dont crash
    const result: ?LoadError = blk: {
        { // NOTE: Parse header
            next_token = tokenizer.next();
            assert(next_token.tag == .@"@");

            next_token = tokenizer.next();
            assert(next_token.tag == .def);

            next_token = tokenizer.next();
            if (next_token.tag != .indentifier and
                !std.mem.eql(u8, data[next_token.start..next_token.end], struct_name))
            {
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
        inline for (1..fields.len) |field_current| {
            next_token = tokenizer.next();
            assert(next_token.tag == .@"@");

            next_token = tokenizer.next();
            // NOTE: check if the names of the fields are the same
            if (!std.mem.eql(u8, out_fields[field_current].name, data[next_token.start..next_token.end])) {
                break :blk LoadError.invalid_fsd_invalid_field_name;
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@":");

            next_token = tokenizer.next();
            // NOTE: Validate type
            switch (comptime fields[field_current].dtype) {
                .base => |b| {
                    if (b != next_token.base_type()) {
                        break :blk LoadError.invalid_fsd_incompatable_type;
                    }
                },
                .array => |arr_info| {
                    if (next_token.tag != .string) {
                        assert(next_token.tag == .@"[");
                        // NOTE: For now disabling numbers in the type of arrays.
                        // All lengths will be inferred from value. The value must fit into the type
                        next_token = tokenizer.next();
                        assert(next_token.tag == .@"]");

                        next_token = tokenizer.next();
                        if (arr_info.base != next_token.base_type()) {
                            break :blk LoadError.invalid_fsd_array_child_type_mismatch;
                        }
                    }
                },
                .@"struct" => std.debug.panic("NOT IMPLEMENTED", .{}),
                .texture => std.debug.panic("NOT IMPLEMENTED", .{}),
                .@"enum" => std.debug.panic("NOT IMPLEMENTED", .{}),
            }

            next_token = tokenizer.next();
            assert(next_token.tag == .@"=");

            next_token = tokenizer.next();
            switch (comptime fields[field_current].dtype) {
                .base => |b| {
                    switch (comptime b) {
                        .vec2s, .vec3s, .vec4s => |vec_type| {
                            // TODO: Move this into a different function
                            assert(next_token.tag == .@"[");
                            // NOTE: Assuming that in the type vec2s, vec3s, and vec4s are consecutive.
                            const size: u8 = @intFromEnum(vec_type) + 2 - @intFromEnum(BaseType.vec2s);
                            const vec_t = vec_type.get_type();
                            const vector: *vec_t = @ptrCast(@alignCast(out_fields[field_current].data.?));
                            for (0..size) |pos| {
                                if (next_token.tag != .@"]") {
                                    next_token = tokenizer.next();
                                    assert(next_token.tag == .number_literal);
                                    vector.vec[pos] = std.fmt.parseFloat(f32, data[next_token.start..next_token.end]) catch {
                                        break :blk LoadError.invalid_fsd_invalid_float;
                                    };
                                    next_token = tokenizer.next();
                                    assert(next_token.tag == .@"," or next_token.tag == .@"]");
                                } else {
                                    // NOTE: If there are less numbers in the array than the type supports then
                                    // the remaining values are filled with 0s
                                    vector.vec[pos] = 0.0;
                                }
                            }
                            // NOTE: If you provide more numbers than Needed
                            assert(next_token.tag == .@"]");
                        },
                        .bool => {
                            const ptr: *bool = @ptrCast(@alignCast(out_fields[field_current].data.?));
                            switch (next_token.tag) {
                                .true => ptr.* = true,
                                .false => ptr.* = false,
                                else => {
                                    // TODO: Continue
                                    break :blk LoadError.invalid_fsd_incompatable_type;
                                },
                            }
                        },
                        else => {
                            assert(next_token.tag == .number_literal);
                            try parse_number_literal(b, data[next_token.start..next_token.end], out_fields[field_current].data.?);
                        },
                    }
                },
                .array => |array_info| {
                    base: switch (comptime array_info.base) {
                        .vec2s, .vec3s, .vec4s => {
                            // TODO: ?
                            @panic("NOT IMPLEMENTED");
                        },
                        // .texture => continue :base .string,
                        .string => {
                            assert(next_token.tag == .string_literal);
                            const strlen: usize = fields[field_current].dtype.array.len;
                            const string_buffer: *[strlen]u8 = @ptrCast(@alignCast(out_fields[field_current].data.?));
                            // TODO: Deal with \" in strings
                            const parsed_strlen = next_token.end - next_token.start;
                            // NOTE: We keep 1 character for null termination
                            assert(parsed_strlen <= strlen - 1);
                            @memcpy(string_buffer[0..parsed_strlen], data[next_token.start..next_token.end]);
                            string_buffer[parsed_strlen] = 0;
                        },
                        inline else => |_type| {
                            if (comptime _type == .u8) {
                                if (next_token.tag == .string_literal) {
                                    continue :base .string;
                                }
                            }
                            assert(next_token.tag == .@"[");
                            var array: [*]_type.get_type() = @ptrCast(@alignCast(out_fields[field_current].data.?));
                            for (0..fields[field_current].dtype.array.len) |pos| {
                                next_token = tokenizer.next();
                                assert(next_token.tag == .number_literal);
                                try parse_number_literal(_type, data[next_token.start..next_token.end], @ptrCast(&array[pos]));
                                next_token = tokenizer.next();
                                if (next_token.tag == .@"]") {
                                    break;
                                }
                                assert(next_token.tag == .@",");
                            }
                            // NOTE: If you provide more numbers than parsed_len this assert will get triggered
                            assert(next_token.tag == .@"]");
                        }
                    }
                },
                else => @panic("NOT IMPLEMENTED"),
            }
        }

        next_token = tokenizer.next();
        assert(next_token.tag == .eof);

        break :blk null;
    };

    if (result) |err| {
        std.debug.print(
            "Error: {s}\n",
            .{@errorName(err)},
        );
    }
}

fn parse_number_literal(comptime base_type: BaseType, noalias payload: []const u8, noalias out_data: *anyopaque) LoadError!void {
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
        else => unreachable,
    }
}

test parse_fsd {
    var material: types.MaterialConfig = undefined;
    var start = std.time.Timer.start() catch unreachable;
    const iterations = 1;
    for (0..iterations) |_| {
        try parse_fsd(.material, "test.fsd", &material);
    }
    const end = start.read() / iterations;
    std.debug.print("Time: {s}\n", .{std.fmt.fmtDuration(end)});

    std.debug.print("Material: {any}\n", .{material});
}

// const math = @import("fr_math");

// test "load binary" {
//     std.debug.print("type: {s}\n", .{@typeName(math.Vec3)});
//     const fields = @typeInfo(math.Vec3).@"struct".fields;
//     inline for (fields) |f| {
//         std.debug.print("Type field: {s}: {s}\n", .{ f.name, @typeName(f.type) });
//     }
// }
