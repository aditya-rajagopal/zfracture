const std = @import("std");
const objc = @import("objc");
const c = @import("macos-c");
const Platform = @import("../platform.zig");
const appkit = @import("appkit.zig");
const Renderer = @import("../software_renderer.zig");
const event_types = @import("../event.zig");
const Key = event_types.Key;
const Event = event_types.Event;
const MouseButton = event_types.MouseButton;
const max_messages_per_frame = 4096;
const Object = objc.Object;
const Rect = c.CGRect;
const Point = c.CGPoint;

const window_style: appkit.NSWindowStyleMask = .{
    .titled = true,
    .closable = true,
    .miniaturizable = true,
    .resizable = true,
};
const nil: objc.c.id = null;

const platform_ivar = "_fracturePlatform";
// General-purpose waits can overshoot by about 1 ms on macOS. Usually only
// the final ~0.5 ms spins; 1.5 ms is the bound when the wait wakes on time.
const spin_margin_ns = 1500 * std.time.ns_per_us;

pub const State = struct {
    application: Object = undefined,
    window: Object = undefined,
    view: Object = undefined,
    delegate: Object = undefined,
    bitmap_context: c.CGContextRef = undefined,
    event_storage: [2][1024]Event = undefined,
    event_lists: [2]std.ArrayList(Event) = undefined,
    pending_event_buffer: u1 = 0,
    back_buffer: *Renderer.FrameBuffer = undefined,
    // NOTE(adi): We store a snapshot of the framebuffer that was bound when the CGBitmapContext was created.
    // If the back buffer changes we need to reflect that in the bound_frame_buffer.
    bound_frame_buffer: Renderer.FrameBuffer = undefined,
    window_placement: Rect = std.mem.zeroes(Rect),
    presentation_options: appkit.NSApplicationPresentationOptions = .{},
    fullscreen: bool = false,
    quit_requested: bool = false,
    tracking_window: bool = false,
    focused: bool = false,
    moving_window: bool = false,
    reset_frame_clock: bool = false,
    cursor_requested_hidden: bool = true,
    cursor_hidden: bool = false,
    native_mouse_buttons: [5]bool = @splat(false),
    client_mouse_buttons: [5]bool = @splat(false),
    keys_by_code: [128]?Key = @splat(null),

    outer_pool: ?*objc.AutoreleasePool = null,
    frame_pool: ?*objc.AutoreleasePool = null,
    windowed_frame_margin: u16 = 10,

    const Self = @This();

    pub fn init(self: *Self) InitError!void {
        std.debug.assert(objc.getClass("NSThread").?.msgSend(bool, "isMainThread", .{}));
        self.* = .{};
        self.outer_pool = objc.AutoreleasePool.init();
    }

    pub fn deinit(self: *Self) void {
        std.debug.assert(self.frame_pool == null);
        self.outer_pool.?.deinit();
        self.outer_pool = null;
    }

    pub fn beginFrame(self: *Self) void {
        std.debug.assert(self.outer_pool != null);
        std.debug.assert(self.frame_pool == null);
        self.frame_pool = objc.AutoreleasePool.init();
    }

    pub fn endFrame(self: *Self) void {
        std.debug.assert(self.outer_pool != null);
        self.frame_pool.?.deinit();
        self.frame_pool = null;
    }

    pub fn waitUntil(_: *Self, io: std.Io, deadline: std.Io.Timestamp) WaitError!void {
        const now = std.Io.Clock.awake.now(io);
        const remaining_ns = @as(i128, deadline.nanoseconds) - now.nanoseconds;
        if (remaining_ns <= 0) return;
        if (remaining_ns > spin_margin_ns) {
            const wake = std.Io.Timestamp.fromNanoseconds(deadline.nanoseconds - spin_margin_ns);
            try wake.withClock(.awake).wait(io);
            // paceFrame rechecks the original deadline and cancellation after sleeping.
            return;
        }
        // Only spin inside the final <=1.5 ms margin.
        while (std.Io.Clock.awake.now(io).nanoseconds < deadline.nanoseconds) {
            std.atomic.spinLoopHint();
        }
    }

    pub fn pollEvents(self: *Self) Platform.WindowStatus {
        pumpMessages(self, max_messages_per_frame);
        self.updateCursor();
        return self.takeWindowStatus();
    }

    fn takeWindowStatus(self: *Self) Platform.WindowStatus {
        const active = self.tracking_window;
        var ended = false;
        if (!active) {
            ended = self.reset_frame_clock;
            self.reset_frame_clock = false;
        }
        return .{
            .quit_requested = self.quit_requested,
            .native_interaction_active = active,
            .interaction_ended = ended,
        };
    }

    pub fn setCursorHidden(self: *Self, hidden: bool) void {
        self.cursor_requested_hidden = hidden;
        self.updateCursor();
    }

    // The slice stays immutable until the next handoff. Native callbacks append to the other list.
    pub fn takeEvents(self: *Self) []const Event {
        const ready = self.pending_event_buffer;
        const next = ready ^ 1;
        self.event_lists[next].clearRetainingCapacity();
        self.pending_event_buffer = next;
        return self.event_lists[ready].items;
    }

    // Initialize in place: the view and delegate borrow this address until teardown.
    pub fn createWindow(self: *Self, config: Platform.WindowConfig) CreateWindowError!void {
        const title = config.title;
        const back_buffer = config.frame_buffer;
        try registerClasses();
        const application_class = objc.getClass("FractureApplication").?;
        const application = application_class.msgSend(Object, "sharedApplication", .{});
        if (!application.msgSend(bool, "isKindOfClass:", .{application_class})) {
            return error.IncompatibleApplicationClass;
        }
        const activation_policy = application.msgSend(
            appkit.NSApplicationActivationPolicy,
            "activationPolicy",
            .{},
        );
        if (activation_policy != .regular) {
            const activated = application.msgSend(
                bool,
                "setActivationPolicy:",
                .{appkit.NSApplicationActivationPolicy.regular},
            );
            if (!activated) return error.FailedToActivateApplication;
        }
        const buffer_width: f64 = @floatFromInt(back_buffer.width);
        const window_width = buffer_width + 2 * @as(f64, @floatFromInt(config.windowed_frame_margin));
        const buffer_height: f64 = @floatFromInt(back_buffer.height);
        const window_height = buffer_height + 2 * @as(f64, @floatFromInt(config.windowed_frame_margin));
        const frame = makeRect(0, 0, window_width, window_height);

        const window_allocated = objc.getClass("FractureWindow").?.msgSend(Object, "alloc", .{});
        const window = window_allocated.msgSend(
            Object,
            "initWithContentRect:styleMask:backing:defer:",
            .{
                frame,
                @as(usize, @bitCast(window_style)),
                appkit.NSBackingStoreType.buffered,
                false,
            },
        );
        if (window.value == null) return error.FailedToCreateWindow;
        errdefer window.release();

        window.msgSend(void, "setReleasedWhenClosed:", .{false});
        window.msgSend(void, "setTitle:", .{nsString(title)});
        const color_space_class = objc.getClass("NSColorSpace").?;
        const window_color_space = color_space_class.msgSend(Object, "sRGBColorSpace", .{});
        window.msgSend(void, "setColorSpace:", .{window_color_space});
        window.msgSend(void, "setAcceptsMouseMovedEvents:", .{true});

        // Opt out of AppKit's separate fullscreen Space; Option+Enter is borderless fullscreen.
        const collection_behavior: appkit.NSWindowCollectionBehavior = .{ .fullscreen_none = true };
        window.msgSend(
            void,
            "setCollectionBehavior:",
            .{@as(usize, @bitCast(collection_behavior))},
        );
        window.msgSend(void, "setTabbingMode:", .{appkit.NSWindowTabbingMode.disallowed});
        window.msgSend(void, "center", .{});

        const view_allocated = objc.getClass("FractureView").?.msgSend(Object, "alloc", .{});
        const view = view_allocated.msgSend(Object, "initWithFrame:", .{frame});
        if (view.value == null) return error.FailedToCreateView;
        errdefer view.release();

        const autoresizing: appkit.NSAutoresizingMask = .{
            .width_sizable = true,
            .height_sizable = true,
        };
        view.msgSend(void, "setAutoresizingMask:", .{@as(usize, @bitCast(autoresizing))});
        window.msgSend(void, "setContentView:", .{view});
        _ = window.msgSend(bool, "makeFirstResponder:", .{view});

        const delegate_class = objc.getClass("FractureDelegate").?;
        const delegate = delegate_class.msgSend(Object, "alloc", .{}).msgSend(Object, "init", .{});
        if (delegate.value == null) return error.FailedToCreateDelegate;
        errdefer delegate.release();
        window.msgSend(void, "setDelegate:", .{delegate});
        application.msgSend(void, "setDelegate:", .{delegate});
        errdefer {
            window.msgSend(void, "setDelegate:", .{nil});
            application.msgSend(void, "setDelegate:", .{nil});
        }
        installMenu(application, title);

        const color_space = c.CGColorSpaceCreateWithName(c.kCGColorSpaceSRGB) orelse
            return error.FailedToCreateColorSpace;
        defer c.CGColorSpaceRelease(color_space);
        const bitmap_context = c.CGBitmapContextCreate(
            back_buffer.data.ptr,
            back_buffer.width,
            back_buffer.height,
            8,
            @as(usize, back_buffer.width) * 4,
            color_space,
            c.kCGBitmapByteOrder32Little | c.kCGImageAlphaNoneSkipFirst,
        ) orelse return error.FailedToCreateBitmapContext;

        self.* = .{
            .application = application,
            .window = window,
            .view = view,
            .delegate = delegate,
            .bitmap_context = bitmap_context,
            .back_buffer = back_buffer,
            .bound_frame_buffer = back_buffer.*,
            .outer_pool = self.outer_pool,
            .frame_pool = self.frame_pool,
            .windowed_frame_margin = config.windowed_frame_margin,
        };

        for (&self.event_lists, &self.event_storage) |*list, *storage| {
            list.* = std.ArrayList(Event).initBuffer(storage);
        }

        // These are raw pointers, not retained Objective-C objects. Bind only
        // after the platform is ready for callbacks, including finishLaunching.
        _ = objc.c.object_setInstanceVariable(application.value, platform_ivar, self);
        _ = objc.c.object_setInstanceVariable(view.value, platform_ivar, self);
        _ = objc.c.object_setInstanceVariable(delegate.value, platform_ivar, self);
        application.msgSend(void, "finishLaunching", .{});
    }

    pub fn showWindow(self: *Self) void {
        self.window.msgSend(void, "makeKeyAndOrderFront:", .{nil});
        self.application.msgSend(void, "activateIgnoringOtherApps:", .{true});
    }

    pub fn destroyWindow(self: *Self) void {
        // AppKit may retain these objects or call them while closing the window.
        // Detach before any native teardown can reenter callbacks.
        _ = objc.c.object_setInstanceVariable(self.application.value, platform_ivar, null);
        _ = objc.c.object_setInstanceVariable(self.view.value, platform_ivar, null);
        _ = objc.c.object_setInstanceVariable(self.delegate.value, platform_ivar, null);

        self.applyCursorHidden(false);
        if (self.fullscreen) {
            self.application.msgSend(
                void,
                "setPresentationOptions:",
                .{@as(usize, @bitCast(self.presentation_options))},
            );
        }

        self.window.msgSend(void, "setDelegate:", .{nil});
        if (self.application.msgSend(Object, "delegate", .{}).value == self.delegate.value) {
            self.application.msgSend(void, "setDelegate:", .{nil});
        }

        self.window.msgSend(void, "close", .{});
        self.window.release();
        self.view.release();
        self.delegate.release();
        c.CGContextRelease(self.bitmap_context);
    }

    pub fn toggleFullscreen(self: *Self) void {
        if (!self.fullscreen) {
            const screen = self.window.msgSend(Object, "screen", .{});
            if (screen.value == null) return;

            self.window_placement = self.window.msgSend(Rect, "frame", .{});
            self.presentation_options = @bitCast(
                self.application.msgSend(usize, "presentationOptions", .{}),
            );
            self.fullscreen = true;

            const presentation: appkit.NSApplicationPresentationOptions = .{
                .hide_dock = true,
                .hide_menu_bar = true,
            };
            self.application.msgSend(
                void,
                "setPresentationOptions:",
                .{@as(usize, @bitCast(presentation))},
            );

            self.window.msgSend(
                void,
                "setStyleMask:",
                .{@as(usize, @bitCast(appkit.NSWindowStyleMask.borderless))},
            );
            self.window.msgSend(
                void,
                "setFrame:display:",
                .{ screen.msgSend(Rect, "frame", .{}), true },
            );
        } else {
            self.fullscreen = false;
            self.application.msgSend(
                void,
                "setPresentationOptions:",
                .{@as(usize, @bitCast(self.presentation_options))},
            );

            self.window.msgSend(void, "setStyleMask:", .{@as(usize, @bitCast(window_style))});
            self.window.msgSend(void, "setFrame:display:", .{ self.window_placement, true });
        }

        self.window.msgSend(void, "makeKeyAndOrderFront:", .{nil});
        _ = self.window.msgSend(bool, "makeFirstResponder:", .{self.view});
    }

    pub fn present(self: *Self) void {
        if (self.window.msgSend(bool, "isMiniaturized", .{})) return;

        self.view.msgSend(void, "setNeedsDisplay:", .{true});
        self.view.msgSend(void, "displayIfNeeded", .{});
        self.application.msgSend(void, "updateWindows", .{});
    }

    fn beginWindowTracking(self: *Self) void {
        self.tracking_window = true;
        self.applyCursorHidden(false);
    }

    fn endWindowTracking(self: *Self) void {
        self.tracking_window = false;
        self.moving_window = false;
        self.reset_frame_clock = true;
    }

    fn applyCursorHidden(self: *Self, hidden: bool) void {
        if (self.cursor_hidden == hidden) return;

        const cursor = objc.getClass("NSCursor").?;
        if (hidden) cursor.msgSend(void, "hide", .{}) else cursor.msgSend(void, "unhide", .{});
        self.cursor_hidden = hidden;
    }

    fn updateCursor(self: *Self) void {
        const window_point = self.window.msgSend(Point, "mouseLocationOutsideOfEventStream", .{});
        const point = self.view.msgSend(Point, "convertPoint:fromView:", .{ window_point, nil });
        const bounds = self.view.msgSend(Rect, "bounds", .{});
        const inside = point.x >= 0 and point.y >= 0 and
            point.x < bounds.size.width and point.y < bounds.size.height;

        const capture_cursor = !self.tracking_window and self.cursor_requested_hidden and inside;
        const focused = capture_cursor and self.window.msgSend(bool, "isKeyWindow", .{});
        const hide_cursor = focused and self.application.msgSend(bool, "isActive", .{});
        self.applyCursorHidden(hide_cursor);
    }
};

