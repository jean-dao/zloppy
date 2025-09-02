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
    const PatchIndex = enum(u32) { _ };
    pub const Patch = union(enum) {
        // function parameters: anchored on block main token (lbrace)
        // captures: if block exists, anchored on block main token (lbrace)
        // if not, anchored on statement main token
        // declarations: anchored on decl main token (`var` or `const`)
        // assign_destructures: anchored on first assign main token (`var` or `const`)
        unused_var: TokenIndex,

        // anchored on block main token (lbrace)
        first_unreachable_stmt: TokenIndex,

        // anchored on block main token (lbrace)
        ignore_ret_val: TokenIndex,
    };

    // mapping between anchors and patchsets
    map: std.AutoHashMapUnmanaged(TokenIndex, PatchIndex),
    patches: std.ArrayList(std.ArrayList(Patch)),
    rendered_comments: u32,

    const empty: Patches = .{
        .map = .{},
        .patches = .{},
        .rendered_comments = 0,
    };

    pub fn deinit(self: *Patches, gpa: std.mem.Allocator) void {
        self.map.deinit(gpa);
        for (self.patches.items) |*patches| {
            patches.deinit(gpa);
        }
        self.patches.deinit(gpa);
        self.* = undefined;
    }

    fn append(self: *Patches, gpa: std.mem.Allocator, token: TokenIndex, patch: Patch) !void {
        var patch_idx: u32 = undefined;
        const result = try self.map.getOrPut(gpa, token);
        if (result.found_existing) {
            patch_idx = @intFromEnum(result.value_ptr.*);
        } else {
            patch_idx = @intCast(self.patches.items.len);
            result.value_ptr.* = @enumFromInt(patch_idx);
            try self.patches.append(gpa, .{});
        }
        try self.patches.items[patch_idx].append(gpa, patch);
    }

    pub fn get(self: Patches, token: TokenIndex) ?[]const Patch {
        if (self.map.get(token)) |patch_idx| {
            return self.patches.items[@intFromEnum(patch_idx)].items[0..];
        } else {
            return null;
        }
    }
};

const TreeTraversalError = error{
    OutOfMemory,
    InvalidFnProto,
    InvalidFnParam,
};

const NodeDataType = enum {
    none,
    node,
    opt_node,
    token,
    node_and_node,
    opt_node_and_opt_node,
    node_and_opt_node,
    opt_node_and_node,
    node_and_extra,
    extra_and_node,
    extra_and_opt_node,
    node_and_token,
    token_and_node,
    token_and_token,
    opt_node_and_token,
    opt_token_and_node,
    opt_token_and_opt_node,
    opt_token_and_opt_token,
    @"for",
    extra_range,
    global_var_decl,
    local_var_decl,
    assign_destructure,
    array_type_sentinel,
    ptr_type,
    ptr_type_bit_range,
    slice,
    slice_sentinel,
    while_cont,
    @"while",
    @"if",
    fn_proto_one,
    fn_proto,
    container_field,
    asm_legacy,
    @"asm",
};

