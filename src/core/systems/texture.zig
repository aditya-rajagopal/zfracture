// TODO: Make this configurable
pub const MAX_TEXTURES_COUNT = 4096;
pub const MAX_TEXTURE_DIM = 4096;

pub const DimnsionType = u14;
comptime {
    assert(std.math.maxInt(DimnsionType) > MAX_TEXTURE_DIM);
}

pub const TextureHandle = enum(u64) {
    missing_texture = @bitCast(MissingTexture),
    base_colour = @bitCast(BaseColour),
    null_handle = @bitCast(NullReference),
    _,
};

const NullReference = TextureReference{ .id = .null_handle, .string = std.math.maxInt(u32) };

const DefaultType = enum(u8) {
    missing_texture = 0,
    base_colour = 1,
};

const RESERVED_TEXTUES_COUNT = std.meta.fields(DefaultType).len;

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

const FREE_SLOTS_COUNT = MAX_TEXTURES_COUNT - RESERVED_TEXTUES_COUNT;

const TextureReference = packed struct(u64) {
    id: T.ResourceHandle,
    string: u32,
};

pub const TextureConfig = struct {
    auto_release: bool,

    pub const default = TextureConfig{
        .auto_release = false,
    };
};

pub fn Textures(renderer_backend: type) type {
    const RendererType = Renderer(renderer_backend);

    return struct {
        pub const Self = @This();
        // TODO: Should this be a diferent handle?
        handles: [MAX_TEXTURES_COUNT]T.Handle,
        infos: [MAX_TEXTURES_COUNT]Texture.Info,
        data: [MAX_TEXTURES_COUNT]Data,
        reference_counts: [MAX_TEXTURES_COUNT]u16,
        auto_release: [MAX_TEXTURES_COUNT]bool,

        // TODO: Maybe make the names instead be fron a virtual file system id or something
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

        // TODO: Make this just be a u32 start so and add null terminator to define the end
        const StringRef = packed struct(u64) {
            start: u32,
            end: u32,
        };

        // TODO: Make this configurable
        pub const DataSize = 8;

        pub const Texture = struct {
            handle: T.Handle = .{},
            info: Info = .{},
            data: Data = .{},

            pub const Info = packed struct(u32) {
                width: DimnsionType = 0,
                height: DimnsionType = 0,
                channel_count: u3 = 0,
                has_transparency: bool = false,

                pub const default = Info{
                    .width = 0,
                    .height = 0,
                    .channel_count = 0,
                    .has_transparency = false,
                };
            };
        };

        /// Opaque data that is managed by the renderer
        pub const Data = struct {
            data: [DataSize]u64 = [_]u64{0} ** DataSize,

            pub fn as(self: *Data, comptime E: type) *E {
                const size = @sizeOf(E);
                comptime assert(size <= DataSize * 8);
                return @alignCast(std.mem.bytesAsValue(E, &self.data[0]));
            }

            pub fn as_const(self: *const Data, comptime E: type) *const E {
                const size = @sizeOf(E);
                comptime assert(size <= DataSize * 8);
                return @alignCast(std.mem.bytesAsValue(E, &self.data[0]));
            }
        };

        // TODO: Best way to handle this
        pub fn init(self: *Self, renderer: *RendererType, allocator: std.mem.Allocator) !void {
            self.renderer = renderer;
            @memset(&self.handles, .{});
            @memset(&self.infos, .default);
            @memset(&self.data, .{});
            @memset(&self.reference_counts, 0);
            @memset(&self.auto_release, false);

            // INFO: Load the default texture
            self.hash_map = TextureNameMap.init(allocator);

            try self.create_defaults();

            // TODO: This wont work when multithreaded
            self.image_arena = std.heap.ArenaAllocator.init(allocator);
            _ = try self.image_arena.allocator().alloc(u8, MAX_TEXTURE_DIM * MAX_TEXTURE_DIM * 4);
            _ = self.image_arena.reset(.retain_capacity);

            // TODO: THis is dynamic. I dont like
            self.string_cache = try std.ArrayList(u8).initCapacity(allocator, 4096);
            self.string_reference = try std.ArrayList(StringRef).initCapacity(allocator, 4096);
            self.string_reference.appendNTimesAssumeCapacity(.{ .start = 0, .end = 0 }, RESERVED_TEXTUES_COUNT + 1);
        }

        pub fn deinit(self: *Self) void {
            for (self.handles, 0..) |handle, i| {
                if (handle.id != .null_handle) {
                    self.renderer._backend.destroy_texture(&self.data[i]);
                }
            }
            self.hash_map.deinit();
            self.string_cache.deinit();
            self.string_reference.deinit();
            self.image_arena.deinit();
        }

        // pub fn create_from_image(self: *Self, name: []const u8, img: image.Image, config: TextureConfig) TextureHandle {
        //     if (std.mem.eql(u8, name, BaseColourName)) {
        //         self.renderer._log.warn(
        //             "Trying to create base colour texture. Just use .base_colour",
        //             .{},
        //         );
        //         return TextureHandle.base_colour;
        //     }
        //     if (std.mem.eql(u8, name, MissingTextureName)) {
        //         self.renderer._log.warn(
        //             "Trying to create base colour texture. Just use .missing_texture",
        //             .{},
        //         );
        //         return TextureHandle.missing_texture;
        //     }
        //
        //     const gop = self.hash_map.getOrPut(name) catch unreachable;
        //
        //     if (!gop.found_existing) {
        //         const start = self.string_cache.items.len;
        //         self.string_cache.appendSlice(name) catch return .missing_texture;
        //         // HACK: This is not valid behavior
        //         gop.key_ptr.* = self.string_cache.items[start .. start + name.len];
        //         self.string_reference.append(
        //             .{ .start = @truncate(start), .end = @truncate(start + name.len) },
        //         ) catch return .missing_texture;
        //
        //         gop.value_ptr.* = .{
        //             .id = .null_handle,
        //             .string = @truncate(self.string_reference.items.len - 1),
        //         };
        //     } else {
        //         return @enumFromInt(@as(u64, @bitCast(gop.value_ptr.*)));
        //     }
        //
        //     var handle: TextureReference = gop.value_ptr.*;
        //     var location: u32 = @intFromEnum(handle.id);
        //
        //     if (handle.id == .null_handle) {
        //         // INFO: Image is already provided so load that image as a texture
        //     }
        //
        //     if (self.reference_counts[location] == 0) {
        //         self.auto_release[location] = config.auto_release;
        //     } else {
        //         assert(self.auto_release[location] == config.auto_release);
        //     }
        //
        //     return @enumFromInt(@as(u64, @bitCast(handle)));
        // }

        // TODO(adi): I hate this. Can we not use strings here?
        // TODO(adi): Should the image be stored instead of being discarded? This could be an option
        pub fn create(self: *Self, name: []const u8, config: TextureConfig) TextureHandle {
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
                // HACK: This is not valid behavior
                gop.key_ptr.* = self.string_cache.items[start .. start + name.len];
                self.string_reference.append(
                    .{ .start = @truncate(start), .end = @truncate(start + name.len) },
                ) catch return .missing_texture;

                gop.value_ptr.* = .{
                    .id = .null_handle,
                    .string = @truncate(self.string_reference.items.len - 1),
                };
            } else {
                return @enumFromInt(@as(u64, @bitCast(gop.value_ptr.*)));
            }

            var handle: TextureReference = gop.value_ptr.*;
            var location: u32 = @intFromEnum(handle.id);

            if (handle.id == .null_handle) {
                // INFO: Texture does not exist so load the texture
                var texture: Texture = .{};
                if (!Self.load_texture(self.renderer, &texture, self.image_arena.allocator(), name, .png)) {
                    self.renderer._log.err("Unable to open texture: {s}", .{name});
                    return TextureHandle.missing_texture;
                }
                _ = self.image_arena.reset(.retain_capacity);

                for (self.handles[RESERVED_TEXTUES_COUNT..], RESERVED_TEXTUES_COUNT..) |h, i| {
                    if (h.id == .null_handle) {
                        location = @truncate(i);
                        break;
                    }
                }
                texture.handle.id = @enumFromInt(location);
                handle.id = @enumFromInt(location);

                self.handles[location] = texture.handle;
                self.data[location] = texture.data;
                self.infos[location] = texture.info;

                gop.value_ptr.* = @bitCast(handle);
                self.reference_counts[location] = 0;
            }

            if (self.reference_counts[location] == 0) {
                self.auto_release[location] = config.auto_release;
            } else {
                assert(self.auto_release[location] == config.auto_release);
            }

            return @enumFromInt(@as(u64, @bitCast(handle)));
        }

        pub fn reload_texture(self: *Self, handle: TextureHandle) bool {
            _ = self;
            _ = handle;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn resize_texture(self: *Self, handle: TextureHandle, new_width: u32, new_height: u32) bool {
            _ = self;
            _ = handle;
            _ = new_width;
            _ = new_height;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn replace_texture(self: *Self, handle: TextureHandle) bool {
            _ = self;
            _ = handle;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn get_resource(self: *const Self, handle: TextureHandle) T.Handle {
            if (handle == .null_handle) {
                self.renderer._log.warn("Trying to get an invalid texture's resource", .{});
                return .{};
            }
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            const location: u32 = @intFromEnum(reference.id);
            assert(location < MAX_TEXTURES_COUNT);
            return self.handles[location];
        }

        pub fn acquire(self: *Self, handle: TextureHandle) *const Data {
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            if (reference.id == .null_handle or reference.string >= self.string_reference.items.len) {
                self.renderer._log.err("Invalid handle: {any}", .{reference});
                return &self.data[0];
            }
            const location: u32 = @intFromEnum(reference.id);
            assert(location < MAX_TEXTURES_COUNT);
            if (self.handles[location].id == .null_handle) {
                self.renderer._log.err("Expired handle: {any}. Texture not available", .{reference});
                return &self.data[0];
            }
            self.reference_counts[location] += 1;
            return &self.data[location];
        }

        pub fn release(self: *Self, handle: TextureHandle) void {
            if (handle == .missing_texture or handle == .base_colour) {
                return;
            }
            if (handle == .null_handle) {
                self.renderer._log.err("Freeing null texture", .{});
                return;
            }
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            if (reference.id == .null_handle) {
                self.renderer._log.err("Freeing invalid texture", .{});
                return;
            }
            const location = @intFromEnum(reference.id);

            if (self.handles[location].id == .null_handle) {
                self.renderer._log.err("Invalid texture handle, cannot release", .{});
                return;
            }

            self.reference_counts[location] -= 1;

            if (self.reference_counts[location] == 0 and self.auto_release[location]) {
                self.renderer._backend.destroy_texture(&self.data[location]);

                // TODO: We dont need to set the other fields here. Seperate id and generation
                self.infos[location] = .default;
                self.handles[location].id = .null_handle;
                self.handles[location].generation = .null_handle;

                assert(reference.string <= self.string_reference.items.len);
                const string_ref = self.string_reference.items[reference.string];
                const string = self.string_cache.items[string_ref.start..string_ref.end];
                const handle_ref = self.hash_map.getPtr(string) orelse unreachable;
                handle_ref.id = .null_handle;
            }
        }

        fn load_texture(
            renderer: *RendererType,
            texture: *Texture,
            allocator: std.mem.Allocator,
            texture_name: []const u8,
            comptime texture_type: image.ImageFileType,
        ) bool {
            // TODO: Revisit this to see if there is something that can be done to streamline this
            var img: image.Image = undefined;
            var resource: Resource = .{ .tag = .image, .data = @ptrCast(&img) };
            resource.load(.{ .image = .{ .requested_image_type = .rgba, .extension = texture_type } }, allocator, texture_name) catch |err| {
                renderer._log.err("Unable to load texture image: {s}", .{@errorName(err)});
                return false;
            };

            const current_generation = texture.handle.generation;
            texture.handle.generation = .null_handle;

            // TODO: This seems unnecessary
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

            texture.info.width = @truncate(img.width);
            texture.info.height = @truncate(img.height);
            texture.info.channel_count = @truncate(img.channels);

            texture.data = renderer._backend.create_texture(
                img.width,
                img.height,
                img.channels,
                img.data,
            ) catch |err| {
                renderer._log.err("Unable to create texture: {s}", .{@errorName(err)});
                return false;
            };
            texture.info.has_transparency = has_transparency;
            texture.handle.id = .null_handle;

            renderer._backend.destroy_texture(&old.data);

            if (current_generation == .null_handle) {
                texture.handle.generation = @enumFromInt(0);
            } else {
                texture.handle.generation = current_generation.increment();
            }

            return true;
        }

        fn create_defaults(self: *Self) !void {
            { // INFO: Default Missing Texture
                self.renderer._log.debug("Creating missing texture", .{});

                const missing_texture = 0;
                self.handles[missing_texture].generation = @enumFromInt(0);
                self.handles[missing_texture].id = MissingTexture.id;

                const texture_dim = 1;
                const channels = 4;
                var pixels = [4]u8{ 255, 0, 255, 255 };

                self.data[missing_texture] = self.renderer._backend.create_texture(
                    texture_dim,
                    texture_dim,
                    channels,
                    &pixels,
                ) catch {
                    self.renderer._log.err("Unable to load default missing texture", .{});
                    return error.InitFailed;
                };
                const missing_texture_info = &self.infos[missing_texture];
                missing_texture_info.width = 1;
                missing_texture_info.height = 1;
                missing_texture_info.channel_count = 4;
                missing_texture_info.has_transparency = false;
                self.hash_map.put(MissingTextureName, MissingTexture) catch return error.InitFailed;
            }

            { // INFO: Default White Base Colour Texture
                self.renderer._log.debug("Creating base colour", .{});

                const base_colour = 1;
                self.handles[base_colour].generation = @enumFromInt(0);
                self.handles[base_colour].id = BaseColour.id;

                const texture_dim = 1;
                const channels = 4;
                var pixels = [4]u8{ 255, 255, 255, 255 };

                self.data[base_colour] = self.renderer._backend.create_texture(
                    texture_dim,
                    texture_dim,
                    channels,
                    &pixels,
                ) catch {
                    self.renderer._log.err("Unable to load default missing texture", .{});
                    return error.InitFailed;
                };
                const base_colour_info = &self.infos[base_colour];
                base_colour_info.width = 1;
                base_colour_info.height = 1;
                base_colour_info.channel_count = 4;
                base_colour_info.has_transparency = false;
                self.hash_map.put(MissingTextureName, MissingTexture) catch return error.InitFailed;
            }
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;
const T = @import("types.zig");
const math = @import("fr_math");
const image = @import("../image.zig");
const Resource = @import("../resource.zig").Resource;
const Renderer = @import("../renderer.zig").Renderer;
