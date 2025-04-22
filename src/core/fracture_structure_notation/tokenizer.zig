const std = @import("std");
const types = @import("types.zig");

const BaseType = types.BaseType;

pub const Token = struct {
    /// The type of token
    tag: Tag,
    /// The start location in the source code
    start: u16,
    /// The end location in the source code
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
        .{ "string", .string },
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
        string = 20,
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

    /// Convert the token type to an equivalent BaseType if it exists else null
    pub fn base_type(self: Token) ?BaseType {
        const int: u8 = @intFromEnum(self.tag);
        if (int <= @intFromEnum(Tag.vec4s)) {
            return @enumFromInt(int);
        } else {
            return null;
        }
    }

    /// Get the equivalent type for a given string keyword
    /// TODO: consider std.meta.stringToEnum(comptime T: type, str: []const u8)
    pub fn getKeyword(bytes: []const u8) ?Tag {
        return keywords.get(bytes);
    }
};

pub const Tokenizer = struct {
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
                    '/' => {
                        self.ptr += 1;
                        if (self.source[self.ptr] != '/') {
                            continue :state_machine .invalid;
                        }
                        continue :state_machine .comment;
                    },
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
                    '"' => self.ptr += 1, // Exit condition
                    '\n' => result.tag = .invalid,
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
            .comment => {
                self.ptr += 1;
                switch (self.source[self.ptr]) {
                    '\n' => {
                        self.ptr += 1;
                        result.start = self.ptr;
                        continue :state_machine .start;
                    },
                    0 => {
                        continue :state_machine .start;
                    },
                    else => continue :state_machine .comment,
                }
            },
            .invalid => {
                std.debug.print("INVALID: position: {d}[{d}], data: {d}\n", .{ self.ptr, self.source.len, self.source[self.ptr..] });
            },
        }

        result.end = self.ptr;
        return result;
    }
};