fn nsString(value: [:0]const u8) Object {
    return objc.getClass("NSString").?.msgSend(Object, "stringWithUTF8String:", .{value.ptr});
}

fn makeRect(x: f64, y: f64, width: f64, height: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = width, .height = height } };
}

fn registerClasses() !void {
    // The runtime takes log2(alignment); ^v describes an unowned void pointer.
    const pointer_alignment = std.math.log2_int(usize, @alignOf(?*State));

    if (objc.getClass("FractureApplication") == null) {
        const class = objc.allocateClassPair(objc.getClass("NSApplication").?, "FractureApplication") orelse
            return error.FailedToRegisterClass;
        errdefer objc.disposeClassPair(class);
        const added = objc.c.class_addIvar(class.value, platform_ivar, @sizeOf(?*State), pointer_alignment, "^v");
        if (added == 0) return error.FailedToRegisterIvar;
        if (!class.addMethod("sendEvent:", sendEvent)) return error.FailedToRegisterMethod;
        objc.registerClassPair(class);
    }

    if (objc.getClass("FractureWindow") == null) {
        const class = objc.allocateClassPair(
            objc.getClass("NSWindow").?,
            "FractureWindow",
        ) orelse return error.FailedToRegisterClass;
        errdefer objc.disposeClassPair(class);

        if (!class.addMethod("canBecomeKeyWindow", nativeTrue)) return error.FailedToRegisterMethod;
        objc.registerClassPair(class);
    }

    if (objc.getClass("FractureView") == null) {
        const class = objc.allocateClassPair(
            objc.getClass("NSView").?,
            "FractureView",
        ) orelse return error.FailedToRegisterClass;
        errdefer objc.disposeClassPair(class);

        const ivar_added = objc.c.class_addIvar(
            class.value,
            platform_ivar,
            @sizeOf(?*State),
            pointer_alignment,
            "^v",
        );
        if (ivar_added == 0) return error.FailedToRegisterIvar;

        if (!class.addMethod("isFlipped", nativeTrue)) return error.FailedToRegisterMethod;
        if (!class.addMethod("isOpaque", nativeTrue)) return error.FailedToRegisterMethod;
        if (!class.addMethod("acceptsFirstResponder", nativeTrue)) {
            return error.FailedToRegisterMethod;
        }
        if (!class.addMethod("drawRect:", drawRect)) return error.FailedToRegisterMethod;

        objc.registerClassPair(class);
    }

    if (objc.getClass("FractureDelegate") == null) {
        const class = objc.allocateClassPair(
            objc.getClass("NSObject").?,
            "FractureDelegate",
        ) orelse return error.FailedToRegisterClass;
        errdefer objc.disposeClassPair(class);

        const ivar_added = objc.c.class_addIvar(
            class.value,
            platform_ivar,
            @sizeOf(?*State),
            pointer_alignment,
            "^v",
        );
        if (ivar_added == 0) return error.FailedToRegisterIvar;

        if (!class.addMethod("windowShouldClose:", windowShouldClose)) {
            return error.FailedToRegisterMethod;
        }
        if (!class.addMethod("applicationShouldTerminate:", applicationShouldTerminate)) {
            return error.FailedToRegisterMethod;
        }

        if (!class.addMethod("windowDidBecomeKey:", didGainFocus)) return error.FailedToRegisterMethod;
        if (!class.addMethod("applicationDidBecomeActive:", didGainFocus)) return error.FailedToRegisterMethod;
        if (!class.addMethod("windowDidResignKey:", didResignFocus)) {
            return error.FailedToRegisterMethod;
        }
        if (!class.addMethod("applicationDidResignActive:", didResignFocus)) {
            return error.FailedToRegisterMethod;
        }

        if (!class.addMethod("windowWillMove:", windowWillMove)) {
            return error.FailedToRegisterMethod;
        }
        if (!class.addMethod("windowWillStartLiveResize:", windowWillStartLiveResize)) {
            return error.FailedToRegisterMethod;
        }
        if (!class.addMethod("windowDidEndLiveResize:", windowDidEndLiveResize)) {
            return error.FailedToRegisterMethod;
        }

        objc.registerClassPair(class);
    }
}

