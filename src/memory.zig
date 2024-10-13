const core = @import("fr_core");
const core_log = core.logging.core_log;
const debug_assert = core.asserts.debug_assert_msg;
const client_memory_tags = @import("config.zig").client_memory_tags;
const client_allocator_tags = @import("config.zig").client_allocator_tags;

const EngineMemoryTag = enum(u8) {
    unknown = 0,
    event,
    renderer,
    application,
    frame_arena,
};

const EngineMemoryTypes = enum(u8) {
    gpa,
    frame_arena,
    testing,
};

/// The combined engine and client memory tags to track
pub const MemoryTag: type = core.MergeEnums(&[_]type{ EngineMemoryTag, client_memory_tags }, u8);

/// The combined engine and client allocators that can be created
pub const AllocatorTag: type = core.MergeEnums(&[_]type{ EngineMemoryTypes, client_allocator_tags }, u8);

const memory_tag_len = switch (builtin.mode) {
    .Debug => std.enums.directEnumArrayLen(MemoryTag, 256),
    else => 0,
};

const AllocatorTypes: [memory_tag_len]type = blk: {
    if (memory_tag_len != 0) {
        var alloc_types: [memory_tag_len]type = undefined;
        for (@typeInfo(MemoryTag).Enum.fields) |field| {
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

// TODO: Does there need to be an allocator tag here? Can it be an EnumLiteral now that it is not stored in the struct
///! An allocator that allows you to track total allocations and deallocations of the backing allocator
///! During release memory stats are not tracked and this essentially becomes a thin wrapper around
///! the backing allocator
pub fn TrackingAllocator(comptime alloc_tag: AllocatorTag) type {
    return struct {
        backing_allocator: Allocator = undefined,

        const struct_tag = alloc_tag;
        const TypeStructs = [memory_tag_len * num_bytes_type_allocator]u8;
        const TypeAllocators = [memory_tag_len]Allocator;

        var type_structs: TypeStructs align(8) = undefined;
        var type_allocators: TypeAllocators = undefined;
        var memory_stats: MemoryStats = std.mem.zeroes(MemoryStats);
        var initialized: bool = false;

        const Self = @This();

        pub fn init(self: *Self, allocator: Allocator) void {
            debug_assert(
                !initialized,
                @src(),
                "Reinitializing {s} allocator. Each allocator type can only be initalized once.",
                .{@tagName(struct_tag)},
            );
            self.backing_allocator = allocator;
            if (comptime memory_tag_len != 0) {
                inline for (AllocatorTypes, 0..) |t, i| {
                    const start = i * num_bytes_type_allocator;
                    const end = start + num_bytes_type_allocator;
                    const temp: *t = @as(*t, @ptrCast(@alignCast(type_structs[start..end].ptr)));
                    temp.* = t.init(allocator, &memory_stats);
                }
                inline for (0..memory_tag_len) |i| {
                    const start = i * num_bytes_type_allocator;
                    const end = start + num_bytes_type_allocator;
                    type_allocators[i] = @as(*AllocatorTypes[i], @ptrCast(@alignCast(type_structs[start..end].ptr))).allocator();
                }
            }
            initialized = true;
        }

        pub fn deinit(self: *Self) void {
            debug_assert(
                initialized,
                @src(),
                "Double shutdown of {s} allocator.",
                .{@tagName(struct_tag)},
            );
            self.backing_allocator = undefined;
            initialized = false;
        }

        pub fn get_type_allocator(self: *const Self, comptime tag: MemoryTag) Allocator {
            debug_assert(
                initialized,
                @src(),
                "Use of {s} allocator before init or after shutdown.",
                .{@tagName(struct_tag)},
            );
            if (comptime memory_tag_len != 0) {
                return type_allocators[@intFromEnum(tag)];
            } else {
                return self.backing_allocator;
            }
        }

        pub fn reset_stats(self: *Self) void {
            debug_assert(
                initialized,
                @src(),
                "Use of {s} allocator before init or after shutdown.",
                .{@tagName(struct_tag)},
            );
            _ = self;
            if (comptime memory_tag_len != 0) {
                memory_stats.current_total_memory = 0;
                memory_stats.current_memory = [_]u64{0} ** memory_tag_len;
            }
        }

        pub fn query_stats(self: *Self) *const MemoryStats {
            debug_assert(
                initialized,
                @src(),
                "Use of {s} allocator before init or after shutdown.",
                .{@tagName(struct_tag)},
            );
            _ = self;
            return &memory_stats;
        }

        pub fn print_memory_stats(self: *Self) void {
            debug_assert(
                initialized,
                @src(),
                "Use of {s} allocator before init or after shutdown.",
                .{@tagName(struct_tag)},
            );
            _ = self;
            if (comptime memory_tag_len != 0) {
                core_log.debug("Memory Subsystem[{s}]: ", .{@tagName(struct_tag)});
                // magic padding
                const padding = 8 + 16 + 2 + 9 + 2 + 9 + 1;
                core_log.debug("=" ** padding, .{});
                core_log.debug("|\t{s:<16}| {s:^9} | {s:^9}|", .{ "MemoryTag", "Current", "Peak" });
                core_log.debug("=" ** padding, .{});
                inline for (@typeInfo(MemoryTag).Enum.fields) |field| {
                    const curr_bytes = core.defines.parse_bytes(memory_stats.current_memory[field.value]);
                    const peak_bytes = core.defines.parse_bytes(memory_stats.peak_memory[field.value]);
                    core_log.debug("|\t{s:<16}| {s} |{s} |", .{ field.name, curr_bytes, peak_bytes });
                }
                const curr_bytes = core.defines.parse_bytes(memory_stats.current_total_memory);
                const peak_bytes = core.defines.parse_bytes(memory_stats.peak_total_memory);
                core_log.debug("=" ** padding, .{});
                core_log.debug("|\t{s:<16}| {s} |{s} |", .{ "TOTAL", curr_bytes, peak_bytes });
                core_log.debug("=" ** padding, .{});
                core_log.debug("\n", .{});
            }
        }
    };
}

// TODO: Write memory tests
test "type consistency" {
    const allocType = TrackingAllocator(.testing);
    const allocType2 = TrackingAllocator(.testing);
    const gpa = TrackingAllocator(.gpa);
    try std.testing.expect(allocType != gpa);
    try std.testing.expect(allocType == allocType2);
    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator);
    defer alloc.deinit();
}

test "allocations" {
    const allocType = TrackingAllocator(.testing);
    const gpaType = TrackingAllocator(.gpa);

    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator);
    defer alloc.deinit();

    var gpa: gpaType = gpaType{};
    gpa.init(std.testing.allocator);
    defer gpa.deinit();

    const allocator = alloc.get_type_allocator(.unknown);
    const gallocator = gpa.get_type_allocator(.unknown);
    const data = try allocator.create(i32);
    const gdata = try gallocator.create(f64);
    const allocator2 = alloc.get_type_allocator(.renderer);
    const gallocator2 = gpa.get_type_allocator(.renderer);
    const data2 = try allocator2.create(MemoryStats);
    const gdata2 = try gallocator2.create(i32);
    allocator2.destroy(data2);
    gallocator2.destroy(gdata2);
    allocator.destroy(data);
    gallocator.destroy(gdata);
}

// ------------------------------------------- TYPES -----------------------------------------------------/

const MemoryStats = switch (builtin.mode) {
    .Debug => struct {
        current_total_memory: u64,
        current_memory: [memory_tag_len]u64,
        peak_total_memory: u64,
        peak_memory: [memory_tag_len]u64,
    },
    else => struct {},
};

fn TypedAllocator(comptime tag: MemoryTag) type {
    return struct {
        backing_allocator: Allocator,
        stats: *MemoryStats,

        const Self = @This();

        pub fn init(parent_allocator: Allocator, stats_ref: *MemoryStats) Self {
            return Self{
                .backing_allocator = parent_allocator,
                .stats = stats_ref,
            };
        }

        pub fn allocator(self: *Self) Allocator {
            return Allocator{
                .ptr = self,
                .vtable = &.{
                    .alloc = alloc,
                    .resize = resize,
                    .free = free,
                },
            };
        }

        pub fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.stats.current_memory[@intFromEnum(tag)] += len;
            self.stats.current_total_memory += len;
            if (self.stats.current_total_memory > self.stats.peak_total_memory) {
                self.stats.peak_total_memory = self.stats.current_total_memory;
            }
            if (self.stats.current_memory[@intFromEnum(tag)] > self.stats.peak_memory[@intFromEnum(tag)]) {
                self.stats.peak_memory[@intFromEnum(tag)] = self.stats.current_memory[@intFromEnum(tag)];
            }
            return self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);
        }

        pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.stats.current_memory[@intFromEnum(tag)] += new_len - buf.len;
            self.stats.current_total_memory += new_len - buf.len;
            if (self.stats.current_total_memory > self.stats.peak_total_memory) {
                self.stats.peak_total_memory = self.stats.current_total_memory;
            }
            if (self.stats.current_memory[@intFromEnum(tag)] > self.stats.peak_memory[@intFromEnum(tag)]) {
                self.stats.peak_memory[@intFromEnum(tag)] = self.stats.current_memory[@intFromEnum(tag)];
            }
            return self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        }

        pub fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.stats.current_memory[@intFromEnum(tag)] -= buf.len;
            self.stats.current_total_memory -= buf.len;
            self.backing_allocator.rawFree(buf, buf_align, ret_addr);
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
