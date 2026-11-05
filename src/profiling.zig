const std = @import("std");
const root = @import("root");

pub const Anchor = enum {
    renderer_end,
    renderer_prepare,
    renderer_bin,
    renderer_publish,
    renderer_wake,
    renderer_help,
    renderer_wait,
    renderer_copy,
    renderer_clear,
    renderer_draw_sprite,
    renderer_draw_textured_rectangle,
    renderer_draw_rectangle,
};

const configured = @hasDecl(root, "fracture_profiling");
const Config = if (configured) root.fracture_profiling else struct {};

pub const Handle = if (configured) ?Config.Tracer.TraceHandle else void;

/// Persistent renderer workers disable shared-tracer hooks on their own thread.
/// Parallel renderer anchor totals cover only work executed by the calling thread.
pub threadlocal var thread_enabled: bool = true;

/// Include an engine anchor's name in Config.Anchors to enable its instrumentation.
/// The tracer binding must stay unchanged until every active handle has ended.
pub inline fn begin(comptime anchor: Anchor) Handle {
    if (comptime !configured) return;
    if (comptime !@hasField(Config.Anchors, @tagName(anchor))) return null;
    if (!thread_enabled) return null;
    const tracer = Config.tracer orelse return null;
    return tracer.startTrace(@field(Config.Anchors, @tagName(anchor)));
}

pub inline fn end(handle: Handle) void {
    if (comptime !configured) return;
    if (handle) |trace| Config.tracer.?.end(&trace);
}

test "unconfigured handles need no storage" {
    if (configured) return error.SkipZigTest;
    const handle = begin(.renderer_draw_sprite);
    end(handle);
    try std.testing.expectEqual(void, Handle);
}
