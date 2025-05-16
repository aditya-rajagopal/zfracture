//! Memory module
//!
//! This module provides a TrackingAllocator type that allows you to track total allocations and deallocations of the backing allocator.
//! This allocator returns is used to return allocators using the backing allocators with a scope that taggs all
//! allocations and deallocations to the given tag.
//!
//! In release modes the memory stats are not tracked and this essentially becomes a thin wrapper around
//! the backing allocator.
//!
//! # Examples
//!
//! ```zig
//! const std = @import("std");
//! const assert = std.debug.assert;
//! const TrackingAllocator = @import("fr_core").memory.TrackingAllocator;
//! const log = @import("fr_core").log;
//!
//! const MemoryTag = enum(u8) {
//!     untagged = 0,
//!     testing1,
//!     testing2,
//! };
//!
//! const TestAllocator = TrackingAllocator(.testing, EngineMemoryTag, true);
//!
//! pub fn main() !void {
//!     var config: log.LogConfig = undefined;
//!     var test_alloc: TestAllocator = TestAllocator{};
//!     test_alloc.init(std.testing.allocator, &config);
//!     defer test_alloc.deinit();
//!
//!     const untagged_alloc = test_alloc.get_type_allocator(.untagged);
//!     const data = try untagged_alloc.create(i32);
//!     assert(test_alloc.query_stats().current_total_memory == 4);
//!     assert(test_alloc.query_stats().current_memory[0] == 4);
//!     untagged_alloc.destroy(data);
//!     assert(test_alloc.query_stats().current_total_memory == 0);
//!
//!     const testing1_alloc = test_alloc.get_type_allocator(.testing1);
//!     const testing2_alloc = test_alloc.get_type_allocator(.testing2);
//!
//!     const data2 = try testing1_alloc.create(i32);
//!     const data3 = try testing2_alloc.create(i32);
//!     assert(test_alloc.query_stats().current_total_memory == 8);
//!     assert(test_alloc.query_stats().current_memory[0] == 0);
//!     assert(test_alloc.query_stats().current_memory[1] == 4);
//!     assert(test_alloc.query_stats().current_memory[2] == 4);
//!     testing1_alloc.destroy(data2);
//!     assert(test_alloc.query_stats().current_total_memory == 4);
//!     assert(test_alloc.query_stats().current_memory[0] == 0);
//!     assert(test_alloc.query_stats().current_memory[1] == 0);
//!     testing2_alloc.destroy(data3);
//!     assert(test_alloc.query_stats().current_total_memory == 0);
//!
//!     test_alloc.print_memory_stats();
//! }
//!
pub fn TrackingAllocator(
    /// Just a tag stored in the allocator to differentiate this struct from other structs constructed with this function
    comptime alloc_tag: @Type(.enum_literal),
    /// The tags that are tracked by this allocator and allocators provided
    comptime MemoryTag: type,
    /// Setting this to true will allow logging
    comptime enable_log: bool,
    //TODO: Add verbositiy level. Maybe we want to track every allocation and deallocation with a log
) type {
    if (comptime @typeInfo(MemoryTag) != .@"enum") {
        @compileError("Memory Tag must be an enum");
    }
    const memory_tag_len = switch (builtin.mode) {
        .Debug => std.enums.directEnumArrayLen(MemoryTag, 256),
        else => 0,
    };

    const MemoryLog = if (enable_log) log.ScopedLogger(log.default_log, alloc_tag, log.default_level) else void;

    return struct {
        backing_allocator: Allocator = undefined,
        type_structs: TypeStructs = undefined,
        type_allocators: TypeAllocators = undefined,
        memory_stats: MemoryStats = std.mem.zeroes(MemoryStats),
        log: MemoryLog = undefined,

        const struct_tag = alloc_tag;
        const TypeStructs = [memory_tag_len * num_bytes_type_allocator]u8;
        const TypeAllocators = [memory_tag_len]Allocator;

        const AllocatorTypes: [memory_tag_len]type = blk: {
            if (memory_tag_len != 0) {
                var alloc_types: [memory_tag_len]type = undefined;
                for (@typeInfo(MemoryTag).@"enum".fields) |field| {
                    const tag: MemoryTag = @enumFromInt(field.value);
                    alloc_types[field.value] = TypedAllocator(tag);
                }
                break :blk alloc_types;
            }
        };
        const num_bytes_type_allocator = switch (builtin.mode) {
            .Debug => @sizeOf(AllocatorTypes[0]),
            else => 0,
        };

        const Self = @This();

        pub fn init(self: *Self, allocator: Allocator, log_config: *log.LogConfig) void {
            self.backing_allocator = allocator;
            if (comptime memory_tag_len != 0) {
                inline for (AllocatorTypes, 0..) |t, i| {
                    const start = i * num_bytes_type_allocator;
                    const end = start + num_bytes_type_allocator;
                    const temp: *t = @as(*t, @ptrCast(@alignCast(self.type_structs[start..end].ptr)));
                    temp.* = t.init(allocator, &self.memory_stats);
                }
                inline for (0..memory_tag_len) |i| {
                    const start = i * num_bytes_type_allocator;
                    const end = start + num_bytes_type_allocator;
                    self.type_allocators[i] = @as(*AllocatorTypes[i], @ptrCast(@alignCast(self.type_structs[start..end].ptr))).allocator();
                }
                self.memory_stats = std.mem.zeroes(MemoryStats);
            }
            if (comptime enable_log) {
                self.log = MemoryLog.init(log_config);
            }
        }

        pub fn deinit(self: *Self) void {
            self.backing_allocator = undefined;
        }

        pub inline fn get_type_allocator(self: *const Self, comptime tag: MemoryTag) Allocator {
            if (comptime memory_tag_len != 0) {
                return self.type_allocators[@intFromEnum(tag)];
            } else {
                return self.backing_allocator;
            }
        }

        pub fn reset_stats(self: *Self) void {
            if (comptime memory_tag_len != 0) {
                self.memory_stats.current_total_memory = 0;
                self.memory_stats.current_memory = [_]u64{0} ** memory_tag_len;
                self.memory_stats.num_allocations = 0;
            }
        }

        pub fn query_stats(self: *const Self) *const MemoryStats {
            return &self.memory_stats;
        }

        pub fn print_memory_stats(self: *Self) void {
            if (comptime memory_tag_len != 0) {
                if (enable_log) {
                    self.log.debug("Memory Subsystem[{s}]: ", .{@tagName(struct_tag)});
                    // magic padding
                    const padding = 8 + 16 + 2 + 9 + 2 + 9 + 1;
                    self.log.debug("=" ** padding, .{});
                    self.log.debug("|\t{s:<16}| {s:^9} | {s:^9}|", .{ "MemoryTag", "Current", "Peak" });
                    self.log.debug("=" ** padding, .{});
                    inline for (@typeInfo(MemoryTag).@"enum".fields) |field| {
                        const curr_bytes = defines.BytesRepr.from_bytes(self.memory_stats.current_memory[field.value]);
                        const peak_bytes = defines.BytesRepr.from_bytes(self.memory_stats.peak_memory[field.value]);
                        self.log.debug("|\t{s:<16}| {s} |{s} |", .{ field.name, curr_bytes, peak_bytes });
                    }
                    const curr_bytes = defines.BytesRepr.from_bytes(self.memory_stats.current_total_memory);
                    const peak_bytes = defines.BytesRepr.from_bytes(self.memory_stats.peak_total_memory);
                    self.log.debug("=" ** padding, .{});
                    self.log.debug("|\t{s:<16}| {s} |{s} |", .{ "TOTAL", curr_bytes, peak_bytes });
                    self.log.debug("=" ** padding, .{});
                    self.log.debug("|\t{s:<16}| {d} |", .{ "TOTAL ALLOCATION", self.memory_stats.num_allocations });
                    self.log.debug("=" ** padding, .{});
                    self.log.debug("", .{});
                }
            }
        }

        pub const MemoryStats = switch (builtin.mode) {
            .Debug => struct {
                current_total_memory: u64,
                current_memory: [memory_tag_len]u64,
                peak_total_memory: u64,
                peak_memory: [memory_tag_len]u64,
                num_allocations: u64,
                max_allocations: u64,
            },
            else => struct {},
        };

        /// An allocator that wraps the backing allocator calls and tracks allocations and deallocations
        /// using the given tag.
        pub fn TypedAllocator(comptime tag: MemoryTag) type {
            return struct {
                backing_allocator: Allocator,
                stats: *MemoryStats,

                const TAlloc = @This();

                pub fn init(parent_allocator: Allocator, stats_ref: *MemoryStats) TAlloc {
                    return TAlloc{
                        .backing_allocator = parent_allocator,
                        .stats = stats_ref,
                    };
                }

                pub fn allocator(self: *TAlloc) Allocator {
                    return Allocator{
                        .ptr = self,
                        .vtable = &.{
                            .alloc = alloc,
                            .resize = resize,
                            .remap = remap,
                            .free = free,
                        },
                    };
                }

                pub fn alloc(ctx: *anyopaque, len: usize, ptr_align: std.mem.Alignment, ret_addr: usize) ?[*]u8 {
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
                    self.stats.current_memory[@intFromEnum(tag)] += len;
                    self.stats.current_total_memory += len;
                    self.stats.num_allocations += 1;
                    if (self.stats.current_total_memory > self.stats.peak_total_memory) {
                        self.stats.peak_total_memory = self.stats.current_total_memory;
                    }
                    if (self.stats.current_memory[@intFromEnum(tag)] > self.stats.peak_memory[@intFromEnum(tag)]) {
                        self.stats.peak_memory[@intFromEnum(tag)] = self.stats.current_memory[@intFromEnum(tag)];
                    }
                    return self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);
                }

                pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, new_len: usize, ret_addr: usize) bool {
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
                    if (new_len > buf.len) {
                        self.stats.current_memory[@intFromEnum(tag)] += new_len - buf.len;
                        self.stats.current_total_memory += new_len - buf.len;
                    } else {
                        self.stats.current_memory[@intFromEnum(tag)] -= buf.len - new_len;
                        self.stats.current_total_memory -= buf.len - new_len;
                    }
                    if (self.stats.current_total_memory > self.stats.peak_total_memory) {
                        self.stats.peak_total_memory = self.stats.current_total_memory;
                    }
                    if (self.stats.current_memory[@intFromEnum(tag)] > self.stats.peak_memory[@intFromEnum(tag)]) {
                        self.stats.peak_memory[@intFromEnum(tag)] = self.stats.current_memory[@intFromEnum(tag)];
                    }
                    return self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
                }

                pub fn remap(
                    ctx: *anyopaque,
                    memory: []u8,
                    alignment: std.mem.Alignment,
                    new_len: usize,
                    ret_addr: usize,
                ) ?[*]u8 {
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
                    if (new_len > memory.len) {
                        self.stats.current_memory[@intFromEnum(tag)] += new_len - memory.len;
                        self.stats.current_total_memory += new_len - memory.len;
                    } else {
                        self.stats.current_memory[@intFromEnum(tag)] -= memory.len - new_len;
                        self.stats.current_total_memory -= memory.len - new_len;
                    }
                    if (self.stats.current_total_memory > self.stats.peak_total_memory) {
                        self.stats.peak_total_memory = self.stats.current_total_memory;
                    }
                    if (self.stats.current_memory[@intFromEnum(tag)] > self.stats.peak_memory[@intFromEnum(tag)]) {
                        self.stats.peak_memory[@intFromEnum(tag)] = self.stats.current_memory[@intFromEnum(tag)];
                    }
                    return self.backing_allocator.rawRemap(memory, alignment, new_len, ret_addr);
                }

                pub fn free(ctx: *anyopaque, buf: []u8, buf_align: std.mem.Alignment, ret_addr: usize) void {
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
                    self.stats.current_memory[@intFromEnum(tag)] -= buf.len;
                    self.stats.current_total_memory -= buf.len;
                    self.backing_allocator.rawFree(buf, buf_align, ret_addr);
                }
            };
        }
    };
}

