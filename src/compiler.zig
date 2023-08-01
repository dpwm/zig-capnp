const std = @import("std");
const main = @import("main.zig");
const Allocator = std.mem.Allocator;

pub const Node = struct {
    pub const NestedNode = struct {
        pub const Reader = struct {
            reader: main.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0);
            }

            pub fn getName(self: @This()) []u8 {
                return self.reader.readStringField(0);
            }
        };
    };
    pub const Reader = struct {
        reader: main.StructReader,

        pub fn getId(self: Reader) u64 {
            return self.reader.readIntField(u64, 0);
        }

        pub fn getDisplayName(self: Reader) []u8 {
            return self.reader.readStringField(0);
        }

        pub fn getNestedNodes(self: @This()) main.CompositeListReader(Node.NestedNode) {
            return self.reader.readCompositeListField(Node.NestedNode, 1);
        }
    };
};

pub const CodeGeneratorRequest = struct {
    pub const RequestedFile = struct {
        pub const Reader = struct {
            reader: main.StructReader,

            pub fn getId(self: @This()) u64 {
                return self.reader.readIntField(u64, 0);
            }
        };
    };
    pub const Reader = struct {
        reader: main.StructReader,

        pub fn getNodes(self: @This()) main.CompositeListReader(Node) {
            return self.reader.readCompositeListField(Node, 0);
        }

        pub fn getRequestedFiles(self: @This()) main.CompositeListReader(CodeGeneratorRequest.RequestedFile) {
            return self.reader.readCompositeListField(CodeGeneratorRequest.RequestedFile, 1);
        }
    };
};

pub fn populateLookupTable(hashMap: *std.AutoHashMap(u64, Node.Reader), cgr: CodeGeneratorRequest.Reader) Allocator.Error!void {
    var iter = cgr.getNodes().iter();
    while (iter.next()) |node| {
        try hashMap.put(node.getId(), node);
    }
}

pub fn print_node(hashMap: std.AutoHashMap(u64, Node.Reader), node: Node.Reader, depth: u32) void {
    var it = node.getNestedNodes().iter();
    while (it.next()) |n| {
        for (0..depth) |_| {
            std.debug.print("  ", .{});
        }
        std.debug.print("{s}\n", .{n.getName()});
        print_node(hashMap, hashMap.get(n.getId()).?, depth + 1);
    }
}

test "test1" {
    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try main.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = message.getRootStruct(CodeGeneratorRequest);
    var hashMap = std.AutoHashMap(u64, Node.Reader).init(std.testing.allocator);
    defer hashMap.deinit();

    try populateLookupTable(&hashMap, s);

    var it = s.getRequestedFiles().iter();
    while (it.next()) |requestedFile| {
        const node = hashMap.get(requestedFile.getId()).?;
        std.debug.print("{s}\n", .{node.getDisplayName()});
        print_node(hashMap, node, 1);
    }
}