fn nativeTrue(_: objc.c.id, _: objc.c.SEL) callconv(.c) bool {
    return true;
}

fn platformForCallback(receiver: objc.c.id) ?*State {
    var pointer: ?*anyopaque = null;
    _ = objc.c.object_getInstanceVariable(receiver, platform_ivar, &pointer);
    return @ptrCast(@alignCast(pointer));
}

fn windowShouldClose(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) bool {
    if (platformForCallback(receiver)) |platform| platform.quit_requested = true;
    return false; // The Zig loop owns teardown.
}

fn applicationShouldTerminate(
    receiver: objc.c.id,
    _: objc.c.SEL,
    _: objc.c.id,
) callconv(.c) c_ulong {
    if (platformForCallback(receiver)) |platform| platform.quit_requested = true;
    // Finish the loop and release engine resources before terminating.
    // TODO: NSTerminateCancel also cancels macOS logout/restart/shutdown.
    // Coordinate AppKit termination with Zig cleanup before accepting termination.
    // NSTerminateLater alone blocks the outer loop from reaching its cleanup.
    return @backingInt(appkit.NSApplicationTerminateReply.cancel);
}

fn didGainFocus(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    const key_window = platform.window.msgSend(bool, "isKeyWindow", .{});
    platform.focused = key_window and platform.application.msgSend(bool, "isActive", .{});
}

fn didResignFocus(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    if (!platform.focused) return;
    platform.focused = false;
    platform.event_lists[platform.pending_event_buffer].appendBounded(.reset_all) catch
        @panic("event buffer overflow");
    platform.native_mouse_buttons = @splat(false);
    platform.client_mouse_buttons = @splat(false);
    platform.keys_by_code = @splat(null);
    platform.applyCursorHidden(false);
}

