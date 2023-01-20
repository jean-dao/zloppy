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
        // function parameters: anchored on block main token (lbrace)
        // captures: if block exists, anchored on block main token (lbrace)
        // if not, anchored on statement main token
        // declarations: anchored on decl main token (`var` or `const`)
        unused_var: TokenIndex,

        // anchored on block main token (lbrace)
        first_unreachable_stmt: TokenIndex,

        // anchored on block main token (lbrace)
        ignore_ret_val: TokenIndex,
    };

    // mapping between anchors and patchsets
    map: std.AutoHashMap(TokenIndex, PatchIndex),
    patches: std.ArrayList(std.ArrayList(Patch)),
    rendered_comments: u32 = 0,

    pub fn init(gpa: mem.Allocator) Patches {
        return .{
            .map = std.AutoHashMap(TokenIndex, PatchIndex).init(gpa),
            .patches = std.ArrayList(std.ArrayList(Patch)).init(gpa),
        };
    }

    pub fn deinit(self: *Patches) void {
        self.map.deinit();
        for (self.patches.items) |patches| {
            patches.deinit();
        }
        self.patches.deinit();
    }

    fn append(self: *Patches, token: TokenIndex, patch: Patch) !void {
        var patch_idx: PatchIndex = undefined;
        const result = try self.map.getOrPut(token);
        if (result.found_existing) {
            patch_idx = result.value_ptr.*;
        } else {
            patch_idx = @intCast(PatchIndex, self.patches.items.len);
            result.value_ptr.* = patch_idx;
            try self.patches.append(std.ArrayList(Patch).init(self.patches.allocator));
        }
        try self.patches.items[patch_idx].append(patch);
    }

    pub fn get(self: Patches, token: TokenIndex) ?[]const Patch {
        if (self.map.get(token)) |patch_idx| {
            return self.patches.items[patch_idx].items[0..];
        } else {
            return null;
        }
    }
};

const TreeTraversalError = error{
    OutOfMemory,
};

fn traverseNodeExtraIndices(
    comptime N: comptime_int,
    action: anytype,
    patches: *Patches,
    tree: Tree,
    parent: NodeIndex,
    node: NodeIndex,
) TreeTraversalError!bool {
    inline for ([_]u8{0} ** N) |_, i| {
        const extra = tree.extra_data[node + i];
        if (extra != 0 and !try traverseNode(action, patches, tree, parent, extra))
            return false;
    }
    return true;
}