fn nodeDataType(tag: Node.Tag) NodeDataType {
    return switch (tag) {
        .root => .none,
        .test_decl => .opt_token_and_node,
        .global_var_decl => .global_var_decl,
        .local_var_decl => .local_var_decl,
        .simple_var_decl => .opt_node_and_opt_node,
        .aligned_var_decl => .node_and_opt_node,
        .@"errdefer" => .opt_token_and_node,
        .@"defer" => .node,
        .@"catch" => .node_and_node,
        .field_access => .node_and_token,
        .unwrap_optional => .node_and_token,
        .equal_equal => .node_and_node,
        .bang_equal => .node_and_node,
        .less_than => .node_and_node,
        .greater_than => .node_and_node,
        .less_or_equal => .node_and_node,
        .greater_or_equal => .node_and_node,
        .assign_mul => .node_and_node,
        .assign_div => .node_and_node,
        .assign_mod => .node_and_node,
        .assign_add => .node_and_node,
        .assign_sub => .node_and_node,
        .assign_shl => .node_and_node,
        .assign_shl_sat => .node_and_node,
        .assign_shr => .node_and_node,
        .assign_bit_and => .node_and_node,
        .assign_bit_xor => .node_and_node,
        .assign_bit_or => .node_and_node,
        .assign_mul_wrap => .node_and_node,
        .assign_add_wrap => .node_and_node,
        .assign_sub_wrap => .node_and_node,
        .assign_mul_sat => .node_and_node,
        .assign_add_sat => .node_and_node,
        .assign_sub_sat => .node_and_node,
        .assign => .node_and_node,
        .assign_destructure => .assign_destructure,
        .merge_error_sets => .node_and_node,
        .mul => .node_and_node,
        .div => .node_and_node,
        .mod => .node_and_node,
        .array_mult => .node_and_node,
        .mul_wrap => .node_and_node,
        .mul_sat => .node_and_node,
        .add => .node_and_node,
        .sub => .node_and_node,
        .array_cat => .node_and_node,
        .add_wrap => .node_and_node,
        .sub_wrap => .node_and_node,
        .add_sat => .node_and_node,
        .sub_sat => .node_and_node,
        .shl => .node_and_node,
        .shl_sat => .node_and_node,
        .shr => .node_and_node,
        .bit_and => .node_and_node,
        .bit_xor => .node_and_node,
        .bit_or => .node_and_node,
        .@"orelse" => .node_and_node,
        .bool_and => .node_and_node,
        .bool_or => .node_and_node,
        .bool_not => .node,
        .negation => .node,
        .bit_not => .node,
        .negation_wrap => .node,
        .address_of => .node,
        .@"try" => .node,
        .optional_type => .node,
        .array_type => .node_and_node,
        .array_type_sentinel => .array_type_sentinel,
        .ptr_type_aligned => .opt_node_and_node,
        .ptr_type_sentinel => .opt_node_and_node,
        .ptr_type => .ptr_type,
        .ptr_type_bit_range => .ptr_type_bit_range,
        .slice_open => .node_and_node,
        .slice => .slice,
        .slice_sentinel => .slice_sentinel,
        .deref => .node,
        .array_access => .node_and_node,
        .array_init_one => .node_and_node,
        .array_init_one_comma => .node_and_node,
        .array_init_dot_two => .opt_node_and_opt_node,
        .array_init_dot_two_comma => .opt_node_and_opt_node,
        .array_init_dot => .extra_range,
        .array_init_dot_comma => .extra_range,
        .array_init => .node_and_extra,
        .array_init_comma => .node_and_extra,
        .struct_init_one => .node_and_opt_node,
        .struct_init_one_comma => .node_and_opt_node,
        .struct_init_dot_two => .opt_node_and_opt_node,
        .struct_init_dot_two_comma => .opt_node_and_opt_node,
        .struct_init_dot => .extra_range,
        .struct_init_dot_comma => .extra_range,
        .struct_init => .node_and_extra,
        .struct_init_comma => .node_and_extra,
        .call_one => .node_and_opt_node,
        .call_one_comma => .node_and_opt_node,
        .call => .node_and_extra,
        .call_comma => .node_and_extra,
        .@"switch" => .node_and_extra,
        .switch_comma => .node_and_extra,
        .switch_case_one => .opt_node_and_node,
        .switch_case_inline_one => .opt_node_and_node,
        .switch_case => .extra_and_node,
        .switch_case_inline => .extra_and_node,
        .switch_range => .node_and_node,
        .while_simple => .node_and_node,
        .while_cont => .while_cont,
        .@"while" => .@"while",
        .for_simple => .node_and_node,
        .@"for" => .@"for",
        .for_range => .node_and_opt_node,
        .if_simple => .node_and_node,
        .@"if" => .@"if",
        .@"suspend" => .node,
        .@"resume" => .node,
        .@"continue" => .opt_token_and_opt_node,
        .@"break" => .opt_token_and_opt_node,
        .@"return" => .opt_node,
        .fn_proto_simple => .opt_node_and_opt_node,
        .fn_proto_multi => .extra_and_opt_node,
        .fn_proto_one => .fn_proto_one,
        .fn_proto => .fn_proto,
        .fn_decl => .node_and_node,
        .anyframe_type => .token_and_node,
        .anyframe_literal => .none,
        .char_literal => .none,
        .number_literal => .none,
        .unreachable_literal => .none,
        .identifier => .none,
        .enum_literal => .none,
        .string_literal => .none,
        .multiline_string_literal => .token_and_token,
        .grouped_expression => .node_and_token,
        .builtin_call_two => .opt_node_and_opt_node,
        .builtin_call_two_comma => .opt_node_and_opt_node,
        .builtin_call => .extra_range,
        .builtin_call_comma => .extra_range,
        .error_set_decl => .token_and_token,
        .container_decl => .extra_range,
        .container_decl_trailing => .extra_range,
        .container_decl_two => .opt_node_and_opt_node,
        .container_decl_two_trailing => .opt_node_and_opt_node,
        .container_decl_arg => .node_and_extra,
        .container_decl_arg_trailing => .node_and_extra,
        .tagged_union => .extra_range,
        .tagged_union_trailing => .extra_range,
        .tagged_union_two => .opt_node_and_opt_node,
        .tagged_union_two_trailing => .opt_node_and_opt_node,
        .tagged_union_enum_tag => .node_and_extra,
        .tagged_union_enum_tag_trailing => .node_and_extra,
        .container_field_init => .node_and_opt_node,
        .container_field_align => .node_and_node,
        .container_field => .container_field,
        .@"comptime" => .node,
        .@"nosuspend" => .node,
        .block_two => .opt_node_and_opt_node,
        .block_two_semicolon => .opt_node_and_opt_node,
        .block => .extra_range,
        .block_semicolon => .extra_range,
        .asm_simple => .node_and_token,
        .asm_legacy => .asm_legacy,
        .@"asm" => .@"asm",
        .asm_output => .opt_node_and_token,
        .asm_input => .node_and_token,
        .error_value => .none,
        .error_union => .node_and_node,
    };
}

