const std = @import("std");
const assert = std.debug.assert;
const Renderer = @import("software_renderer.zig");
const profile = @import("profiling.zig");
const Self = @This();

pub const Config = struct {
    io: std.Io,
    /// Null selects logical CPUs minus the calling thread, capped at 32.
    count: ?usize = null,
};

io: std.Io = undefined,
jobs: []Renderer.TileJob = &.{},
threads: [32]std.Thread = undefined,
thread_count: usize = 0,
published: std.atomic.Value(u64) = .init(0),
next: std.atomic.Value(u64) = .init(0),
remaining: std.atomic.Value(usize) = .init(0),
wake_epoch: std.atomic.Value(u32) = .init(0),
stopping: std.atomic.Value(bool) = .init(false),
done: std.Io.Event = .unset,

pub fn init(self: *Self, gpa: std.mem.Allocator, capacity: usize, config: Config) !void {
    self.* = .{};
    const count = config.count orelse @min((std.Thread.getCpuCount() catch 1) - 1, self.threads.len);
    if (count > self.threads.len) return error.TooManyWorkers;
    if (count == 0) return;
    assert(capacity > 0);
    self.io = config.io;
    self.jobs = try gpa.alloc(Renderer.TileJob, capacity);
    errdefer self.deinit(gpa);
    for (0..count) |i| {
        self.threads[i] = try std.Thread.spawn(.{}, worker, .{self});
        self.thread_count += 1;
    }
}

pub fn deinit(self: *Self, gpa: std.mem.Allocator) void {
    if (self.jobs.len == 0) return;
    self.stopping.store(true, .release);
    // Teardown can run after the caller has finished its final profiling frame.
    self.wake();
    for (self.threads[0..self.thread_count]) |thread| thread.join();
    gpa.free(self.jobs);
    self.* = .{};
}

pub fn begin(self: *Self, count: usize) void {
    assert(self.thread_count > 0);
    assert(count > 0 and count <= self.jobs.len);
    assert(self.remaining.load(.acquire) == 0);
    const published = self.published.load(.monotonic);
    assert(self.next.load(.monotonic) == published);
    if (count > std.math.maxInt(u64) - published) @panic("Renderer tile ticket overflow");
    self.done.reset();
    self.remaining.store(count, .monotonic);
}

pub fn submit(self: *Self, job: Renderer.TileJob) void {
    const ticket = self.published.load(.monotonic);
    self.jobs[ticket % self.jobs.len] = job;
    // Acquiring published makes both the descriptor and its borrowed data visible.
    self.published.store(ticket + 1, .release);
}

pub fn notify(self: *Self) void {
    const trace = profile.begin(.renderer_wake);
    defer profile.end(trace);
    self.wake();
}

fn wake(self: *Self) void {
    _ = self.wake_epoch.fetchAdd(1, .release);
    self.io.futexWake(u32, &self.wake_epoch.raw, std.math.maxInt(u32));
}

pub fn finish(self: *Self) void {
    self.notify();
    const help = profile.begin(.renderer_help);
    while (self.runOne()) {}
    profile.end(help);
    const wait = profile.begin(.renderer_wait);
    self.done.waitUncancelable(self.io);
    profile.end(wait);
}

fn runOne(self: *Self) bool {
    var ticket = self.next.load(.monotonic);
    while (true) {
        if (ticket >= self.published.load(.acquire)) return false;
        if (self.next.cmpxchgWeak(ticket, ticket + 1, .monotonic, .monotonic)) |actual| {
            ticket = actual;
            continue;
        }
        break;
    }
    const job = self.jobs[ticket % self.jobs.len];
    Renderer.renderTile(job.back_buffer, .{ .x = job.tile_id.x, .y = job.tile_id.y }, job.headers, job.command_data);
    // No descriptor or borrowed frame data may be accessed after this decrement.
    // The acq_rel chain collects all framebuffer writes for the final event signal.
    if (self.remaining.fetchSub(1, .acq_rel) == 1) self.done.set(self.io);
    return true;
}

fn worker(self: *Self) void {
    // The root's tracer is shared with the main thread and is not threadsafe.
    profile.thread_enabled = false;
    while (true) {
        // Snapshot before rechecking predicates: publication between the check and
        // futex wait changes the expected value, so the worker cannot miss a wake.
        const epoch = self.wake_epoch.load(.acquire);
        if (self.stopping.load(.acquire)) return;
        if (self.runOne()) continue;
        self.io.futexWaitUncancelable(u32, &self.wake_epoch.raw, epoch);
    }
}