fn windowWillMove(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    platform.moving_window = true;
    platform.beginWindowTracking();
}

fn windowWillStartLiveResize(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    platform.beginWindowTracking();
}

fn windowDidEndLiveResize(receiver: objc.c.id, _: objc.c.SEL, _: objc.c.id) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    platform.endWindowTracking();
}

fn drawRect(receiver: objc.c.id, _: objc.c.SEL, _: Rect) callconv(.c) void {
    const platform = platformForCallback(receiver) orelse return;
    // AppKit can draw during event handling as well as an explicit present call.
    const buffer = platform.back_buffer;
    std.debug.assert(buffer.width == platform.bound_frame_buffer.width);
    std.debug.assert(buffer.height == platform.bound_frame_buffer.height);
    std.debug.assert(buffer.data.ptr == platform.bound_frame_buffer.data.ptr);
    const required_bytes = @as(usize, buffer.width) * buffer.height * Renderer.bytes_per_pixel;
    std.debug.assert(buffer.data.len >= required_bytes);

    const graphics = objc.getClass("NSGraphicsContext").?.msgSend(Object, "currentContext", .{});
    const context = graphics.msgSend(c.CGContextRef, "CGContext", .{});
    const bounds = platform.view.msgSend(Rect, "bounds", .{});
    if (bounds.size.width <= 0 or bounds.size.height <= 0) return;

    c.CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    c.CGContextFillRect(context, bounds);

    // Release the snapshot before Zig writes the next frame. Drawing and updates share one thread.
    const image = c.CGBitmapContextCreateImage(platform.bitmap_context) orelse return;
    defer c.CGImageRelease(image);
    const dest = if (platform.fullscreen) bounds else makeRect(
        @floatFromInt(platform.windowed_frame_margin),
        @floatFromInt(platform.windowed_frame_margin),
        @floatFromInt(buffer.width),
        @floatFromInt(buffer.height),
    );

    c.CGContextSaveGState(context);
    defer c.CGContextRestoreGState(context);
    c.CGContextSetInterpolationQuality(context, c.kCGInterpolationNone);
    c.CGContextTranslateCTM(context, dest.origin.x, dest.origin.y + dest.size.height);
    c.CGContextScaleCTM(context, 1, -1);
    c.CGContextDrawImage(context, makeRect(0, 0, dest.size.width, dest.size.height), image);
}

fn installMenu(application: Object, title: [:0]const u8) void {
    const menu_class = objc.getClass("NSMenu").?;
    const item_class = objc.getClass("NSMenuItem").?;

    const menu_allocated = menu_class.msgSend(Object, "alloc", .{});
    const menu = menu_allocated.msgSend(Object, "initWithTitle:", .{nsString(title)});
    defer menu.release();

    const root_allocated = item_class.msgSend(Object, "alloc", .{});
    const root = root_allocated.msgSend(
        Object,
        "initWithTitle:action:keyEquivalent:",
        .{ nsString(title), @as(objc.c.SEL, null), nsString("") },
    );
    defer root.release();

    const submenu_allocated = menu_class.msgSend(Object, "alloc", .{});
    const submenu = submenu_allocated.msgSend(Object, "initWithTitle:", .{nsString(title)});
    defer submenu.release();

    const quit_allocated = item_class.msgSend(Object, "alloc", .{});
    const quit = quit_allocated.msgSend(
        Object,
        "initWithTitle:action:keyEquivalent:",
        .{ nsString("Quit"), objc.sel("terminate:"), nsString("") },
    );
    defer quit.release();
    quit.msgSend(void, "setTarget:", .{application});

    submenu.msgSend(void, "addItem:", .{quit});
    root.msgSend(void, "setSubmenu:", .{submenu});
    menu.msgSend(void, "addItem:", .{root});
    application.msgSend(void, "setMainMenu:", .{menu});
}

fn pumpMessages(platform: *State, budget: usize) void {
    std.debug.assert(budget <= max_messages_per_frame);
    if (platform.quit_requested) return;

    const date = objc.getClass("NSDate").?.msgSend(Object, "distantPast", .{});
    const mode = nsString("kCFRunLoopDefaultMode");

    // Bound event work so continuous input cannot starve a frame.
    for (0..budget) |_| {
        // WindowServer can drag a title bar without a blocking AppKit loop.
        // didMove can fire more than once, so wait for the initiating button up.
        const left_button_mask = @as(usize, 1) << @backingInt(MouseButton.left);
        if (platform.moving_window) {
            const event_class = objc.getClass("NSEvent").?;
            const pressed_buttons = event_class.msgSend(usize, "pressedMouseButtons", .{});
            const left_released = (pressed_buttons & left_button_mask) == 0;
            const move_finished = left_released and
                !platform.window.msgSend(bool, "inLiveResize", .{});
            if (move_finished) platform.endWindowTracking();
        }

        const event = platform.application.msgSend(
            Object,
            "nextEventMatchingMask:untilDate:inMode:dequeue:",
            .{
                appkit.NSEventMaskAny, date, mode, true,
            },
        );
        if (event.value == null or platform.quit_requested) break;

        platform.application.msgSend(void, "sendEvent:", .{event});
        if (platform.quit_requested) break;
    }
}

// One producer path also covers AppKit dispatch invoked outside our explicit pump.
fn sendEvent(receiver: objc.c.id, _: objc.c.SEL, raw_event: objc.c.id) callconv(.c) void {
    const application: Object = .{ .value = receiver };
    const event: Object = .{ .value = raw_event };

    if (platformForCallback(receiver)) |platform| {
        if (platform.quit_requested) return;
        const event_window = event.msgSend(Object, "window", .{});

        if (event_window.value == platform.window.value) {
            const event_type = event.msgSend(appkit.NSEventType, "type", .{});
            const button_press = event_type == .left_mouse_down or
                event_type == .right_mouse_down or event_type == .other_mouse_down;
            var client_press = false;

            const key_window = platform.window.msgSend(bool, "isKeyWindow", .{});
            const is_active = application.msgSend(bool, "isActive", .{});

            if (button_press) {
                client_press = eventInsideView(platform, event);
                if (client_press) {
                    if (!key_window) {
                        platform.window.msgSend(void, "makeKeyAndOrderFront:", .{nil});
                    }
                    if (!is_active) {
                        application.msgSend(void, "activateIgnoringOtherApps:", .{true});
                    }
                }
            }
            const active = key_window and is_active;
            if (client_press or active) {
                if (active) platform.focused = true;
                if (processEvent(platform, event, event_type)) return;
            }
        }
    }
    application.msgSendSuper(objc.getClass("NSApplication").?, void, "sendEvent:", .{event});
}

