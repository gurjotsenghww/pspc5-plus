// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 Artur Strazewicz

//! Proves a deliberately narrow structured CFG: disjoint natural loops with
//! single latches, nested forward selections, terminal arms, breaks and continues.
//! No shader instructions or SPIR-V IDs are changed while checking eligibility.
const std = @import("std");
const instruction = @import("instruction.zig");
const control_flow = @import("control_flow.zig");

pub const none = std.math.maxInt(u32);
pub const Kind = enum { ordinary, selection, loop_exit };
pub const Block = struct {
    loop_header: u32 = none,
    latch: u32 = none,
    target: u32 = none,
    merge: u32 = none,
    kind: Kind = .ordinary,
};

pub fn analyze(a: std.mem.Allocator, instructions: []const instruction.Instruction, graph: *const control_flow.Graph) std.mem.Allocator.Error!?[]Block {
    if (graph.back_edge_count == 0 or graph.irreducible) return null;
    const blocks = try a.alloc(Block, graph.blocks.items.len);
    var accepted = false;
    defer if (!accepted) a.free(blocks);
    @memset(blocks, .{});
    // Disjoint intervals, a single back edge, and an exit after
    // the latch. Nested loops remain on the existing lowering paths.
    for (graph.edges.items) |edge| {
        if (edge.to > edge.from) continue;
        const source = graph.blocks.items[edge.from];
        const last = instructions[source.first_instruction + source.instruction_count - 1];
        if (edge.kind != .branch or !last.opcode.isBranch() or edge.to == edge.from or edge.from + 1 >= blocks.len) return null;
        for (blocks[edge.to .. edge.from + 1]) |*block| {
            if (block.loop_header != none) return null;
            block.loop_header = edge.to;
            block.latch = edge.from;
        }
    }
    for (graph.blocks.items) |block| {
        const index = block.index;
        const last = instructions[block.first_instruction + block.instruction_count - 1];
        if (last.opcode == .s_setpc_b64) return null;
        if (last.opcode.isProgramEnd()) {
            if (blocks[index].loop_header != none) return null;
        } else if (last.opcode.isBranch()) {
            const target = graph.blockForPc(last.branch_target) orelse return null;
            blocks[index].target = target;
            if (last.opcode == .s_branch) {
                if (target <= index) {
                    if (index != blocks[index].latch or target != blocks[index].loop_header) return null;
                } else if (blocks[index].loop_header != none) return null;
            } else {
                if (index == blocks[index].latch and target == blocks[index].loop_header) continue;
                if (target <= index or index + 1 >= blocks.len) return null;
                const owner = blocks[index];
                blocks[index].kind = if (owner.loop_header != none and (target == owner.latch or target == owner.latch + 1)) .loop_exit else .selection;
                if (blocks[index].kind == .selection) {
                    // Ordinary reachability can circle around the latch and
                    // mistake the fallthrough for an inner selection's merge.
                    const merge = if (owner.loop_header != none) target else if (graph.selectionForHeader(index)) |selection| selection.merge else @as(u32, @intCast(blocks.len));
                    if (merge <= index or target > merge) return null;
                    // Inside loops preserve the original forward-skip proof.
                    if (owner.loop_header != none and merge != target) return null;
                    blocks[index].merge = merge;
                }
            }
        } else if (index + 1 == blocks.len) return null;
    }
    for (graph.edges.items) |edge| {
        const source = blocks[edge.from];
        const target = blocks[edge.to];
        if (edge.kind == .fallthrough and edge.to != edge.from + 1) return null;
        if (target.loop_header != none and source.loop_header != target.loop_header and edge.to != target.loop_header) return null;
        if (source.loop_header != none and target.loop_header != source.loop_header and edge.to != source.latch + 1) return null;
    }
    for (blocks, 0..) |block, i| {
        if (block.loop_header != i) continue;
        var has_exit = blocks[block.latch].target == i and instructions[graph.blocks.items[block.latch].first_instruction + graph.blocks.items[block.latch].instruction_count - 1].opcode != .s_branch;
        for (blocks[i .. block.latch + 1]) |inside| {
            if (inside.kind == .loop_exit and inside.target == block.latch + 1) has_exit = true;
        }
        if (!has_exit) return null;
    }
    // Lexical forward regions must nest. A skip can contain a complete loop,
    // but cannot enter or escape its middle except through break/continue.
    for (blocks, 0..) |block, i| {
        if (block.kind != .selection) continue;
        for (blocks, 0..) |other, j| {
            if (other.kind == .selection and i < j and j < block.merge and block.merge < other.merge) return null;
            if (other.loop_header != j) continue;
            if ((i < j and j < block.merge and block.merge <= other.latch) or
                (j <= i and i <= other.latch and other.latch < block.merge)) return null;
        }
        // No predecessor may enter a selection body without its header. A
        // forward jump may leave only through this selection's merge (or a
        // terminal return); crossing regions keep the dispatcher.
        for (graph.edges.items) |edge| {
            const inside_source = i < edge.from and edge.from < block.merge;
            const inside_target = i < edge.to and edge.to < block.merge;
            if (inside_target and !inside_source and edge.from != i) return null;
            if (inside_source and !inside_target and edge.to != block.merge) {
                const source = blocks[edge.from];
                if (source.kind != .loop_exit or source.loop_header != block.loop_header) return null;
            }
        }
    }
    // Canonical loop-only graphs already have a dedicated lowering path with
    // its own semantics. In particular, do not introduce the dispatcher's cap
    // into loops which previously executed without that fallback.
    var canonical = true;
    for (blocks, 0..) |block, i| {
        if (block.loop_header == i and graph.selectionForHeader(@intCast(i)) == null) canonical = false;
    }
    for (graph.selections.items) |selection| {
        if (blocks[selection.header].loop_header != selection.header) canonical = false;
    }
    if (canonical) return null;
    accepted = true;
    return blocks;
}

