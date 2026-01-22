const std = @import("std");

const Node = @import("node.zig").Node;

pub const CenterLine = struct {
    nodes: std.ArrayList(Node),

    allocator: *const std.mem.Allocator,

    pub fn addNode(self: *CenterLine, node: Node) !void {
        try self.nodes.append(self.allocator.*, node);
    }

    pub fn deinit(self: *CenterLine) void {
        for (self.nodes.items) |*node| {
            node.deinit();
        }
        self.nodes.deinit(self.allocator.*);
    }
};
