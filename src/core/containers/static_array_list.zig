// TODO: This is incomplete
pub fn StaticArrayList(comptime T: type, comptime size: usize) type {
    return struct {
        const Self = @This();
        items: [size]T,
        len: usize = 0,

        pub const Slice = []T;

        pub fn get_slice(self: *Self) Slice {
            return self.items[0..self.len];
        }

        pub fn insert_move(self: *Self, index: usize, item: T) void {
            const dest = self.add_many_at(index, 1);
            dest[0] = item;
        }

        pub fn add_many_at_move(self: *Self, index: usize, num_items: usize) Slice {
            debug_assert(index < self.len, @src(), "Index out of bounds!", .{});
            debug_assert(self.len + num_items < size, @src(), "Insufficient space in StaticArrayList of type " ++ @typeName(T) ++ ". Requested {d}", .{num_items});
            std.mem.copyBackwards(T, self.items[index + num_items .. self.len + num_items], self.items[index..self.len]);
            self.len += num_items;
            return self.items[index .. index + num_items];
        }

        pub fn insert(self: *Self, index: usize, item: T) void {
            const dest = self.add_many_at(index, 1);
            dest[0] = item;
        }

        pub fn insert_slice(self: *Self, index: usize, items: []T) void {
            const dest = self.add_many_at(index, items.len);
            @memcpy(dest, items);
        }

        pub fn add_many_at(self: *Self, index: usize, num_items: usize) Slice {
            debug_assert(index < self.len, @src(), "Index out of bounds!", .{});
            debug_assert(self.len + num_items < size, @src(), "Insufficient space in StaticArrayList of type " ++ @typeName(T) ++ ". Requested {d}", .{num_items});
            std.mem.copyBackwards(T, self.items[self.len .. self.len + num_items], self.items[index .. index + num_items]);
            self.len += num_items;
            return self.items[index .. index + num_items];
        }

        pub fn append(self: *Self, item: T) void {
            debug_assert(self.len < size, @src(), "Insufficient space in StaticArrayList of type " ++ @typeName(T) ++ ". Requested 1", .{});
            self.items[self.len] = item;
            self.len += 1;
        }

        pub fn append_slice(self: *Self, items: []T) void {
            debug_assert(self.len + items.len < size, @src(), "Insufficient space in StaticArrayList of type " ++ @typeName(T) ++ ". Requested {d}", .{items.len});
            @memcpy(self.items[self.len .. self.len + items.len], items);
            self.len += items.len;
        }

        pub fn pop(self: *Self) T {
            debug_assert(self.len > 0, @src(), "Array is empty. Cannot Pop.", .{});
            self.len -= 1;
            return self.items[self.len];
        }

        pub fn swap_remove(self: *Self, index: usize) void {
            debug_assert(index < self.len, @src(), "Index out of bounds!", .{});
            self.items[index] = self.items[self.len - 1];
            self.len -= 1;
        }

        pub fn shrink(self: *Self, new_len: usize) void {
            debug_assert(new_len < self.len, @src(), "Shrinking to size bigger than current length", .{});
            self.len = new_len;
        }

        pub fn clear(self: *Self) void {
            self.shrink(0);
        }

        pub fn clear_and_free(self: *Self, zero_value: T) void {
            self.shrink(0);
            const slice = self.get_slice();
            @memset(slice, zero_value);
        }

        pub fn get(self: *Self, index: usize) T {
            debug_assert(index < self.len, @src(), "Index out of bounds!", .{});
            return self.items[index];
        }

        pub fn getPtr(self: *Self, index: usize) *T {
            debug_assert(index < self.len, @src(), "Index out of bounds!", .{});
            return &self.items[index];
        }
    };
}

const std = @import("std");
const debug_assert = @import("../asserts.zig").debug_assert_msg;
