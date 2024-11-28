// TODO: Make this configurable
pub const MAX_TEXTURES = 1024;
pub const MAX_TEXTURE_DIM = 4096;

pub const TextureHandle = enum(u64) {
    missing_texture = @bitCast(MissingTexture),
    base_colour = @bitCast(BaseColour),
    null_handle = @bitCast(NullReference),
    _,
};

pub const TextureUse = enum(u8) {
    unknown = 0,
    diffuse,
};

const NullReference = TextureReference{ .id = .null_handle, .string = std.math.maxInt(u32) };

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
    id: T.ResourceHandle,
    string: u32,
};

pub fn Textures(renderer_backend: type) type {
    const RendererType = Renderer(renderer_backend);

    return struct {
        pub const Self = @This();
        //TODO: Should this be dynamic?
        //TODO: Make this safe when more textures are available. Overwrite the oldest texture?
        // items: [MAX_TEXTURES]Texture,
        /// Texture Data
        handles: [MAX_TEXTURES]T.Handle,
        uses: [MAX_TEXTURES]TextureUse,
        infos: [MAX_TEXTURES]Texture.Info,
        data: [MAX_TEXTURES]Data,

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

        // TODO: Make this configurable
        pub const DataSize = 8;

        pub const Texture = struct {
            handle: T.Handle = .{},
            use: TextureUse = .unknown,
            info: Info = .{},
            data: Data = .{},

            pub const Info = struct {
                width: u32 = 0,
                height: u32 = 0,
                has_transparency: u8 = 0,
                channel_count: u8 = 0,
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
            self.free_list_ptr = 0;
            for (0..MAX_TEXTURES - RESERVED_TEXTUES) |i| {
                self.free_list[i] = @as(u16, @truncate(i)) + @as(u16, RESERVED_TEXTUES);
            }
            self.renderer = renderer;
            @memset(&self.handles, .{});
            @memset(&self.uses, .unknown);
            @memset(&self.infos, .{});
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

            self.string_cache = try std.ArrayList(u8).initCapacity(allocator, 4096);
            self.string_reference = try std.ArrayList(StringRef).initCapacity(allocator, 4096);
            self.string_reference.appendNTimesAssumeCapacity(.{ .start = 0, .end = 0 }, RESERVED_TEXTUES + 1);
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

        pub fn get_default(self: *const Self) *const Texture {
            return Texture{
                .handle = self.handles[1],
                .use = self.uses[1],
                .width = self.widths[1],
                .height = self.heights[1],
                .channel_count = self.channel_counts[1],
                .has_transparency = self.has_transparencys[1],
                .data = self.data[1],
            };
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
                assert(self.handles[free_index].id == .null_handle);
                texture.handle.id = @enumFromInt(free_index);
                handle.id = @enumFromInt(free_index);

                self.handles[free_index] = texture.handle;
                self.uses[free_index] = texture.use;
                self.data[free_index] = texture.data;
                self.infos[free_index] = texture.info;

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

        pub fn replace_texture(self: *Self, handle: TextureHandle) bool {
            _ = self;
            _ = handle;
            @compileError("NOT IMPLEMENTED");
        }

        pub fn get_info(self: *const Self, handle: TextureHandle) T.Handle {
            if (handle == .null_handle) {
                return .{};
            }
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            const location: u32 = @intFromEnum(reference.id);
            assert(location < MAX_TEXTURES);
            return self.handles[location];
        }

        pub fn acquire(self: *Self, handle: TextureHandle) *const Data {
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            if (reference.id == .null_handle or reference.string >= self.string_reference.items.len) {
                self.renderer._log.err("Invalid handle: {any}", .{reference});
                return &self.data[0];
            }
            const location: u32 = @intFromEnum(reference.id);
            assert(location < MAX_TEXTURES);
            if (self.handles[location].id == .null_handle) {
                self.renderer._log.err("Expired handle: {any}. Texture not available", .{reference});
                return &self.data[0];
            }
            self.reference_counts[location] += 1;
            return &self.data[location];
        }

        pub fn release(self: *Self, handle: TextureHandle) void {
            if (handle == .null_handle or handle == .missing_texture or handle == .base_colour) {
                self.renderer._log.err("Freeing static textures", .{});
                return;
            }
            const reference: TextureReference = @bitCast(@intFromEnum(handle));
            if (reference.id == .null_handle) {
                self.renderer._log.err("Freeing invalid texture", .{});
                return;
            }
            const location = @intFromEnum(reference.id);

            self.reference_counts[location] -= 1;

            if (self.reference_counts[location] == 0 and self.auto_release[location]) {
                // const texture = &self.items[location];

                self.renderer._backend.destroy_texture(&self.data[location]);

                self.handles[location].id = .null_handle;
                self.handles[location].generation = .null_handle;
                self.infos[location].has_transparency = 0;
                self.infos[location].channel_count = 0;
                self.infos[location].width = 0;
                self.infos[location].height = 0;

                assert(reference.string <= self.string_reference.items.len);
                const string_ref = self.string_reference.items[reference.string];
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

            const current_generation = texture.handle.generation;
            texture.handle.generation = .null_handle;

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

            texture.info.width = img.width;
            texture.info.height = img.height;
            texture.info.channel_count = required_channel_count;

            texture.data = self.renderer._backend.create_texture(
                img.width,
                img.height,
                required_channel_count,
                img.data,
            ) catch |err| {
                self.renderer._log.err("Unable to create texture: {s}", .{@errorName(err)});
                return false;
            };
            texture.info.has_transparency = @intFromBool(has_transparency);
            texture.handle.id = .null_handle;

            self.renderer._backend.destroy_texture(&old.data);

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
                self.handles[missing_texture].generation = .null_handle;
                self.handles[missing_texture].id = MissingTexture.id;
                self.uses[missing_texture] = .diffuse;

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
                missing_texture_info.has_transparency = 0;
                self.hash_map.put(MissingTextureName, MissingTexture) catch return error.InitFailed;
            }

            { // INFO: Default White Base Colour Texture
                self.renderer._log.debug("Creating base colour", .{});

                const base_colour = 1;
                self.handles[base_colour].generation = .null_handle;
                self.handles[base_colour].id = MissingTexture.id;
                self.uses[base_colour] = .diffuse;

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
                base_colour_info.has_transparency = 0;
                self.hash_map.put(MissingTextureName, MissingTexture) catch return error.InitFailed;
            }
        }

        test Self {
            std.debug.print("{any}\n", .{Self.default_hash});
        }
    };
}

const std = @import("std");
const assert = std.debug.assert;
const T = @import("types.zig");
const math = @import("../math/math.zig");
const image = @import("../image.zig");
const Renderer = @import("../renderer.zig").Renderer;