// Translate game input; false leaves the event for AppKit's native dispatch.
fn processEvent(platform: *State, event: Object, event_type: appkit.NSEventType) bool {
    switch (event_type) {
        .key_down, .key_up => {
            const code = event.msgSend(appkit.VirtualKeyCode, "keyCode", .{});
            const index = @backingInt(code);
            const down = event_type == .key_down;

            // Remember the logical key so changing layouts while held cannot
            // send its release to a different key. Command follows this path too.
            const cached = if (index < platform.keys_by_code.len)
                platform.keys_by_code[index]
            else
                null;
            if (cached orelse keyFromEvent(event, code)) |key| {
                const repeat = down and event.msgSend(bool, "isARepeat", .{});
                const translated: Event = if (!down)
                    .{ .key_released = key }
                else if (repeat)
                    .{ .key_repeat = key }
                else
                    .{ .key_pressed = key };
                platform.event_lists[platform.pending_event_buffer].appendBounded(translated) catch
                    @panic("event buffer overflow");
                if (index < platform.keys_by_code.len) {
                    platform.keys_by_code[index] = if (down) key else null;
                }
            }
            return true;
        },
        .flags_changed => {
            updateModifiers(
                platform,
                event.msgSend(appkit.VirtualKeyCode, "keyCode", .{}),
                event.msgSend(usize, "modifierFlags", .{}),
            );
            return true;
        },
        .left_mouse_down,
        .left_mouse_up,
        .right_mouse_down,
        .right_mouse_up,
        .other_mouse_down,
        .other_mouse_up,
        => {
            const button = event.msgSend(isize, "buttonNumber", .{});
            if (button < 0 or button >= 5) return false;

            const mapped: MouseButton = @fromBackingInt(@as(u8, @intCast(button)));
            const down = event_type == .left_mouse_down or
                event_type == .right_mouse_down or event_type == .other_mouse_down;

            // AppKit must receive title-bar/control clicks and their matching releases.
            // A release from a game click is still recorded after dragging outside the view.
            const index: usize = @intCast(button);
            if (down and !eventInsideView(platform, event)) {
                platform.native_mouse_buttons[index] = true;
                return false;
            }
            if (!down and platform.native_mouse_buttons[index]) {
                platform.native_mouse_buttons[index] = false;
                return false;
            }

            const unmatched_release = !down and !platform.client_mouse_buttons[index];
            if (unmatched_release and !eventInsideView(platform, event)) {
                return false;
            }

            if (down) platform.native_mouse_buttons[index] = false;
            const position = mousePosition(platform, event);
            platform.client_mouse_buttons[index] = down;
            const translated: Event = if (down)
                .{ .mouse_pressed = .{ .button = mapped, .pos = position } }
            else
                .{ .mouse_released = .{ .button = mapped, .pos = position } };
            platform.event_lists[platform.pending_event_buffer].appendBounded(translated) catch
                @panic("event buffer overflow");
            return true;
        },
        .mouse_moved, .left_mouse_dragged, .right_mouse_dragged, .other_mouse_dragged => {
            const dragging = std.mem.indexOfScalar(bool, &platform.client_mouse_buttons, true) != null;
            if (!dragging and !eventInsideView(platform, event)) return false;
            const position = mousePosition(platform, event);
            platform.event_lists[platform.pending_event_buffer].appendBounded(.{ .mouse_move = position }) catch
                @panic("event buffer overflow");
            return true;
        },
        .scroll_wheel => {
            const delta = event.msgSend(f64, "scrollingDeltaY", .{});
            // WM_MOUSEWHEEL reports device direction; undo macOS natural scrolling.
            const inverted = event.msgSend(bool, "isDirectionInvertedFromDevice", .{});
            const device_delta = if (inverted) -delta else delta;
            if (device_delta != 0) {
                const position = mousePosition(platform, event);
                platform.event_lists[platform.pending_event_buffer].appendBounded(.{
                    .mouse_scroll = .{ .value = if (device_delta > 0) 1 else -1, .mouse_pos = position },
                }) catch @panic("event buffer overflow");
            }
            return true;
        },
        else => return false,
    }
}

fn eventInsideView(platform: *State, event: Object) bool {
    const window_point = event.msgSend(Point, "locationInWindow", .{});
    const point = platform.view.msgSend(Point, "convertPoint:fromView:", .{ window_point, nil });
    const bounds = platform.view.msgSend(Rect, "bounds", .{});
    return point.x >= 0 and point.y >= 0 and
        point.x < bounds.size.width and point.y < bounds.size.height;
}

fn mousePosition(platform: *State, event: Object) event_types.MousePosition {
    const window_point = event.msgSend(Point, "locationInWindow", .{});
    const point = platform.view.msgSend(Point, "convertPoint:fromView:", .{ window_point, nil });
    return .{
        .x = mouseCoordinate(point.x),
        .y = mouseCoordinate(point.y),
    };
}

fn mouseCoordinate(value: f64) i16 {
    const clamped = std.math.clamp(value, std.math.minInt(i16), std.math.maxInt(i16));
    return @intFromFloat(clamped);
}

fn updateModifiers(platform: *State, code: appkit.VirtualKeyCode, raw_flags: usize) void {
    const flags: appkit.NSEventModifierFlags = @bitCast(raw_flags);
    // Only the key named in flagsChanged changed. Sampling every modifier here
    // invents presses for keys held while another application had focus.
    const down = switch (code) {
        .shift => flags.device.left_shift,
        .right_shift => flags.device.right_shift,
        .control => flags.device.left_control,
        .right_control => flags.device.right_control,
        .option => flags.device.left_option,
        .right_option => flags.device.right_option,
        .command => flags.device.left_command,
        .right_command => flags.device.right_command,
        // The lock/LED bit stays on after release; never use it as held state.
        .caps_lock => flags.caps_lock_pressed or flags.device.caps_lock_pressed,
        else => return,
    };
    const key = keyFromCode(code).?;
    const translated: Event = if (down) .{ .key_pressed = key } else .{ .key_released = key };
    platform.event_lists[platform.pending_event_buffer].appendBounded(translated) catch
        @panic("event buffer overflow");
}

fn keyFromEvent(event: Object, code: appkit.VirtualKeyCode) ?Key {
    const physical = keyFromCode(code) orelse return null;

    // Like Win32 virtual keys, printable keys follow the active layout. Keep
    // keypad and special keys distinct even if they produce the same text.
    switch (physical) {
        .a,
        .b,
        .c,
        .d,
        .e,
        .f,
        .g,
        .h,
        .i,
        .j,
        .k,
        .l,
        .m,
        .n,
        .o,
        .p,
        .q,
        .r,
        .s,
        .t,
        .u,
        .v,
        .w,
        .x,
        .y,
        .z,
        .@"0",
        .@"1",
        .@"2",
        .@"3",
        .@"4",
        .@"5",
        .@"6",
        .@"7",
        .@"8",
        .@"9",
        .equal,
        .minus,
        .lbracket,
        .rbracket,
        .apostrophe,
        .colon,
        .backslash,
        .comma,
        .slash,
        .period,
        .grave,
        => {
            const characters = event.msgSend(
                Object,
                "charactersByApplyingModifiers:",
                .{@as(usize, 0)},
            );
            if (characters.value != null and characters.msgSend(usize, "length", .{}) == 1) {
                return keyFromCharacter(
                    characters.msgSend(u16, "characterAtIndex:", .{@as(usize, 0)}),
                ) orelse physical;
            }
        },
        else => {},
    }
    return physical;
}

