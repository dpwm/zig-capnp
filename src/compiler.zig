const std = @import("std");
const main = @import("main.zig");

pub const Node = struct {
    pub const Reader = struct {
        reader: main.StructReader,
    };
};

pub const CodeGeneratorRequest = struct {
    pub const Reader = struct {
        reader: main.StructReader,

        pub fn getNodes(self: Reader) main.CompositeListReader(Node) {
            return self.reader.readCompositeListField(Node, 0);
        }
    };
};

test "test1" {
    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try main.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = message.getRootStruct(CodeGeneratorRequest);
    var it = s.getNodes().iter();
    while (it.next()) |x| {
        std.debug.print("{}\n", .{x});
    }
}
