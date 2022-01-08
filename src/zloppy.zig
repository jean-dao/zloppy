const std = @import("std");
const mem = std.mem;

const Tree = std.zig.Ast;
const Node = Tree.Node;
const TokenIndex = Tree.TokenIndex;
const NodeIndex = Tree.Node.Index;

pub const zloppy_comment = "// XXX ZLOPPY";

comptime {
    if (zloppy_comment[0] != '/' or zloppy_comment[1] != '/')
        @compileError("zloppy_comment must start with '//'");
}

pub const Patches = struct {
    const PatchIndex = u32;
    pub const Patch = union(enum) {
        remove,
        unused_var: TokenIndex,
        ignore_to_block_end: TokenIndex,
    };

    token_map: std.AutoHashMap(TokenIndex, PatchIndex),
    source_map: std.AutoHashMap(usize, PatchIndex),
    patches: std.ArrayList(std.ArrayList(Patch)),

    pub fn init(gpa: mem.Allocator) Patches {
        return .{
            .token_map = std.AutoHashMap(TokenIndex, PatchIndex).init(gpa),
            .source_map = std.AutoHashMap(usize, PatchIndex).init(gpa),
            .patches = std.ArrayList(std.ArrayList(Patch)).init(gpa),
        };
    }

    pub fn deinit(self: *Patches) void {
        self.token_map.deinit();
        self.source_map.deinit();
        for (self.patches.items) |patches| {
            patches.deinit();
        }
        self.patches.deinit();
    }

    fn addAny(self: *Patches, map: anytype, key: anytype, patch: Patch) !void {
        var patch_idx: PatchIndex = undefined;
        const result = try map.getOrPut(key);
        if (result.found_existing) {
            patch_idx = result.value_ptr.*;
        } else {
            patch_idx = @intCast(PatchIndex, self.patches.items.len);
            result.value_ptr.* = patch_idx;
            try self.patches.append(std.ArrayList(Patch).init(self.patches.allocator));
        }
        try self.patches.items[patch_idx].append(patch);
    }

    fn addOnToken(self: *Patches, token: TokenIndex, patch: Patch) !void {
        try self.addAny(&self.token_map, token, patch);
    }

    fn addOnSource(self: *Patches, src_idx: usize, patch: Patch) !void {
        try self.addAny(&self.source_map, src_idx, patch);
    }

    pub fn getForToken(self: Patches, token: TokenIndex) ?[]const Patch {
        if (self.token_map.get(token)) |patch_idx| {
            return self.patches.items[patch_idx].items[0..];
        } else {
            return null;
        }
    }

    pub fn getForSource(self: Patches, src_idx: usize) ?[]const Patch {
        if (self.source_map.get(src_idx)) |patch_idx| {
            return self.patches.items[patch_idx].items[0..];
        } else {
            return null;
        }
    }
};

const TreeTraversalError = error{
    OutOfMemory,
};

