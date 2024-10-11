const core = @import("fr_core");
const config = @import("config.zig");

const EngineMemoryTag = enum(u8) {
    unknown = 0,
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
pub const MemoryTag: type = core.MergeEnums(&[_]type{ EngineMemoryTag, config.client_memory_tags }, u8);

/// The combined engine and client allocators that can be created
pub const AllocatorTag: type = core.MergeEnums(&[_]type{ EngineMemoryTypes, config.client_allocator_tags }, u8);

const memory_tag_len = std.enums.directEnumArrayLen(MemoryTag, 256);

const AllocatorTypes: [memory_tag_len]type = blk: {
    var alloc_types: [memory_tag_len]type = undefined;
    for (@typeInfo(MemoryTag).Enum.fields) |field| {
        const tag: MemoryTag = @enumFromInt(field.value);
        alloc_types[field.value] = TypedAllocator(tag);
    }
    break :blk alloc_types;
};

const num_bytes_type_allocator = @sizeOf(AllocatorTypes[0]);

///! An allocator that allows you to track total allocations and deallocations of the backing allocator
///! During release memory stats are not tracked and this essentially becomes a thin wrapper around
///! the backing allocator
pub fn TrackingAllocator(comptime alloc_tag: AllocatorTag) type {
    switch (builtin.mode) {
        .Debug => {
            return struct {
                type_structs: [memory_tag_len * num_bytes_type_allocator]u8 = undefined,
                type_allocators: [memory_tag_len]Allocator = undefined,
                memory_stats: MemoryStats = std.mem.zeroes(MemoryStats),

                const struct_tag = alloc_tag;

                const Self = @This();

                pub fn init(self: *Self, allocator: Allocator) !void {
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
                }

                pub fn deinit(self: *Self) void {
                    _ = self;
                }

                pub fn get_type_allocator(self: *Self, tag: MemoryTag) Allocator {
                    return self.type_allocators[@intFromEnum(tag)];
                }

                pub fn print_memory_stats(self: *Self) void {
                    std.debug.print("Memory Subsystem[{s}]: \n", .{@tagName(struct_tag)});
                    inline for (@typeInfo(MemoryTag).Enum.fields) |field| {
                        std.debug.print("\t{s}: {d} bytes\n", .{ field.name, self.memory_stats.current_memory[field.value] });
                    }
                    std.debug.print("\n", .{});
                }
            };
        },
        else => {
            return struct {
                backing_allocator: Allocator = undefined,
                const Self = @This();

                pub fn init(self: *Self, allocator: Allocator) !void {
                    self.backing_allocator = allocator;
                    const a = alloc_tag;
                    _ = a;
                }

                pub fn deinit(self: *Self) void {
                    _ = self;
                }

                pub fn get_type_allocator(self: *Self, tag: MemoryTag) Allocator {
                    _ = tag;
                    return self.backing_allocator;
                }
                pub fn print_memory_stats(self: *Self) void {
                    _ = self;
                }
            };
        },
    }
}

// TODO: Write memory tests
test "memory" {
    const allocType = TrackingAllocator(.testing);
    const allocType2 = TrackingAllocator(.testing);
    const gpa = TrackingAllocator(.gpa);
    std.debug.print("Is eq? : {any}\n", .{allocType == gpa});
    std.debug.print("Is eq? : {any}\n", .{allocType == allocType2});
    var alloc: allocType = allocType{};
    try alloc.init(std.testing.allocator);
    std.debug.print("Size of allocator: {d}\n", .{@sizeOf(allocType)});
    std.debug.print("Size of allocator: {d}\n", .{@sizeOf(Allocator)});
    defer alloc.deinit();
}

test "memory2" {
    const allocType = TrackingAllocator(.testing);
    const gpaType = TrackingAllocator(.gpa);
    var alloc: allocType = allocType{};
    try alloc.init(std.testing.allocator);
    defer alloc.deinit();

    var gpa: gpaType = gpaType{};
    try gpa.init(std.testing.allocator);
    defer gpa.deinit();
    alloc.print_memory_stats();
    gpa.print_memory_stats();
    const allocator = alloc.get_type_allocator(.unknown);
    const gallocator = gpa.get_type_allocator(.unknown);
    const data = try allocator.create(i32);
    const gdata = try gallocator.create(f64);
    const allocator2 = alloc.get_type_allocator(.renderer);
    const gallocator2 = gpa.get_type_allocator(.renderer);
    const data2 = try allocator2.create(MemoryStats);
    const gdata2 = try gallocator2.create(i32);
    alloc.print_memory_stats();
    gpa.print_memory_stats();
    allocator2.destroy(data2);
    gallocator2.destroy(gdata2);
    alloc.print_memory_stats();
    gpa.print_memory_stats();
    allocator.destroy(data);
    gallocator.destroy(gdata);

    alloc.print_memory_stats();
    gpa.print_memory_stats();
}

// ------------------------------------------- TYPES -----------------------------------------------------/

const MemoryStats = struct {
    current_total_memory: u64,
    current_memory: [memory_tag_len]u64,
    peak_total_memory: u64,
    peak_memory: [memory_tag_len]u64,
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
            return self.backing_allocator.rawAlloc(len, ptr_align, ret_addr);
        }

        pub fn resize(ctx: *anyopaque, buf: []u8, buf_align: u8, new_len: usize, ret_addr: usize) bool {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.stats.current_memory[@intFromEnum(tag)] += new_len - buf.len;
            return self.backing_allocator.rawResize(buf, buf_align, new_len, ret_addr);
        }

        pub fn free(ctx: *anyopaque, buf: []u8, buf_align: u8, ret_addr: usize) void {
            const self: *Self = @ptrCast(@alignCast(ctx));
            self.stats.current_memory[@intFromEnum(tag)] -= buf.len;
            self.backing_allocator.rawFree(buf, buf_align, ret_addr);
        }
    };
}

const std = @import("std");
const Allocator = std.mem.Allocator;
const builtin = @import("builtin");
