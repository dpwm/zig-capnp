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
            try self.writeLineC(content);
            try self.writer.writeAll("\n");
        }

        pub fn writeLineC(self: *Self, content: []const u8) Error!void {
            for (0..self.indent) |_| {
                try self.writer.writeAll("  ");
            }
            try self.writer.writeAll(content);
        }

        pub fn printLineC(self: *Self, comptime format: []const u8, args: anytype) Error!void {
            for (0..self.indent) |_| {
                try self.writer.writeAll("  ");
            }
            try self.writer.print(format, args);
        }

        pub fn printLine(self: *Self, comptime format: []const u8, args: anytype) Error!void {
            try self.printLineC(format, args);
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

            try self.writeLine("reader: capnp.StructReader,\n");
        }

        pub fn closeStruct(self: *Self) Error!void {
            self.indent -= 1;
            try self.writeLine("};\n");
        }

        pub fn openTag(self: *Self) Error!void {
            try self.writeLine("const _Tag = union(enum) {");
            self.indent += 1;
        }

        pub fn closeTag(self: *Self) Error!void {
            self.indent -= 1;
            try self.writeLine("};\n");
        }

        pub fn functionDefOpenArgs(self: *Self, name: []const u8) Error!void {
            try self.printLineC("pub fn {s}(", .{name});
        }

        pub fn getterOpenArgs(self: *Self, name: []const u8) Error!void {
            try self.printLineC("pub fn get{c}{s}(", .{ std.ascii.toUpper(name[0]), name[1..] });
        }

        pub fn functionDefArgPrint(self: *Self, name: []const u8, arg_type: []const u8) Error!void {
            return self.writer.print("{s}:{s},", .{ name, arg_type });
        }

        pub fn functionDefCloseArgs(self: *Self) Error!void {
            try self.writer.writeAll(") ");
        }

        pub fn functionDefOpenBlock(self: *Self) Error!void {
            try self.writer.writeAll(" {\n");
            self.indent += 1;
        }

        pub fn functionDefCloseBlock(self: *Self) Error!void {
            self.indent -= 1;
            try self.writeLine("}\n");
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
        allocator: std.mem.Allocator,

        const Self = @This();

        const Error = std.mem.Allocator.Error || CapnpWriterType.Error || capnp.Counter.Error;

        pub fn print_field_type(self: *Self, field: schema.Field.Reader) Error!void {
            switch (try field.which()) {
                .slot => |slot| {
                    try self.zigType(try slot.getType());
                },
                .group => |group| {
                    const node = self.hashMap.get(group.getId()).?;
                    const name = try node.getDisplayName();
                    try self.writer.writer.writeAll(name);
                },
                else => {
                    unreachable;
                },
            }
        }

        pub fn print_field(self: *Self, field: schema.Field.Reader) Error!void {
            if (field.getDiscriminantValue() == 65535) return;
            {
                const name = try field.getName();

                try self.writer.getterOpenArgs(name);
                try self.writer.functionDefCloseArgs();
            }

            try self.print_field_type(field);

            try self.writer.functionDefOpenBlock();
            try self.writer.functionDefCloseBlock();
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

        pub fn zigType(self: *Self, type_: schema.Type.Reader) Error!void {
            const typename = switch (try type_.which()) {
                .void => "void",
                .bool => "bool",
                .uint8 => "u8",
                .uint16 => "u16",
                .uint32 => "u32",
                .uint64 => "u64",
                .int8 => "i8",
                .int16 => "i16",
                .int32 => "i32",
                .int64 => "i64",
                .float32 => "f32",
                .float64 => "f64",
                .text => "[]const u8",
                .data => "[]const u8",
                .list => |list| {
                    switch (try (try list.getElementType()).which()) {
                        .struct_ => |struct_| {
                            _ = struct_;
                            try self.writer.writer.writeAll("Error!capnp.CompositeListReader(");
                        },
                        else => {
                            try self.writer.writer.writeAll("Error!capnp.ListReader(");
                        },
                    }
                    try self.zigType(try list.getElementType());
                    try self.writer.writer.writeAll(")");
                    return;
                },
                .struct_ => |struct_| blk: {
                    const node = self.hashMap.get(struct_.getId()).?;
                    const name = try node.getDisplayName();
                    const pos = if (std.mem.indexOfScalar(u8, name, ':')) |x| (x + 1) else 0;
                    break :blk name[pos..];
                },
                .enum_ => "enum",
                .anyPointer => "capnp.AnyPointer",

                else => "anytype",
            };
            try self.writer.writer.writeAll(typename);
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

                    if (struct_.getDiscriminantCount() > 0) {
                        var fields_it = (try struct_.getFields()).iter();
                        var discriminantFields = try self.allocator.alloc(schema.Field.Reader, struct_.getDiscriminantCount());
                        defer self.allocator.free(discriminantFields);

                        while (fields_it.next()) |field| {
                            if (field.getDiscriminantValue() != 65535) {
                                discriminantFields[field.getDiscriminantValue()] = field;
                            }
                        }
                        try self.writer.openTag();
                        for (0.., discriminantFields) |n, field| {
                            _ = n;
                            try self.writer.printLineC(".{s}: ", .{try field.getName()});
                            try self.print_field_type(field);
                            try self.writer.writer.writeAll(",\n");
                        }
                        try self.writer.closeTag();
                    }

                    {
                        const fields = try struct_.getFields();
                        var fields_it = fields.iter();
                        while (fields_it.next()) |field| {
                            try self.print_field(field);
                        }
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
    var transformer: Transformer(@TypeOf(out.writer)) = .{ .hashMap = hashMap, .writer = out, .allocator = std.testing.allocator };

    var it = (try s.getRequestedFiles()).iter();
    while (it.next()) |requestedFile| {
        try transformer.print_file(requestedFile);
    }
}
