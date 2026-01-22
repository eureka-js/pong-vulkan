const vk = @import("bindings/vulkan.zig").vk;

const std = @import("std");

const Node   = @import("node.zig").Node;
const Vertex = @import("vertex.zig").Vertex;

pub const BufferManager = struct {
    pub const Data = struct {
        node:         *Node,
        firstVertex:  i32,
        firstIndex:   u32,
    };

    device:             vk.VkDevice,

    vertexBuffer:       vk.VkBuffer        = undefined,
    vertexBufferMemory: vk.VkDeviceMemory  = undefined,
    vertexBufferSize:   u32                = 0,
    vertexBufferLen:    u32                = 0,

    indexBuffer:       vk.VkBuffer        = undefined,
    indexBufferMemory: vk.VkDeviceMemory  = undefined,
    indexBufferSize:   u32                = 0,
    indexBufferLen:    u32                = 0,

    data: std.ArrayList(Data),

    allocator: *const std.mem.Allocator,

    pub fn init(
        device:     vk.VkDevice,
        allocator:  *const std.mem.Allocator,
        length:     usize,
    ) !BufferManager {
        return .{
            .device    = device,
            .data      = try std.ArrayList(BufferManager.Data).initCapacity(allocator.*, length),
            .allocator = allocator,
        };
    }

    pub fn deinit(self: *BufferManager) void {
        self.data.deinit(self.allocator.*);

        vk.vkDestroyBuffer(self.device, self.vertexBuffer, null);
        vk.vkDestroyBuffer(self.device, self.indexBuffer, null);
        vk.vkFreeMemory(self.device, self.vertexBufferMemory, null);
        vk.vkFreeMemory(self.device, self.indexBufferMemory, null);
    }

    pub fn addNode(self: *BufferManager, node: *Node) !void {
        try self.data.append(self.allocator.*, .{
            .node         = node,
            .firstVertex  = @intCast(self.vertexBufferLen),
            .firstIndex   = self.indexBufferLen,
        });

        for (node.mesh.vertices.items) |*vertex| {
            self.vertexBufferSize +=  @sizeOf(@TypeOf(vertex.*));
            self.vertexBufferLen  += 1;
        }
        for (node.mesh.indices.items) |index| {
            self.indexBufferSize +=  @sizeOf(@TypeOf(index));
            self.indexBufferLen  += 1;
        }
    }

    pub fn getVertices(self: *BufferManager, allocator: *const std.mem.Allocator) !std.ArrayList(Vertex) {
        var vertexCount: usize = 0;
        for (self.data.items) |*data| {
            vertexCount += data.node.mesh.vertices.items.len;
        }

        var vertices = try std.ArrayList(Vertex).initCapacity(allocator.*, vertexCount);
        for (self.data.items) |*data| {
            for (data.node.mesh.vertices.items) |*vertex| {
                try vertices.append(allocator.*, vertex.*);
            }
        }

        return vertices;
    }

    pub fn getIndices(self: *BufferManager, allocator: *const std.mem.Allocator) !std.ArrayList(u32) {
        var indexCount: usize = 0;
        for (self.data.items) |*data| {
            indexCount += data.node.mesh.indices.items.len;
        }

        var indices = try std.ArrayList(u32).initCapacity(allocator.*, indexCount);
        for (self.data.items) |*data| {
            for (data.node.mesh.indices.items) |*index| {
                try indices.append(allocator.*, index.*);
            }
        }

        return indices;
    }
};
