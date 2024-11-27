// TODO: Make this configurable
pub const MAX_TEXTURES = 1024;
pub const MAX_TEXTURE_DIM = 4096;

pub const TextureHandle = enum(u64) {
    missing_texture = @bitCast(MissingTexture),
    base_colour = @bitCast(BaseColour),
    null_handle = @bitCast(NullReference),
    _,
};

const NullReference = TextureReference{ .id = .null_handle, .string = 0 };

const DefaultType = enum(u8) {
    missing_texture = 0,
    base_colour = 1,
};

const RESERVED_TEXTUES = std.meta.fields(DefaultType).len;

const MissingTexture = TextureReference{
    .id = @enumFromInt(@intFromEnum(DefaultType.missing_texture)),
    .string = 1,
};
const MissingTextureName: []const u8 = @tagName(DefaultType.missing_texture);

// Default texture for diffuse
const BaseColour = TextureReference{
    .id = @enumFromInt(@intFromEnum(DefaultType.base_colour)),
    .string = 2,
};
const BaseColourName: []const u8 = @tagName(DefaultType.base_colour);

const FREE_SLOTS = MAX_TEXTURES - RESERVED_TEXTUES;

const TextureReference = packed struct(u64) {
    id: resource.ResourceHandle,
    string: u32,
};