fn traverseNode(
    action: anytype,
    patches: *Patches,
    tree: Tree,
    node: NodeIndex,
) TreeTraversalError!void {
    try action.before(patches, tree, node);

    const datas = tree.nodes.items(.data);
    const tag = tree.nodes.items(.tag)[node];
    switch (tag) {
        // sub list from lhs to rhs
        .block,
        .block_semicolon,
        .array_init_dot,
        .array_init_dot_comma,
        .struct_init_dot,
        .struct_init_dot_comma,
        .container_decl,
        .container_decl_trailing,
        => {
            const first = datas[node].lhs;
            const last = datas[node].rhs;
            for (tree.extra_data[first..last]) |stmt_idx| {
                try traverseNode(action, patches, tree, stmt_idx);
            }
        },

        // check lhs (if set) and sub range list from rhs
        .array_init,
        .array_init_comma,
        .struct_init,
        .struct_init_comma,
        .call,
        .call_comma,
        .async_call,
        .async_call_comma,
        .@"switch",
        .switch_comma,
        .container_decl_arg,
        .container_decl_arg_trailing,
        .tagged_union_enum_tag,
        .tagged_union_enum_tag_trailing,
        => {
            if (datas[node].lhs != 0)
                try traverseNode(action, patches, tree, datas[node].lhs);
            const range = tree.extraData(datas[node].rhs, Node.SubRange);
            for (tree.extra_data[range.start..range.end]) |idx| {
                try traverseNode(action, patches, tree, idx);
            }
        },

        // check sub range list from lhs and rhs (if set)
        .switch_case => {
            const range = tree.extraData(datas[node].lhs, Node.SubRange);
            for (tree.extra_data[range.start..range.end]) |idx| {
                try traverseNode(action, patches, tree, idx);
            }
            if (datas[node].rhs != 0)
                try traverseNode(action, patches, tree, datas[node].rhs);
        },

        // both lhs and rhs must be checked (if set)
        .@"catch",
        .equal_equal,
        .bang_equal,
        .less_than,
        .greater_than,
        .less_or_equal,
        .greater_or_equal,
        .assign_mul,
        .assign_div,
        .assign_mod,
        .assign_add,
        .assign_sub,
        .assign_shl,
        .assign_shl_sat,
        .assign_shr,
        .assign_bit_and,
        .assign_bit_xor,
        .assign_bit_or,
        .assign_mul_wrap,
        .assign_add_wrap,
        .assign_sub_wrap,
        .assign_mul_sat,
        .assign_add_sat,
        .assign_sub_sat,
        .assign,
        .merge_error_sets,
        .mul,
        .div,
        .mod,
        .array_mult,
        .mul_wrap,
        .mul_sat,
        .add,
        .sub,
        .array_cat,
        .add_wrap,
        .sub_wrap,
        .add_sat,
        .sub_sat,
        .shl,
        .shl_sat,
        .shr,
        .bit_and,
        .bit_xor,
        .bit_or,
        .@"orelse",
        .bool_and,
        .bool_or,
        .array_type,
        .ptr_type_aligned,
        .ptr_type_sentinel,
        .slice_open,
        .array_access,
        .array_init_one,
        .array_init_one_comma,
        .array_init_dot_two,
        .array_init_dot_two_comma,
        .struct_init_one,
        .struct_init_one_comma,
        .struct_init_dot_two,
        .struct_init_dot_two_comma,
        .call_one,
        .call_one_comma,
        .async_call_one,
        .async_call_one_comma,
        .switch_case_one,
        .switch_range,
        .while_simple,
        .for_simple,
        .if_simple,
        .fn_decl,
        .builtin_call_two,
        .builtin_call_two_comma,
        .container_decl_two,
        .container_decl_two_trailing,
        .tagged_union_two,
        .tagged_union_two_trailing,
        .container_field_init,
        .container_field_align,
        .block_two,
        .block_two_semicolon,
        => {
            if (datas[node].lhs != 0)
                try traverseNode(action, patches, tree, datas[node].lhs);
            if (datas[node].rhs != 0)
                try traverseNode(action, patches, tree, datas[node].rhs);
        },

        // only lhs must be checked (if set)
        .field_access,
        .unwrap_optional,
        .bool_not,
        .negation,
        .bit_not,
        .negation_wrap,
        .address_of,
        .@"try",
        .@"await",
        .optional_type,
        .deref,
        .@"suspend",
        .@"resume",
        .@"return",
        .grouped_expression,
        => {
            if (datas[node].lhs != 0)
                try traverseNode(action, patches, tree, datas[node].lhs);
        },

        // only rhs must be checked (if set)
        .global_var_decl,
        .local_var_decl,
        .simple_var_decl,
        .aligned_var_decl,
        .test_decl,
        .@"errdefer",
        .@"defer",
        .@"break",
        => {
            if (datas[node].rhs != 0)
                try traverseNode(action, patches, tree, datas[node].rhs);
        },

        // check lhs and 2 indices at rhs
        .while_cont,
        .@"if",
        .slice,
        .container_field,
        => {
            const TwoIndices = struct {
                expr1: NodeIndex,
                expr2: NodeIndex,
            };

            try traverseNode(action, patches, tree, datas[node].lhs);

            const extra = tree.extraData(datas[node].rhs, TwoIndices);
            if (extra.expr1 != 0)
                try traverseNode(action, patches, tree, extra.expr1);
            if (extra.expr2 != 0)
                try traverseNode(action, patches, tree, extra.expr2);
        },

        // check lhs and 3 indices at rhs
        .slice_sentinel,
        .@"while",
        => {
            const ThreeIndices = struct {
                expr1: NodeIndex,
                expr2: NodeIndex,
                expr3: NodeIndex,
            };

            try traverseNode(action, patches, tree, datas[node].lhs);

            const extra = tree.extraData(datas[node].rhs, ThreeIndices);
            if (extra.expr1 != 0)
                try traverseNode(action, patches, tree, extra.expr1);
            if (extra.expr2 != 0)
                try traverseNode(action, patches, tree, extra.expr2);
            if (extra.expr3 != 0)
                try traverseNode(action, patches, tree, extra.expr3);
        },

        else => {},
    }

    try action.after(patches, tree, node);
}

