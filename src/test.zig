const std = @import("std");

const zloppy = @import("zloppy.zig");

// zig fmt: off
const test_cases_off = [_]TestCase{
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    // existing comment
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    // existing comment2
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    // existing comment
            \\    // existing comment2
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    // existing comment
            \\    // _ = bar; // XXX ZLOPPY unreachable code
            \\    //// existing comment2 // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    // existing comment
            \\    _ = bar;
            \\    // existing comment2
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    // existing comment
            \\    // _ = bar; // XXX ZLOPPY unreachable code
            \\    //// existing comment2 // XXX ZLOPPY unreachable code
            \\    // _ = 42; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    // existing comment
            \\    _ = bar;
            \\    // existing comment2
            \\    _ = 42;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    //while (true) { // XXX ZLOPPY unreachable code
            \\    //_ = bar; // XXX ZLOPPY unreachable code
            \\    //if (42 > 0) { // XXX ZLOPPY unreachable code
            \\    //_ = 1; // XXX ZLOPPY unreachable code
            \\    //} // XXX ZLOPPY unreachable code
            \\    //} // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    while (true) {
            \\        _ = bar;
            \\        if (42 > 0) {
            \\            _ = 1;
            \\        }
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) u32 {
            \\    while (true) {
            \\        _ = bar;
            \\        if (42 > 0) {
            \\            return 0;
            \\            //_ = 1; // XXX ZLOPPY unreachable code
            \\        }
            \\        _ = 42;
            \\        return if (bar) 42 else 1 + 2 + 3;
            \\        //_ = true; // XXX ZLOPPY unreachable code
            \\        //{ // XXX ZLOPPY unreachable code
            \\        //// some comment // XXX ZLOPPY unreachable code
            \\        //} // XXX ZLOPPY unreachable code
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) u32 {
            \\    while (true) {
            \\        _ = bar;
            \\        if (42 > 0) {
            \\            return 0;
            \\            _ = 1;
            \\        }
            \\        _ = 42;
            \\        return if (bar) 42 else 1 + 2 + 3;
            \\        _ = true;
            \\        {
            \\            // some comment
            \\        }
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    // zig fmt: off
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    // zig fmt: off
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    _ = bar(); // XXX ZLOPPY ignored call return value
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    bar();
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    switch (42) {
            \\        inline else => |bar| {
            \\            _ = bar; // XXX ZLOPPY unused var bar
            \\        },
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    switch (42) {
            \\        inline else => |bar| {},
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const size = 42;
            \\    const buf: [size]u8 align(8) = undefined;
            \\    _ = buf;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    const size = 42;
            \\    const buf: [size]u8 align(8) = undefined;
            \\    _ = buf;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for (&.{}) |_| {} else {
            \\        const bar = true;
            \\        _ = bar; // XXX ZLOPPY unused var bar
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for (&.{}) |_| {} else {
            \\        const bar = true;
            \\    }
            \\}
            \\
        ,
    },
};
// zig fmt: on

// zig fmt: off
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
            \\    _ = baz; // XXX ZLOPPY unused var baz
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
            \\    _ = trois; // XXX ZLOPPY unused var trois
            \\    _ = deux; // XXX ZLOPPY unused var deux
            \\    _ = un; // XXX ZLOPPY unused var un
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
            \\    _ = cinq; // XXX ZLOPPY unused var cinq
            \\    _ = trois; // XXX ZLOPPY unused var trois
            \\    _ = deux; // XXX ZLOPPY unused var deux
            \\    _ = un; // XXX ZLOPPY unused var un
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
            \\    _ = baz; // XXX ZLOPPY unused var baz
            \\    _ = bar; // XXX ZLOPPY unused var bar
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
    .{
        .input =
            \\fn foo() void {
            \\    return;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    return;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    return;
            \\    _ = 42;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    return;
            \\    //_ = 42; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    return;
            \\    // some comment
            \\    _ = 42;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    return;
            \\    // some comment
            \\    //_ = 42; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    return;
            \\    _ = 42;
            \\    while (true) {
            \\        // some comment
            \\        _ = true;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    return;
            \\    //_ = 42; // XXX ZLOPPY unreachable code
            \\    //while (true) { // XXX ZLOPPY unreachable code
            \\    //// some comment // XXX ZLOPPY unreachable code
            \\    //_ = true; // XXX ZLOPPY unreachable code
            \\    //} // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    return;
            \\    _ = bar;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    return;
            \\    //_ = bar; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    //_ = bar; // XXX ZLOPPY unreachable code
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
            \\    if (true)
            \\        return;
            \\    _ = bar;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    if (true)
            \\        return;
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    if (true) {
            \\        return;
            \\    }
            \\    _ = bar;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    if (true) {
            \\        return;
            \\    }
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    while (true)
            \\        return;
            \\    _ = bar;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    while (true)
            \\        return;
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    for ([_]u8{ 1, 2, 3 }) |baz|
            \\        _ = 42;
            \\    _ = bar;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    for ([_]u8{ 1, 2, 3 }) |baz| {
            \\        _ = baz; // XXX ZLOPPY unused var baz
            \\        _ = 42;
            \\    }
            \\    _ = bar;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    switch (bar) {
            \\        .foo, .bar => return,
            \\        .baz => {},
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    switch (bar) {
            \\        .foo, .bar => return,
            \\        .baz => {},
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    {
            \\        _ = 42;
            \\    }
            \\    const baz = 0;
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    {
            \\        _ = 42;
            \\    }
            \\    const baz = 0;
            \\    _ = baz; // XXX ZLOPPY unused var baz
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    {
            \\        _ = 42;
            \\    }
            \\    return;
            \\    _ = "unreachable";
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\    {
            \\        _ = 42;
            \\    }
            \\    return;
            \\    //_ = "unreachable"; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    {
            \\        return;
            \\        //_ = "unreachable"; // XXX ZLOPPY unreachable code
            \\    }
            \\    const bar = "unused";
            \\}
            \\
            \\fn bar(quux: bool) void {}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    {
            \\        return;
            \\        //_ = "unreachable"; // XXX ZLOPPY unreachable code
            \\    }
            \\    const bar = "unused";
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\}
            \\
            \\fn bar(quux: bool) void {
            \\    _ = quux; // XXX ZLOPPY unused var quux
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    _ = 42 orelse return;
            \\    _ = "reachable code";
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    _ = 42 orelse return;
            \\    _ = "reachable code";
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    _ = 42 catch return;
            \\    _ = "reachable code";
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    _ = 42 catch return;
            \\    _ = "reachable code";
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(_: bool) void {}
            \\
        ,
        .expected =
            \\fn foo(_: bool) void {}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime Bar: type) void {
            \\    const quux: std.ArrayList(Bar) = undefined;
            \\}
            \\
        ,
        .expected =
            \\fn foo(comptime Bar: type) void {
            \\    const quux: std.ArrayList(Bar) = undefined;
            \\    _ = quux; // XXX ZLOPPY unused var quux
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    comptime {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    comptime {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: bool) void {
            \\    nosuspend {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: bool) void {
            \\    nosuspend {
            \\        _ = bar;
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(bar: u8) void {
            \\    var res: u8 = undefined;
            \\    @mulWithOverflow(u8, bar, 8, &res);
            \\}
            \\
        ,
        .expected =
            \\fn foo(bar: u8) void {
            \\    var res: u8 = undefined;
            \\    @mulWithOverflow(u8, bar, 8, &res);
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime T: type, bar: T) void {
            \\}
            \\
        ,
        .expected =
            \\fn foo(comptime T: type, bar: T) void {
            \\    _ = bar; // XXX ZLOPPY unused var bar
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn drc(comptime second: bool, comptime rc: u8, t: BlockVec, tx: BlockVec) BlockVec {
            \\    var s: BlockVec = undefined;
            \\    var ts: BlockVec = undefined;
            \\    return asm (
            \\        \\ vaeskeygenassist %[rc], %[t], %[s]
            \\        \\ vpslldq $4, %[tx], %[ts]
            \\        \\ vpxor   %[ts], %[tx], %[r]
            \\        \\ vpslldq $8, %[r], %[ts]
            \\        \\ vpxor   %[ts], %[r], %[r]
            \\        \\ vpshufd %[mask], %[s], %[ts]
            \\        \\ vpxor   %[ts], %[r], %[r]
            \\        : [r] "=&x" (-> BlockVec),
            \\          [s] "=&x" (s),
            \\          [ts] "=&x" (ts),
            \\        : [rc] "n" (rc),
            \\          [t] "x" (t),
            \\          [tx] "x" (tx),
            \\          [mask] "n" (@as(u8, if (second) 0xaa else 0xff)),
            \\    );
            \\}
            \\
        ,
        .expected =
            \\fn drc(comptime second: bool, comptime rc: u8, t: BlockVec, tx: BlockVec) BlockVec {
            \\    var s: BlockVec = undefined;
            \\    var ts: BlockVec = undefined;
            \\    return asm (
            \\        \\ vaeskeygenassist %[rc], %[t], %[s]
            \\        \\ vpslldq $4, %[tx], %[ts]
            \\        \\ vpxor   %[ts], %[tx], %[r]
            \\        \\ vpslldq $8, %[r], %[ts]
            \\        \\ vpxor   %[ts], %[r], %[r]
            \\        \\ vpshufd %[mask], %[s], %[ts]
            \\        \\ vpxor   %[ts], %[r], %[r]
            \\        : [r] "=&x" (-> BlockVec),
            \\          [s] "=&x" (s),
            \\          [ts] "=&x" (ts),
            \\        : [rc] "n" (rc),
            \\          [t] "x" (t),
            \\          [tx] "x" (tx),
            \\          [mask] "n" (@as(u8, if (second) 0xaa else 0xff)),
            \\    );
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime T: type) error.OutOfMemory!T {}
            \\
        ,
        .expected =
            \\fn foo(comptime T: type) error.OutOfMemory!T {}
            \\
        ,
    },
    .{
        .input =
            \\fn Foo(comptime T: type) type {
            \\    return struct {
            \\        pub usingnamespace T;
            \\    };
            \\}
            \\
        ,
        .expected =
            \\fn Foo(comptime T: type) type {
            \\    return struct {
            \\        pub usingnamespace T;
            \\    };
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime s: u8) [4:s]u8 {}
            \\
        ,
        .expected =
            \\fn foo(comptime s: u8) [4:s]u8 {}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(comptime s: u8) [:s]align(42) u8 {}
            \\
        ,
        .expected =
            \\fn foo(comptime s: u8) [:s]align(42) u8 {}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for ([_]u8{ 1, 2, 3 }) |i| {
            \\        continue;
            \\        _ = i;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for ([_]u8{ 1, 2, 3 }) |i| {
            \\        _ = i; // XXX ZLOPPY unused var i
            \\        continue;
            \\        //_ = i; // XXX ZLOPPY unreachable code
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for ([_]u8{ 1, 2, 3 }) |i| {
            \\        break;
            \\        _ = i;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for ([_]u8{ 1, 2, 3 }) |i| {
            \\        _ = i; // XXX ZLOPPY unused var i
            \\        break;
            \\        //_ = i; // XXX ZLOPPY unreachable code
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {}
            \\
            \\fn bar() void {
            \\    foo();
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {}
            \\
            \\fn bar() void {
            \\    foo();
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() u32 {
            \\    return 0;
            \\}
            \\
            \\fn bar() void {
            \\    foo();
            \\}
            \\
        ,
        .expected =
            \\fn foo() u32 {
            \\    return 0;
            \\}
            \\
            \\fn bar() void {
            \\    _ = foo(); // XXX ZLOPPY ignored call return value
            \\}
            \\
        ,
    },
    .{
        .input =
            \\const Foo = struct {
            \\    fn quux() u32 {
            \\        return 0;
            \\    }
            \\};
            \\
            \\fn bar() void {
            \\    Foo.quux();
            \\}
            \\
        ,
        .expected =
            \\const Foo = struct {
            \\    fn quux() u32 {
            \\        return 0;
            \\    }
            \\};
            \\
            \\fn bar() void {
            \\    _ = Foo.quux(); // XXX ZLOPPY ignored call return value
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    switch (42) {
            \\        inline else => |bar| {},
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    switch (42) {
            \\        inline else => |bar| {
            \\            _ = bar; // XXX ZLOPPY unused var bar
            \\        },
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const size = 42;
            \\    const buf: [size]u8 align(8) = undefined;
            \\    _ = buf;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    const size = 42;
            \\    const buf: [size]u8 align(8) = undefined;
            \\    _ = buf;
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(a: anytype) void {}
            \\
        ,
        .expected =
            \\fn foo(a: anytype) void {
            \\    _ = a; // XXX ZLOPPY unused var a
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo(f: fn (bar: usize) void) void {}
            \\
        ,
        .expected =
            \\fn foo(f: fn (bar: usize) void) void {
            \\    _ = f; // XXX ZLOPPY unused var f
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    unreachable;
            \\    _ = 42;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    unreachable;
            \\    //_ = 42; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    @panic("hello");
            \\    _ = 42;
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    @panic("hello");
            \\    //_ = 42; // XXX ZLOPPY unreachable code
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for (&.{}) |_| {} else {
            \\        const bar = true;
            \\    }
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for (&.{}) |_| {} else {
            \\        const bar = true;
            \\        _ = bar; // XXX ZLOPPY unused var bar
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    const a = 42;
            \\    for (0..a) |i| {}
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    const a = 42;
            \\    for (0..a) |i| {
            \\        _ = i; // XXX ZLOPPY unused var i
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for (&.{}, 0..) |foo, i| {}
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for (&.{}, 0..) |foo, i| {
            \\        _ = foo; // XXX ZLOPPY unused var foo
            \\        _ = i; // XXX ZLOPPY unused var i
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for (&.{}, 0..) |*foo, i| {}
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for (&.{}, 0..) |*foo, i| {
            \\        _ = foo; // XXX ZLOPPY unused var foo
            \\        _ = i; // XXX ZLOPPY unused var i
            \\    }
            \\}
            \\
        ,
    },
    .{
        .input =
            \\fn foo() void {
            \\    for (&.{}, 0..) |foo, *i| {}
            \\}
            \\
        ,
        .expected =
            \\fn foo() void {
            \\    for (&.{}, 0..) |foo, *i| {
            \\        _ = foo; // XXX ZLOPPY unused var foo
            \\        _ = i; // XXX ZLOPPY unused var i
            \\    }
            \\}
            \\
        ,
    },
};
// zig fmt: on

fn applyOn(input: [:0]u8, expected: []const u8) ![]u8 {
    _ = try zloppy.cleanSource("<test input>", input);

    var tree = try std.zig.Ast.parse(std.testing.allocator, input, .zig);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expect(tree.errors.len == 0);

    var patches = try zloppy.genPatches(std.testing.allocator, tree, true);
    defer patches.deinit();

    var out_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer out_buffer.deinit();

    try @import("render.zig").renderTreeWithPatches(&out_buffer, tree, &patches);
    try std.testing.expectEqualStrings(expected, out_buffer.items);

    try out_buffer.append(0);
    return out_buffer.toOwnedSlice();
}

fn applyOff(input: [:0]u8, expected: []const u8) ![]u8 {
    _ = try zloppy.cleanSource("<test input>", input);

    var tree = try std.zig.Ast.parse(std.testing.allocator, input, .zig);
    defer tree.deinit(std.testing.allocator);
    try std.testing.expect(tree.errors.len == 0);

    var out_buffer = std.ArrayList(u8).init(std.testing.allocator);
    defer out_buffer.deinit();

    try tree.renderToArrayList(&out_buffer);
    try std.testing.expectEqualStrings(expected, out_buffer.items);

    try out_buffer.append(0);
    return out_buffer.toOwnedSlice();
}

fn applyFn(fun: anytype, count: u8, input: [:0]const u8, expected: [:0]const u8) !void {
    var last_output = try std.testing.allocator.dupe(u8, input[0 .. input.len + 1]);
    for (0..count) |_| {
        var output = try fun(last_output[0 .. last_output.len - 1 :0], expected);
        std.testing.allocator.free(last_output);
        last_output = output;
    }
    std.testing.allocator.free(last_output);
}

test "zloppy off" {
    for (test_cases_off) |t| {
        try applyFn(applyOff, 2, t.input, t.expected);
    }
}

test "zloppy on" {
    for (test_cases_on) |t| {
        try applyFn(applyOn, 2, t.input, t.expected);
    }
}

const TestCase = struct {
    input: [:0]const u8,
    expected: [:0]const u8,
};
