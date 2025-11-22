const std = @import("std");
const builtin = @import("builtin");
const mime = @import("mime.zig");
const Allocator = std.mem.Allocator;

const Watcher = switch (builtin.os.tag) {
    .linux => @import("watcher/LinuxWatcher.zig"),
    .macos => @import("watcher/MacosWatcher.zig"),
    .windows => @import("watcher/WindowsWatcher.zig"),
    else => @compileError("unsupported platform"),
};

pub const Context = struct {
    gpa: Allocator,
    serve_dir: std.fs.Dir,
    serve_dir_path: []const u8,
    reload_timestamp: std.atomic.Value(i64),
};

fn usage() void {
    std.debug.print(
        \\Usage: liver [options]
        \\
        \\A simple development web server with live reload (the internal organ for dev!).
        \\
        \\Options:
        \\  -d, --dir <path>       Directory to serve (required)
        \\  -p, --port <number>    Port to listen on (default: 0 = auto)
        \\  -w, --watch <path>     Directory to watch for changes (default: same as --dir)
        \\  -n, --no-browser       Don't auto-open browser (default: auto-open)
        \\  -h, --help             Show this help
        \\
        \\Examples:
        \\  liver -d ./public
        \\  liver -d ./dist -p 8080 -w ./src
        \\  liver -d ./public -n
        \\
    , .{});
}

