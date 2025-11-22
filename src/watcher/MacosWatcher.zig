// Based on file watcher from Zine by Loris Cro
// https://github.com/kristoff-it/zine (commit 2bba322)
//
// Changes from original:
// - Removed Multiplex integration, now calls root.onInputChange() directly
// - Simplified to watch single directory instead of input/output tree tracking
// - Removed recursive tree watching and complex directory management
// - Changed context from Multiplex to generic anytype accepting root.Context

const MacosWatcher = @This();

const std = @import("std");
const root = @import("root");
const c = @cImport({
    @cInclude("CoreServices/CoreServices.h");
});

const log = std.log.scoped(.watcher);

watch_path: []const u8,
in_dir_paths: []const []const u8,

pub fn init(
    gpa: std.mem.Allocator,
    watch_path: []const u8,
    in_dir_paths: []const []const u8,
) !MacosWatcher {
    _ = gpa;
    return .{
        .watch_path = watch_path,
        .in_dir_paths = in_dir_paths,
    };
}

pub fn callback(
    streamRef: c.ConstFSEventStreamRef,
    clientCallBackInfo: ?*anyopaque,
    numEvents: usize,
    eventPaths: ?*anyopaque,
    eventFlags: ?[*]const c.FSEventStreamEventFlags,
    eventIds: ?[*]const c.FSEventStreamEventId,
) callconv(.c) void {
    _ = eventIds;
    _ = eventFlags;
    _ = streamRef;
    const ctx: *root.Context = @alignCast(@ptrCast(clientCallBackInfo));

    const paths: [*][*:0]u8 = @alignCast(@ptrCast(eventPaths));
    for (paths[0..numEvents]) |p| {
        const path = std.mem.span(p);
        log.debug("Changed: {s}\n", .{path});

        const basename = std.fs.path.basename(path);
        var base_path = path[0 .. path.len - basename.len];
        if (std.mem.endsWith(u8, base_path, "/"))
            base_path = base_path[0 .. base_path.len - 1];

        // Call root module's onInputChange function
        root.onInputChange(ctx, base_path, basename);
    }
}

pub fn listen(
    self: *MacosWatcher,
    gpa: std.mem.Allocator,
    context: anytype,
) !noreturn {
    var macos_paths = try gpa.alloc(c.CFStringRef, 1);
    defer gpa.free(macos_paths);

    macos_paths[0] = c.CFStringCreateWithCString(
        null,
        self.watch_path.ptr,
        c.kCFStringEncodingUTF8,
    );

    const paths_to_watch: c.CFArrayRef = c.CFArrayCreate(
        null,
        @ptrCast(macos_paths.ptr),
        @intCast(macos_paths.len),
        null,
    );

    var stream_context: c.FSEventStreamContext = .{ .info = context };
    const stream: c.FSEventStreamRef = c.FSEventStreamCreate(
        null,
        &callback,
        &stream_context,
        paths_to_watch,
        c.kFSEventStreamEventIdSinceNow,
        0.05,
        c.kFSEventStreamCreateFlagFileEvents,
    );

    c.FSEventStreamScheduleWithRunLoop(
        stream,
        c.CFRunLoopGetCurrent(),
        c.kCFRunLoopDefaultMode,
    );

    if (c.FSEventStreamStart(stream) == 0) {
        @panic("failed to start the event stream");
    }

    while (true) {
        c.CFRunLoopRun();
    }

    c.FSEventStreamStop(stream);
    c.FSEventStreamInvalidate(stream);
    c.FSEventStreamRelease(stream);

    c.CFRelease(paths_to_watch);
}
