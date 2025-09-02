const std = @import("std");

const zloppy = @import("zloppy.zig");

const usage =
    \\Usage: zloppy [options] [command] [file]...
    \\
    \\   Modifies the input files in-places to silence errors about
    \\   unused variable/parameters and unreachable code.
    \\   Arguments can be files or directories, which are searched
    \\   recursively.
    \\
    \\Options:
    \\    -h, --help      Print this help and exit
    \\    --stdin         Format code from stdin; output to stdout
    \\
    \\Commands:
    \\    on          Enable sloppy mode
    \\    off         Disable sloppy mode
    \\
;

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

fn fatalOom(err: anyerror) noreturn {
    switch (err) {
        error.OutOfMemory => {
            std.log.err("out of memory, aborting", .{});
            std.process.exit(2);
        },
        else => unreachable,
    }
}

fn logErr(err: anyerror, comptime format: []const u8, args: anytype) void {
    std.log.err(format ++ ": {s}", args ++ .{@errorName(err)});
}

const Params = struct {
    cmd: Cmd,
    stdin: bool,
    input_paths: std.ArrayList([]const u8),

    const Cmd = enum {
        on,
        off,
    };
};

fn parseParams(gpa: std.mem.Allocator, args: []const [:0]const u8) Params {
    var params: Params = .{
        .cmd = undefined,
        .stdin = false,
        .input_paths = .{},
    };

    {
        var i: usize = 0;

        // options
        while (i < args.len and std.mem.startsWith(u8, args[i], "-")) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                std.debug.print("{s}", .{usage});
                std.process.exit(0);
            } else if (std.mem.eql(u8, arg, "--stdin")) {
                params.stdin = true;
            } else {
                fatal("unrecognized parameter: '{s}'", .{arg});
            }
        }

        if (args.len == 0) {
            fatal("expected command argument", .{});
        } else if (i >= args.len) {
            fatal("expected command argument after '{s}'", .{args[i - 1]});
        }

        // cmd
        const cmd_type = args[i];
        if (std.mem.eql(u8, cmd_type, "on")) {
            params.cmd = .on;
        } else if (std.mem.eql(u8, cmd_type, "off")) {
            params.cmd = .off;
        } else {
            fatal("unrecognized command: '{s}'", .{cmd_type});
        }

        i += 1;

        // files
        while (i < args.len) : (i += 1) {
            params.input_paths.append(gpa, args[i]) catch |err| fatalOom(err);
        }
    }

    if (params.stdin) {
        if (params.input_paths.items.len != 0) {
            fatal("cannot specify both --stdin and files", .{});
        }
    } else if (params.input_paths.items.len == 0) {
        fatal("expected at least one source file argument", .{});
    }

    return params;
}

const FmtResult = struct {
    content: []u8,
    noop: bool,
    comments_removed: u32,
    comments_added: u32,
};

fn fmtFile(
    arena: std.mem.Allocator,
    cmd: Params.Cmd,
    input_file: *const std.fs.File,
    filename: []const u8,
    size_hint: ?usize,
) !FmtResult {
    const source = try input_file.readToEndAllocOptions(
        arena,
        std.math.maxInt(u32),
        size_hint,
        .@"16",
        0,
    );

    const removed = try zloppy.cleanSource(filename, source);

    var tree = try std.zig.Ast.parse(arena, source, .zig);

    if (tree.errors.len != 0) {
        return error.ParsingError;
    }

    var out_buffer: std.Io.Writer.Allocating = .init(arena);

    var added: u32 = 0;
    switch (cmd) {
        .on => {
            var patches = try zloppy.genPatches(arena, tree);

            try @import("Render.zig").renderTreeWithPatches(
                arena,
                &out_buffer.writer,
                tree,
                &patches,
            );
            added = patches.rendered_comments;
        },
        .off => {
            try tree.render(arena, &out_buffer.writer, .{});
        },
    }

    const content = out_buffer.writer.buffered();
    return FmtResult{
        .noop = std.mem.eql(u8, content, source),
        .content = content,
        .comments_removed = removed,
        .comments_added = added,
    };
}

const TopLevelDir = struct {
    file_paths: [][]const u8,
    cur_idx: usize = 0,

    fn appendPathName(
        self: *TopLevelDir,
        gpa: std.mem.Allocator,
        path: []const u8,
    ) []const u8 {
        _ = self;
        return gpa.dupe(u8, path) catch |err| fatalOom(err);
    }

    fn getNextFileName(self: *TopLevelDir) ?[]const u8 {
        const next_idx = self.cur_idx;
        if (next_idx < self.file_paths.len) {
            self.cur_idx += 1;
            return self.file_paths[next_idx];
        } else {
            return null;
        }
    }

    fn getDir(self: *TopLevelDir) std.fs.Dir {
        _ = self;
        return std.fs.cwd();
    }
};