const ZloppyChecks = struct {
    const Scope = struct {
        const Binding = struct {
            token: TokenIndex,
            anchor: TokenIndex,
            used: bool = false,
        };

        bindings: std.ArrayList(Binding),
        block_anchor: TokenIndex,
        return_reached: bool,
        unreachable_from: ?TokenIndex,

        fn init(gpa: mem.Allocator, block_anchor: TokenIndex) Scope {
            return .{
                .bindings = std.ArrayList(Binding).init(gpa),
                .block_anchor = block_anchor,
                .return_reached = false,
                .unreachable_from = null,
            };
        }

        fn deinit(self: Scope) void {
            self.bindings.deinit();
        }

        fn addPatches(self: Scope, patches: *Patches) !void {
            for (self.bindings.items) |binding| {
                if (!binding.used) {
                    try patches.addOnToken(binding.anchor, .{ .unused_var = binding.token });
                }
            }

            if (self.unreachable_from) |token| {
                try patches.addOnToken(self.block_anchor, .{ .ignore_to_block_end = token });
            }
        }

        fn addBinding(self: *Scope, token: TokenIndex) !void {
            if (self.return_reached)
                return;
            try self.bindings.append(.{ .token = token, .anchor = self.block_anchor });
        }

        fn addBindingWithAnchor(self: *Scope, token: TokenIndex, anchor: TokenIndex) !void {
            if (self.return_reached)
                return;
            try self.bindings.append(.{ .token = token, .anchor = anchor });
        }

        fn markReturn(self: *Scope) void {
            self.return_reached = true;
        }

        fn markUnreachableFrom(self: *Scope, tree: Tree, node: NodeIndex) void {
            if (self.unreachable_from == null) {
                self.unreachable_from = tree.nodes.items(.main_token)[node];
            }
        }

        fn setUsed(self: *Scope, tree: Tree, token: TokenIndex) bool {
            // still return true, since we don't want to check parent scope
            if (self.return_reached)
                return true;

            const tag = tree.tokens.items(.tag)[token];
            std.debug.assert(tag == .identifier);
            const name = tree.tokenSlice(token);

            for (self.bindings.items) |*binding| {
                const bname = tree.tokenSlice(binding.token);
                if (mem.eql(u8, name, bname)) {
                    binding.used = true;
                    return true;
                }
            }

            return false;
        }
    };

    scopes: std.ArrayList(Scope),

    fn init(gpa: mem.Allocator) !ZloppyChecks {
        var self = ZloppyChecks{
            .scopes = std.ArrayList(Scope).init(gpa),
        };

        try self.scopes.append(Scope.init(gpa, 0));
        return self;
    }

    fn deinit(self: *ZloppyChecks) void {
        std.debug.assert(self.scopes.items.len == 1);
        self.scopes.items[0].deinit();
        self.scopes.deinit();
    }

    fn scope(self: *ZloppyChecks) *Scope {
        std.debug.assert(self.scopes.items.len > 0);
        return &self.scopes.items[self.scopes.items.len - 1];
    }

    fn pushScope(self: *ZloppyChecks, block_anchor: TokenIndex) !void {
        try self.scopes.append(Scope.init(self.scopes.allocator, block_anchor));
    }

    fn popScope(self: *ZloppyChecks) void {
        std.debug.assert(self.scopes.items.len > 1);
        self.scope().deinit();
        self.scopes.items.len -= 1;
    }

    fn setUsed(self: *ZloppyChecks, tree: Tree, token: TokenIndex) void {
        var i: usize = self.scopes.items.len;
        while (i > 0) : (i -= 1) {
            if (self.scopes.items[i - 1].setUsed(tree, token))
                return;
        }
    }

    fn before(self: *ZloppyChecks, patches: *Patches, tree: Tree, node: NodeIndex) !void {
        _ = patches;

        if (self.scope().return_reached) {
            self.scope().markUnreachableFrom(tree, node);
        }

        switch (tree.nodes.items(.tag)[node]) {
            // create a new scope for fn decls, blocks, containers
            .fn_decl => {
                const body = tree.nodes.items(.data)[node].rhs;
                try self.pushScope(tree.nodes.items(.main_token)[body]);
            },
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            => {
                try self.pushScope(tree.nodes.items(.main_token)[node]);
            },
            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                try self.pushScope(tree.nodes.items(.main_token)[node]);
            },

            // create a new scope and add the capture binding for captures
            .switch_case_one,
            .while_simple,
            .for_simple,
            .if_simple,
            => {
                const rhs = tree.nodes.items(.data)[node].rhs;
                const maybe_capture = tree.firstToken(rhs) - 1;
                if (tree.tokens.items(.tag)[maybe_capture] == .pipe) {
                    const anchor = tree.nodes.items(.main_token)[rhs];
                    try self.pushScope(anchor);

                    const capture = maybe_capture - 1;
                    std.debug.assert(tree.tokens.items(.tag)[capture] == .identifier);
                    try self.scope().addBinding(capture);
                }
            },
            else => {},
        }
    }

    fn after(self: *ZloppyChecks, patches: *Patches, tree: Tree, node: Node.Index) !void {
        const node_data = tree.nodes.items(.data)[node];
        const node_token = tree.nodes.items(.main_token)[node];
        switch (tree.nodes.items(.tag)[node]) {
            // check unused variable in current fn_decls, blocks, captures
            .fn_decl,
            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                try self.scope().addPatches(patches);
                self.popScope();
            },
            .switch_case_one,
            .while_simple,
            .for_simple,
            .if_simple,
            => {
                const rhs = tree.nodes.items(.data)[node].rhs;
                const maybe_capture = tree.firstToken(rhs) - 1;
                if (tree.tokens.items(.tag)[maybe_capture] == .pipe) {
                    try self.scope().addPatches(patches);
                    self.popScope();
                }
            },

            // only pop scope in containers, don't check for unused variables
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            => {
                self.popScope();
            },

            // update current scope for var decls and fn param decls
            .global_var_decl, .local_var_decl, .simple_var_decl, .aligned_var_decl => {
                const name = node_token + 1;
                try self.scope().addBindingWithAnchor(name, node_token);
            },
            .fn_proto_simple => {
                var param = node_token + 3;
                if (tree.tokens.items(.tag)[param] == .keyword_comptime)
                    param += 1;
                if (tree.tokens.items(.tag)[param] == .identifier)
                    try self.scope().addBinding(param);
            },
            .fn_proto_multi => {
                const params_range = tree.extraData(node_data.lhs, Node.SubRange);
                for (tree.extra_data[params_range.start..params_range.end]) |param_idx| {
                    const param = tree.firstToken(param_idx) - 2;
                    try self.scope().addBinding(param);
                }
            },
            .fn_proto_one => {
                const extra = tree.extraData(node_data.lhs, Node.FnProtoOne);
                if (extra.param != 0) {
                    const param = tree.firstToken(extra.param) - 2;
                    try self.scope().addBinding(param);
                }
            },
            .fn_proto => {
                const extra = tree.extraData(node_data.lhs, Node.FnProto);
                for (tree.extra_data[extra.params_start..extra.params_end]) |param_idx| {
                    const param = tree.firstToken(param_idx) - 2;
                    try self.scope().addBinding(param);
                }
            },

            // set used bit for identifier
            .identifier => {
                self.setUsed(tree, node_token);
            },

            // indicate next statements in scope will unreachable
            .@"return" => {
                self.scope().markReturn();
            },

            else => {},
        }
    }
};

