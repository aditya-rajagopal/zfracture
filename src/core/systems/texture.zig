const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const root = @import("root");

const image = @import("../image.zig");
const Renderer = @import("../renderer.zig").Renderer;
const T = @import("types.zig");

pub const TextureSystemConfig = struct {
    /// The maximum number of textures that can be loaded at once
    max_textures_count: u32,
    /// The maximum dimension of a texture in pixels
    max_texture_dim: u32,

    pub const defualt: TextureSystemConfig = .{
        .max_textures_count = 4096,
        .max_texture_dim = 4096,
    };
};

const texture_system_config: TextureSystemConfig = if (@hasDecl(root, "config") and @hasDecl(root.config, "texture_system_config"))
    root.texture_system_config
else
    .defualt;

/// Renderer backend
pub const renderer_backend: type = if (@hasDecl(root, "config") and @hasDecl(root.config, "renderer_backend"))
    root.config.renderer_backend
else
    @compileError("No renderer backend defined in root.config");

pub const MAX_TEXTURES_COUNT = texture_system_config.max_textures_count;
pub const MAX_TEXTURE_DIM = texture_system_config.max_texture_dim;

/// The integer type used to store the dimension of the texture.
/// Most textures are not much larger than 16348 pixels in either dimension.
/// We can rethink this if we need to support textures larger than that.
pub const DimnsionType = u14;
comptime {
    assert(std.math.maxInt(DimnsionType) > MAX_TEXTURE_DIM);
}

pub const TextureInfo = packed struct(u32) {
    /// The width of the texture in pixels
    width: DimnsionType,
    /// The height of the texture in pixels
    height: DimnsionType,
    /// The number of channels in the texture stored as a u2. The actual number is channel_count + 1.
    channel_count: u2,
    /// Whether or not the texture should be automatically released when the last reference is released
    auto_release: bool,
    /// Whether or not the texture has transparency
    has_transparency: bool,

    pub const empty = TextureInfo{
        .width = 0,
        .height = 0,
        .channel_count = 0,
        .auto_release = false,
        .has_transparency = false,
    };

    pub inline fn get_channel_count(self: TextureInfo) u8 {
        return self.channel_count + 1;
    }
};

/// This defines the size of data in number of u64s that is used to store the texture data by the renderer backend.
/// This number should match the maximum of the size of different backends and must be kept in sync.
/// Vulkan backend: 5 u64s
pub const DataSize = 5;
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

pub const TextureRepresentation = u64;

/// An opaque handle to the texture that will be interpreted as TextureInternal by the texture system
pub const Texture = enum(TextureRepresentation) {
    null_handle = @bitCast(TextureInternal.null_handle),
    missing_texture = @bitCast(TextureInternal{
        .index = .missing_texture,
        .extra_data_location = std.math.maxInt(u32),
        ._reserved = 0,
    }),
    base_colour = @bitCast(TextureInternal{
        .index = .base_colour,
        .extra_data_location = std.math.maxInt(u32),
        ._reserved = 0,
    }),
    _,
};

pub const Index = enum(u16) {
    null_handle = std.math.maxInt(u16),
    missing_texture = 0,
    base_colour = 1,
    _,
};

const TextureInternal = packed struct(TextureRepresentation) {
    index: Index,
    extra_data_location: u32,
    _reserved: u16,

    pub const null_handle: TextureInternal = .{ .index = .null_handle, .extra_data_location = 0, ._reserved = 0 };
};

pub const TextureGeneration = T.Generation(u16);

pub const TextureHandle = extern struct {
    id: Index,
    generation: TextureGeneration,

    pub const null_handle = .{ .id = .null_handle, .generation = .null_handle };
};

pub const TextureCreateInfo = struct {
    /// The name of the texture
    name: []const u8,
    /// Whether to auto release the texture when the last reference is released
    auto_release: bool,
    /// The image type of the texture
    image_type: image.ImageType,
    /// Optionally provide an image to load into the texture
    img: ?image.Image,

    pub const default = TextureCreateInfo{
        .name = "",
        .auto_release = false,
        .image_type = .rgba,
        .images = .{ .diffuse = null },
    };
};

const RendererType = Renderer(renderer_backend);

