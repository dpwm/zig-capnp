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

pub fn CapnpWriter(comptime WriterType: type) type {
    return struct {
        indent: usize = 0,
        writer: WriterType,

        pub const Error = WriterType.Error;

        const Self = @This();

        pub fn writeLine(self: *Self, content: []const u8) Error!void {
            for (0..self.indent) |_| {
                try self.writer.writeAll("  ");
            }
            try self.writer.writeAll(content);
            try self.writer.writeAll("\n");
        }

        pub fn printLine(self: *Self, comptime format: []const u8, args: anytype) Error!void {
            for (0..self.indent) |_| {
                try self.writer.writeAll("  ");
            }
            try self.writer.print(format, args);
            try self.writer.writeAll("\n");
        }

        pub fn toplevelImports(self: *Self) Error!void {
            try self.writeLine("const std = @import(\"std\");");
            try self.writeLine("const capnp = @import(\"capnp.zig\");");
            try self.writer.writeAll("\n");
        }

        pub fn openStruct(self: *Self, name: []const u8) Error!void {
            try self.printLine("const {s} = struct {{", .{name});
            self.indent += 1;

            try self.writeLine("reader: capnp.StructReader,");
        }

        pub fn closeStruct(self: *Self) Error!void {
            self.indent -= 1;
            try self.writeLine("};");
        }
    };
}

pub fn capnpWriter(writer: anytype) CapnpWriter(@TypeOf(writer)) {
    return .{ .writer = writer };
}

pub fn print_field(hashMap: std.AutoHashMap(u64, schema.Node.Reader), field: schema.Field.Reader) !void {
    std.debug.print("- {s}: ", .{try field.getName()});

    switch (try field.which()) {
        .slot => |slot| {
            const t = try slot.getType();
            std.debug.print("{s}\n", .{(try t.which()).toString()});
        },
        .group => |group| {
            const n = hashMap.get(group.getId()).?;
            std.debug.print("{s}\n", .{try n.getDisplayName()});
        },
        else => {},
    }
}

pub fn print_node(hashMap: std.AutoHashMap(u64, schema.Node.Reader), node: schema.Node.Reader, depth: u32) !void {
    var it = (try node.getNestedNodes()).iter();
    while (it.next()) |nestedNode| {
        const node_ = hashMap.get(nestedNode.getId()).?;
        const w = try node.which();

        indent(depth);
        std.debug.print("{s}\n", .{try nestedNode.getName()});

        switch (w) {
            .struct_ => |x| {
                var fieldsIterator = (try x.getFields()).iter();
                while (fieldsIterator.next()) |f| {
                    indent(depth);
                    try print_field(hashMap, f);
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

pub fn Transformer(comptime WriterType: type) type {
    return struct {
        const CapnpWriterType = CapnpWriter(WriterType);
        hashMap: std.AutoHashMap(u64, schema.Node.Reader),
        writer: CapnpWriterType,
        const Self = @This();

        const Error = CapnpWriterType.Error || capnp.Counter.Error;

        pub fn print_field(self: Self, field: schema.Field.Reader) Error!void {
            _ = field;
            _ = self;
            return;
        }

        pub fn print_file(self: *Self, requestedFile: schema.CodeGeneratorRequest.RequestedFile.Reader) Error!void {
            const node = self.hashMap.get(requestedFile.getId()).?;
            switch (try node.which()) {
                .file => |file| {
                    _ = file;
                    try self.writer.toplevelImports();
                    const nested = try node.getNestedNodes();
                    var nested_it = nested.iter();
                    while (nested_it.next()) |nestedNode| {
                        try self.print_node(nestedNode.getId(), try nestedNode.getName());
                    }
                },
                else => {},
            }
        }

        pub fn print_node(self: *Self, nodeId: u64, name: []const u8) Error!void {
            const node = self.hashMap.get(nodeId).?;
            switch (try node.which()) {
                .struct_ => |struct_| {
                    try self.writer.openStruct(name);
                    const nested = try node.getNestedNodes();
                    var nested_it = nested.iter();
                    while (nested_it.next()) |nested_node| {
                        try self.print_node(nested_node.getId(), try nested_node.getName());
                    }

                    const fields = try struct_.getFields();
                    var fields_it = fields.iter();
                    while (fields_it.next()) |field| {
                        try self.print_field(field);
                    }
                    try self.writer.closeStruct();
                },

                else => {},
            }
        }
    };
}

test "test2" {
    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(schema.CodeGeneratorRequest);
    var hashMap = std.AutoHashMap(u64, schema.Node.Reader).init(std.testing.allocator);
    defer hashMap.deinit();

    try populateLookupTable(&hashMap, s);
    var out = capnpWriter(std.io.getStdOut().writer());
    var transformer: Transformer(@TypeOf(out.writer)) = .{ .hashMap = hashMap, .writer = out };

    var it = (try s.getRequestedFiles()).iter();
    while (it.next()) |requestedFile| {
        try transformer.print_file(requestedFile);
    }
}
