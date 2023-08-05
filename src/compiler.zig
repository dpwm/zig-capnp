const std = @import("std");
const capnp = @import("capnp.zig");
const schema = @import("schema.zig");
const Allocator = std.mem.Allocator;

pub fn populateLookupTable(hashMap: *std.AutoHashMap(u64, schema.Node.Reader), cgr: schema.CodeGeneratorRequest.Reader) !void {
    var iter = (try cgr.getNodes()).iter();
    while (iter.next()) |node| {
        //std.debug.print("id={x}\n", .{node.getId()});
        // std.debug.print("name={s}\n", .{try node.getDisplayName()});

        try hashMap.put(node.getId(), node);
    }
}

pub fn indent(depth: usize) void {
    for (0..depth) |_| {
        std.debug.print("  ", .{});
    }
}

pub fn print_node(hashMap: std.AutoHashMap(u64, schema.Node.Reader), node: schema.Node.Reader, depth: u32) !void {
    var it = (try node.getNestedNodes()).iter();
    while (it.next()) |nestedNode| {
        const node_ = hashMap.get(nestedNode.getId()).?;
        const w = node.which();

        indent(depth);
        std.debug.print("{s}\n", .{try nestedNode.getName()});

        switch (w) {
            .struct_ => |x| {
                var fieldsIterator = (try x.getFields()).iter();
                while (fieldsIterator.next()) |f| {
                    indent(depth);
                    std.debug.print("- {s}\n", .{try f.getName()});
                }
            },
            else => {},
        }

        try print_node(hashMap, node_, depth + 1);
    }
}

test "test1" {
    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(schema.CodeGeneratorRequest);
    var hashMap = std.AutoHashMap(u64, schema.Node.Reader).init(std.testing.allocator);
    defer hashMap.deinit();

    try populateLookupTable(&hashMap, s);
    std.debug.print("s={}\n", .{s});

    var it = (try s.getRequestedFiles()).iter();
    while (it.next()) |requestedFile| {
        //std.debug.print("nodeid={x}\n", .{requestedFile.getId()});
        const node = hashMap.get(requestedFile.getId()).?;
        std.debug.print("{s}\n", .{try node.getDisplayName()});
        try print_node(hashMap, node, 1);
    }
}