pub const TextureSystem = struct {
    const Self = @This();

    /// The meta information about the textures
    /// TODO: Should this be decomposed into seperate fields?
    infos: [MAX_TEXTURES_COUNT]TextureInfo,
    /// The texture data stored anonymously for the backend to use.
    data: [MAX_TEXTURES_COUNT]Data,
    /// The reference count for each texture
    reference_counts: [MAX_TEXTURES_COUNT]u16,
    /// The texture generation
    generations: [MAX_TEXTURES_COUNT]TextureGeneration,

    /// Local memory arena for reading images,
    /// TODO: Cannot use this in mutilple threads
    image_arena: std.heap.ArenaAllocator,

    /// Reference to the frontend
    renderer: *RendererType,

    /// Storeage for strings
    /// Data is stored in this array such that the first 2 bytes are the length of the string.
    /// The string is stored in the array after the 2 bytes
    extra_data: std.ArrayList(u8),
    texture_map: TextureMap,

    pub const TextureMap = std.StringArrayHashMap(TextureInternal);

    pub fn init(self: *Self, renderer: *RendererType, allocator: Allocator) !void {
        self.renderer = renderer;

        @memset(&self.infos, .empty);
        @memset(&self.data, .{});
        @memset(&self.generations, @enumFromInt(0));
        @memset(&self.reference_counts, 0);

        try self.create_defaults();

        // TODO: Make a larger buffer for different threads
        self.image_arena = std.heap.ArenaAllocator.init(allocator);
        _ = try self.image_arena.allocator().alloc(u8, MAX_TEXTURE_DIM * MAX_TEXTURE_DIM * 4);
        _ = self.image_arena.reset(.retain_capacity);

        self.extra_data = try std.ArrayList(u8).initCapacity(allocator, 65536);
        self.texture_map = TextureMap.init(allocator);
        try self.texture_map.ensureTotalCapacity(1024);
    }

    pub fn deinit(self: *Self) void {
        for (self.infos, 0..) |info, i| {
            if (info != TextureInfo.empty) {
                self.renderer.destroy_texture(&self.data[i]);
            }
        }

        self.texture_map.deinit();
        self.extra_data.deinit();
        self.image_arena.deinit();
    }

    pub fn create(self: *Self, create_info: *const TextureCreateInfo) Texture {
        const result = self.texture_map.getOrPut(create_info.name) catch return .missing_texture;
        var string_location: u32 = 0;

        if (result.found_existing and result.value_ptr.index != .null_handle) {
            const location: u16 = @intFromEnum(result.value_ptr.index);
            self.reference_counts[location] += 1;
            return @enumFromInt(@as(u64, @bitCast(result.value_ptr.*)));
        } else {
            assert(create_info.name.len < std.math.maxInt(u16));

            const length: u16 = @truncate(create_info.name.len);
            const location_slice: [2]u8 = .{ @truncate(length), @truncate(length >> 8) };
            string_location = @truncate(self.extra_data.items.len);
            self.extra_data.appendSlice(location_slice[0..]) catch return .missing_texture;
            self.extra_data.appendSlice(create_info.name) catch return .missing_texture;
            result.key_ptr.* = self.extra_data.items[string_location + 2 .. string_location + 2 + length];
            result.value_ptr.* = .{
                .index = .null_handle,
                .extra_data_location = string_location,
                ._reserved = 0,
            };
        }

        var img: image.Image = undefined;
        if (create_info.img) |im| {
            img = im;
        } else {
            var file_buffer: [1024]u8 = undefined;
            // TODO: Figure out a way to get the file type configurable. For now we just use png
            const file = std.fmt.bufPrint(&file_buffer, "{s}.png", .{create_info.name}) catch return .missing_texture;
            img = switch (create_info.image_type) {
                .rgba => image.load(file, self.image_arena.allocator(), .{ .requested_channels = 4 }) catch |err| {
                    self.renderer._log.err("Unable to load texture image '{s}': {s}", .{ file, @errorName(err) });
                    return .missing_texture;
                },
                .rgb => image.load(file, self.image_arena.allocator(), .{ .requested_channels = 3 }) catch |err| {
                    self.renderer._log.err("Unable to load texture image '{s}': {s}", .{ file, @errorName(err) });
                    return .missing_texture;
                },
                .ga => image.load(file, self.image_arena.allocator(), .{ .requested_channels = 2 }) catch |err| {
                    self.renderer._log.err("Unable to load texture image '{s}': {s}", .{ file, @errorName(err) });
                    return .missing_texture;
                },
                .g => image.load(file, self.image_arena.allocator(), .{ .requested_channels = 1 }) catch |err| {
                    self.renderer._log.err("Unable to load texture image '{s}': {s}", .{ file, @errorName(err) });
                    return .missing_texture;
                },
            };
        }

        var location: u16 = 0;

        // NOTE(adi): Instead of keeping a list of free slots we just search for the first empty slot
        // We only need to check the info array which is a list of 32bit unsigned integers. So this should be fast to go
        // through.
        for (&self.infos, 0..) |*info, i| {
            if (info.* == TextureInfo.empty) {
                location = @truncate(i);
                info.* = .{
                    .width = @truncate(img.width),
                    .height = @truncate(img.height),
                    .channel_count = @truncate(img.channels),
                    .auto_release = create_info.auto_release,
                    .has_transparency = img.forced_transparency or create_info.image_type == .ga or create_info.image_type == .rgba,
                };
                break;
            }
        }

        if (location == 0) {
            self.renderer._log.err("Unable to find a free slot for the texture", .{});
            assert(false);
            return .missing_texture;
        }

        if (!self.load_texture(location, img)) {
            self.renderer._log.err("Unable to load texture", .{});
            return .missing_texture;
        }

        result.value_ptr.index = @enumFromInt(location);

        _ = self.image_arena.reset(.retain_capacity);

        // NOTE: When we crate a texture the caller has a reference to it. So we increment the reference count
        self.reference_counts[location] = 1;

        return @enumFromInt(@as(u64, @bitCast(result.value_ptr.*)));
    }

    fn load_texture(self: *Self, location: u16, img: image.Image) bool {
        // TODO: Revisit this to see if there is something that can be done to streamline this
        const current_generation = self.generations[location];
        self.generations[location] = .null_handle;

        var old_texture_data: Data = self.data[location];

        self.data[location] = self.renderer.create_texture(
            img.width,
            img.height,
            img.channels,
            img.data,
        ) catch |err| {
            self.renderer._log.err("Unable to create texture: {s}", .{@errorName(err)});
            return false;
        };

        self.renderer.destroy_texture(&old_texture_data);

        if (current_generation == .null_handle) {
            self.generations[location] = @enumFromInt(0);
        } else {
            self.generations[location] = current_generation.increment();
        }

        return true;
    }

    pub fn get_handle(self: *const Self, texture: Texture) TextureHandle {
        const reference: TextureInternal = @bitCast(@intFromEnum(texture));
        const location: u16 = @intFromEnum(reference.index);

        if (self.infos[location] == TextureInfo.empty or location >= MAX_TEXTURES_COUNT) {
            self.renderer._log.err("Invalid texture handle: {any}", .{reference});
            return .{ .id = .missing_texture, .generation = @enumFromInt(0) };
        }
        return .{ .id = reference.index, .generation = self.generations[location] };
    }

    pub fn acquire(self: *Self, texture: Texture) *const Data {
        const reference: TextureInternal = @bitCast(@intFromEnum(texture));
        const location: u16 = @intFromEnum(reference.index);

        if (self.infos[location] == TextureInfo.empty or location >= MAX_TEXTURES_COUNT) {
            self.renderer._log.err("Invalid handle: {any}", .{reference});
            return &self.data[0];
        }

        self.reference_counts[location] += 1;
        return &self.data[location];
    }

    pub fn release(self: *Self, texture: Texture) void {
        if (texture == .missing_texture or texture == .base_colour) {
            return;
        }

        const reference: TextureInternal = @bitCast(@intFromEnum(texture));
        const location: u16 = @intFromEnum(reference.index);

        if (self.infos[location] == TextureInfo.empty or location >= MAX_TEXTURES_COUNT) {
            self.renderer._log.err("Freeing invalid texture", .{});
            return;
        }

        if (self.reference_counts[location] == 0) {
            self.renderer._log.err("Freeing texture with 0 reference count", .{});
            return;
        }

        self.reference_counts[location] -= 1;

        if (self.reference_counts[location] == 0 and self.infos[location].auto_release) {
            self.renderer.destroy_texture(&self.data[location]);
            self.infos[location] = .empty;
            self.generations[location] = .null_handle;
            self.reference_counts[location] = 0;

            // Set the index in the map to null so we know the texture name has no data in the texture pool
            const string_location: u32 = reference.extra_data_location;
            const length: u16 = @bitCast(self.extra_data.items[string_location .. string_location + 2][0..2].*);
            const key = self.extra_data.items[string_location + 2 .. string_location + 2 + length];
            const result = self.texture_map.getPtr(key) orelse unreachable;
            result.index = .null_handle;
        }
    }

    pub fn reload_texture(self: *Self, texture: Texture) bool {
        _ = self;
        _ = texture;
        @compileError("NOT IMPLEMENTED");
    }

    pub fn replace_texture(self: *Self, texture: Texture, new_texture: []const u8) Texture {
        _ = self;
        _ = texture;
        _ = new_texture;
        @compileError("NOT IMPLEMENTED");
    }

    fn create_defaults(self: *Self) !void {
        { // INFO: Default Missing Texture
            self.renderer._log.debug("Creating missing texture", .{});

            const missing_texture_id = 0;

            const texture_dim = 1;
            const channels = 4;
            const pixels = [4]u8{ 255, 0, 255, 255 };

            self.data[missing_texture_id] = self.renderer.create_texture(
                texture_dim,
                texture_dim,
                channels,
                &pixels,
            ) catch {
                self.renderer._log.err("Unable to load default missing texture", .{});
                return error.InitFailed;
            };
            self.infos[missing_texture_id] = .{
                .width = 1,
                .height = 1,
                .channel_count = 3,
                .auto_release = false,
                .has_transparency = false,
            };
        }

        { // INFO: Default White Base Colour Texture
            self.renderer._log.debug("Creating base colour", .{});

            const base_colour_id = 1;

            const texture_dim = 1;
            const channels = 4;
            const pixels = [4]u8{ 255, 255, 255, 255 };

            self.data[base_colour_id] = self.renderer.create_texture(
                texture_dim,
                texture_dim,
                channels,
                &pixels,
            ) catch {
                self.renderer._log.err("Unable to load default missing texture", .{});
                return error.InitFailed;
            };
            self.infos[base_colour_id] = .{
                .width = 1,
                .height = 1,
                .channel_count = 3,
                .auto_release = false,
                .has_transparency = false,
            };
        }
    }
};
