# liver

A simple development web server with automatic live reload.

## Synopsis

    liver -d <directory> [-p <port>] [-w <watch-dir>] [-n]

## Description

liver is a minimal HTTP server that automatically reloads browsers when files
change. It serves static files from a directory and watches for modifications,
using polling to notify connected clients.

## Options

    -d, --dir <path>        Directory to serve (required)
    -p, --port <number>     Port to listen on (default: 0 = auto)
    -w, --watch <path>      Directory to watch for changes (default: same as --dir)
    -n, --no-browser        Don't auto-open browser (default: auto-open)
    -h, --help              Show help

## Examples

Serve current directory on random port:

    liver -d ./public

Serve on specific port, watch different directory:

    liver -d ./dist -p 8080 -w ./src

Serve without opening browser:

    liver -d ./public -n

## Implementation

The server uses platform-specific file watching (FSEvents on macOS, inotify on
Linux, ReadDirectoryChangesW on Windows). When files change, an atomic timestamp
is updated. Browsers poll /reload-time every 100ms and reload when the timestamp
changes.

Binary size: ~141KB (ReleaseSmal on macOS ARM64)

## Building

Requires Zig 0.15.2 or later.

    zig build
    zig build --release=small

Cross-compilation:

    zig build -Dtarget=x86_64-linux
    zig build -Dtarget=x86_64-windows
    zig build -Dtarget=aarch64-linux

## Attribution

File watching implementations adapted from Zine by Loris Cro:
https://github.com/kristoff-it/zine (commit 2bba322)

The watcher code has been substantially simplified from the original.

