pub const log = @import("log.zig");
pub const defines = @import("defines.zig");

pub const MergeEnums = comptime_funcs.MergeEnums;
pub const Distinct = comptime_funcs.Distinct;
pub const StaticArrayList = static_array_list.StaticArrayList;

pub fn not_implemented(comptime msg: []const u8) void {
    @compileError("NOT IMPLEMENTED: " ++ msg);
}

test {
    testing.refAllDeclsRecursive(@This());
}

const std = @import("std");
const testing = std.testing;
const comptime_funcs = @import("comptime.zig");
const static_array_list = @import("containers/static_array_list.zig");
