const std = @import("std");

const patch = @import("patch.zig");
const renderPatchedTree = @import("render.zig").renderPatchedTree;

const usage =
    \\Usage: zloppy [options] [command] [file]...
    \\
    \\   Modifies the input files in-places to silence errors about
    \\   unused variable/parameters.
    \\   Arguments can be files or directories, which are searched
    \\   recursively.
    \\
    \\Options:
    \\    -h, --help  Print this help and exit
    \\    --stdin     Format code from stdin; output to stdout
    \\
    \\Commands:
    \\    on          Enable sloppy mode, unused variable errors will be silenced
    \\                by adding a `_ = <var>;` statement prefixed by `// XXX zloppy`
    \\    off         Disable sloppy mode, statements prefixed by `// XXX zloppy`
    \\                will be removed, as well as the comment
    \\
;

const Cmd = struct {
    cmd: Type,
    stdin: bool,
    input_paths: std.ArrayList([]const u8),

    const Type = enum {
        on,
        off,
    };
};

fn fatal(comptime format: []const u8, args: anytype) noreturn {
    std.log.err(format, args);
    std.process.exit(1);
}

pub fn logErr(err: anyerror, comptime format: []const u8, args: anytype) void {
    std.log.err(format ++ ": {s}", args ++ .{ @errorName(err) });
}

fn parseCmd(gpa: std.mem.Allocator, args: [][:0]const u8) !Cmd {
    var cmd = Cmd{
        .cmd = undefined,
        .stdin = false,
        .input_paths = std.ArrayList([]const u8).init(gpa),
    };

    {
        var i: usize = 0;

        // options
        while (i < args.len and std.mem.startsWith(u8, args[i], "-")) : (i += 1) {
            const arg = args[i];
            if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
                std.log.info("{s}", .{usage});
                std.process.exit(0);
            } else if (std.mem.eql(u8, arg, "--stdin")) {
                cmd.stdin = true;
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
            cmd.cmd = .on;
        } else if (std.mem.eql(u8, cmd_type, "off")) {
            cmd.cmd = .off;
        } else {
            fatal("unrecognized command: '{s}'", .{cmd_type});
        }

        i += 1;

        // files
        while (i < args.len) : (i += 1) {
            try cmd.input_paths.append(args[i]);
        }
    }

    if (cmd.stdin) {
        if (cmd.input_paths.items.len != 0) {
            fatal("cannot specify both --stdin and files", .{});
        }
    } else if (cmd.input_paths.items.len == 0) {
        fatal("expected at least one source file argument", .{});
    }

    return cmd;
}

fn fmtFile(
    gpa: std.mem.Allocator,
    cmd: Cmd.Type,
    input_name: []const u8,
    input_file: *const std.fs.File,
    size_hint: ?usize,
) ![]u8 {
    const source = input_file.readToEndAllocOptions(
        gpa,
        std.math.maxInt(u32),
        size_hint,
        @alignOf(u16),
        0,
    ) catch |err| switch (err) {
        error.ConnectionResetByPeer => unreachable,
        error.ConnectionTimedOut => unreachable,
        error.NotOpenForReading => unreachable,
        else => |e| {
            fatal("unable to read from {s}: {s}", .{ input_name, e });
        },
    };
    defer gpa.free(source);

    var tree = try std.zig.parse(gpa, source);
    defer tree.deinit(gpa);

    if (tree.errors.len != 0) {
        fatal("{s}: parsing errors, aborting.", .{ input_name });
    }

    var patches = switch (cmd) {
        .on => try patch.patchTreeOn(gpa, tree),
        .off => try patch.patchTreeOff(gpa, tree),
    };
    defer patches.deinit();

    var out_buffer = std.ArrayList(u8).init(gpa);
    defer out_buffer.deinit();

    try renderPatchedTree(&out_buffer, tree, patches);
    return out_buffer.toOwnedSlice();
}

const FmtPathError =
    std.fs.Dir.OpenError ||
    std.fs.File.OpenError ||
    std.os.WriteError ||
    std.os.RenameError ||
    error{ OutOfMemory }
;

fn fmtPaths(
    gpa: std.mem.Allocator,
    cmd: Cmd.Type,
    parent_dir: std.fs.Dir,
    rel_paths: [][]const u8,
    has_error: *bool,
) FmtPathError!void {
    for (rel_paths) |path| {
        //std.debug.print("checking path {s}\n", .{ path });
        var file = parent_dir.openFile(path, .{}) catch |err| {
            std.log.err("unable to open file '{s}': {s}", .{ path, @errorName(err) });
            has_error.* = true;
            continue;
        };
        defer file.close();

        const stat = try file.stat();
        if (stat.kind == .Directory) {
            const subdir = parent_dir.openDir(path, .{ .iterate = true }) catch |err| {
                logErr(err, "unable to open directory '{s}'", .{ path });
                has_error.* = true;
                continue;
            };
            var paths = std.ArrayList([]const u8).init(gpa);
            defer paths.deinit();

            std.debug.print("path {s} is a directory\n", .{ path });

            var it = subdir.iterate();
            while (try it.next()) |entry| {
                if (std.mem.endsWith(u8, entry.name, ".zig")) {
                    std.debug.print("add (file) {s} to subpaths\n", .{ entry.name });
                    try paths.append(entry.name);
                } else if (entry.kind == .Directory and !std.mem.eql(u8, entry.name, "zig-cache")) {
                    std.debug.print("add (dir) {s} to subpaths\n", .{ entry.name });
                    try paths.append(entry.name);
                }
            }

            fmtPaths(gpa, cmd, subdir, paths.items[0..], has_error) catch |err| {
                logErr(err, "failed to format directory '{s}'", .{ path });
                has_error.* = true;
                continue;
            };
        } else {
            const content = try fmtFile(gpa, cmd, path, &file, stat.size);
            defer gpa.free(content);

            var af = try parent_dir.atomicFile(path, .{ .mode = stat.mode });
            defer af.deinit();

            try af.file.writeAll(content);
            try af.finish();
            std.log.info("{s} updated", .{path});
        }
    }
}

pub fn main() !void {
    var gpa_instance = std.heap.GeneralPurposeAllocator(.{}){};
    const gpa = gpa_instance.allocator();
    defer {
        _ = gpa_instance.deinit();
    }

    const args = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, args);

    if (args.len == 0)
        unreachable;

    const cmd = try parseCmd(gpa, args[1..]);
    defer cmd.input_paths.deinit();

    if (cmd.stdin) {
        var stdin = std.io.getStdIn();
        const content = try fmtFile(gpa, cmd.cmd, "<stdin>", &stdin, null);
        defer gpa.free(content);
        try std.io.getStdOut().writeAll(content);
    } else {
        var has_error = false;
        fmtPaths(
            gpa,
            cmd.cmd,
            std.fs.cwd(),
            cmd.input_paths.items[0..],
            &has_error,
        ) catch |err| {
            logErr(err, "failed to format files in current directory", .{});
            std.process.exit(1);
        };

        if (has_error) {
            std.process.exit(1);
        }
    }
}