/// The automatic graphics path is narrower than the diagnostic full proof:
/// one short loop plus forward if/else or terminal arms. Long and nested loops
/// retain the established dispatcher until separately validated.
pub fn shortFragmentLoop(instructions: []const instruction.Instruction, graph: *const control_flow.Graph, blocks: []const Block) bool {
    if (graph.back_edge_count != 1) return false;
    var diamond = false;
    for (blocks, 0..) |block, i| {
        if (block.loop_header == i and block.latch - i >= 4) return false;
        if (block.kind == .selection and block.target != block.merge) diamond = true;
        const guest = graph.blocks.items[i];
        if (instructions[guest.first_instruction + guest.instruction_count - 1].opcode.isProgramEnd() and i + 1 < blocks.len) diamond = true;
    }
    return diamond;
}

test "branch loop proof accepts forward selections and rejects unsafe boundaries" {
    const a = std.testing.allocator;
    const original = [_]instruction.Instruction{
        .{ .pc = 0, .opcode = .s_cbranch_scc0, .branch_target = 32 },
        .{ .pc = 4, .opcode = .s_nop },
        .{ .pc = 8, .opcode = .s_cbranch_scc1, .branch_target = 32 },
        .{ .pc = 12, .opcode = .s_cbranch_scc1, .branch_target = 28 },
        .{ .pc = 16, .opcode = .s_cbranch_scc1, .branch_target = 24 },
        .{ .pc = 20, .opcode = .s_nop },
        .{ .pc = 24, .opcode = .s_nop },
        .{ .pc = 28, .opcode = .s_branch, .branch_target = 4 },
        .{ .pc = 32, .opcode = .s_endpgm },
    };
    for (0..8) |variant| {
        var inst = original;
        switch (variant) {
            0 => {},
            1 => inst[7].opcode = .s_cbranch_scc1,
            2 => inst[0].branch_target = 20, // bypass the loop header
            3 => inst[4].opcode = .s_branch, // unsupported forward jump
            4 => inst[3].opcode = .s_setpc_b64, // indirect exit
            5 => inst[5].opcode = .s_endpgm, // early termination
            6 => inst[2].branch_target = 28, // no loop exit
            7 => inst[5] = .{ .pc = 20, .opcode = .s_branch, .branch_target = 16 }, // nested loop
            else => unreachable,
        }
        var graph = try control_flow.buildInstructions(a, &inst);
        defer graph.deinit(a);
        const plan = try analyze(a, &inst, &graph);
        defer if (plan) |blocks| a.free(blocks);
        try std.testing.expectEqual(variant < 2, plan != null);
    }
}

test "short fragment loop proof admits diamonds and terminal arms with single entry" {
    const a = std.testing.allocator;
    const original = [_]instruction.Instruction{
        .{ .pc = 0, .opcode = .s_cbranch_scc1, .branch_target = 36 },
        .{ .pc = 4, .opcode = .s_cbranch_scc0, .branch_target = 16 },
        .{ .pc = 8, .opcode = .s_cbranch_scc1, .branch_target = 16 },
        .{ .pc = 12, .opcode = .s_branch, .branch_target = 4 },
        .{ .pc = 16, .opcode = .s_cbranch_scc0, .branch_target = 28 },
        .{ .pc = 20, .opcode = .s_nop },
        .{ .pc = 24, .opcode = .s_branch, .branch_target = 32 },
        .{ .pc = 28, .opcode = .s_nop },
        .{ .pc = 32, .opcode = .s_endpgm },
        .{ .pc = 36, .opcode = .s_endpgm },
    };
    for (0..4) |variant| {
        var inst = original;
        switch (variant) {
            0 => {},
            1 => inst[0].branch_target = 8, // enter loop after its header
            2 => inst[6].branch_target = 36, // cross the inner selection
            3 => inst[3].branch_target = 0, // terminal arm exits a loop
            else => unreachable,
        }
        var graph = try control_flow.buildInstructions(a, &inst);
        defer graph.deinit(a);
        const plan = try analyze(a, &inst, &graph);
        defer if (plan) |blocks| a.free(blocks);
        try std.testing.expectEqual(variant == 0, plan != null);
        if (plan) |blocks| try std.testing.expect(shortFragmentLoop(&inst, &graph, blocks));
    }
}