pub fn genPatches(gpa: mem.Allocator, tree: Tree) !Patches {
    var patches = Patches.init(gpa);
    var checks = try ZloppyChecks.init(gpa);
    defer checks.deinit();

    //std.debug.print("tokens:\n", .{});
    //for (tree.tokens.items(.tag)) |tag, i| {
    //    std.debug.print("[{}] {}\n", .{ i, tag });
    //}

    //std.debug.print("nodes:\n", .{});
    //for (tree.nodes.items(.tag)) |tag, i| {
    //    std.debug.print("[{}] {}\n", .{ i, tag });
    //}

    for (tree.rootDecls()) |node| {
        try traverseNode(&checks, &patches, tree, node);
    }

    // return without checking unused variables in top-level scope (not needed)
    return patches;
}

fn isAllowedInZloppyComment(char: u8) bool {
    return switch (char) {
        '"', '/', '\'', ';', ',', '{', '}' => false,
        else => true,
    };
}

fn cleanLine(
    source: []u8,
    start: usize,
    end: usize,
    zloppy_comment_start: usize,
) !void {
    const descr = mem.trimLeft(u8, source[zloppy_comment_start + zloppy_comment.len .. end], " ");
    if (mem.startsWith(u8, descr, "unused var")) {
        // overwrite line '\n' (end + 1) to make sure no extraneous empty line is left over
        mem.set(u8, source[start .. end + 1], ' ');
    } else if (mem.startsWith(u8, descr, "unreachable code")) {
        mem.set(u8, source[zloppy_comment_start..end], ' ');
        if (mem.indexOf(u8, source[start..end], "//")) |first_comment| {
            mem.set(u8, source[start + first_comment .. start + first_comment + 2], ' ');
        } else {
            return error.InvalidCommentFound;
        }
    } else {
        return error.InvalidCommentFound;
    }
}

pub fn cleanSource(filename: []const u8, source: []u8) !void {
    var start: usize = 0;
    var line_no: usize = 1;
    blk: while (mem.indexOfPos(u8, source, start, "\n")) |end| : ({
        start = end + 1;
        line_no += 1;
    }) {
        const line = source[start..end];
        if (line.len < zloppy_comment.len)
            continue :blk;

        // Since not all characters are allowed in zloppy comments, we can
        // simply look for "// XXX ZLOPPY" from the end of the line without
        // having to check for string literals and such.
        var i: usize = line.len;
        while (i > 1) : (i -= 1) {
            const maybe_comment_start = line[i - 2 .. i];
            const char = line[i - 1];
            if (mem.eql(u8, maybe_comment_start, "//") and
                mem.startsWith(u8, line[i - 2 ..], zloppy_comment))
            {
                cleanLine(source, start, end, start + i - 2) catch |err| {
                    std.log.warn(
                        "invalid zloppy comment found in file '{s}' on line {}, " ++
                            "file left untouched",
                        .{ filename, line_no },
                    );
                    return err;
                };
            } else if (!isAllowedInZloppyComment(char)) {
                continue :blk;
            }
        }
    }
}
