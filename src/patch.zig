const std = @import("std");

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
    };

    token_map: std.AutoHashMap(TokenIndex, PatchIndex),
    source_map: std.AutoHashMap(usize, PatchIndex),
    patches: std.ArrayList(std.ArrayList(Patch)),

    pub fn init(gpa: std.mem.Allocator) Patches {
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
        .switch_case_one,
        .switch_case,
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

const FixupUnused = struct {
    const Scope = struct {
        const Binding = struct {
            token: TokenIndex,
            anchor: TokenIndex,
            used: bool = false,
        };

        bindings: std.ArrayList(Binding),
        block_anchor: TokenIndex,

        fn init(gpa: std.mem.Allocator, block_anchor: TokenIndex) Scope {
            return .{
                .bindings = std.ArrayList(Binding).init(gpa),
                .block_anchor = block_anchor,
            };
        }

        fn deinit(self: Scope) void {
            self.bindings.deinit();
        }

        fn patchUnused(self: Scope, patches: *Patches) !void {
            for (self.bindings.items) |binding| {
                if (!binding.used) {
                    try patches.addOnToken(binding.anchor, .{ .unused_var = binding.token });
                }
            }
        }

        fn addBinding(self: *Scope, token: TokenIndex) !void {
            try self.bindings.append(.{ .token = token, .anchor = self.block_anchor });
        }

        fn addBindingWithAnchor(self: *Scope, token: TokenIndex, anchor: TokenIndex) !void {
            try self.bindings.append(.{ .token = token, .anchor = anchor });
        }

        fn setUsed(self: *Scope, tree: Tree, token: TokenIndex) bool {
            const tag = tree.tokens.items(.tag)[token];
            std.debug.assert(tag == .identifier);
            const name = tree.tokenSlice(token);

            for (self.bindings.items) |*binding| {
                const bname = tree.tokenSlice(binding.token);
                if (std.mem.eql(u8, name, bname)) {
                    binding.used = true;
                    return true;
                }
            }

            return false;
        }
    };

    scopes: std.ArrayList(Scope),

    fn init(gpa: std.mem.Allocator) !FixupUnused {
        var self = FixupUnused{
            .scopes = std.ArrayList(Scope).init(gpa),
        };

        try self.scopes.append(Scope.init(gpa, 0));
        return self;
    }

    fn deinit(self: *FixupUnused) void {
        std.debug.assert(self.scopes.items.len == 1);
        self.scopes.items[0].deinit();
        self.scopes.deinit();
    }

    fn scope(self: *FixupUnused) *Scope {
        std.debug.assert(self.scopes.items.len > 0);
        return &self.scopes.items[self.scopes.items.len - 1];
    }

    fn pushScope(self: *FixupUnused, block_anchor: TokenIndex) !void {
        try self.scopes.append(Scope.init(self.scopes.allocator, block_anchor));
    }

    fn popScope(self: *FixupUnused) void {
        std.debug.assert(self.scopes.items.len > 1);
        self.scope().deinit();
        self.scopes.items.len -= 1;
    }

    fn setUsed(self: *FixupUnused, tree: Tree, token: TokenIndex) void {
        var i: usize = self.scopes.items.len;
        while (i > 0) : (i -= 1) {
            if (self.scopes.items[i - 1].setUsed(tree, token))
                return;
        }
    }

    fn before(self: *FixupUnused, patches: *Patches, tree: Tree, node: NodeIndex) !void {
        _ = patches;
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

    fn after(self: *FixupUnused, patches: *Patches, tree: Tree, node: Node.Index) !void {
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
                try self.scope().patchUnused(patches);
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
                    try self.scope().patchUnused(patches);
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

            else => {},
        }
    }
};

const RemoveZloppy = struct {
    fn before(self: *RemoveZloppy, patches: *Patches, tree: Tree, node: NodeIndex) !void {
        _ = self;
        _ = patches;
        _ = tree;
        _ = node;
    }

    fn after(self: *RemoveZloppy, patches: *Patches, tree: Tree, node: NodeIndex) !void {
        _ = self;
        switch (tree.nodes.items(.tag)[node]) {
            // find '_ = ...' assignments with a '// XXX ZLOPPY' comment on the previous line
            // mark both the comment and the assignment for removal
            .assign => blk: {
                const lhs = tree.nodes.items(.data)[node].lhs;
                const name = tree.nodes.items(.main_token)[lhs];

                if (!std.mem.eql(u8, tree.tokenSlice(name), "_"))
                    break :blk;

                const name_idx = tree.tokens.items(.start)[name];
                if (name_idx == 0)
                    break :blk;

                // backtrack to previous line, should only be indentation (spaces)
                const end = end: {
                    if (std.mem.lastIndexOf(u8, tree.source[0..name_idx - 1], "\n")) |nl_idx| {
                        if (!std.mem.allEqual(u8, tree.source[nl_idx + 1..name_idx], ' '))
                            break :blk;

                        if (nl_idx == 0)
                            break :blk;
                        break :end nl_idx;
                    } else {
                        break :blk;
                    }
                };

                // find out if previous line contains '// XXX ZLOPPY'
                if (std.mem.lastIndexOf(u8, tree.source[0..end], "\n")) |start| {
                    const line = tree.source[start..end];
                    if (std.mem.indexOf(u8, line, zloppy_comment)) |offset| {
                        // mark comment to be removed
                        try patches.addOnSource(start + offset, .remove);
                        // mark var decl to be removed
                        try patches.addOnToken(tree.nodes.items(.main_token)[node], .remove);
                    }
                }
            },

            else => {},
        }
    }
};

pub fn patchTreeOn(gpa: std.mem.Allocator, tree: Tree) !Patches {
    var patches = Patches.init(gpa);
    var action = try FixupUnused.init(gpa);
    defer action.deinit();

    std.debug.print("tokens:\n", .{});
    for (tree.tokens.items(.tag)) |tag, i| {
        std.debug.print("[{}] {}\n", .{ i, tag });
    }

    std.debug.print("nodes:\n", .{});
    for (tree.nodes.items(.tag)) |tag, i| {
        std.debug.print("[{}] {}\n", .{ i, tag });
    }

    for (tree.rootDecls()) |node| {
        try traverseNode(&action, &patches, tree, node);
    }

    // return without checking unused variables in top-level scope
    return patches;
}

pub fn patchTreeOff(gpa: std.mem.Allocator, tree: Tree) !Patches {
    var patches = Patches.init(gpa);
    var action = RemoveZloppy{};

    for (tree.rootDecls()) |node| {
        try traverseNode(&action, &patches, tree, node);
    }

    return patches;
}