fn keyFromCharacter(character: u16) ?Key {
    return switch (character) {
        'a'...'z' => @fromBackingInt(@as(u8, @intCast(character - 'a' + 'A'))),
        'A'...'Z', '0'...'9' => @fromBackingInt(@as(u8, @intCast(character))),
        ';', ':' => .colon,
        '=', '+' => .equal,
        ',', '<' => .comma,
        '-', '_' => .minus,
        '.', '>' => .period,
        '/', '?' => .slash,
        '`', '~' => .grave,
        '[', '{' => .lbracket,
        '\\', '|' => .backslash,
        ']', '}' => .rbracket,
        '\'', '"' => .apostrophe,
        else => null,
    };
}

// macOS virtual key codes identify physical keys; these names follow the US layout.
fn keyFromCode(code: appkit.VirtualKeyCode) ?Key {
    return switch (code) {
        .ansi_a => .a,
        .ansi_s => .s,
        .ansi_d => .d,
        .ansi_f => .f,
        .ansi_h => .h,
        .ansi_g => .g,
        .ansi_z => .z,
        .ansi_x => .x,
        .ansi_c => .c,
        .ansi_v => .v,
        .ansi_b => .b,
        .ansi_q => .q,
        .ansi_w => .w,
        .ansi_e => .e,
        .ansi_r => .r,
        .ansi_y => .y,
        .ansi_t => .t,
        .ansi_1 => .@"1",
        .ansi_2 => .@"2",
        .ansi_3 => .@"3",
        .ansi_4 => .@"4",
        .ansi_6 => .@"6",
        .ansi_5 => .@"5",
        .ansi_equal => .equal,
        .ansi_9 => .@"9",
        .ansi_7 => .@"7",
        .ansi_minus => .minus,
        .ansi_8 => .@"8",
        .ansi_0 => .@"0",
        .ansi_right_bracket => .rbracket,
        .ansi_o => .o,
        .ansi_u => .u,
        .ansi_left_bracket => .lbracket,
        .ansi_i => .i,
        .ansi_p => .p,
        .return_key => .enter,
        .ansi_l => .l,
        .ansi_j => .j,
        .ansi_quote => .apostrophe,
        .ansi_k => .k,
        .ansi_semicolon => .colon,
        .ansi_backslash => .backslash,
        .ansi_comma => .comma,
        .ansi_slash => .slash,
        .ansi_n => .n,
        .ansi_m => .m,
        .ansi_period => .period,
        .tab => .tab,
        .space => .space,
        .ansi_grave => .grave,
        .delete => .backspace,
        .escape => .escape,
        .right_command => .rsuper,
        .command => .lsuper,
        .shift => .lshift,
        .caps_lock => .caps,
        .option => .lalt,
        .control => .lcontrol,
        .right_shift => .rshift,
        .right_option => .ralt,
        .right_control => .rcontrol,
        .f17 => .f17,
        .ansi_keypad_decimal => .decimal,
        .ansi_keypad_multiply => .multiply,
        .ansi_keypad_plus => .add,
        .ansi_keypad_clear => .numlock,
        .ansi_keypad_divide => .divide,
        .ansi_keypad_enter => .enter,
        .ansi_keypad_minus => .subtract,
        .f18 => .f18,
        .f19 => .f19,
        .f20 => .f20,
        .ansi_keypad_equals => .numpad_equal,
        .jis_keypad_comma => .separator,
        .contextual_menu => .apps,
        .volume_up => .volume_up,
        .volume_down => .volume_down,
        .mute => .volume_mute,
        .ansi_keypad0 => .numpad0,
        .ansi_keypad1 => .numpad1,
        .ansi_keypad2 => .numpad2,
        .ansi_keypad3 => .numpad3,
        .ansi_keypad4 => .numpad4,
        .ansi_keypad5 => .numpad5,
        .ansi_keypad6 => .numpad6,
        .ansi_keypad7 => .numpad7,
        .ansi_keypad8 => .numpad8,
        .ansi_keypad9 => .numpad9,
        .f5 => .f5,
        .f6 => .f6,
        .f7 => .f7,
        .f3 => .f3,
        .f8 => .f8,
        .f9 => .f9,
        .f11 => .f11,
        .f13 => .f13,
        .f16 => .f16,
        .f14 => .f14,
        .f10 => .f10,
        .f12 => .f12,
        .f15 => .f15,
        .help => .insert,
        .home => .home,
        .page_up => .pageup,
        .forward_delete => .delete,
        .f4 => .f4,
        .end => .end,
        .f2 => .f2,
        .page_down => .pagedown,
        .f1 => .f1,
        .left_arrow => .left,
        .right_arrow => .right,
        .down_arrow => .down,
        .up_arrow => .up,
        else => null,
    };
}

fn testInputPlatform(platform: *State) void {
    platform.* = .{
        .application = .{ .value = null },
        .window = .{ .value = null },
        .view = .{ .value = null },
        .delegate = .{ .value = null },
        .bitmap_context = null,
        .back_buffer = undefined,
    };
    for (&platform.event_lists, &platform.event_storage) |*list, *storage| {
        list.* = std.ArrayList(Event).initBuffer(storage);
    }
}

fn testKeyEvent(
    event_type: appkit.NSEventType,
    code: appkit.VirtualKeyCode,
    flags: usize,
    repeat: bool,
    window_number: isize,
) Object {
    const process_info = objc.getClass("NSProcessInfo").?.msgSend(Object, "processInfo", .{});
    const timestamp = process_info.msgSend(f64, "systemUptime", .{});

    const event_class = objc.getClass("NSEvent").?;
    return event_class.msgSend(
        Object,
        "keyEventWithType:location:modifierFlags:timestamp:windowNumber:context:" ++
            "characters:charactersIgnoringModifiers:isARepeat:keyCode:",
        .{
            event_type,
            Point{ .x = 0, .y = 0 },
            flags,
            timestamp,
            window_number,
            nil,
            nsString(""),
            nsString(""),
            repeat,
            code,
        },
    );
}

fn testMouseEvent(event_type: appkit.NSEventType, point: Point, window_number: isize) Object {
    const event_class = objc.getClass("NSEvent").?;
    return event_class.msgSend(
        Object,
        "mouseEventWithType:location:modifierFlags:timestamp:windowNumber:" ++
            "context:eventNumber:clickCount:pressure:",
        .{
            event_type,
            point,
            @as(usize, 0),
            @as(f64, 0),
            window_number,
            nil,
            @as(isize, 1),
            @as(isize, 1),
            @as(f32, 1),
        },
    );
}

