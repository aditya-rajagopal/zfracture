//! Static terrain for the 2D mechanics testbed.
//! From game.zig, select a map with @import("levels/open_arena.zig").level.
//! Other maps: cover_arena.zig and connected_rooms.zig.
//! Tile IDs: 0 = void, 1 = floor, 2 = wall. ID 3 is reserved for a future portal.
//! Each map defines its terrain and player entry tile.

pub const Level = struct {
    width: u32,
    height: u32,
    /// Row-major tiles: tiles[y * width + x]. Origin is the top-left corner;
    /// x increases to the right and y increases downward.
    tiles: []const u8,
    /// Safe floor tile for entry. Place the player's center at (x + 0.5, y + 0.5).
    start: struct { x: u32, y: u32 },
};

pub const test_levels = [_]Level{
    @import("open_arena.zig").level,
    @import("cover_arena.zig").level,
    @import("connected_rooms.zig").level,
};

comptime {
    for (test_levels) |level| {
        if (level.start.x >= level.width or level.start.y >= level.height)
            @compileError("Level start must be inside the map");
        if (level.tiles[level.start.y * level.width + level.start.x] != 1)
            @compileError("Level start must be on a floor tile");
    }
}
