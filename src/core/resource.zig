const T = @import("systems/types.zig");

pub const ResourceHandle = T.ResourceHandle;
pub const Generation = T.Generation;
pub const Handle = T.Handle;
pub const ResourceTypes = T.ResourceTypes;

pub const Textures = @import("systems/texture.zig").Textures;

pub const ResourceSystemConfig = struct {
    asset_path: []const u8,
    base_paths: [NumResources][]const u8,

    pub const NumResources = std.enums.directEnumArrayLen(T.ResourceTypes, 0);
};

const root = @import("root");
pub const resource_system_config: ResourceSystemConfig = if (@hasDecl(root, "config") and @hasDecl(root.config, "resource_system_config"))
    root.config.renderer_backend
else
    // TODO: Make path checking better
    ResourceSystemConfig{
        .asset_path = "./assets/",
        .base_paths = std.enums.directEnumArrayDefault(T.ResourceTypes, []const u8, "", 0, .{
            .text = "text/",
            .binary = "data/",
            .image = "textures/",
        }),
    };

// TODO: Does this need to be a system. I dont need to handle any custom types yet
pub const Resource = struct {
    tag: T.ResourceTypes,
    data: *anyopaque,

    pub const Config = union(T.ResourceTypes) {
        text: TextConfig,
        binary: BinaryConfig,
        image: ImageConfig,
    };

    pub const Error = error{FailedToLoadResource};

    pub fn load(
        self: *Resource,
        config: Config,
        allocator: std.mem.Allocator,
        name: []const u8,
    ) !void {
        var file_buffer: [512]u8 = undefined;
        switch (config) {
            .image => |img_config| {
                const base_path = resource_system_config.asset_path ++ resource_system_config.base_paths[@intFromEnum(ResourceTypes.image)];
                const img_resource: *image.Image = @ptrCast(@alignCast(self.data));
                const file = std.fmt.bufPrint(&file_buffer, base_path ++ "{s}.{s}", .{ name, @tagName(img_config.extension) }) catch unreachable;
                img_resource.* = switch (img_config.requested_image_type) {
                    .rgba => image.load(file, allocator, .{ .requested_channels = 4 }) catch {
                        return error.FailedToLoadResource;
                    },
                    .rgb => image.load(file, allocator, .{ .requested_channels = 3 }) catch {
                        return error.FailedToLoadResource;
                    },
                    .ga => image.load(file, allocator, .{ .requested_channels = 2 }) catch {
                        return error.FailedToLoadResource;
                    },
                    .g => image.load(file, allocator, .{ .requested_channels = 1 }) catch {
                        return error.FailedToLoadResource;
                    },
                };
                self.tag = .image;
            },
            else => unreachable,
        }
    }

    pub fn unload(
        self: *Resource,
    ) void {
        switch (self.tag) {
            .image => {},
            else => unreachable,
        }
    }

    pub const ImageConfig = struct {
        requested_image_type: ImageType = .rgba,
        extension: image.ImageFileType = .png,

        pub const ImageType = enum(u8) {
            rgba,
            rgb,
            g,
            ga,
        };
    };

    pub const TextConfig = void;
    pub const BinaryConfig = void;
};

const image = @import("image.zig");
const std = @import("std");
