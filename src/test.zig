const std = @import("std");

const zloppy = @import("zloppy.zig");
const renderTreeWithPatches = @import("render.zig").renderTreeWithPatches;

const test_cases_on = [_]TestCase{
    .{
        .input =
            \\
        ,
        .expected =
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {}
            \\
        ,
        .expected =
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
        .expected =
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
        .expected =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
        .expected =
            \\fn foo(bar: bool, baz: u32) void {
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
            \\fn foo(bar: bool) void {
            \\    // existing comment
            \\    // existing comment2
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
        .expected =
            \\fn foo(bar: bool, baz: u32) void {
            \\    // existing comment
            \\    // existing comment2
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
            \\fn foo() void {
            \\    const bar = 42;
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
        .expected =
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
        .expected =
            \\fn foo(bar: bool) void {
            \\    const baz = bar;
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
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
        .expected =
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
        .expected =
            \\fn foo(comptime bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
        .expected =
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
        .expected =
            \\fn foo(bar: bool, baz: bool, quux: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool) void {
            \\    _ = un; // XXX ZLOPPY unused var un
            \\    _ = deux; // XXX ZLOPPY unused var deux
            \\    _ = trois; // XXX ZLOPPY unused var trois
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
        .expected =
            \\fn foo(un: bool, deux: bool, trois: bool, quatre: bool, cinq: bool) void {
            \\    _ = un; // XXX ZLOPPY unused var un
            \\    _ = deux; // XXX ZLOPPY unused var deux
            \\    _ = trois; // XXX ZLOPPY unused var trois
            \\    _ = cinq; // XXX ZLOPPY unused var cinq
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
        .expected =
            \\fn foo(bar: bool) callconv(.C) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
        .expected =
            \\fn foo(bar: bool, baz: bool) callconv(.C) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [1]usize{bar};
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
            \\fn foo() void {
            \\    const bar = 42;
            \\    const baz = [_]usize{ 1, 2, 3, bar };
            \\    _ = baz; // XXX ZLOPPY unused var baz
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
        .expected =
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
        .expected =
            \\fn foo() void {
            \\    const bar = [_]usize{ 1, 2, 3, 4 };
            \\    for (bar) |quux| {
            \\        _ = quux; // XXX ZLOPPY unused var quux
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
        .expected =
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
        .expected =
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
        .expected =
            \\fn foo() void {
            \\    const bar: union(enum) { val: bool } = .{ .val = true };
            \\    switch (bar) {
            \\        .val => |quux| {
            \\            _ = quux; // XXX ZLOPPY unused var quux
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
            \\fn foo(bar: ?bool) void {
            \\    while (bar) |quux| {
            \\        _ = quux; // XXX ZLOPPY unused var quux
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
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
        .expected =
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

fn applyOn(input: [:0]u8, expected: []const u8) ![]u8 {
    try zloppy.cleanSource("<test input>", input);

    var tree = try std.zig.parse(std.testing.allocator, input);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expect(tree.errors.len == 0);

    var patches = try zloppy.genPatches(std.testing.allocator, tree);
    defer patches.deinit();

    var out_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer out_buffer.deinit();

    try renderTreeWithPatches(&out_buffer, tree, patches);
    try std.testing.expectEqualStrings(expected, out_buffer.items);

    try out_buffer.append(0);
    return out_buffer.toOwnedSlice();
}

test "zloppy on" {
    for (test_cases_on) |t| {
        var input = try std.testing.allocator.dupe(u8, t.input[0..t.input.len + 1]);
        defer std.testing.allocator.free(input);

        var input2 = try applyOn(input[0..input.len - 1 :0], t.expected);
        defer std.testing.allocator.free(input2);
        std.testing.allocator.free(try applyOn(input2[0..input2.len - 1 :0], t.expected));
    }
}

const TestCase = struct {
    input: [:0]const u8,
    expected: [:0]const u8,
};
