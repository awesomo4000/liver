// Based on file watcher from Zine by Loris Cro
// https://github.com/kristoff-it/zine (commit 2bba322)
//
// Changes from original:
// - Removed Multiplex integration, now calls root.onInputChange() directly
// - Simplified to watch single directory instead of input/output tree tracking
// - Removed recursive tree watching, directory move handling, and complex inotify management
// - Removed cookie tracking for move events and parent/child relationship tracking
// - Changed context from Multiplex to generic anytype accepting root.Context

const LinuxWatcher = @This();

const std = @import("std");
const root = @import("root");

const log = std.log.scoped(.watcher);

watch_path: []const u8,
in_dir_paths: []const []const u8,

notify_fd: std.posix.fd_t,
watch_fds: std.AutoHashMapUnmanaged(std.posix.fd_t, []const u8) = .{},

pub fn init(
    gpa: std.mem.Allocator,
    watch_path: []const u8,
    in_dir_paths: []const []const u8,
) !LinuxWatcher {
    _ = gpa;
    const notify_fd = try std.posix.inotify_init1(0);
    return .{
        .watch_path = watch_path,
        .in_dir_paths = in_dir_paths,
        .notify_fd = notify_fd,
    };
}

pub fn listen(
    self: *LinuxWatcher,
    gpa: std.mem.Allocator,
    context: anytype,
) !noreturn {
    const ctx: *root.Context = @alignCast(@ptrCast(context));

    // Add watch for the directory
    const mask = Mask.all(&.{
        .IN_CLOSE_WRITE,
        .IN_MOVED_TO,
        .IN_CREATE,
        .IN_MODIFY,
    });

    const watch_fd = try std.posix.inotify_add_watch(
        self.notify_fd,
        self.watch_path,
        mask,
    );

    try self.watch_fds.put(gpa, watch_fd, self.watch_path);
    log.debug("Watching: {s}", .{self.watch_path});

    const Event = std.os.linux.inotify_event;
    const event_size = @sizeOf(Event);

    while (true) {
        var buffer: [event_size * 10]u8 = undefined;
        const len = try std.posix.read(self.notify_fd, &buffer);
        if (len < 0) @panic("notify fd read error");

        var event_data = buffer[0..len];
        while (event_data.len > 0) {
            const event: *Event = @alignCast(@ptrCast(event_data[0..event_size]));
            event_data = event_data[event_size + event.len ..];

            if (event.getName()) |name| {
                log.debug("Changed: {s}/{s}", .{ self.watch_path, name });
                root.onInputChange(ctx, self.watch_path, name);
            }
        }
    }
}

const Mask = struct {
    pub const IN_MODIFY = 0x00000002;
    pub const IN_CLOSE_WRITE = 0x00000008;
    pub const IN_MOVED_TO = 0x00000080;
    pub const IN_CREATE = 0x00000100;

    pub fn all(comptime flags: []const std.meta.DeclEnum(Mask)) u32 {
        var result: u32 = 0;
        inline for (flags) |f| result |= @field(Mask, @tagName(f));
        return result;
    }
};