test "AppKit ignores unknown keycodes" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var platform: State = undefined;
    testInputPlatform(&platform);

    const unknown_code: appkit.VirtualKeyCode = @fromBackingInt(@as(u16, 65535));
    const event = testKeyEvent(.key_down, unknown_code, 0, false, 0);
    try std.testing.expect(processEvent(&platform, event, .key_down));
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

test "AppKit releases retain the key chosen by the earlier layout" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var platform: State = undefined;
    testInputPlatform(&platform);

    platform.keys_by_code[@backingInt(appkit.VirtualKeyCode.ansi_e)] = .z;

    const release = testKeyEvent(.key_up, .ansi_e, 0, false, 0);
    try std.testing.expect(processEvent(&platform, release, .key_up));
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_released = .z }}, platform.takeEvents());
}

test "AppKit modifier snapshots do not invent unrelated presses" {
    var platform: State = undefined;
    testInputPlatform(&platform);
    updateModifiers(
        &platform,
        .shift,
        c.NX_DEVICELSHIFTKEYMASK | c.NX_DEVICERALTKEYMASK | c.NX_ALPHASHIFTMASK,
    );
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .lshift }}, platform.takeEvents());
}

test "AppKit nonclient presses suppress their releases inside the view" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    try registerClasses();

    const view_allocated = objc.getClass("FractureView").?.msgSend(Object, "alloc", .{});
    const view = view_allocated.msgSend(Object, "initWithFrame:", .{makeRect(0, 0, 320, 180)});
    defer view.release();

    var platform: State = undefined;
    testInputPlatform(&platform);
    platform.view = view;

    const press = testMouseEvent(.left_mouse_down, .{ .x = 100, .y = 190 }, 0);
    try std.testing.expect(!processEvent(&platform, press, .left_mouse_down));

    const release = testMouseEvent(.left_mouse_up, .{ .x = 20, .y = 30 }, 0);
    try std.testing.expect(!processEvent(&platform, release, .left_mouse_up));
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

// Native integration tests need a desktop session to create and activate a window.
const TestWindow = struct {
    buffer: Renderer.FrameBuffer,
    platform: State,

    // Initialize in place: the native callbacks retain pointers into this fixture.
    fn init(self: *TestWindow) !void {
        if (!@import("test_options").window_smoke) return error.SkipZigTest;

        const pixels = try std.testing.allocator.alignedAlloc(
            u8,
            .fromByteUnits(4096),
            320 * 180 * 4,
        );
        errdefer std.testing.allocator.free(pixels);
        @memset(pixels, 0);

        self.buffer = .{ .width = 320, .height = 180, .data = pixels };
        try self.platform.init();
        errdefer self.platform.deinit();
        try self.platform.createWindow(.{ .title = "Fracture window test", .frame_buffer = &self.buffer });
        errdefer self.platform.destroyWindow();
        self.platform.showWindow();

        // Activation is asynchronous. Inject only after the desktop grants focus.
        for (0..200) |_| {
            const key_window = self.platform.window.msgSend(bool, "isKeyWindow", .{});
            const active = key_window and self.platform.application.msgSend(bool, "isActive", .{});
            if (active) break;

            pumpMessages(&self.platform, max_messages_per_frame);
            try std.testing.expect(!self.platform.quit_requested);
            const date_class = objc.getClass("NSDate").?;
            const until = date_class.msgSend(
                Object,
                "dateWithTimeIntervalSinceNow:",
                .{@as(f64, 0.01)},
            );
            const run_loop = objc.getClass("NSRunLoop").?.msgSend(Object, "currentRunLoop", .{});
            run_loop.msgSend(void, "runUntilDate:", .{until});
        }
        try std.testing.expect(self.platform.window.msgSend(bool, "isKeyWindow", .{}));
        try std.testing.expect(self.platform.application.msgSend(bool, "isActive", .{}));
        pumpMessages(&self.platform, max_messages_per_frame);
        try std.testing.expect(!self.platform.quit_requested);
        _ = self.platform.takeEvents();
    }

    fn deinit(self: *TestWindow) void {
        defer self.platform.deinit();
        self.platform.destroyWindow();
        std.testing.allocator.free(self.buffer.data);

        // Tests may intentionally leave input queued after quit. Discard it so
        // a later test cannot inherit events from this window.
        const date = objc.getClass("NSDate").?.msgSend(Object, "distantPast", .{});
        for (0..max_messages_per_frame) |_| {
            const event = self.platform.application.msgSend(
                Object,
                "nextEventMatchingMask:untilDate:inMode:dequeue:",
                .{
                    appkit.NSEventMaskAny, date, nsString("kCFRunLoopDefaultMode"), true,
                },
            );
            if (event.value == null) break;
        }
    }
};

test "queued Command-modified keys reach the event buffer" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window_number = platform.window.msgSend(isize, "windowNumber", .{});

    // F1 has a layout-independent mapping, so the expected event is explicit.
    const press = testKeyEvent(.key_down, .f1, c.NX_COMMANDMASK, false, window_number);
    platform.application.msgSend(void, "postEvent:atStart:", .{ press, true });
    pumpMessages(platform, max_messages_per_frame);
    try std.testing.expect(!platform.quit_requested);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .f1 }}, platform.takeEvents());

    const release = testKeyEvent(.key_up, .f1, c.NX_COMMANDMASK, false, window_number);
    platform.application.msgSend(void, "postEvent:atStart:", .{ release, true });
    pumpMessages(platform, max_messages_per_frame);
    try std.testing.expect(!platform.quit_requested);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_released = .f1 }}, platform.takeEvents());
}

test "native pump leaves events beyond its budget for the next frame" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const events = objc.getClass("NSEvent").?;
    const window_number = platform.window.msgSend(isize, "windowNumber", .{});
    // Deliberately leave another event after the deferred key, as native input can.
    platform.application.msgSend(
        void,
        "postEvent:atStart:",
        .{ testKeyEvent(.key_down, .f2, 0, false, window_number), true },
    );
    platform.application.msgSend(
        void,
        "postEvent:atStart:",
        .{ testKeyEvent(.key_down, .f1, 0, false, window_number), true },
    );

    // Use distinct unhandled events to fill the queue without relying on
    // repeat coalescing, and also exercise the native dispatch fallback.
    const test_budget = 8;
    for (0..test_budget - 1) |index| {
        const unhandled = events.msgSend(
            Object,
            "otherEventWithType:location:modifierFlags:timestamp:windowNumber:" ++
                "context:subtype:data1:data2:",
            .{
                appkit.NSEventType.application_defined,
                Point{ .x = 0, .y = 0 },
                @as(usize, 0),
                @as(f64, 0),
                window_number,
                nil,
                @as(i16, 0),
                @as(isize, @intCast(index)),
                @as(isize, 0),
            },
        );
        platform.application.msgSend(void, "postEvent:atStart:", .{ unhandled, true });
    }

    platform.application.msgSend(
        void,
        "postEvent:atStart:",
        .{ testKeyEvent(.key_down, .escape, 0, false, window_number), true },
    );

    pumpMessages(platform, test_budget);
    try std.testing.expect(!platform.quit_requested);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .escape }}, platform.takeEvents());
    // Consume exactly the deferred event; real input may already follow it.
    pumpMessages(platform, 1);
    try std.testing.expect(!platform.quit_requested);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .f1 }}, platform.takeEvents());
    pumpMessages(platform, 1);
    try std.testing.expect(!platform.quit_requested);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .f2 }}, platform.takeEvents());
}