const Dir = struct {
    dir: std.fs.Dir,
    path: []const u8,
    fullpath: []const u8,
    iterator: std.fs.Dir.Iterator,

    fn init(
        parent: std.fs.Dir,
        path: []const u8,
        fullpath: []const u8,
    ) !Dir {
        var self = Dir{
            .dir = try parent.openDir(path, .{ .iterate = true }),
            .path = path,
            .fullpath = fullpath,
            .iterator = undefined,
        };

        self.iterator = self.dir.iterate();
        return self;
    }

    fn appendPathName(self: *Dir, gpa: std.mem.Allocator, path: []const u8) []const u8 {
        const left_len = self.fullpath.len;
        const sep_len = std.fs.path.sep_str.len;
        var new_path = gpa.alloc(u8, left_len + sep_len + path.len) catch |err| fatalOom(err);
        @memcpy(new_path[0..left_len], self.fullpath);
        @memcpy(new_path[left_len..][0..sep_len], std.fs.path.sep_str);
        @memcpy(new_path[left_len + sep_len ..], path);
        return new_path;
    }

    fn getNextFileName(self: *Dir) ?[]const u8 {
        while (self.iterator.next() catch |err| {
            logErr(err, "failed to get files in directory {s}", .{self.fullpath});
            return null;
        }) |entry| {
            switch (entry.kind) {
                .directory => {
                    if (std.mem.eql(u8, entry.name, "zig-cache")) {
                        continue;
                    } else {
                        return entry.name;
                    }
                },
                else => {
                    if (std.mem.endsWith(u8, entry.name, ".zig")) {
                        return entry.name;
                    } else {
                        continue;
                    }
                },
            }
        }

        return null;
    }

    fn getDir(self: *Dir) std.fs.Dir {
        return self.dir;
    }

    fn deinit(self: *Dir) void {
        self.dir.close();
    }
};

fn fmtDir(
    gpa: std.mem.Allocator,
    arena_instance: *std.heap.ArenaAllocator,
    cmd: Params.Cmd,
    dir: anytype,
) error{FmtDirError}!void {
    var has_error = false;
    while (dir.getNextFileName()) |path| {
        const fullpath = dir.appendPathName(gpa, path);
        defer gpa.free(fullpath);

        var file = dir.getDir().openFile(path, .{}) catch |err| {
            logErr(err, "unable to open file '{s}'", .{fullpath});
            has_error = true;
            continue;
        };

        const stat = file.stat() catch |err| {
            logErr(err, "unable to stat file '{s}'", .{fullpath});
            has_error = true;
            continue;
        };

        if (stat.kind == .directory) {
            // close file right away to not let open fd pile up
            file.close();

            var subdir = Dir.init(dir.getDir(), path, fullpath) catch |err| {
                logErr(err, "unable to open directory '{s}'", .{fullpath});
                has_error = true;
                continue;
            };
            defer subdir.deinit();

            fmtDir(gpa, arena_instance, cmd, &subdir) catch {
                has_error = true;
                continue;
            };
        } else {
            defer {
                _ = arena_instance.reset(.retain_capacity);
            }

            // close file after reading content
            defer file.close();
            const result = fmtFile(
                arena_instance.allocator(),
                cmd,
                &file,
                path,
                stat.size,
            ) catch |err| {
                logErr(err, "failed to format file '{s}'", .{fullpath});
                has_error = true;
                continue;
            };

            if (result.noop)
                continue;

            var buffer: [1024]u8 = undefined;
            var af = dir.getDir().atomicFile(
                path,
                .{ .mode = stat.mode, .write_buffer = &buffer },
            ) catch |err| {
                logErr(err, "failed to initialize atomic write on '{s}'", .{fullpath});
                has_error = true;
                continue;
            };
            defer af.deinit();

            _ = af.file_writer.interface.write(result.content) catch |err| {
                logErr(err, "failed to write content of {s} to temporary file", .{fullpath});
                has_error = true;
                continue;
            };

            af.finish() catch |err| {
                logErr(err, "failed to write to {s}", .{fullpath});
                has_error = true;
                continue;
            };

            if (result.comments_removed == 0 and result.comments_added == 0) {
                std.debug.print("{s} updated (format only)\n", .{fullpath});
            } else {
                std.debug.print(
                    "{s} updated ({} removed, {} added)\n",
                    .{ fullpath, result.comments_removed, result.comments_added },
                );
            }
        }
    }

    if (has_error)
        return error.FmtDirError;
}

pub fn main() !void {
    var gpa_instance: std.heap.GeneralPurposeAllocator(.{}) = .{};
    const gpa = gpa_instance.allocator();
    defer {
        _ = gpa_instance.deinit();
    }

    var arena_instance: std.heap.ArenaAllocator = .init(gpa);
    defer arena_instance.deinit();

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    std.debug.assert(args.len > 0);
    var params = parseParams(gpa, args[1..]);
    defer params.input_paths.deinit(gpa);

    if (params.stdin) {
        var stdin = std.fs.File.stdin();
        const result = fmtFile(
            arena_instance.allocator(),
            params.cmd,
            &stdin,
            "<stdin>",
            null,
        ) catch |err| {
            logErr(err, "failed to format stdin", .{});
            std.process.exit(1);
        };
        _ = std.fs.File.stdout().write(result.content) catch |err| {
            logErr(err, "failed to write to stdout", .{});
            std.process.exit(1);
        };
    } else {
        var cwd = TopLevelDir{ .file_paths = params.input_paths.items };
        fmtDir(gpa, &arena_instance, params.cmd, &cwd) catch {
            std.process.exit(1);
        };
    }
}
