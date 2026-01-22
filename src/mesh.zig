const std    = @import("std");
const Vertex = @import("vertex.zig").Vertex;

pub const Mesh = struct {
    vertices: std.ArrayList(Vertex),
    indices:  std.ArrayList(u32),

    allocator: *const std.mem.Allocator,

    pub fn appendVertex(self: *Mesh, vertex: Vertex) !void {
        try self.vertices.append(self.allocator.*, vertex);
    }

    pub fn appendIndex(self: *Mesh, index: u32) !void {
        try self.indices.append(self.allocator.*, index);
    }

    pub fn init(allocator: *const std.mem.Allocator) !*Mesh {
        const mesh = try allocator.create(Mesh);
        mesh.* = .{
            .vertices = try std.ArrayList(Vertex).initCapacity(allocator.*, 0),
            .indices  = try std.ArrayList(u32).initCapacity(allocator.*, 0),
            .allocator   = allocator,
        };

        return mesh;
    }

    pub fn deinit(self: *Mesh) void {
        self.vertices.deinit(self.allocator.*);
        self.indices.deinit(self.allocator.*);

        self.allocator.destroy(self);
    }
};