pub fn main() !void {
    var gpa_impl = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_impl.deinit();
    const gpa = gpa_impl.allocator();

    var args = try std.process.argsWithAllocator(gpa);
    defer args.deinit();
    _ = args.skip(); // Skip program name

    var serve_dir_path: ?[]const u8 = null;
    var watch_dir_path: ?[]const u8 = null;
    var port: u16 = 0; // 0 = ephemeral port
    var open_browser = true;

    // Parse arguments
    while (args.next()) |arg| {
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            usage();
            std.process.exit(0);
        } else if (std.mem.eql(u8, arg, "-d") or std.mem.eql(u8, arg, "--dir")) {
            serve_dir_path = args.next() orelse {
                std.debug.print("Error: --dir requires a path\n\n", .{});
                usage();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-p") or std.mem.eql(u8, arg, "--port")) {
            const port_str = args.next() orelse {
                std.debug.print("Error: --port requires a number\n\n", .{});
                usage();
                std.process.exit(1);
            };
            port = std.fmt.parseInt(u16, port_str, 10) catch {
                std.debug.print("Error: Invalid port number '{s}'\n\n", .{port_str});
                usage();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-w") or std.mem.eql(u8, arg, "--watch")) {
            watch_dir_path = args.next() orelse {
                std.debug.print("Error: --watch requires a path\n\n", .{});
                usage();
                std.process.exit(1);
            };
        } else if (std.mem.eql(u8, arg, "-n") or std.mem.eql(u8, arg, "--no-browser")) {
            open_browser = false;
        } else {
            std.debug.print("Error: Unknown argument '{s}'\n\n", .{arg});
            usage();
            std.process.exit(1);
        }
    }

    // Require serve directory
    if (serve_dir_path == null) {
        std.debug.print("Error: --dir is required\n\n", .{});
        usage();
        std.process.exit(1);
    }

    // Default watch directory to serve directory
    if (watch_dir_path == null) {
        watch_dir_path = serve_dir_path;
    }

    // Open directories
    const serve_dir = std.fs.cwd().openDir(serve_dir_path.?, .{}) catch |err| {
        std.debug.print("Error: Failed to open serve directory '{s}': {s}\n", .{ serve_dir_path.?, @errorName(err) });
        std.process.exit(1);
    };

    // Create context
    var context = Context{
        .gpa = gpa,
        .serve_dir = serve_dir,
        .serve_dir_path = serve_dir_path.?,
        .reload_timestamp = std.atomic.Value(i64).init(std.time.timestamp()),
    };

    // Start file watcher thread
    const watcher_thread = try std.Thread.spawn(.{}, watcherThread, .{ &context, watch_dir_path.? });
    watcher_thread.detach();

    // Start HTTP server
    const address = std.net.Address.parseIp("127.0.0.1", port) catch unreachable;
    var http_server = address.listen(.{ .reuse_address = true }) catch |err| {
        std.debug.print("Error: Failed to listen on port {d}: {s}\n", .{ port, @errorName(err) });
        std.process.exit(1);
    };
    defer http_server.deinit();

    const actual_port = http_server.listen_address.in.getPort();
    const url = try std.fmt.allocPrint(gpa, "http://127.0.0.1:{d}/", .{actual_port});
    defer gpa.free(url);

    std.debug.print("\n", .{});
    std.debug.print("🚀 Live reload server running!\n", .{});
    std.debug.print("📂 Serving:  {s}\n", .{serve_dir_path.?});
    std.debug.print("👀 Watching: {s}\n", .{watch_dir_path.?});
    std.debug.print("🌐 URL:      {s}\n", .{url});
    std.debug.print("\n", .{});
    std.debug.print("Press Ctrl+C to stop\n", .{});
    std.debug.print("\n", .{});

    // Auto-open browser
    if (open_browser) {
        openBrowser(gpa, url) catch |err| {
            std.debug.print("Warning: Failed to open browser: {s}\n", .{@errorName(err)});
        };
    }

    // Accept connections (blocking, thread-per-connection like zig std)
    while (true) {
        const connection = http_server.accept() catch |err| {
            std.debug.print("Error: Failed to accept connection: {s}\n", .{@errorName(err)});
            continue;
        };
        _ = std.Thread.spawn(.{}, acceptConnection, .{ &context, connection }) catch |err| {
            std.debug.print("Error: Failed to spawn connection thread: {s}\n", .{@errorName(err)});
            connection.stream.close();
            continue;
        };
    }
}

fn watcherThread(ctx: *Context, watch_path: []const u8) !void {
    var watcher = Watcher.init(ctx.gpa, watch_path, &.{}) catch |err| {
        std.debug.print("Error: Failed to init watcher: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
    watcher.listen(ctx.gpa, ctx) catch |err| {
        std.debug.print("Error: Watcher failed: {s}\n", .{@errorName(err)});
        std.process.exit(1);
    };
}

// Called by watcher when files change
pub fn onInputChange(ctx: *Context, path: []const u8, name: []const u8) void {
    _ = path;
    _ = name;
    // Update timestamp atomically - browser will detect and reload
    ctx.reload_timestamp.store(std.time.timestamp(), .monotonic);
}

pub fn onOutputChange(ctx: *Context, path: []const u8, name: []const u8) void {
    // For simplified version, treat all changes the same
    onInputChange(ctx, path, name);
}

fn acceptConnection(ctx: *Context, connection: std.net.Server.Connection) void {
    defer connection.stream.close();

    var recv_buffer: [4096]u8 = undefined;
    var send_buffer: [4096]u8 = undefined;
    var conn_reader = connection.stream.reader(&recv_buffer);
    var conn_writer = connection.stream.writer(&send_buffer);
    var server = std.http.Server.init(conn_reader.interface(), &conn_writer.interface);

    while (server.reader.state == .ready) {
        var request = server.receiveHead() catch |err| switch (err) {
            error.HttpConnectionClosing => return,
            else => {
                std.debug.print("Error: Failed to receive request: {s}\n", .{@errorName(err)});
                return;
            },
        };

        serveRequest(ctx, &request) catch |err| {
            std.debug.print("Error: Failed to serve '{s}': {s}\n", .{ request.head.target, @errorName(err) });
            return;
        };
    }
}

fn serveRequest(ctx: *Context, request: *std.http.Server.Request) !void {
    const target = request.head.target;

    // Reload timestamp endpoint
    if (std.mem.eql(u8, target, "/reload-time")) {
        const timestamp = ctx.reload_timestamp.load(.monotonic);
        const timestamp_str = try std.fmt.allocPrint(ctx.gpa, "{d}", .{timestamp});
        defer ctx.gpa.free(timestamp_str);
        try request.respond(timestamp_str, .{
            .extra_headers = &.{
                .{ .name = "content-type", .value = "text/plain" },
                .{ .name = "cache-control", .value = "no-cache, no-store, must-revalidate" },
            },
        });
        return;
    }

    // Serve static file
    try serveFile(ctx, request, target);
}

fn serveFile(ctx: *Context, request: *std.http.Server.Request, target: []const u8) !void {
    var arena_impl = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_impl.deinit();
    const arena = arena_impl.allocator();

    // Normalize path
    var path = target;

    // Strip leading slash
    if (path.len > 0 and path[0] == '/') {
        path = path[1..];
    }

    // Strip query string
    if (std.mem.indexOfScalar(u8, path, '?')) |idx| {
        path = path[0..idx];
    }

    // Default to index.html for root
    if (path.len == 0 or std.mem.eql(u8, path, "/")) {
        path = "index.html";
    }

    // Append index.html if path ends with /
    if (path.len > 0 and path[path.len - 1] == '/') {
        path = try std.fmt.allocPrint(arena, "{s}index.html", .{path});
    }

    // Security: reject paths with ..
    if (std.mem.indexOf(u8, path, "..")) |_| {
        try request.respond("Forbidden", .{
            .status = .forbidden,
            .extra_headers = &.{.{ .name = "content-type", .value = "text/plain" }},
        });
        return;
    }

    // Try to open and read file
    const file = ctx.serve_dir.openFile(path, .{}) catch |err| switch (err) {
        error.FileNotFound => {
            try request.respond("Not Found", .{
                .status = .not_found,
                .extra_headers = &.{.{ .name = "content-type", .value = "text/plain" }},
            });
            return;
        },
        else => return err,
    };
    defer file.close();

    const content = try file.readToEndAlloc(arena, 10 * 1024 * 1024); // 10MB max

    // Inject reload script for HTML files
    const final_content = if (std.mem.endsWith(u8, path, ".html"))
        try injectReloadScript(arena, content)
    else
        content;

    // Get content type
    const content_type = mime.getContentType(path);

    // Send response
    try request.respond(final_content, .{
        .extra_headers = &.{
            .{ .name = "content-type", .value = content_type },
            .{ .name = "cache-control", .value = "no-cache, no-store, must-revalidate" },
        },
    });
}

fn injectReloadScript(allocator: Allocator, html: []const u8) ![]const u8 {
    const reload_script =
        \\<script>
        \\  // Live reload - polls server every 100ms
        \\  setInterval(() => {
        \\    fetch('/reload-time').then(r => r.text()).then(time => {
        \\      if (window.__reloadTime && time !== window.__reloadTime) {
        \\        console.log('🔄 Files changed, reloading...');
        \\        window.location.reload();
        \\      }
        \\      window.__reloadTime = time;
        \\    }).catch(() => {});
        \\  }, 100);
        \\  console.log('👀 Live reload enabled');
        \\</script>
        \\
    ;

    // Find </body> and inject before it
    if (std.mem.indexOf(u8, html, "</body>")) |pos| {
        return try std.fmt.allocPrint(allocator, "{s}{s}{s}", .{
            html[0..pos],
            reload_script,
            html[pos..],
        });
    }

    // No </body> found, append at end
    return try std.fmt.allocPrint(allocator, "{s}{s}", .{ html, reload_script });
}

fn openBrowser(gpa: Allocator, url: []const u8) !void {
    // Spawn in thread to avoid blocking (from zig std-docs.zig)
    _ = try std.Thread.spawn(.{}, openBrowserThread, .{ gpa, url });
}

fn openBrowserThread(gpa: Allocator, url: []const u8) void {
    const exe = switch (builtin.os.tag) {
        .windows => "explorer",
        .macos => "open",
        else => "xdg-open",
    };

    var child = std.process.Child.init(&.{ exe, url }, gpa);
    child.stdin_behavior = .Ignore;
    child.stdout_behavior = .Ignore;
    child.stderr_behavior = .Ignore;
    child.spawn() catch return;
    _ = child.wait() catch return;
}