fn Traversal(comptime Action: type) type {
    return struct {
        gpa: std.mem.Allocator,
        action: *Action,
        patches: *Patches,
        tree: Tree,

        fn traverse(self: @This(), parent: NodeIndex, node: NodeIndex) TreeTraversalError!bool {
            var cont = try self.action.before(
                self.gpa,
                self.patches,
                self.tree,
                parent,
                node,
            );
            if (!cont)
                return false;

            const data = self.tree.nodeData(node);
            switch (nodeDataType(self.tree.nodeTag(node))) {
                .none => {},

                .node => {
                    cont = try self.traverse(node, data.node);
                },

                .opt_node => {
                    cont = try self.traverseOpt(node, data.opt_node);
                },

                .token => {},

                .node_and_node => {
                    cont = try self.traverse(node, data.node_and_node[0]);
                    if (cont)
                        cont = try self.traverse(node, data.node_and_node[1]);
                },

                .opt_node_and_opt_node => {
                    cont = try self.traverseOpt(node, data.opt_node_and_opt_node[0]);
                    if (cont)
                        cont = try self.traverseOpt(node, data.opt_node_and_opt_node[1]);
                },

                .node_and_opt_node => {
                    cont = try self.traverse(node, data.node_and_opt_node[0]);
                    if (cont)
                        cont = try self.traverseOpt(node, data.node_and_opt_node[1]);
                },

                .opt_node_and_node => {
                    cont = try self.traverseOpt(node, data.opt_node_and_node[0]);
                    if (cont)
                        cont = try self.traverse(node, data.opt_node_and_node[1]);
                },

                .node_and_extra => {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (cont) {
                        const range = self.tree.extraData(data.node_and_extra[1], Node.SubRange);
                        cont = try self.traverseRange(node, range);
                    }
                },

                .extra_and_node => {
                    const range = self.tree.extraData(data.extra_and_node[0], Node.SubRange);
                    cont = try self.traverseRange(node, range);
                    if (cont)
                        cont = try self.traverse(node, data.extra_and_node[1]);
                },

                .extra_and_opt_node => {
                    const range = self.tree.extraData(data.extra_and_opt_node[0], Node.SubRange);
                    cont = try self.traverseRange(node, range);
                    if (cont)
                        cont = try self.traverseOpt(node, data.extra_and_opt_node[1]);
                },

                .node_and_token => {
                    cont = try self.traverse(node, data.node_and_token[0]);
                },

                .token_and_node => {
                    cont = try self.traverse(node, data.token_and_node[1]);
                },

                .token_and_token => {},

                .opt_node_and_token => {
                    cont = try self.traverseOpt(node, data.opt_node_and_token[0]);
                },

                .opt_token_and_node => {
                    cont = try self.traverse(node, data.opt_token_and_node[1]);
                },

                .opt_token_and_opt_node => {
                    cont = try self.traverseOpt(node, data.opt_token_and_opt_node[1]);
                },

                .opt_token_and_opt_token => {},

                .@"for" => blk: {
                    const ast = self.tree.forFull(node).ast;
                    for (ast.inputs) |input| {
                        cont = try self.traverse(node, input);
                        if (!cont) break :blk;
                    }

                    cont = try self.traverse(node, ast.then_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, ast.else_expr);
                },

                .extra_range => {
                    cont = try self.traverseRange(node, data.extra_range);
                },

                .global_var_decl => blk: {
                    const decl = self.tree.extraData(data.extra_and_opt_node[0], Node.GlobalVarDecl);

                    cont = try self.traverseOpt(node, decl.type_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, decl.align_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, decl.addrspace_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, decl.section_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, data.extra_and_opt_node[1]);
                },

                .local_var_decl => blk: {
                    const decl = self.tree.extraData(data.extra_and_opt_node[0], Node.LocalVarDecl);

                    cont = try self.traverse(node, decl.type_node);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, decl.align_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, data.extra_and_opt_node[1]);
                },

                .assign_destructure => blk: {
                    const ast = self.tree.assignDestructure(node).ast;

                    for (ast.variables) |variable| {
                        cont = try self.traverse(node, variable);
                        if (!cont) break :blk;
                    }

                    cont = try self.traverse(node, ast.value_expr);
                },

                .array_type_sentinel => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const array = self.tree.extraData(data.node_and_extra[1], Node.ArrayTypeSentinel);

                    cont = try self.traverse(node, array.sentinel);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, array.elem_type);
                },

                .ptr_type => blk: {
                    const ptr = self.tree.extraData(data.extra_and_node[0], Node.PtrType);

                    cont = try self.traverseOpt(node, ptr.sentinel);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, ptr.align_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, ptr.addrspace_node);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, data.extra_and_node[1]);
                },

                .ptr_type_bit_range => blk: {
                    const ptr = self.tree.extraData(data.extra_and_node[0], Node.PtrTypeBitRange);

                    cont = try self.traverseOpt(node, ptr.sentinel);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, ptr.align_node);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, ptr.addrspace_node);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, ptr.bit_range_start);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, ptr.bit_range_end);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, data.extra_and_node[1]);
                },

                .slice => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const slice = self.tree.extraData(data.node_and_extra[1], Node.Slice);

                    cont = try self.traverse(node, slice.start);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, slice.end);
                },

                .slice_sentinel => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const slice = self.tree.extraData(data.node_and_extra[1], Node.SliceSentinel);

                    cont = try self.traverse(node, slice.start);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, slice.end);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, slice.sentinel);
                },

                .while_cont => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const loop = self.tree.extraData(data.node_and_extra[1], Node.WhileCont);

                    cont = try self.traverse(node, loop.cont_expr);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, loop.then_expr);
                },

                .@"while" => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const loop = self.tree.extraData(data.node_and_extra[1], Node.While);

                    cont = try self.traverseOpt(node, loop.cont_expr);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, loop.then_expr);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, loop.else_expr);
                },

                .@"if" => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const cond = self.tree.extraData(data.node_and_extra[1], Node.If);

                    cont = try self.traverse(node, cond.then_expr);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, cond.else_expr);
                },

                .fn_proto_one => blk: {
                    const proto = self.tree.extraData(data.extra_and_opt_node[0], Node.FnProtoOne);

                    cont = try self.traverseOpt(node, proto.param);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.align_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.addrspace_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.section_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.callconv_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, data.extra_and_opt_node[1]);
                },

                .fn_proto => blk: {
                    const proto = self.tree.extraData(data.extra_and_opt_node[0], Node.FnProto);

                    const params = self.tree.extraDataSlice(.{
                        .start = proto.params_start,
                        .end = proto.params_end,
                    }, NodeIndex);
                    for (params) |param| {
                        cont = try self.traverse(node, param);
                        if (!cont) break :blk;
                    }

                    cont = try self.traverseOpt(node, proto.align_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.addrspace_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.section_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, proto.callconv_expr);
                    if (!cont) break :blk;

                    cont = try self.traverseOpt(node, data.extra_and_opt_node[1]);
                },

                .container_field => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const field = self.tree.extraData(data.node_and_extra[1], Node.ContainerField);

                    cont = try self.traverse(node, field.align_expr);
                    if (!cont) break :blk;

                    cont = try self.traverse(node, field.value_expr);
                },

                .asm_legacy => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const ass = self.tree.extraData(data.node_and_extra[1], Node.AsmLegacy);

                    const items = self.tree.extraDataSlice(.{
                        .start = ass.items_start,
                        .end = ass.items_end,
                    }, NodeIndex);
                    for (items) |item| {
                        cont = try self.traverse(node, item);
                        if (!cont) break :blk;
                    }
                },

                .@"asm" => blk: {
                    cont = try self.traverse(node, data.node_and_extra[0]);
                    if (!cont) break :blk;

                    const ass = self.tree.extraData(data.node_and_extra[1], Node.Asm);

                    const items = self.tree.extraDataSlice(.{
                        .start = ass.items_start,
                        .end = ass.items_end,
                    }, NodeIndex);
                    for (items) |item| {
                        cont = try self.traverse(node, item);
                        if (!cont) break :blk;
                    }

                    cont = try self.traverseOpt(node, ass.clobbers);
                },
            }

            try self.action.after(self.gpa, self.patches, self.tree, parent, node);

            // do not propagate tree traversal skipping outside of blocks/structs
            return switch (self.tree.nodeTag(node)) {
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

        fn traverseOpt(
            self: @This(),
            parent: NodeIndex,
            opt: Node.OptionalIndex,
        ) TreeTraversalError!bool {
            if (opt.unwrap()) |child|
                return try self.traverse(parent, child);

            return true;
        }

        fn traverseRange(
            self: @This(),
            parent: NodeIndex,
            range: Node.SubRange,
        ) TreeTraversalError!bool {
            const slice = self.tree.extraDataSlice(range, NodeIndex);
            for (slice) |child| {
                if (!try self.traverse(parent, child))
                    return false;
            }

            return true;
        }
    };
}

