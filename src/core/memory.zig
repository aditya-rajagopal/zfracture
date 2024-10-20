pub const EngineMemoryTag = enum(u8) {
    untagged = 0,
    event,
    renderer,
    application,
    game,
    frame_arena,
};

pub const ArenaMemoryTags = enum(u8) {
    untagged = 0,
};

pub const GPA = TrackingAllocator(.gpa, EngineMemoryTag, true);
pub const FrameArena: type = TrackingAllocator(.frame_arena, ArenaMemoryTags, true);

/// The memory system passed to the game
pub const Memory = struct {
    /// The general allocator used to allocate permanent data
    gpa: GPA = undefined,
    /// Temporary Allocator that is cleared each frame. Used for storing transient frame data.
    frame_allocator: FrameArena = undefined,
};

///! An allocator that allows you to track total allocations and deallocations of the backing allocator
///! During release memory stats are not tracked and this essentially becomes a thin wrapper around
///! the backing allocator
pub fn TrackingAllocator(comptime alloc_tag: @Type(.enum_literal), comptime MemoryTag: type, comptime enable_log: bool) type {
    if (comptime @typeInfo(MemoryTag) != .@"enum") {
        @compileError("Memory Tag must be an enum");
    }
    const memory_tag_len = switch (builtin.mode) {
        .Debug => std.enums.directEnumArrayLen(MemoryTag, 256),
        else => 0,
    };

    const MemoryLog = if (enable_log) log.ScopedLogger(log.default_log, .MEMORY, log.default_level) else void;

    return struct {
        backing_allocator: Allocator = undefined,
        type_structs: TypeStructs = undefined,
        type_allocators: TypeAllocators = undefined,
        memory_stats: MemoryStats = std.mem.zeroes(MemoryStats),
        log: MemoryLog,

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
            // debug_assert(
            //     !initialized,
            //     @src(),
            //     "Reinitializing {s} allocator. Each allocator type can only be initalized once.",
            //     .{@tagName(struct_tag)},
            // );
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
            // initialized = true;
        }

        pub fn deinit(self: *Self) void {
            // debug_assert(
            //     initialized,
            //     @src(),
            //     "Double shutdown of {s} allocator.",
            //     .{@tagName(struct_tag)},
            // );
            self.backing_allocator = undefined;
            // initialized = false;
        }

        pub fn get_type_allocator(self: *const Self, comptime tag: MemoryTag) Allocator {
            // debug_assert(
            //     initialized,
            //     @src(),
            //     "Use of {s} allocator before init or after shutdown.",
            //     .{@tagName(struct_tag)},
            // );
            if (comptime memory_tag_len != 0) {
                return self.type_allocators[@intFromEnum(tag)];
            } else {
                return self.backing_allocator;
            }
        }

        pub fn reset_stats(self: *Self) void {
            // debug_assert(
            //     initialized,
            //     @src(),
            //     "Use of {s} allocator before init or after shutdown.",
            //     .{@tagName(struct_tag)},
            // );
            if (comptime memory_tag_len != 0) {
                self.memory_stats.current_total_memory = 0;
                self.memory_stats.current_memory = [_]u64{0} ** memory_tag_len;
            }
        }

        pub fn query_stats(self: *Self) *const MemoryStats {
            // debug_assert(
            //     initialized,
            //     @src(),
            //     "Use of {s} allocator before init or after shutdown.",
            //     .{@tagName(struct_tag)},
            // );
            return &self.memory_stats;
        }

        pub fn print_memory_stats(self: *Self) void {
            // debug_assert(
            //     initialized,
            //     @src(),
            //     "Use of {s} allocator before init or after shutdown.",
            //     .{@tagName(struct_tag)},
            // );
            if (comptime memory_tag_len != 0 or enable_log) {
                self.log.debug("Memory Subsystem[{s}]: ", .{@tagName(struct_tag)});
                // magic padding
                const padding = 8 + 16 + 2 + 9 + 2 + 9 + 1;
                self.log.debug("=" ** padding, .{});
                self.log.debug("|\t{s:<16}| {s:^9} | {s:^9}|", .{ "MemoryTag", "Current", "Peak" });
                self.log.debug("=" ** padding, .{});
                inline for (@typeInfo(MemoryTag).@"enum".fields) |field| {
                    const curr_bytes = defines.parse_bytes(self.memory_stats.current_memory[field.value]);
                    const peak_bytes = defines.parse_bytes(self.memory_stats.peak_memory[field.value]);
                    self.log.debug("|\t{s:<16}| {s} |{s} |", .{ field.name, curr_bytes, peak_bytes });
                }
                const curr_bytes = defines.parse_bytes(self.memory_stats.current_total_memory);
                const peak_bytes = defines.parse_bytes(self.memory_stats.peak_total_memory);
                self.log.debug("=" ** padding, .{});
                self.log.debug("|\t{s:<16}| {s} |{s} |", .{ "TOTAL", curr_bytes, peak_bytes });
                self.log.debug("=" ** padding, .{});
                self.log.debug("\n", .{});
            }
        }

        pub const MemoryStats = switch (builtin.mode) {
            .Debug => struct {
                current_total_memory: u64,
                current_memory: [memory_tag_len]u64,
                peak_total_memory: u64,
                peak_memory: [memory_tag_len]u64,
            },
            else => struct {},
        };

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
                            .free = free,
                        },
                    };
                }

                pub fn alloc(ctx: *anyopaque, len: usize, ptr_align: u8, ret_addr: usize) ?[*]u8 {
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
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
                    const self: *TAlloc = @ptrCast(@alignCast(ctx));
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
    const allocType = TrackingAllocator(.testing, EngineMemoryTag);
    const allocType2 = TrackingAllocator(.testing, EngineMemoryTag);
    const gpa = TrackingAllocator(.gpa, EngineMemoryTag);
    try std.testing.expect(allocType != gpa);
    try std.testing.expect(allocType == allocType2);
    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator);
    defer alloc.deinit();
}

test "allocations" {
    const allocType = TrackingAllocator(.testing, EngineMemoryTag);
    const gpaType = TrackingAllocator(.gpa, EngineMemoryTag);

    var alloc: allocType = allocType{};
    alloc.init(std.testing.allocator);
    defer alloc.deinit();

    var gpa: gpaType = gpaType{};
    gpa.init(std.testing.allocator);
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

// ------------------------------------------- TYPES -----------------------------------------------------/

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
const log = @import("log.zig");
const defines = @import("defines.zig");