test "type consistency" {
    const allocType = TrackingAllocator(.testing, EngineMemoryTag, true);
    const allocType2 = TrackingAllocator(.testing, EngineMemoryTag, true);
    const gpa = TrackingAllocator(.gpa, EngineMemoryTag, true);
    try std.testing.expect(allocType != gpa);
    try std.testing.expect(allocType == allocType2);
    var config: log.LogConfig = undefined;
    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator, &config);
    defer alloc.deinit();
}

test "allocations" {
    var config: log.LogConfig = undefined;
    const allocType = TrackingAllocator(.testing, EngineMemoryTag, true);
    const gpaType = TrackingAllocator(.gpa, EngineMemoryTag, true);

    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator, &config);
    defer alloc.deinit();

    var gpa: gpaType = gpaType{};
    gpa.init(std.testing.allocator, &config);
    defer gpa.deinit();

    const allocator = alloc.get_type_allocator(.untagged);
    const gallocator = gpa.get_type_allocator(.untagged);
    const data = try allocator.create(i32);
    const gdata = try gallocator.create(f64);
    const allocator2 = alloc.get_type_allocator(.renderer);
    const gallocator2 = gpa.get_type_allocator(.renderer);
    const data2 = try allocator2.create(allocType.MemoryStats);
    const gdata2 = try gallocator2.create(i32);
    allocator2.destroy(data2);
    gallocator2.destroy(gdata2);
    allocator.destroy(data);
    gallocator.destroy(gdata);
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const log = @import("log.zig");
const defines = @import("defines.zig");
const EngineMemoryTag = @import("fracture.zig").EngineMemoryTag;