fn anchorFromNode(tree: Tree, node: NodeIndex) TokenIndex {
    const tag = tree.nodeTag(node);
    switch (tag) {
        .fn_proto_simple,
        .fn_proto_multi,
        .fn_proto_one,
        .fn_proto,
        => {
            const maybe_lbrace = tree.lastToken(node) + 1;
            if (tree.tokenTag(maybe_lbrace) == .l_brace) {
                return maybe_lbrace;
            } else {
                return tree.nodeMainToken(node);
            }
        },

        .fn_decl => {
            const body = tree.nodeData(node).node_and_node[1];
            const lbrace = tree.firstToken(body);
            std.debug.assert(tree.tokenTag(lbrace) == .l_brace);
            return lbrace;
        },

        else => return tree.nodeMainToken(node),
    }
}

const ZloppyChecks = struct {
    bindings: std.ArrayList(Binding),
    state: union(enum) {
        reachable_code,
        return_reached,
        unreachable_from: TokenIndex,
    },
    destructure_anchor: TokenIndex = 0,

    const Binding = struct {
        token: TokenIndex = 0,
        anchor: TokenIndex = 0,
        used: bool = false,
        scope_marker: bool = false,
    };

    fn init(gpa: std.mem.Allocator) !ZloppyChecks {
        var self = ZloppyChecks{
            .bindings = .{},
            .state = .reachable_code,
        };

        try self.pushScope(gpa);
        return self;
    }

    fn deinit(self: *ZloppyChecks, gpa: std.mem.Allocator) void {
        // assert only the toplevel scope remains
        std.debug.assert(self.bindings.items.len >= 1);
        for (self.bindings.items[1..]) |binding| {
            std.debug.assert(!binding.scope_marker);
        }
        self.bindings.deinit(gpa);

        self.* = undefined;
    }

    fn pushScope(self: *ZloppyChecks, gpa: std.mem.Allocator) !void {
        try self.bindings.append(gpa, .{ .scope_marker = true });
    }

    fn pushScopeWithCapture(
        self: *ZloppyChecks,
        gpa: std.mem.Allocator,
        tree: Tree,
        node: NodeIndex,
    ) !void {
        try self.pushScope(gpa);

        const tags = tree.tokens.items(.tag);
        const maybe_capture_end = tree.firstToken(node) - 1;
        if (tags[maybe_capture_end] == .pipe) {
            var capture_name = maybe_capture_end - 1;
            while (true) {
                std.debug.assert(tags[capture_name] == .identifier);
                try self.addBinding(gpa, tree, node, capture_name);

                const maybe_asterisk = capture_name - 1;
                const maybe_capture_sep = if (tags[maybe_asterisk] == .asterisk)
                    maybe_asterisk - 1
                else
                    maybe_asterisk;

                switch (tags[maybe_capture_sep]) {
                    .comma => capture_name = maybe_capture_sep - 1,
                    .pipe => break,
                    else => unreachable,
                }
            }
        }
    }

    fn popScope(self: *ZloppyChecks) void {
        var i: usize = self.bindings.items.len;
        while (i > 0 and !self.bindings.items[i - 1].scope_marker) : (i -= 1) {}
        self.bindings.items.len = i - 1;

        // potentially faulty scope was popped, reset state to reachable
        self.state = .reachable_code;
    }

    fn popScopeGenPatches(
        self: *ZloppyChecks,
        gpa: std.mem.Allocator,
        patches: *Patches,
        anchor: TokenIndex,
    ) !void {
        // unused vars
        var i: usize = self.bindings.items.len;
        while (i > 0 and !self.bindings.items[i - 1].scope_marker) : (i -= 1) {
            const binding = self.bindings.items[i - 1];
            if (!binding.used) {
                try patches.append(gpa, binding.anchor, .{ .unused_var = binding.token });
            }
        }
        self.bindings.items.len = i - 1;

        // unreachable code
        switch (self.state) {
            .unreachable_from => |token| {
                try patches.append(gpa, anchor, .{ .first_unreachable_stmt = token });
            },
            else => {},
        }

        // potentially faulty scope was popped, reset state to reachable
        self.state = .reachable_code;
    }

    fn addBinding(
        self: *ZloppyChecks,
        gpa: std.mem.Allocator,
        tree: Tree,
        node: NodeIndex,
        token: TokenIndex,
    ) !void {
        // _ variable is ignored by compiler
        if (mem.eql(u8, "_", tree.tokenSlice(token)))
            return;

        const anchor = if (self.destructure_anchor != 0)
            self.destructure_anchor
        else
            anchorFromNode(tree, node);

        try self.bindings.append(gpa, .{ .token = token, .anchor = anchor });
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
        gpa: std.mem.Allocator,
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
                self.state = .{ .unreachable_from = tree.nodeMainToken(node) };
                return false;
            },
            .unreachable_from => unreachable,
        }

        // Check parent to know if we should push a new scope and possibly add
        // a capture. In some cases we cannot tell if a new scope should be
        // pushed only from the node itself (e.g. for single-statement blocks).
        // Captures are not part of the Ast, so they must be added here.
        if (nodeIsBody(tree, parent, node)) {
            try self.pushScopeWithCapture(gpa, tree, node);
            return true;
        }

        switch (tree.nodeTag(node)) {
            // create new scope and add bindings for fn args
            .fn_decl => {
                try self.pushScope(gpa);
                errdefer self.popScope();

                var buf: [1]NodeIndex = undefined;
                const fn_proto = tree.fullFnProto(&buf, node) orelse return error.InvalidFnProto;
                var it = fn_proto.iterate(&tree);
                while (it.next()) |param| {
                    try self.addBinding(gpa, tree, node, param.name_token orelse return error.InvalidFnParam);
                }
            },

            // create a new scope for blocks, containers and defers
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
            .@"defer",
            .@"errdefer",
            => {
                try self.pushScope(gpa);
            },

            .assign_destructure => self.destructure_anchor = tree.nodeMainToken(node),

            else => {},
        }

        // continue tree traversal
        return true;
    }

    fn after(
        self: *ZloppyChecks,
        gpa: std.mem.Allocator,
        patches: *Patches,
        tree: Tree,
        parent: NodeIndex,
        node: NodeIndex,
    ) !void {
        const node_token = tree.nodeMainToken(node);
        switch (tree.nodeTag(node)) {
            // check unused variable in current fn_decls, blocks
            .fn_decl,
            .block_two,
            .block_two_semicolon,
            .block,
            .block_semicolon,
            => {
                try self.popScopeGenPatches(gpa, patches, anchorFromNode(tree, node));
                return;
            },

            // only pop scope in containers and defers, don't check for unused variables
            .container_decl,
            .container_decl_trailing,
            .container_decl_two,
            .container_decl_two_trailing,
            .container_decl_arg,
            .container_decl_arg_trailing,
            .@"defer",
            .@"errdefer",
            => {
                self.popScope();
                return;
            },

            // update current scope for var decls
            .global_var_decl, .local_var_decl, .simple_var_decl, .aligned_var_decl => {
                const name = node_token + 1;
                try self.addBinding(gpa, tree, node, name);
            },

            // set used bit for identifier
            .identifier => {
                self.setUsed(tree, node_token);
            },

            // indicate next statements in scope will be unreachable
            .@"continue",
            .@"break",
            .@"return",
            .unreachable_literal,
            => {
                std.debug.assert(self.state == .reachable_code);
                self.state = .return_reached;
            },

            .builtin_call_two,
            .builtin_call_two_comma,
            => {
                const name = tree.nodeMainToken(node);
                if (std.mem.eql(u8, tree.tokenSlice(name), "@panic")) {
                    std.debug.assert(self.state == .reachable_code);
                    self.state = .return_reached;
                }
            },

            // set used bit for identifier used in asm_output
            .asm_output => {
                const lhs, const r_paren = tree.nodeData(node).opt_node_and_token;
                // if lhs is null, then there is an identifier
                if (lhs.unwrap() == null) {
                    const name = r_paren - 1;
                    std.debug.assert(tree.tokenTag(name) == .identifier);
                    self.setUsed(tree, name);
                }
            },

            .assign_destructure => self.destructure_anchor = 0,

            else => {},
        }

        // If the current node is the actual body of parent, pop scope
        if (nodeIsBody(tree, parent, node)) {
            try self.popScopeGenPatches(gpa, patches, anchorFromNode(tree, node));
        }
    }
};

