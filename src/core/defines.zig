pub const BytesRepr = union(enum) {
    B: f64,
    KB: f64,
    MB: f64,
    GB: f64,

    pub fn format(self: BytesRepr, comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
        return switch (self) {
            .B => |b| writer.print("{d:>7.0}B ", .{b}),
            .KB => |kb| writer.print("{d:>7.3}Kb", .{kb}),
            .MB => |mb| writer.print("{d:>7.3}Mb", .{mb}),
            .GB => |gb| writer.print("{d:>7.3}Gb", .{gb}),
        };
    }
};

pub const KB: u64 = 1024;
pub const MB: u64 = 1024 * 1024;
pub const GB: u64 = 1024 * 1024 * 1024;

pub fn parse_bytes(bytes: u64) BytesRepr {
    switch (bytes) {
        0...1024 => return .{ .B = @floatFromInt(bytes) },
        KB + 1...MB => {
            const as_float: f64 = @floatFromInt(bytes);
            const value = as_float / @as(f64, @floatFromInt(KB));
            return .{ .KB = value };
        },
        MB + 1...GB => {
            const as_float: f64 = @floatFromInt(bytes);
            const value = as_float / @as(f64, @floatFromInt(MB));
            return .{ .MB = value };
        },
        else => {
            const as_float: f64 = @floatFromInt(bytes);
            const value = as_float / @as(f64, @floatFromInt(GB));
            return .{ .GB = value };
        },
    }
}

test parse_bytes {
    const bytes: u64 = 1024;
    const kb: u64 = KB * 2;
    const mb: u64 = 2 * MB;
    const gb: u64 = 2 * GB;

    var out = parse_bytes(bytes);
    try testing.expectEqual(out, BytesRepr{ .B = 1024 });
    out = parse_bytes(kb);
    try testing.expectEqual(out, BytesRepr{ .KB = 2 });
    out = parse_bytes(mb);
    try testing.expectEqual(out, BytesRepr{ .MB = 2 });
    out = parse_bytes(gb);
    try testing.expectEqual(out, BytesRepr{ .GB = 2 });
}

const std = @import("std");
const testing = std.testing;