pub fn TextureSystem(renderer_backend: type) type {
    const RendererType = Renderer(renderer_backend);

    return struct {
        pub const Self = @This();
        //TODO: Should this be dynamic?
        //TODO: Make this safe when more textures are available. Overwrite the oldest texture?
        items: [MAX_TEXTURES]Texture,
        reference_counts: [MAX_TEXTURES]u16,
        auto_release: [MAX_TEXTURES]bool,

        // The first element of the freelist holds the pointer this corresponds to the default texture
        free_list_ptr: u16,
        free_list: [FREE_SLOTS]u16,

        // TODO: Maybe make the names instead be fron a virtual file system id or something
        /// Hashmap storing the current handle for a given texture name
        hash_map: TextureNameMap,

        /// Local cache to store string keys for the lifetime of this system
        string_cache: std.ArrayList(u8),
        string_reference: std.ArrayList(StringRef),

        /// Local memory arena for reading images,
        /// TODO: Cannot use this in mutilple threads
        image_arena: std.heap.ArenaAllocator,

        /// Reference to the frontend
        renderer: *RendererType,

        const TextureKey = []const u8;
        const TextureNameMap =
            if (TextureKey == []const u8)
            std.StringHashMap(TextureReference)
        else
            std.AutoHashMap(TextureKey, TextureReference);

        const StringRef = packed struct(u64) {
            start: u32,
            end: u32,
        };

        pub const Handle = TextureHandle;

        // TODO: Best way to handle this

        pub fn init(self: *Self, renderer: *RendererType, allocator: std.mem.Allocator) !void {
            self.free_list_ptr = 0;
            for (0..MAX_TEXTURES - RESERVED_TEXTUES) |i| {
                self.free_list[i] = @as(u16, @truncate(i)) + @as(u16, RESERVED_TEXTUES);
            }
            self.renderer = renderer;
            @memset(&self.items, Texture{});
            @memset(&self.reference_counts, 0);
            @memset(&self.auto_release, false);

            // INFO: Load the default texture
            self.hash_map = TextureNameMap.init(allocator);

            try self.create_defaults();

            // TODO: This wont work when multithreaded
            self.image_arena = std.heap.ArenaAllocator.init(allocator);
            _ = try self.image_arena.allocator().alloc(u8, MAX_TEXTURE_DIM * MAX_TEXTURE_DIM * 4);
            _ = self.image_arena.reset(.retain_capacity);

            self.string_cache = try std.ArrayList(u8).initCapacity(allocator, 4096);
            self.string_reference = try std.ArrayList(StringRef).initCapacity(allocator, 4096);
            self.string_reference.appendNTimesAssumeCapacity(.{ .start = 0, .end = 0 }, RESERVED_TEXTUES + 1);
        }

        pub fn deinit(self: *Self) void {
            for (&self.items) |*texture| {
                if (texture.id != .null_handle) {
                    self.renderer._backend.destroy_texture(&texture.data);
                }
            }
            self.hash_map.deinit();
            self.string_cache.deinit();
            self.string_reference.deinit();
            self.image_arena.deinit();
        }

        pub fn get_default(self: *const Self) *const Texture {
            return &self.items[1];
        }

        pub fn create(self: *Self, name: []const u8, auto_release: bool) TextureHandle {
            if (std.mem.eql(u8, name, BaseColourName)) {
                self.renderer._log.warn(
                    "Trying to create base colour texture. Just use .base_colour",
                    .{},
                );
                return TextureHandle.base_colour;
            }
            if (std.mem.eql(u8, name, MissingTextureName)) {
                self.renderer._log.warn(
                    "Trying to create base colour texture. Just use .missing_texture",
                    .{},
                );
                return TextureHandle.missing_texture;
            }

            const gop = self.hash_map.getOrPut(name) catch unreachable;

            if (!gop.found_existing) {
                const start = self.string_cache.items.len;
                self.string_cache.appendSlice(name) catch return .missing_texture;
                gop.key_ptr.* = self.string_cache.items[start .. start + name.len];
                self.string_reference.append(
                    .{ .start = @truncate(start), .end = @truncate(start + name.len) },
                ) catch return .missing_texture;

                gop.value_ptr.* = .{
                    .id = .null_handle,
                    .string = @truncate(self.string_reference.items.len - 1),
                };
            }

            var handle: TextureReference = gop.value_ptr.*;
            var location: u32 = @intFromEnum(handle.id);

            if (handle.id == .null_handle) {
                // INFO: Texture does not exist so load the texture
                assert(self.free_list_ptr < MAX_TEXTURES);
                var texture: Texture = .{};
                if (!self.load_texture(&texture, self.image_arena.allocator(), name, .png)) {
                    self.renderer._log.err("Unable to open texture: {s}", .{name});
                    return TextureHandle.missing_texture;
                }
                _ = self.image_arena.reset(.retain_capacity);

                const free_index = self.free_list[self.free_list_ptr];
                location = free_index;
                assert(self.items[free_index].id == .null_handle);
                texture.id = @enumFromInt(free_index);
                handle.id = @enumFromInt(free_index);
                self.items[free_index] = texture;
                self.items[free_index] = texture;
                gop.value_ptr.* = @bitCast(handle);
                self.reference_counts[free_index] = 0;
                self.free_list_ptr += 1;
            }

            if (self.reference_counts[location] == 0) {
                self.auto_release[location] = auto_release;
            } else {
                assert(self.auto_release[location] == auto_release);
            }

            return @enumFromInt(@as(u64, @bitCast(handle)));
        }

        pub fn reload_texture(self: *Self, handle: TextureHandle) bool {
            _ = self;
            _ = handle;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn replace_texture(self: *Self, handle: Handle) bool {
            _ = self;
            _ = handle;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn get_info(self: *const Self, handle: TextureHandle) struct { ResourceHandle, Generation } {
            if (handle == .null_handle) {
                return .{ .null_handle, .null_handle };
            }
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            const location: u32 = @intFromEnum(reference.id);
            assert(location < self.items.len);
            return .{ self.items[location].id, self.items[location].generation };
        }

        pub fn get_data(self: *const Self, handle: TextureHandle) *const Texture.Data {
            assert(handle != .null_handle);
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            const location: u32 = @intFromEnum(reference.id);
            assert(location < self.items.len);
            return &self.items[location].data;
        }

        pub fn acquire(self: *Self, handle: TextureHandle) *Texture {
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            self.renderer._log.debug("Requesting texture {any}", .{reference});
            if (reference.id == .null_handle or reference.string >= self.string_reference.items.len) {
                self.renderer._log.err("Invalid handle: {any}", .{reference});
                return &self.items[0];
            }
            const location: u32 = @intFromEnum(reference.id);
            if (self.items[location].id == .null_handle) {
                self.renderer._log.err("Expired handle: {any}. Texture not available", .{reference});
                return &self.items[0];
            }

            self.reference_counts[location] += 1;
            return &self.items[location];
        }

        pub fn release(self: *Self, handle: TextureHandle) void {
            if (handle == .null_handle or handle == .missing_texture or handle == .base_colour) {
                self.renderer._log.err("Freeing static textures", .{});
                return;
            }
            const reference: TextureReference = @bitCast(handle);
            if (reference.id == .null_handle) {
                self.renderer._log.err("Freeing invalid texture", .{});
                return;
            }
            const location = @intFromEnum(reference.id);

            self.reference_counts[location] -= 1;

            if (self.reference_counts[location] == 0 and self.auto_release[location]) {
                const texture = &self.items[location];

                self.renderer._backend.destroy_texture(&texture.data);

                texture.id = .null_handle;
                texture.generation = .null_handle;
                texture.has_transparency = 0;
                texture.channel_count = 0;
                texture.width = 0;
                texture.height = 0;

                assert(reference.string <= self.string_reference.items.len);
                const string_ref = self.string_reference.items[reference.ref_count];
                const string = self.string_cache.items[string_ref.start..string_ref.end];
                const handle_ref = self.hash_map.getPtr(string) orelse unreachable;
                handle_ref.id = .null_handle;
            }
        }

        fn load_texture(
            self: *Self,
            texture: *Texture,
            allocator: std.mem.Allocator,
            texture_name: []const u8,
            comptime texture_type: image.ImageFileType,
        ) bool {
            // TODO: This needs to be configurable
            const format_string: []const u8 = "assets/textures/{s}.{s}";
            var file_name_buffer: [512]u8 = undefined;
            const file_name = std.fmt.bufPrint(&file_name_buffer, format_string, .{ texture_name, @tagName(texture_type) }) catch unreachable;
            const required_channel_count = 4;

            const img = image.load(file_name, allocator, .{ .requested_channels = required_channel_count }) catch |err| {
                self.renderer._log.err("Unable to load texture image: {s}", .{@errorName(err)});
                return false;
            };

            const current_generation = texture.generation;
            texture.generation = .null_handle;

            var has_transparency: bool = false;
            if (img.forced_transparency) {
                has_transparency = true;
            } else {
                var index: usize = 3;
                while (index < img.data.len) : (index += 4) {
                    if (img.data[index] < 255) {
                        has_transparency = true;
                        break;
                    }
                }
            }

            var old = texture.*;

            texture.width = img.width;
            texture.height = img.height;
            texture.channel_count = required_channel_count;

            texture.data = self.renderer._backend.create_texture(
                img.width,
                img.height,
                required_channel_count,
                img.data,
            ) catch |err| {
                self.renderer._log.err("Unable to create texture: {s}", .{@errorName(err)});
                return false;
            };
            texture.has_transparency = @intFromBool(has_transparency);
            texture.id = .null_handle;

            self.renderer._backend.destroy_texture(&old.data);

            if (current_generation == .null_handle) {
                texture.generation = @enumFromInt(0);
            } else {
                texture.generation = current_generation.increment();
            }

            return true;
        }

        fn create_defaults(self: *Self) !void {
            { // INFO: Default Missing Texture
                self.renderer._log.debug("Creating missing texture", .{});

                const missing_texture = &self.items[0];
                missing_texture.generation = .null_handle;
                missing_texture.id = MissingTexture.id;
                const texture_dim = 1;
                const channels = 4;
                const pixel_count = texture_dim * texture_dim;
                var pixels = [pixel_count * channels]u8{ 255, 0, 255, 255 };

                missing_texture.data = self.renderer._backend.create_texture(
                    texture_dim,
                    texture_dim,
                    channels,
                    &pixels,
                ) catch {
                    self.renderer._log.err("Unable to load default missing texture", .{});
                    return error.InitFailed;
                };
                missing_texture.width = 1;
                missing_texture.height = 1;
                missing_texture.channel_count = 4;
                missing_texture.has_transparency = 0;
                self.hash_map.put(MissingTextureName, MissingTexture) catch return error.InitFailed;
            }

            { // INFO: Default White Base Colour Texture
                self.renderer._log.debug("Creating base colour", .{});

                const base_colour = &self.items[1];
                base_colour.generation = .null_handle;
                base_colour.id = BaseColour.id;
                const texture_dim = 1;
                const channels = 4;
                const pixel_count = texture_dim * texture_dim;
                var pixels: [pixel_count * channels]u8 = undefined;
                @memset(&pixels, 255);

                base_colour.data = self.renderer._backend.create_texture(
                    texture_dim,
                    texture_dim,
                    channels,
                    &pixels,
                ) catch {
                    self.renderer._log.err("Unable to load default missing texture", .{});
                    return error.InitFailed;
                };
                base_colour.width = 1;
                base_colour.height = 1;
                base_colour.channel_count = 4;
                base_colour.has_transparency = 0;
                self.hash_map.put(BaseColourName, BaseColour) catch return error.InitFailed;
            }
        }

        test Self {
            std.debug.print("{any}\n", .{Self.default_hash});
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;
const resource = @import("../resource.zig");
const ResourceHandle = resource.ResourceHandle;
const Generation = resource.Generation;
const Texture = resource.Texture;
const math = @import("../math/math.zig");
const image = @import("../image.zig");
const Renderer = @import("../renderer.zig").Renderer;