fn nodeIsBody(tree: Tree, parent: NodeIndex, node: NodeIndex) bool {
    switch (tree.nodeTag(parent)) {
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
            const data = tree.nodeData(parent);
            const parent_type = nodeDataType(tree.nodeTag(parent));
            const node1: NodeIndex, const node2: ?NodeIndex = switch (parent_type) {
                .node_and_node => .{ data.node_and_node[1], null },
                .opt_node_and_node => .{ data.opt_node_and_node[1], null },
                .extra_and_node => .{ data.extra_and_node[1], null },
                .while_cont => blk: {
                    const ast = tree.whileCont(parent).ast;
                    break :blk .{ ast.then_expr, ast.else_expr.unwrap() };
                },
                .@"while" => blk: {
                    const ast = tree.whileFull(parent).ast;
                    break :blk .{ ast.then_expr, ast.else_expr.unwrap() };
                },
                .@"for" => blk: {
                    const ast = tree.forFull(parent).ast;
                    break :blk .{ ast.then_expr, ast.else_expr.unwrap() };
                },
                .@"if" => blk: {
                    const ast = tree.ifFull(parent).ast;
                    break :blk .{ ast.then_expr, ast.else_expr.unwrap() };
                },
                else => unreachable,
            };

            return node == node1 or node == node2;
        },

        else => {},
    }

    return false;
}

pub fn genPatches(gpa: mem.Allocator, tree: Tree) !Patches {
    var patches: Patches = .empty;
    const roots = tree.rootDecls();

    var checks = try ZloppyChecks.init(gpa);
    defer checks.deinit(gpa);

    const traversal: Traversal(ZloppyChecks) = .{
        .gpa = gpa,
        .action = &checks,
        .patches = &patches,
        .tree = tree,
    };

    for (roots) |node| {
        if (!try traversal.traverse(.root, node))
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
        @memset(source[start .. end + 1], ' ');
    } else if (mem.startsWith(u8, descr, "unreachable code")) {
        @memset(source[zloppy_comment_start..end], ' ');
        if (mem.indexOf(u8, source[start..end], "//")) |first_comment| {
            @memset(source[start + first_comment .. start + first_comment + 2], ' ');
        } else {
            return error.InvalidCommentFound;
        }
    } else if (mem.startsWith(u8, descr, "ignored call return value")) {
        @memset(source[zloppy_comment_start..end], ' ');
        if (mem.indexOf(u8, source[start..end], "_ = ")) |ignore_stmt| {
            @memset(source[start + ignore_stmt .. start + ignore_stmt + 3], ' ');
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
