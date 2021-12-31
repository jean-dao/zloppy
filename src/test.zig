const std = @import("std");

const patch = @import("patch.zig");
const renderPatchedTree = @import("render.zig").renderPatchedTree;

const test_cases = [_]TestCase{
    .{
        .input =
            \\
        ,
        .output =
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {}
            \\
        ,
        .output =
            \\fn foo() void {}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    _ = bar;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool, baz: u32) void {
            \\    _ = bar;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool, baz: u32) void {
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    // existing comment
            \\    // existing comment2
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    // existing comment
            \\    // existing comment2
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool, baz: u32) void {
            \\    // existing comment
            \\    // existing comment2
            \\    _ = bar;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool, baz: u32) void {
            \\    // existing comment
            \\    // existing comment2
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\    _ = bar;
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    const baz = bar;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    const baz = bar;
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: fn () void) void {
            \\    bar();
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: fn () void) void {
            \\    bar();
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: *u32) void {
            \\    bar.* = 0;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: *u32) void {
            \\    bar.* = 0;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime bar: bool) void {
            \\}
            \\
        ,
        .output =
            \\fn foo(comptime bar: bool) void {
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    std.debug.print("bar={}\n", .{bar});
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    std.debug.print("bar={}\n", .{bar});
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool, baz: bool, quux: bool) void {
            \\    std.debug.print("quux={}\n", .{quux});
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool, baz: bool, quux: bool) void {
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\    std.debug.print("quux={}\n", .{quux});
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool) void {
            \\    std.debug.print("quatre={}\n", .{quatre});
            \\}
            \\
        ,
        .output =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool) void {
            \\    // XXX ZLOPPY unused var un
            \\    _ = un;
            \\    // XXX ZLOPPY unused var deux
            \\    _ = deux;
            \\    // XXX ZLOPPY unused var trois
            \\    _ = trois;
            \\    std.debug.print("quatre={}\n", .{quatre});
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool, cinq: bool) void {
            \\    std.debug.print("quatre={}\n", .{quatre});
            \\}
            \\
        ,
        .output =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool, cinq: bool) void {
            \\    // XXX ZLOPPY unused var un
            \\    _ = un;
            \\    // XXX ZLOPPY unused var deux
            \\    _ = deux;
            \\    // XXX ZLOPPY unused var trois
            \\    _ = trois;
            \\    // XXX ZLOPPY unused var cinq
            \\    _ = cinq;
            \\    std.debug.print("quatre={}\n", .{quatre});
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) callconv(.C) void {
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) callconv(.C) void {
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool, baz: bool) callconv(.C) void {
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool, baz: bool) callconv(.C) void {
            \\    // XXX ZLOPPY unused var bar
            \\    _ = bar;
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() usize {
            \\    const bar = 42;
            \\    return bar;
            \\}
            \\
        ,
        .output =
            \\fn foo() usize {
            \\    const bar = 42;
            \\    return bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\    if (bar == 0) {}
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    if (bar == 0) {}
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\    if (true) {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    if (true) {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    const baz = if (bar) 1 else 0;
            \\    _ = baz;
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    const baz = if (bar) 1 else 0;
            \\    _ = baz;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [1]usize{bar};
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [1]usize{bar};
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [_]usize{ 1, 2, 3, bar };
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [_]usize{ 1, 2, 3, bar };
            \\    // XXX ZLOPPY unused var baz
            \\    _ = baz;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = [_]usize{ 1, 2, 3, 4 };
            \\    for (bar) |quux| {
            \\        _ = quux;
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = [_]usize{ 1, 2, 3, 4 };
            \\    for (bar) |quux| {
            \\        _ = quux;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar = [_]usize{ 1, 2, 3, 4 };
            \\    for (bar) |quux| {
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar = [_]usize{ 1, 2, 3, 4 };
            \\    for (bar) |quux| {
            \\        // XXX ZLOPPY unused var quux
            \\        _ = quux;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    switch (bar) {}
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    switch (bar) {}
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    switch (42) {
            \\        else => {
            \\            _ = bar;
            \\        },
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    switch (42) {
            \\        else => {
            \\            _ = bar;
            \\        },
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const bar: union(enum) { val: bool } = .{ .val = true };
            \\    switch (bar) {
            \\        .val => |quux| {
            \\        },
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo() void {
            \\    const bar: union(enum) { val: bool } = .{ .val = true };
            \\    switch (bar) {
            \\        .val => |quux| {
            \\            // XXX ZLOPPY unused var quux
            \\            _ = quux;
            \\        },
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    while (bar) {}
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    while (bar) {}
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    while (true) {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    while (true) {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: u8) void {
            \\    while (bar < 16) : (bar += 1) {}
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: u8) void {
            \\    while (bar < 16) : (bar += 1) {}
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: ?bool) void {
            \\    while (bar) |quux| {
            \\    }
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: ?bool) void {
            \\    while (bar) |quux| {
            \\        // XXX ZLOPPY unused var quux
            \\        _ = quux;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    while (true) {
            \\        _ = bar;
            \\    } else {}
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: bool) void {
            \\    while (true) {
            \\        _ = bar;
            \\    } else {}
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..];
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..];
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..3];
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..3];
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..3 :0];
            \\}
            \\
        ,
        .output =
            \\fn foo(bar: usize) void {
            \\    const quux = [_]u32{ 0, 1, 2, 3, 4 };
            \\    _ = quux[bar..3 :0];
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime bar: usize) type {
            \\    return struct {
            \\        quux: [bar]u32,
            \\    };
            \\}
            \\
        ,
        .output =
            \\fn foo(comptime bar: usize) type {
            \\    return struct {
            \\        quux: [bar]u32,
            \\    };
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() type {
            \\    return struct {
            \\        const bar = 42;
            \\        quux: bool = true,
            \\    };
            \\}
            \\
        ,
        .output =
            \\fn foo() type {
            \\    return struct {
            \\        const bar = 42;
            \\        quux: bool = true,
            \\    };
            \\}
            \\
        ,
    },
};

fn runFn(fun: anytype, input: [:0]const u8, expected: [:0]const u8) !void {
    var tree = try std.zig.parse(std.testing.allocator, input);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expect(tree.errors.len == 0);

    var patches = try fun(std.testing.allocator, tree);
    defer patches.deinit();

    var out_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer out_buffer.deinit();

    try renderPatchedTree(&out_buffer, tree, patches);

    try std.testing.expectEqualStrings(expected, out_buffer.items);
}

test "zloppy" {
    for (test_cases) |t| {
        try runFn(patch.patchTreeOn, t.input, t.output);
        try runFn(patch.patchTreeOff, t.output, t.input);
    }
}

const TestCase = struct {
    input: [:0]const u8,
    output: [:0]const u8,
};