fn traverseNode(
    action: anytype,
    patches: *Patches,
    tree: Tree,
    parent: NodeIndex,
    node: NodeIndex,
) TreeTraversalError!bool {
    var cont = try action.before(patches, tree, parent, node);
    if (!cont)
        return false;

    const datas = tree.nodes.items(.data);
    const tag = tree.nodes.items(.tag)[node];
    blk: {
        switch (tag) {
            // sub list from lhs to rhs
            .block,
            .block_semicolon,
            .array_init_dot,
            .array_init_dot_comma,
            .struct_init_dot,
            .struct_init_dot_comma,
            .builtin_call,
            .builtin_call_comma,
            .container_decl,
            .container_decl_trailing,
            => {
                const first = datas[node].lhs;
                const last = datas[node].rhs;
                for (tree.extra_data[first..last]) |stmt_idx| {
                    cont = try traverseNode(action, patches, tree, node, stmt_idx);
                    if (!cont) break :blk;
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
            .@"asm",
            => {
                if (datas[node].lhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].lhs);
                    if (!cont) break :blk;
                }
                const range = tree.extraData(datas[node].rhs, Node.SubRange);
                for (tree.extra_data[range.start..range.end]) |idx| {
                    cont = try traverseNode(action, patches, tree, node, idx);
                    if (!cont) break :blk;
                }
            },

            // check sub range list from lhs and rhs (if set)
            .switch_case,
            .switch_case_inline,
            .fn_proto_multi,
            => {
                const range = tree.extraData(datas[node].lhs, Node.SubRange);
                for (tree.extra_data[range.start..range.end]) |idx| {
                    cont = try traverseNode(action, patches, tree, node, idx);
                    if (!cont) break :blk;
                }
                if (datas[node].rhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                    if (!cont) break :blk;
                }
            },

            // both lhs and rhs must be checked (if set)
            .simple_var_decl,
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
            .switch_case_inline_one,
            .switch_range,
            .while_simple,
            .for_simple,
            .if_simple,
            .fn_proto_simple,
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
            .error_union,
            => {
                if (datas[node].lhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].lhs);
                    if (!cont) break :blk;
                }
                if (datas[node].rhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                    if (!cont) break :blk;
                }
            },

            // only lhs must be checked (if set)
            .@"usingnamespace",
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
            .@"comptime",
            .@"nosuspend",
            .asm_simple,
            .asm_output,
            .asm_input,
            => {
                if (datas[node].lhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].lhs);
                    if (!cont) break :blk;
                }
            },

            // only rhs must be checked (if set)
            .global_var_decl,
            .aligned_var_decl,
            .test_decl,
            .@"errdefer",
            .@"defer",
            .@"break",
            => {
                if (datas[node].rhs != 0) {
                    cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                    if (!cont) break :blk;
                }
            },

            // check lhs and 2 indices at rhs
            .array_type_sentinel,
            .while_cont,
            .@"if",
            .@"for",
            .slice,
            .container_field,
            => {
                cont = try traverseNode(action, patches, tree, node, datas[node].lhs);
                if (!cont) break :blk;

                cont = try traverseNodeExtraIndices(2, action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            // check lhs and 3 indices at rhs
            .slice_sentinel,
            .@"while",
            => {
                cont = try traverseNode(action, patches, tree, node, datas[node].lhs);
                if (!cont) break :blk;

                cont = try traverseNodeExtraIndices(3, action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            // check 2 indices at lhs and rhs
            .local_var_decl => {
                cont = try traverseNodeExtraIndices(2, action, patches, tree, node, datas[node].lhs);
                if (!cont) break :blk;

                cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            // check 3 indices at lhs and rhs
            .ptr_type => {
                cont = try traverseNodeExtraIndices(3, action, patches, tree, node, datas[node].lhs);
                if (!cont) break :blk;

                cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            // check 5 indices at lhs and rhs
            .fn_proto_one => {
                cont = try traverseNodeExtraIndices(5, action, patches, tree, node, datas[node].lhs);
                if (!cont) break :blk;

                cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            // special case: fn proto
            .fn_proto => {
                // fn proto has first a range (2 indices) then 3 indices in extra data
                const range = tree.extraData(datas[node].lhs, Node.SubRange);
                for (tree.extra_data[range.start..range.end]) |idx| {
                    cont = try traverseNode(action, patches, tree, node, idx);
                    if (!cont) break :blk;
                }

                const extraIndex = datas[node].lhs + 2;
                cont = try traverseNodeExtraIndices(3, action, patches, tree, node, extraIndex);
                if (!cont) break :blk;

                cont = try traverseNode(action, patches, tree, node, datas[node].rhs);
                if (!cont) break :blk;
            },

            else => {},
        }
    }

    try action.after(patches, tree, parent, node);

    // do not propagate tree traversal skipping outside of blocks/structs
    return switch (tag) {
        .block_two,
        .block_two_semicolon,
        .block,
        .block_semicolon,
        .container_decl,
        .container_decl_trailing,
        .container_decl_arg,
        .container_decl_arg_trailing,
        => true,
        else => cont,
    };
}

fn anchorFromNode(tree: Tree, node: NodeIndex) TokenIndex {
    const tag = tree.nodes.items(.tag)[node];
    switch (tag) {
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            const maybe_lbrace = tree.lastToken(node) + 1;
            if (tree.tokens.items(.tag)[maybe_lbrace] == .l_brace) {
                return maybe_lbrace;
            } else {
                return tree.nodes.items(.main_token)[node];
            }
        },

        .fn_decl => {
            const rhs = tree.nodes.items(.data)[node].rhs;
            const lbrace = tree.firstToken(rhs);
            std.debug.assert(tree.tokens.items(.tag)[lbrace] == .l_brace);
            return lbrace;
        },

        else => return tree.nodes.items(.main_token)[node],
    }
}

const FnRetMap = struct {
    const NamespaceIndex = u16;
    const NamespaceValue = union(enum) {
        fn_no_return_value,
        fn_has_return_value,
        nested: NamespaceIndex,
    };

    const NamespaceBinding = struct {
        token: TokenIndex,
        value: NamespaceValue,
    };

    const Namespace = std.ArrayList(NamespaceBinding);
    namespaces: std.ArrayList(Namespace),
    cur_chain: std.ArrayList(NamespaceIndex),

    fn init(gpa: mem.Allocator) !FnRetMap {
        var self = FnRetMap{
            .namespaces = std.ArrayList(Namespace).init(gpa),
            .cur_chain = std.ArrayList(NamespaceIndex).init(gpa),
        };

        try self.namespaces.append(Namespace.init(gpa));
        try self.cur_chain.append(0);
        return self;
    }

    fn deinit(self: *FnRetMap) void {
        for (self.namespaces.items) |namespace| {
            namespace.deinit();
        }
        self.namespaces.deinit();
        self.cur_chain.deinit();
    }

    fn pushNamespace(self: *FnRetMap, token: TokenIndex) !void {
        const namespace_idx = @intCast(NamespaceIndex, self.namespaces.items.len);
        var namespace = Namespace.init(self.namespaces.allocator);
        try self.namespaces.append(namespace);

        const parent_namespace_idx = self.cur_chain.items[self.cur_chain.items.len - 1];
        try self.namespaces.items[parent_namespace_idx].append(.{
            .token = token,
            .value = .{ .nested = namespace_idx },
        });

        try self.cur_chain.append(namespace_idx);
    }

    fn popNamespace(self: *FnRetMap) void {
        std.debug.assert(self.cur_chain.items.len > 0);
        self.cur_chain.items.len -= 1;
    }

    fn pushFn(self: *FnRetMap, token: TokenIndex, has_return_value: bool) !void {
        const parent_namespace_idx = self.cur_chain.items[self.cur_chain.items.len - 1];
        try self.namespaces.items[parent_namespace_idx].append(.{
            .token = token,
            .value = if (has_return_value) .fn_has_return_value else .fn_no_return_value,
        });
    }

    fn getNamespaceValue(
        self: FnRetMap,
        tree: Tree,
        parent: NamespaceIndex,
        token: TokenIndex,
    ) ?NamespaceValue {
        for (self.namespaces.items[parent].items) |binding| {
            if (std.mem.eql(u8, tree.tokenSlice(token), tree.tokenSlice(binding.token))) {
                return binding.value;
            }
        }

        return null;
    }

    fn getNamespaceRec(self: FnRetMap, tree: Tree, node: NodeIndex) ?NamespaceIndex {
        var token: TokenIndex = undefined;
        var parent: NamespaceIndex = undefined;
        switch (tree.nodes.items(.tag)[node]) {
            .field_access => {
                token = tree.nodes.items(.data)[node].rhs;
                parent = self.getNamespaceRec(tree, tree.nodes.items(.data)[node].lhs) orelse
                    return null;
            },
            .identifier => {
                token = tree.nodes.items(.main_token)[node];
                parent = self.cur_chain.items[0];
            },
            else => return null,
        }

        if (self.getNamespaceValue(tree, parent, token)) |value| {
            switch (value) {
                .nested => |idx| return idx,
                else => return null,
            }
        } else {
            return null;
        }
    }

    fn fnHasRet(self: FnRetMap, tree: Tree, node: NodeIndex) bool {
        var token: TokenIndex = undefined;
        var namespace: NamespaceIndex = undefined;
        switch (tree.nodes.items(.tag)[node]) {
            .field_access => {
                token = tree.nodes.items(.data)[node].rhs;
                namespace = self.getNamespaceRec(tree, tree.nodes.items(.data)[node].lhs) orelse
                    return false;
            },
            .identifier => {
                token = tree.nodes.items(.main_token)[node];
                namespace = self.cur_chain.items[0];
            },
            else => return false,
        }

        if (self.getNamespaceValue(tree, namespace, token)) |value| {
            return value == .fn_has_return_value;
        } else {
            return false;
        }
    }

    fn before(
        self: *FnRetMap,
        patches: *Patches,
        tree: Tree,
        parent: NodeIndex,
        node: NodeIndex,
    ) !bool {
        _ = parent;
        _ = patches;
        switch (tree.nodes.items(.tag)[node]) {
            .global_var_decl,
            .local_var_decl,
            .simple_var_decl,
            .aligned_var_decl,
            => {
                const var_or_const = tree.nodes.items(.main_token)[node];
                const init_expr = tree.nodes.items(.data)[node].rhs;
                if (tree.tokens.items(.tag)[var_or_const] == .keyword_const and
                    init_expr != 0)
                {
                    switch (tree.nodes.items(.tag)[init_expr]) {
                        .container_decl,
                        .container_decl_trailing,
                        .container_decl_two,
                        .container_decl_two_trailing,
                        => {
                            const name = var_or_const + 1;
                            try self.pushNamespace(name);
                        },
                        .builtin_call_two,
                        .builtin_call_two_comma,
                        => {
                            const builtin = tree.nodes.items(.main_token)[init_expr];
                            const builtin_name = tree.tokenSlice(builtin);
                            const lhs = tree.nodes.items(.data)[init_expr].lhs;
                            if (std.mem.eql(u8, builtin_name, "@import") and lhs != 0) {
                                const name = var_or_const + 1;
                                try self.pushNamespace(name);

                                const arg = tree.nodes.items(.main_token)[lhs];
                                const arg_name = tree.tokenSlice(arg);
                                if (std.mem.eql(u8, arg_name, "\"std\""))
                                    std.debug.print("got std import\n", .{});
                            }
                        },
                        else => {},
                    }
                }
            },
            else => {},
        }

        return true;
    }

    fn after(
        self: *FnRetMap,
        patches: *Patches,
        tree: Tree,
        parent: NodeIndex,
        node: NodeIndex,
    ) !void {
        _ = parent;
        _ = patches;
        switch (tree.nodes.items(.tag)[node]) {
            .global_var_decl,
            .local_var_decl,
            .simple_var_decl,
            .aligned_var_decl,
            => {
                const var_or_const = tree.nodes.items(.main_token)[node];
                const init_expr = tree.nodes.items(.data)[node].rhs;
                if (tree.tokens.items(.tag)[var_or_const] == .keyword_const and
                    init_expr != 0)
                {
                    switch (tree.nodes.items(.tag)[init_expr]) {
                        .container_decl,
                        .container_decl_trailing,
                        .container_decl_two,
                        .container_decl_two_trailing,
                        => {
                            self.popNamespace();
                        },
                        else => {},
                    }
                }
            },
            .fn_proto_simple,
            .fn_proto_multi,
            .fn_proto_one,
            .fn_proto,
            => {
                const kw_fn = tree.nodes.items(.main_token)[node];
                const maybe_name = kw_fn + 1;
                if (tree.tokens.items(.tag)[maybe_name] == .identifier) {
                    const ret_type = tree.nodes.items(.data)[node].rhs;
                    const ret_type_tok = tree.nodes.items(.main_token)[ret_type];
                    const ret_type_str = tree.tokenSlice(ret_type_tok);
                    const has_ret = !mem.eql(u8, ret_type_str, "void") and
                        !mem.eql(u8, ret_type_str, "noreturn");
                    try self.pushFn(maybe_name, has_ret);
                }
            },
            else => {},
        }
    }
};

const ZloppyChecks = struct {
    const Binding = struct {
        token: TokenIndex = 0,
        anchor: TokenIndex = 0,
        used: bool = false,
        scope_marker: bool = false,
    };

    bindings: std.ArrayList(Binding),
    state: union(enum) {
        reachable_code,
        return_reached,
        unreachable_from: TokenIndex,
    },
    fn_ret_map: ?FnRetMap,

    fn init(gpa: mem.Allocator, fn_ret_map: ?FnRetMap) !ZloppyChecks {
        var self = ZloppyChecks{
            .bindings = std.ArrayList(Binding).init(gpa),
            .state = .reachable_code,
            .fn_ret_map = fn_ret_map,
        };

        try self.pushScope();
        return self;
    }

    fn deinit(self: *ZloppyChecks) void {
        // assert only the toplevel scope remains
        std.debug.assert(self.bindings.items.len >= 1);
        var i: usize = 1;
        while (i < self.bindings.items.len) : (i += 1) {
            std.debug.assert(!self.bindings.items[i].scope_marker);
        }
        self.bindings.deinit();

        if (self.fn_ret_map) |*fn_ret_map| {
            fn_ret_map.deinit();
        }
    }

    fn pushScope(self: *ZloppyChecks) !void {
        try self.bindings.append(.{ .scope_marker = true });
    }

    fn pushScopeWithCapture(self: *ZloppyChecks, tree: Tree, node: NodeIndex) !void {
        try self.pushScope();

        const maybe_capture = tree.firstToken(node) - 1;
        if (tree.tokens.items(.tag)[maybe_capture] == .pipe) {
            const capture = maybe_capture - 1;
            std.debug.assert(tree.tokens.items(.tag)[capture] == .identifier);
            try self.addBinding(tree, node, capture);
        }
    }

    fn popScope(self: *ZloppyChecks) void {
        var i: usize = self.bindings.items.len;
        while (i > 0 and !self.bindings.items[i - 1].scope_marker) : (i -= 1) {}
        self.bindings.items.len = i - 1;

        // potentially faulty scope was popped, reset state to reachable
        self.state = .reachable_code;
    }

    fn popScopeGenPatches(self: *ZloppyChecks, patches: *Patches, anchor: TokenIndex) !void {
        // unused vars
        var i: usize = self.bindings.items.len;
        while (i > 0 and !self.bindings.items[i - 1].scope_marker) : (i -= 1) {
            const binding = self.bindings.items[i - 1];
            if (!binding.used) {
                try patches.append(binding.anchor, .{ .unused_var = binding.token });
            }
        }
        self.bindings.items.len = i - 1;

        // unreachable code
        switch (self.state) {
            .unreachable_from => |token| {
                try patches.append(anchor, .{ .first_unreachable_stmt = token });
            },
            else => {},
        }

        // potentially faulty scope was popped, reset state to reachable
        self.state = .reachable_code;
    }

    fn addBinding(self: *ZloppyChecks, tree: Tree, node: NodeIndex, token: TokenIndex) !void {
        // _ variable is ignored by compiler
        if (mem.eql(u8, "_", tree.tokenSlice(token)))
            return;

        const anchor = anchorFromNode(tree, node);
        try self.bindings.append(.{ .token = token, .anchor = anchor });
    }

    fn setUsed(self: *ZloppyChecks, tree: Tree, token: TokenIndex) void {
        std.debug.assert(self.state == .reachable_code);

        const tag = tree.tokens.items(.tag)[token];
        const name = tree.tokenSlice(token);
        std.debug.assert(tag == .identifier);

        // no need to check bindings[0], it's the first scope marker
        var i: usize = self.bindings.items.len - 1;
        while (i > 1) : (i -= 1) {
            var binding = &self.bindings.items[i];
            if (binding.scope_marker)
                continue;

            const bname = tree.tokenSlice(binding.token);
            if (mem.eql(u8, name, bname)) {
                binding.used = true;
                return;
            }
        }
    }

    fn before(
        self: *ZloppyChecks,
        patches: *Patches,
        tree: Tree,
        parent: NodeIndex,
        node: NodeIndex,
    ) !bool {
        _ = patches;

        switch (self.state) {
            .reachable_code => {},
            .return_reached => {
                // reached first unreachable statement, stop tree traversal
                self.state = .{ .unreachable_from = tree.nodes.items(.main_token)[node] };
                return false;
            },
            .unreachable_from => unreachable,
        }

        switch (tree.nodes.items(.tag)[parent]) {
            // Check parent to know if we should push a new scope and possibly add
            // a capture. In some cases we cannot tell if a new scope should be
            // pushed only from the node itself (e.g. for single-statement blocks).
            // Captures are not part of the Ast, so they must be added here.
            .@"catch",
            .@"orelse",
            .switch_case_one,
            .switch_case_inline_one,
            .switch_case,
            .switch_case_inline,
            .while_simple,
            .while_cont,
            .@"while",
            .for_simple,
            .@"for",
            .if_simple,
            .@"if",
            => {
                // lhs is the condition, nothing special to do
                const lhs = tree.nodes.items(.data)[parent].lhs;
                if (node != lhs) {
                    try self.pushScopeWithCapture(tree, node);
                    return true;
                }
            },

            // Check parent to know if we are traversing fn parameter declarations
            .fn_proto_simple,
            .fn_proto_multi,
            .fn_proto_one,
            .fn_proto,
            => {
                // Only declare parameters if fn_proto* is part of a fn_decl
                // (i.e. has a lbrace afterward).
                // Since fn_proto* sub nodes are types, check for a leading ':'
                // to distinguish parameters from return type.
                const maybe_colon = tree.firstToken(node) - 1;
                const maybe_lbrace = tree.lastToken(parent) + 1;
                if (tree.tokens.items(.tag)[maybe_lbrace] == .l_brace and
                    tree.tokens.items(.tag)[maybe_colon] == .colon)
                {
                    const name = maybe_colon - 1;
                    std.debug.assert(tree.tokens.items(.tag)[name] == .identifier);
                    try self.addBinding(tree, parent, name);
                }
            },

            else => {},
        }

        // normal case: create a new scope for fn decls, blocks and containers
        switch (tree.nodes.items(.tag)[node]) {
            .fn_decl,
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                try self.pushScope();
            },

            else => {},
        }

        // continue tree traversal
        return true;
    }

    fn after(
        self: *ZloppyChecks,
        patches: *Patches,
        tree: Tree,
        parent: NodeIndex,
        node: NodeIndex,
    ) !void {
        const parent_tag = tree.nodes.items(.tag)[parent];
        const node_token = tree.nodes.items(.main_token)[node];
        switch (tree.nodes.items(.tag)[node]) {
            // check unused variable in current fn_decls, blocks
            .fn_decl,
            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                try self.popScopeGenPatches(patches, anchorFromNode(tree, node));
                return;
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
                return;
            },

            // update current scope for var decls
            .global_var_decl, .local_var_decl, .simple_var_decl, .aligned_var_decl => {
                const name = node_token + 1;
                try self.addBinding(tree, node, name);
            },

            // set used bit for identifier
            .identifier => {
                self.setUsed(tree, node_token);
            },

            // indicate next statements in scope will be unreachable
            .@"continue",
            .@"break",
            .@"return",
            => {
                std.debug.assert(self.state == .reachable_code);
                self.state = .return_reached;
            },

            // set used bit for identifier used in asm_output
            .asm_output => {
                const lhs = tree.nodes.items(.data)[node].lhs;
                if (lhs == 0) {
                    const name = tree.nodes.items(.data)[node].rhs - 1;
                    std.debug.assert(tree.tokens.items(.tag)[name] == .identifier);
                    self.setUsed(tree, name);
                }
            },

            // check unused call return values
            .call_one,
            .call_one_comma,
            .call,
            .call_comma,
            => {
                if (self.fn_ret_map) |fn_ret_map| switch (parent_tag) {
                    .block,
                    .block_semicolon,
                    .block_two,
                    .block_two_semicolon,
                    => {
                        const name = tree.nodes.items(.data)[node].lhs;
                        if (fn_ret_map.fnHasRet(tree, name)) {
                            try patches.append(
                                tree.nodes.items(.main_token)[parent],
                                .{ .ignore_ret_val = tree.nodes.items(.main_token)[node] },
                            );
                        }
                    },
                    else => {},
                };
            },

            else => {},
        }

        // scope pushed in before() must be popped on same conditions
        switch (parent_tag) {
            .@"catch",
            .@"orelse",
            .switch_case_one,
            .switch_case_inline_one,
            .switch_case,
            .switch_case_inline,
            .while_simple,
            .while_cont,
            .@"while",
            .for_simple,
            .@"for",
            .if_simple,
            .@"if",
            => {
                // lhs is the condition, nothing special to do
                const lhs = tree.nodes.items(.data)[parent].lhs;
                if (node != lhs) {
                    try self.popScopeGenPatches(patches, anchorFromNode(tree, node));
                }
            },

            else => {},
        }
    }
};

pub fn genPatches(gpa: mem.Allocator, tree: Tree, fix_ret_vals: bool) !Patches {
    var patches = Patches.init(gpa);
    const roots = tree.rootDecls();

    var checks = blk: {
        if (fix_ret_vals) {
            var fn_ret_map = try FnRetMap.init(gpa);

            for (roots) |node| {
                if (!try traverseNode(&fn_ret_map, &patches, tree, 0, node))
                    break;
            }

            break :blk try ZloppyChecks.init(gpa, fn_ret_map);
        } else {
            break :blk try ZloppyChecks.init(gpa, null);
        }
    };

    defer checks.deinit();
    for (roots) |node| {
        if (!try traverseNode(&checks, &patches, tree, 0, node))
            break;
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
    } else if (mem.startsWith(u8, descr, "ignored call return value")) {
        mem.set(u8, source[zloppy_comment_start..end], ' ');
        if (mem.indexOf(u8, source[start..end], "_ = ")) |ignore_stmt| {
            mem.set(u8, source[start + ignore_stmt .. start + ignore_stmt + 3], ' ');
        } else {
            return error.InvalidCommentFound;
        }
    } else {
        return error.InvalidCommentFound;
    }
}

fn lastComment(line: []const u8) ?usize {
    if (line.len < "//".len)
        return null;

    var i: usize = line.len;
    while (i > 1) : (i -= 1) {
        if (mem.eql(u8, line[i - 2 .. i], "//")) {
            return i - 2;
        } else if (!isAllowedInZloppyComment(line[i - 1])) {
            return null;
        }
    }

    return null;
}

pub fn cleanSource(filename: []const u8, source: []u8) !u32 {
    var removed: u32 = 0;
    var start: usize = 0;
    var line_no: usize = 1;
    var ignoring = false;
    blk: while (mem.indexOfPos(u8, source, start, "\n")) |end| : ({
        start = end + 1;
        line_no += 1;
    }) {
        const line = source[start..end];

        if (lastComment(line)) |index| {
            const comment = line[index..];

            // Respect zig fmt: on/off
            const content = mem.trim(u8, comment[2..], " ");
            if (mem.eql(u8, content, "zig fmt: on")) {
                ignoring = false;
            } else if (mem.eql(u8, content, "zig fmt: off")) {
                ignoring = true;
            }

            if (ignoring)
                continue :blk;

            // Clean line if a zloppy comment is present
            if (mem.startsWith(u8, comment, zloppy_comment)) {
                cleanLine(source, start, end, start + index) catch |err| {
                    std.log.warn(
                        "invalid zloppy comment found in file '{s}' on line {}, " ++
                            "file left untouched",
                        .{ filename, line_no },
                    );
                    return err;
                };
                removed += 1;
            }
        }
    }

    return removed;
}
