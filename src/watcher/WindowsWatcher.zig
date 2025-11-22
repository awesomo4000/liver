// Based on file watcher from Zine by Loris Cro
// https://github.com/kristoff-it/zine (commit 2bba322)
//
// Changes from original:
// - Removed Multiplex integration, now calls root.onInputChange() directly
// - Simplified to watch single directory instead of input/output tree tracking
// - Removed IOCP (I/O Completion Port) async handling, now uses synchronous ReadDirectoryChangesW
// - Removed complex buffer management and overlapped I/O structures
// - Changed context from Multiplex to generic anytype accepting root.Context

const WindowsWatcher = @This();

const std = @import("std");
const windows = std.os.windows;
const root = @import("root");

const log = std.log.scoped(.watcher);

watch_path: []const u8,
in_dir_paths: []const []const u8,

pub fn init(
    gpa: std.mem.Allocator,
    watch_path: []const u8,
    in_dir_paths: []const []const u8,
) !WindowsWatcher {
    _ = gpa;
    return .{
        .watch_path = watch_path,
        .in_dir_paths = in_dir_paths,
    };
}

pub fn listen(
    self: *WindowsWatcher,
    gpa: std.mem.Allocator,
    context: anytype,
) !noreturn {
    const ctx: *root.Context = @alignCast(@ptrCast(context));

    const path_w = try windows.sliceToPrefixedFileW(null, self.watch_path);
    const dir_handle = windows.kernel32.CreateFileW(
        path_w.span().ptr,
        windows.FILE_LIST_DIRECTORY,
        windows.FILE_SHARE_READ | windows.FILE_SHARE_WRITE | windows.FILE_SHARE_DELETE,
        null,
        windows.OPEN_EXISTING,
        windows.FILE_FLAG_BACKUP_SEMANTICS,
        null,
    );

    if (dir_handle == windows.INVALID_HANDLE_VALUE) {
        return error.InvalidHandle;
    }
    defer windows.CloseHandle(dir_handle);

    log.debug("Watching: {s}", .{self.watch_path});

    var buffer: [4096]u8 align(@alignOf(windows.FILE_NOTIFY_INFORMATION)) = undefined;

    while (true) {
        var bytes_returned: windows.DWORD = undefined;
        if (windows.kernel32.ReadDirectoryChangesW(
            dir_handle,
            &buffer,
            buffer.len,
            @intFromBool(true), // watch subtree
            .{ .file_name = true, .dir_name = true, .last_write = true },
            &bytes_returned,
            null,
            null,
        ) == 0) {
            log.err("ReadDirectoryChanges error: {s}", .{@tagName(windows.kernel32.GetLastError())});
            return error.WatchFailed;
        }

        var offset: usize = 0;
        while (offset < bytes_returned) {
            const info: *windows.FILE_NOTIFY_INFORMATION = @alignCast(@ptrCast(&buffer[offset]));
            const name_len = info.FileNameLength / 2; // UTF-16 to char count

            // FileName is a flexible array member after the struct
            const name_ptr: [*]u16 = @ptrCast(@alignCast(@as([*]u8, @ptrCast(info)) + @sizeOf(windows.FILE_NOTIFY_INFORMATION)));
            const name_slice = name_ptr[0..name_len];

            const name = try std.unicode.utf16LeToUtf8Alloc(gpa, name_slice);
            defer gpa.free(name);

            log.debug("Changed: {s}", .{name});
            root.onInputChange(ctx, self.watch_path, name);

            if (info.NextEntryOffset == 0) break;
            offset += info.NextEntryOffset;
        }
    }
}
