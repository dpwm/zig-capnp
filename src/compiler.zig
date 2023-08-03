const std = @import("std");
const capnp = @import("capnp.zig");
const schema = @import("schema.zig");
const Allocator = std.mem.Allocator;

pub fn populateLookupTable(hashMap: *std.AutoHashMap(u64, schema.Node.Reader), cgr: schema.CodeGeneratorRequest.Reader) Allocator.Error!void {
    var iter = cgr.getNodes().iter();
    while (iter.next()) |node| {
        try hashMap.put(node.getId(), node);
    }
}

pub fn indent(depth: usize) void {
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }
}

pub fn print_node(hashMap: std.AutoHashMap(u64, schema.Node.Reader), node: schema.Node.Reader, depth: u32) void {
    var it = node.getNestedNodes().iter();
    while (it.next()) |nestedNode| {
        const node_ = hashMap.get(nestedNode.getId()).?;
        const w = node.which();

        indent(depth);
        std.debug.print("{s}\n", .{nestedNode.getName()});

        switch (w) {
            .struct_ => |x| {
                var fieldsIterator = x.getFields().iter();
                while (fieldsIterator.next()) |f| {
                    indent(depth);
                    std.debug.print("- {s}: {}\n", .{ f.getName(), f.which() });
                }
            },
            else => {},
        }

        print_node(hashMap, node_, depth + 1);
    }
}

test "test1" {
    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = message.getRootStruct(schema.CodeGeneratorRequest);
    var hashMap = std.AutoHashMap(u64, schema.Node.Reader).init(std.testing.allocator);
    defer hashMap.deinit();

    try populateLookupTable(&hashMap, s);

    var it = s.getRequestedFiles().iter();
    while (it.next()) |requestedFile| {
        const node = hashMap.get(requestedFile.getId()).?;
        std.debug.print("{s}\n", .{node.getDisplayName()});
        print_node(hashMap, node, 1);
    }
}
