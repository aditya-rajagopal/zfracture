///! Keep this entrypoint parallel to entrypoint_win32.zig until the platform boundaries settle.
const std = @import("std");
const builtin = @import("builtin");
const objc = @import("objc");
const c = @import("macos-c");
const options = @import("build_options");

const fr = @import("fracture");
const appkit = fr.appkit;
const game = @import("game.zig");
const common = @import("common.zig");
const EngineState = common.EngineState;
const Renderer = fr.Renderer;
const Key = fr.input.Key;
const Event = fr.event.Event;
const max_messages_per_frame = 4096;
const MouseButton = fr.input.MouseButton;
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

const MacOSPlatform = struct {
    application: Object,
    window: Object,
    view: Object,
    delegate: Object,
    bitmap_context: c.CGContextRef,
    event_storage: [2][1024]Event = undefined,
    event_lists: [2]std.ArrayList(Event) = undefined,
    pending_event_buffer: usize = 0,
    back_buffer: *Renderer.FrameBuffer,
    window_placement: Rect = std.mem.zeroes(Rect),
    presentation_options: appkit.NSApplicationPresentationOptions = .{},
    fullscreen: bool = false,
    quit_requested: bool = false,
    tracking_window: bool = false,
    focused: bool = false,
    moving_window: bool = false,
    reset_frame_clock: bool = false,
    debug_show_cursor: bool = false,
    cursor_hidden: bool = false,
    native_mouse_buttons: [5]bool = @splat(false),
    client_mouse_buttons: [5]bool = @splat(false),
    keys_by_code: [128]?Key = @splat(null),

    const Self = @This();

    // The slice stays immutable until the next handoff. Native callbacks append to the other list.
    fn takeEvents(self: *Self) []const Event {
        const ready = self.pending_event_buffer;
        const next = ready ^ 1;
        self.event_lists[next].clearRetainingCapacity();
        self.pending_event_buffer = next;
        return self.event_lists[ready].items;
    }

    // Initialize in place: the view and delegate borrow this address until teardown.
    fn createWindow(
        self: *Self,
        title: [:0]const u8,
        back_buffer: *Renderer.FrameBuffer,
    ) !void {
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
        const window_width = buffer_width + 2 * common.windowed_frame_margin;
        const buffer_height: f64 = @floatFromInt(back_buffer.height);
        const window_height = buffer_height + 2 * common.windowed_frame_margin;
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
        installMenu(application);

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

    fn showWindow(self: *Self) void {
        self.window.msgSend(void, "makeKeyAndOrderFront:", .{nil});
        self.application.msgSend(void, "activateIgnoringOtherApps:", .{true});
    }

    fn destroyWindow(self: *Self) void {
        // AppKit may retain these objects or call them while closing the window.
        // Detach before any native teardown can reenter callbacks.
        _ = objc.c.object_setInstanceVariable(self.application.value, platform_ivar, null);
        _ = objc.c.object_setInstanceVariable(self.view.value, platform_ivar, null);
        _ = objc.c.object_setInstanceVariable(self.delegate.value, platform_ivar, null);

        self.setCursorHidden(false);
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

    fn toggleFullscreen(self: *Self) void {
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

    fn present(self: *Self) void {
        if (self.window.msgSend(bool, "isMiniaturized", .{})) return;

        self.view.msgSend(void, "setNeedsDisplay:", .{true});
        self.view.msgSend(void, "displayIfNeeded", .{});
        self.application.msgSend(void, "updateWindows", .{});
    }

    fn beginWindowTracking(self: *Self) void {
        self.tracking_window = true;
        self.setCursorHidden(false);
    }

    fn endWindowTracking(self: *Self) void {
        self.tracking_window = false;
        self.moving_window = false;
        self.reset_frame_clock = true;
    }

    fn setCursorHidden(self: *Self, hidden: bool) void {
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

        const capture_cursor = !self.tracking_window and !self.debug_show_cursor and inside;
        const focused = capture_cursor and self.window.msgSend(bool, "isKeyWindow", .{});
        const hide_cursor = focused and self.application.msgSend(bool, "isActive", .{});
        self.setCursorHidden(hide_cursor);
    }
};

pub const DebugGameDLLApi = struct {
    pub const InitFn = *const fn (*EngineState) callconv(.c) ?*anyopaque;
    pub const DeinitFn = *const fn (*EngineState, *anyopaque) callconv(.c) void;
    pub const UpdateAndRenderFn = *const fn (*EngineState, *anyopaque, [*]const Event, usize) callconv(.c) bool;
    init: InitFn,
    deinit: DeinitFn,
    updateAndRender: UpdateAndRenderFn,
};

const DebugGame = struct {
    instance: ?*anyopaque = null,
    generation: u64 = 0,
    time_stamp: i96 = 0,
    file_size: u64 = 0,
    temp_name: [4096]u8 = undefined,
    temp_name_len: usize = 0,
    game_api: DebugGameDLLApi = undefined,

    fn unload(self: *DebugGame, io: std.Io) void {
        if (self.instance) |instance| _ = std.c.dlclose(instance);
        if (self.temp_name_len != 0) {
            std.Io.Dir.cwd().deleteFile(
                io,
                self.temp_name[0..self.temp_name_len],
            ) catch {};
        }
        self.instance = null;
        self.temp_name_len = 0;
    }
};

pub const AppState = struct {
    engine: EngineState,
    debug_game: if (builtin.mode == .debug) DebugGame else void,
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const pool = objc.AutoreleasePool.init();
    defer pool.deinit();

    const allocator = std.heap.page_allocator;
    const permanent_memory_size = fr.MB(128);
    const transient_memory_size = fr.MB(128);
    const game_memory = try allocator.alloc(u8, permanent_memory_size + transient_memory_size);
    defer allocator.free(game_memory);

    const permanent_memory = game_memory[0..permanent_memory_size];
    var permanent_fixed_buffer = std.heap.FixedBufferAllocator.init(permanent_memory);
    const transient_memory = game_memory[permanent_memory_size..];
    var transient_fixed_buffer = std.heap.FixedBufferAllocator.init(transient_memory);
    const permanent_allocator = permanent_fixed_buffer.allocator();

    const app_state = try permanent_allocator.create(AppState);
    const engine_state = &app_state.engine;
    engine_state.io = io;
    engine_state.permanent_allocator = permanent_allocator;
    engine_state.transient_allocator = transient_fixed_buffer.allocator();
    engine_state.delta_time = 0;

    try engine_state.sound.init();
    defer engine_state.sound.deinit();

    engine_state.renderer.back_buffer = .{
        .width = 1280,
        .height = 720,
        .data = try permanent_allocator.alignedAlloc(
            u8,
            .fromByteUnits(4096),
            4096 * 2048 * Renderer.bytes_per_pixel,
        ),
    };
    engine_state.renderer.clearScreen(0, 0, 0);

    var platform_state: MacOSPlatform = undefined;
    try platform_state.createWindow(
        "Testbed",
        &engine_state.renderer.back_buffer,
    );
    defer platform_state.destroyWindow();
    platform_state.showWindow();

    if (builtin.mode == .debug) {
        app_state.debug_game = .{};
        _ = try reloadLibrary(io, &app_state.debug_game, options.game_library_path);
    }
    defer if (builtin.mode == .debug) app_state.debug_game.unload(io);

    const game_state = if (builtin.mode == .debug)
        app_state.debug_game.game_api.init(engine_state) orelse
            return error.GameInitializationFailed
    else
        game.init(engine_state);
    defer {
        if (builtin.mode == .debug) {
            app_state.debug_game.game_api.deinit(engine_state, game_state);
        } else {
            game.deinit(engine_state, game_state);
        }
    }

    var running = true;
    var host_controls: common.HostControls = .{};
    var frame_timestamp = std.Io.Clock.awake.now(io);
    var dll_timestamp = frame_timestamp;
    var last_reload_error: ?anyerror = null;

    while (running) {
        const frame_start = std.Io.Clock.awake.now(io);
        defer {
            if (running and !platform_state.quit_requested) {
                fr.paceFrame(io, frame_start, common.frame_duration) catch {
                    running = false;
                };
            }
        }

        const frame_pool = objc.AutoreleasePool.init();
        defer frame_pool.deinit();
        defer transient_fixed_buffer.reset();

        if (!pumpMessages(&platform_state)) {
            running = false;
            break;
        }
        engine_state.sound.update();

        // Native window tracking can stall the pump; exclude that time to avoid movement jumps.
        const now = std.Io.Clock.awake.now(io);
        if (platform_state.tracking_window) {
            frame_timestamp = now;
            continue;
        }

        if (platform_state.reset_frame_clock) {
            engine_state.delta_time = 0;
        } else {
            const elapsed = frame_timestamp.durationTo(now);
            const elapsed_ns: f32 = @floatFromInt(elapsed.toNanoseconds());
            engine_state.delta_time = elapsed_ns / std.time.ns_per_s;
        }
        platform_state.reset_frame_clock = false;
        frame_timestamp = now;

        const events = platform_state.takeEvents();
        host_controls.consumeFrame(events);
        running = if (builtin.mode == .debug)
            app_state.debug_game.game_api.updateAndRender(engine_state, game_state, events.ptr, events.len)
        else
            game.updateAndRender(engine_state, game_state, events);

        platform_state.present();

        const control = host_controls.down.ctrl or host_controls.pressed_this_frame.ctrl;
        if (host_controls.pressed_this_frame.@"3" and !control) {
            platform_state.debug_show_cursor = !platform_state.debug_show_cursor;
        }

        const toggle_fullscreen = host_controls.down.alt and host_controls.pressed_this_frame.enter;
        if (toggle_fullscreen) {
            platform_state.toggleFullscreen();
        }

        platform_state.updateCursor();

        if (builtin.mode == .debug) {
            if (dll_timestamp.durationTo(now).toNanoseconds() > std.time.ns_per_s / 30) {
                dll_timestamp = now;
                _ = reloadLibrary(
                    io,
                    &app_state.debug_game,
                    options.game_library_path,
                ) catch |err| {
                    if (last_reload_error == null or last_reload_error.? != err) {
                        std.log.err(
                            "Failed to reload game library: {s}",
                            .{@errorName(err)},
                        );
                    }
                    last_reload_error = err;
                    continue;
                };
                last_reload_error = null;
            }
        }
    }
}

fn nsString(value: [:0]const u8) Object {
    return objc.getClass("NSString").?.msgSend(Object, "stringWithUTF8String:", .{value.ptr});
}

fn makeRect(x: f64, y: f64, width: f64, height: f64) Rect {
    return .{ .origin = .{ .x = x, .y = y }, .size = .{ .width = width, .height = height } };
}

fn presentationRect(fullscreen: bool, bounds: Rect, width: u16, height: u16) Rect {
    return if (fullscreen) bounds else makeRect(
        common.windowed_frame_margin,
        common.windowed_frame_margin,
        @floatFromInt(width),
        @floatFromInt(height),
    );
}

fn registerClasses() !void {
    // The runtime takes log2(alignment); ^v describes an unowned void pointer.
    const pointer_alignment = std.math.log2_int(usize, @alignOf(?*MacOSPlatform));

    if (objc.getClass("FractureApplication") == null) {
        const class = objc.allocateClassPair(objc.getClass("NSApplication").?, "FractureApplication") orelse
            return error.FailedToRegisterClass;
        errdefer objc.disposeClassPair(class);
        const added = objc.c.class_addIvar(class.value, platform_ivar, @sizeOf(?*MacOSPlatform), pointer_alignment, "^v");
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
            @sizeOf(?*MacOSPlatform),
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
            @sizeOf(?*MacOSPlatform),
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

fn platformForCallback(receiver: objc.c.id) ?*MacOSPlatform {
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
    platform.setCursorHidden(false);
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
    const graphics = objc.getClass("NSGraphicsContext").?.msgSend(Object, "currentContext", .{});
    const context = graphics.msgSend(c.CGContextRef, "CGContext", .{});
    const bounds = platform.view.msgSend(Rect, "bounds", .{});
    if (bounds.size.width <= 0 or bounds.size.height <= 0) return;

    c.CGContextSetRGBFillColor(context, 0, 0, 0, 1);
    c.CGContextFillRect(context, bounds);

    // Release the snapshot before Zig writes the next frame. Drawing and updates share one thread.
    const image = c.CGBitmapContextCreateImage(platform.bitmap_context) orelse return;
    defer c.CGImageRelease(image);
    const dest = presentationRect(
        platform.fullscreen,
        bounds,
        platform.back_buffer.width,
        platform.back_buffer.height,
    );

    c.CGContextSaveGState(context);
    defer c.CGContextRestoreGState(context);
    c.CGContextSetInterpolationQuality(context, c.kCGInterpolationNone);
    c.CGContextTranslateCTM(context, dest.origin.x, dest.origin.y + dest.size.height);
    c.CGContextScaleCTM(context, 1, -1);
    c.CGContextDrawImage(context, makeRect(0, 0, dest.size.width, dest.size.height), image);
}

fn installMenu(application: Object) void {
    const menu_class = objc.getClass("NSMenu").?;
    const item_class = objc.getClass("NSMenuItem").?;

    const menu_allocated = menu_class.msgSend(Object, "alloc", .{});
    const menu = menu_allocated.msgSend(Object, "initWithTitle:", .{nsString("Testbed")});
    defer menu.release();

    const root_allocated = item_class.msgSend(Object, "alloc", .{});
    const root = root_allocated.msgSend(
        Object,
        "initWithTitle:action:keyEquivalent:",
        .{ nsString("Testbed"), @as(objc.c.SEL, null), nsString("") },
    );
    defer root.release();

    const submenu_allocated = menu_class.msgSend(Object, "alloc", .{});
    const submenu = submenu_allocated.msgSend(Object, "initWithTitle:", .{nsString("Testbed")});
    defer submenu.release();

    const quit_allocated = item_class.msgSend(Object, "alloc", .{});
    const quit = quit_allocated.msgSend(
        Object,
        "initWithTitle:action:keyEquivalent:",
        .{ nsString("Quit Testbed"), objc.sel("terminate:"), nsString("") },
    );
    defer quit.release();
    quit.msgSend(void, "setTarget:", .{application});

    submenu.msgSend(void, "addItem:", .{quit});
    root.msgSend(void, "setSubmenu:", .{submenu});
    menu.msgSend(void, "addItem:", .{root});
    application.msgSend(void, "setMainMenu:", .{menu});
}

fn pumpMessages(platform: *MacOSPlatform) bool {
    return pumpMessagesWithBudget(platform, max_messages_per_frame);
}

fn pumpMessagesWithBudget(platform: *MacOSPlatform, budget: usize) bool {
    std.debug.assert(budget <= max_messages_per_frame);
    if (platform.quit_requested) return false;

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

        sendEvent(platform.application.value, null, event.value);
        if (platform.quit_requested) break;
    }
    return !platform.quit_requested;
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
                if (processEvent(platform, event)) return;
            }
        }
    }
    application.msgSendSuper(objc.getClass("NSApplication").?, void, "sendEvent:", .{event});
}

fn processEvent(platform: *MacOSPlatform, event: Object) bool {
    const event_type = event.msgSend(appkit.NSEventType, "type", .{});

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

fn eventInsideView(platform: *MacOSPlatform, event: Object) bool {
    const window_point = event.msgSend(Point, "locationInWindow", .{});
    const point = platform.view.msgSend(Point, "convertPoint:fromView:", .{ window_point, nil });
    const bounds = platform.view.msgSend(Rect, "bounds", .{});
    return point.x >= 0 and point.y >= 0 and
        point.x < bounds.size.width and point.y < bounds.size.height;
}

fn mousePosition(platform: *MacOSPlatform, event: Object) fr.input.MousePosition {
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

fn updateModifiers(platform: *MacOSPlatform, code: appkit.VirtualKeyCode, raw_flags: usize) void {
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

fn reloadLibrary(io: std.Io, debug_game: *DebugGame, library_path: []const u8) !bool {
    const dir = std.Io.Dir.cwd();
    const stats = try dir.statFile(io, library_path, .{});
    if (debug_game.instance != null and
        debug_game.time_stamp == stats.mtime.nanoseconds and
        debug_game.file_size == stats.size)
    {
        return false;
    }

    debug_game.generation = std.math.add(
        u64,
        debug_game.generation,
        1,
    ) catch return error.ReloadGenerationOverflow;
    var temp_name_buffer: [4096]u8 = undefined;
    const temp_name = try std.fmt.bufPrintSentinel(
        &temp_name_buffer,
        "{s}.{d}.{d}.dylib",
        .{ library_path, std.c.getpid(), debug_game.generation },
        0,
    );
    try dir.copyFile(library_path, dir, temp_name, io, .{ .replace = false });
    errdefer dir.deleteFile(io, temp_name) catch {};

    const copied_stats = try dir.statFile(io, library_path, .{});
    if (stats.mtime.nanoseconds != copied_stats.mtime.nanoseconds or
        stats.size != copied_stats.size)
    {
        return error.LibraryChangedDuringCopy;
    }

    const instance = std.c.dlopen(
        temp_name.ptr,
        .{ .NOW = true, .LOCAL = true },
    ) orelse return error.FailedToLoadLibrary;
    errdefer _ = std.c.dlclose(instance);

    const init_address = std.c.dlsym(instance, "init") orelse return error.FailedToLookupInitFn;
    const init_fn: DebugGameDLLApi.InitFn = @ptrCast(@alignCast(init_address));
    const deinit_address = std.c.dlsym(instance, "deinit") orelse
        return error.FailedToLookupDeinitFn;
    const deinit_fn: DebugGameDLLApi.DeinitFn = @ptrCast(@alignCast(deinit_address));
    const update_address = std.c.dlsym(instance, "updateAndRender") orelse
        return error.FailedToLookupUpdateAndRenderFn;
    const update_fn: DebugGameDLLApi.UpdateAndRenderFn = @ptrCast(@alignCast(update_address));

    // A failed reload must leave the old game callable, so validate before unloading it.
    debug_game.unload(io);
    debug_game.instance = instance;
    debug_game.game_api = .{ .init = init_fn, .deinit = deinit_fn, .updateAndRender = update_fn };
    debug_game.time_stamp = stats.mtime.nanoseconds;
    debug_game.file_size = stats.size;
    @memcpy(debug_game.temp_name[0..temp_name.len], temp_name);
    debug_game.temp_name_len = temp_name.len;
    std.log.info("Loaded game library generation {d}", .{debug_game.generation});
    return true;
}