test "either focus-loss callback resets input once per focus interval" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;

    // Both notifications may describe the same loss; either one may arrive first.
    platform.delegate.msgSend(void, "windowDidResignKey:", .{nil});
    try std.testing.expectEqualDeep(&[_]Event{.reset_all}, platform.takeEvents());
    platform.delegate.msgSend(void, "applicationDidResignActive:", .{nil});
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
    platform.delegate.msgSend(void, "windowDidBecomeKey:", .{nil});
    platform.delegate.msgSend(void, "applicationDidBecomeActive:", .{nil});
    platform.delegate.msgSend(void, "applicationDidResignActive:", .{nil});
    try std.testing.expectEqualDeep(&[_]Event{.reset_all}, platform.takeEvents());
    platform.delegate.msgSend(void, "windowDidResignKey:", .{nil});
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

test "resize callbacks preserve explicitly delivered input without a reset" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const number = platform.window.msgSend(isize, "windowNumber", .{});
    // This exercises the callbacks; it does not enter AppKit's native tracking loop.
    platform.delegate.msgSend(void, "windowWillStartLiveResize:", .{nil});
    platform.application.msgSend(void, "sendEvent:", .{testKeyEvent(.key_down, .f1, 0, false, number)});
    platform.delegate.msgSend(void, "windowDidEndLiveResize:", .{nil});
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .f1 }}, platform.takeEvents());
    // An earlier end must stay latched if another interaction starts before polling.
    platform.delegate.msgSend(void, "windowWillStartLiveResize:", .{nil});
    const active = platform.takeWindowStatus();
    try std.testing.expect(active.native_interaction_active);
    try std.testing.expect(!active.interaction_ended);
    platform.delegate.msgSend(void, "windowDidEndLiveResize:", .{nil});
    const ended = platform.takeWindowStatus();
    try std.testing.expect(!ended.native_interaction_active);
    try std.testing.expect(ended.interaction_ended);
    try std.testing.expect(!platform.takeWindowStatus().interaction_ended);
}

test "sendEvent outside pump reaches the next batch" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const number = platform.window.msgSend(isize, "windowNumber", .{});
    platform.application.msgSend(void, "sendEvent:", .{testKeyEvent(.key_down, .f1, 0, false, number)});
    const first = platform.takeEvents();
    platform.application.msgSend(void, "sendEvent:", .{testKeyEvent(.key_up, .f1, 0, false, number)});
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_pressed = .f1 }}, first);
    try std.testing.expectEqualDeep(&[_]Event{.{ .key_released = .f1 }}, platform.takeEvents());
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

test "native close stops the pump before queued input is applied" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    const window_number = platform.window.msgSend(isize, "windowNumber", .{});

    platform.window.msgSend(void, "performClose:", .{nil});
    try std.testing.expect(platform.quit_requested);

    _ = platform.takeEvents();
    platform.application.msgSend(
        void,
        "postEvent:atStart:",
        .{ testKeyEvent(.key_down, .escape, 0, false, window_number), true },
    );
    pumpMessages(platform, max_messages_per_frame);
    try std.testing.expect(platform.quit_requested);
    try std.testing.expectEqual(@as(usize, 0), platform.takeEvents().len);
}

test "client click focuses the window and its drag releases outside the view" {
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();
    var fixture: TestWindow = undefined;
    try fixture.init();
    defer fixture.deinit();
    const platform = &fixture.platform;
    // Use a real focus transition: calling resignKeyWindow directly leaves NSApp's
    // keyWindow pointer naming a window that no longer considers itself key.
    platform.window.msgSend(void, "orderOut:", .{nil});
    platform.window.msgSend(void, "orderFront:", .{nil});
    try std.testing.expect(!platform.window.msgSend(bool, "isKeyWindow", .{}));
    _ = platform.takeEvents();
    const number = platform.window.msgSend(isize, "windowNumber", .{});
    const point = platform.view.msgSend(Point, "convertPoint:toView:", .{ Point{ .x = 17, .y = 23 }, nil });
    const click = testMouseEvent(.left_mouse_down, point, number);
    platform.application.msgSend(void, "sendEvent:", .{click});
    try std.testing.expect(platform.window.msgSend(bool, "isKeyWindow", .{}));
    const pressed = platform.takeEvents();
    try std.testing.expectEqualDeep(&[_]Event{.{ .mouse_pressed = .{ .button = .left, .pos = .{ .x = 17, .y = 23 } } }}, pressed);
    // The release from a client drag still belongs to the game outside the view.
    const outside = platform.view.msgSend(Point, "convertPoint:toView:", .{ Point{ .x = -11, .y = 27 }, nil });
    platform.application.msgSend(void, "sendEvent:", .{testMouseEvent(.left_mouse_up, outside, number)});
    try std.testing.expectEqualDeep(&[_]Event{.{ .mouse_released = .{ .button = .left, .pos = .{ .x = -11, .y = 27 } } }}, platform.takeEvents());
}

pub const InitError = error{};
pub const WaitError = std.Io.Cancelable;
pub const CreateWindowError = error{
    FailedToRegisterClass,
    FailedToRegisterIvar,
    FailedToRegisterMethod,
    IncompatibleApplicationClass,
    FailedToActivateApplication,
    FailedToCreateWindow,
    FailedToCreateView,
    FailedToCreateDelegate,
    FailedToCreateColorSpace,
    FailedToCreateBitmapContext,
};

pub fn processId() u32 {
    return @intCast(std.c.getpid());
}

pub const DynamicLibrary = struct {
    handle: *anyopaque,
    pub fn open(path: [:0]const u8) error{FailedToLoadLibrary}!DynamicLibrary {
        const handle = std.c.dlopen(path.ptr, .{ .NOW = true, .LOCAL = true }) orelse return error.FailedToLoadLibrary;
        return .{ .handle = handle };
    }
    pub fn lookup(self: *DynamicLibrary, comptime T: type, name: [:0]const u8) ?T {
        const address = std.c.dlsym(self.handle, name.ptr) orelse return null;
        return @ptrCast(@alignCast(address));
    }
    pub fn close(self: *DynamicLibrary) void {
        _ = std.c.dlclose(self.handle);
        self.* = undefined;
    }
};
