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

pub fn print_node(hashMap: std.AutoHashMap(u64, schema.Node.Reader), node: schema.Node.Reader, depth: u32) void {
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
