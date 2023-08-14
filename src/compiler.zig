const std = @import("std");
const capnp = @import("capnp.zig");
const schema = @import("schema.zig");
const Allocator = std.mem.Allocator;

const NodeIdMap = std.AutoHashMap(u64, schema.Node.Reader);

pub fn populateLookupTable(hashMap: *NodeIdMap, cgr: schema.CodeGeneratorRequest.Reader) !void {
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
            try self.writeLine("const _Root = @This();");
            try self.writer.writeAll("\n");
        }

        pub fn openStruct(self: *Self, name: anytype) Error!void {
            try self.printLine("pub const {s} = struct {{", .{name});
            self.indent += 1;
        }

        pub fn declareReader(self: *Self) Error!void {
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
            try self.printLineC("pub fn get{s}(", .{Capitalized.wrap(name)});
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

const Capitalized = struct {
    str: []const u8,

    pub fn wrap(str: []const u8) Capitalized {
        return Capitalized{ .str = str };
    }

    pub fn format(value: Capitalized, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        if (value.str.len == 0) return;
        try writer.print("{c}{s}", .{ std.ascii.toUpper(value.str[0]), value.str[1..] });
    }
};

const ValueTypeFormatter = struct {
    value: schema.Value.Reader._Tag,

    pub fn format(value: ValueTypeFormatter, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;

        switch (value.value) {
            .uint64 => |x| {
                try writer.print("{}", .{x});
            },
            .uint32 => |x| {
                try writer.print("{}", .{x});
            },
            .uint16 => |x| {
                try writer.print("{}", .{x});
            },
            .uint8 => |x| {
                try writer.print("{}", .{x});
            },
            .int64 => |x| {
                try writer.print("{}", .{x});
            },
            .int32 => |x| {
                try writer.print("{}", .{x});
            },
            .int16 => |x| {
                try writer.print("{}", .{x});
            },
            .int8 => |x| {
                try writer.print("{}", .{x});
            },
            .float32 => |x| {
                try writer.print("{}", .{x});
            },
            .float64 => |x| {
                try writer.print("{}", .{x});
            },
            .bool => |x| {
                try writer.print("{}", .{x});
            },
            .void => {
                try writer.writeAll("void{}");
            },
            .text => |x| {
                try writer.writeAll(x);
            },
            .data => |x| {
                _ = x;
                unreachable;
            },
            .list => |x| {
                _ = x;
                unreachable;
            },
            .enum_ => |x| {
                _ = x;
                unreachable;
            },
            .struct_ => |x| {
                _ = x;
                unreachable;
            },
            .interface => {
                unreachable;
            },
            .anyPointer => |x| {
                _ = x;
                unreachable;
            },
            ._other => {
                unreachable;
            },
        }
    }
};

pub fn Transformer(comptime WriterType: type) type {
    return struct {
        const CapnpWriterType = CapnpWriter(WriterType);
        pub const StringSet = std.StringHashMap(void);
        hashMap: NodeIdMap,
        writer: CapnpWriterType,
        allocator: std.mem.Allocator,
        reserved_names: StringSet,
        pathTable: PathTable,

        const Self = @This();

        const Error = std.mem.Allocator.Error || CapnpWriterType.Error || capnp.Counter.Error;

        pub fn is_reserved_name(self: Self, name: []const u8) bool {
            return (self.reserved_names.get(name) != null);
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
                            try self.writer.writer.writeAll("capnp.CompositeListReader(");
                        },
                        else => {
                            try self.writer.writer.writeAll("capnp.ListReader(");
                        },
                    }
                    try self.zigType(try list.getElementType());
                    try self.writer.writer.writeAll(")");
                    return;
                },
                .struct_ => |struct_| self.pathTable.get(struct_.getId()).?,
                .enum_ => |enum_| self.pathTable.get(enum_.getTypeId()).?,
                .anyPointer => "capnp.AnyPointer",

                else => "anytype",
            };
            try self.writer.writer.writeAll(typename);
        }

        pub fn print_field_type(self: *Self, field: schema.Field.Reader) Error!void {
            switch (try field.which()) {
                .slot => |slot| {
                    const type_ = try slot.getType();
                    switch (try type_.which()) {
                        .anyPointer, .struct_, .list, .text, .data => {
                            try self.writer.writer.writeAll("capnp.Error!");
                        },
                        else => {},
                    }
                    try self.zigType(type_);
                },
                .group => |group| {
                    try self.writer.writer.writeAll(self.pathTable.get(group.getId()).?);
                    try self.writer.writer.writeAll(".Reader");
                },
                else => {
                    unreachable;
                },
            }
        }

        pub fn print_getter_body(self: *Self, field: schema.Field.Reader) Error!void {
            const writer = self.writer.writer;

            switch (try field.which()) {
                .slot => |slot| {
                    const typeR = try slot.getType();
                    switch (try typeR.which()) {
                        .void => {
                            try writer.writeAll("void {}");
                        },
                        .bool => {
                            try writer.print("self.reader.readBoolField({})", .{slot.getOffset()});
                        },
                        .float32 => {
                            try writer.print(
                                "self.reader.readFloatField(f32, {})",
                                .{slot.getOffset()},
                            );
                        },
                        .float64 => {
                            try writer.print(
                                "self.reader.readFloatField(f64, {})",
                                .{slot.getOffset()},
                            );
                        },
                        .text, .data => {
                            try writer.print(
                                "try self.reader.readStringField({})",
                                .{slot.getOffset()},
                            );
                        },
                        .list => |list| {
                            _ = list;
                            try writer.writeAll("try self.reader.readPtrField(");
                            // try self.zigType((try list.getElementType()));
                            try self.zigType(typeR);
                            try self.writer.writer.print(", {})", .{slot.getOffset()});
                        },
                        .struct_ => |struct_| {
                            const nodeId = struct_.getId();
                            try writer.print(
                                "try self.reader.readPtrField({s}.Reader, {})",
                                .{
                                    self.pathTable.get(nodeId).?,
                                    slot.getOffset(),
                                },
                            );
                        },
                        .enum_ => |enum_| {
                            _ = enum_;
                        },
                        .anyPointer => {
                            try writer.print("try self.reader.readPtrField(capnp.AnyPointerReader, {})", .{
                                slot.getOffset(),
                            });
                        },

                        .uint8, .uint16, .uint32, .uint64, .int8, .int16, .int32, .int64 => {
                            try writer.writeAll("self.reader.readIntField(");
                            try self.zigType(typeR);
                            try self.writer.writer.print(", {d}) ^ {d}", .{ slot.getOffset(), ValueTypeFormatter{ .value = try (try slot.getDefaultValue()).which() } });
                        },
                        else => {},
                    }
                },
                .group => {
                    try writer.writeAll(".{ .reader = self.reader }");
                },
                else => {},
            }
        }

        pub fn print_field(self: *Self, field: schema.Field.Reader) Error!void {
            if (field.getDiscriminantValue() != 65535) return;
            {
                const name = try field.getName();

                try self.writer.getterOpenArgs(name);
                try self.writer.writer.writeAll("self: @This()");
                try self.writer.functionDefCloseArgs();
            }

            try self.print_field_type(field);

            try self.writer.functionDefOpenBlock();
            try self.writer.writeLineC("return ");
            try self.print_getter_body(field);
            try self.writer.writer.writeAll(";\n");
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

        pub fn print_node(self: *Self, nodeId: u64, name: anytype) Error!void {
            const node = self.hashMap.get(nodeId) orelse return Allocator.Error.OutOfMemory;
            switch (try node.which()) {
                .struct_ => |struct_| {
                    try self.writer.openStruct(name);

                    try self.writer.printLine("const id: u64 = 0x{x};\n", .{node.getId()});

                    { // Group
                        try self.writer.openStruct("_Group");
                        var field_it = (try struct_.getFields()).iter();
                        while (field_it.next()) |field| {
                            switch (try field.which()) {
                                .group => |group| {
                                    try self.print_node(group.getId(), Capitalized.wrap(try field.getName()));
                                },
                                else => {},
                            }
                        }
                        try self.writer.closeStruct();
                    }

                    { // Nested Nodes

                        const nested = try node.getNestedNodes();
                        var nested_it = nested.iter();

                        while (nested_it.next()) |nested_node| {
                            try self.print_node(nested_node.getId(), try nested_node.getName());
                        }
                    }

                    { // Define the reader
                        try self.writer.openStruct("Reader");
                        try self.writer.declareReader();

                        if (struct_.getDiscriminantCount() > 0) {
                            var discriminantFields = try self.allocator.alloc(schema.Field.Reader, struct_.getDiscriminantCount());
                            defer self.allocator.free(discriminantFields);

                            { // Extract the discriminantFields
                                var fields_it = (try struct_.getFields()).iter();

                                while (fields_it.next()) |field| {
                                    if (field.getDiscriminantValue() != 65535) {
                                        discriminantFields[field.getDiscriminantValue()] = field;
                                    }
                                }
                            }

                            { // Write the tag union
                                try self.writer.writeLine("const _Tag = union(enum) {");
                                self.writer.indent += 1;

                                for (0.., discriminantFields) |n, field| {
                                    _ = n;
                                    const fieldName = try field.getName();

                                    if (self.is_reserved_name(fieldName)) {
                                        try self.writer.printLineC("{s}_: ", .{fieldName});
                                    } else {
                                        try self.writer.printLineC("{s}: ", .{fieldName});
                                    }
                                    try self.print_field_type(field);
                                    try self.writer.writer.writeAll(",\n");
                                }

                                try self.writer.writeLine("_: u16,");
                                try self.writer.closeStruct();
                            }

                            { // Write the tag getter
                                try self.writer.writeLine("pub fn which (self: @This()) capnp.Error!_Tag {");
                                self.writer.indent += 1;
                                try self.writer.printLine("return switch(self.reader.readIntField(u16, {})) {{", .{struct_.getDiscriminantOffset()});
                                self.writer.indent += 1;

                                for (0.., discriminantFields) |n, field| {
                                    const fieldName = try field.getName();
                                    try self.writer.printLineC("{} => _Tag{{ ", .{n});
                                    if (self.is_reserved_name(fieldName)) {
                                        try self.writer.writer.print(".{s}_ = ", .{fieldName});
                                    } else {
                                        try self.writer.writer.print(".{s} = ", .{fieldName});
                                    }

                                    try self.print_getter_body(field);

                                    try self.writer.writer.writeAll(" },\n");
                                }

                                try self.writer.writeLine("else => |n| _Tag { ._ = n},");

                                self.writer.indent -= 1;
                                try self.writer.writeLine("};");
                                self.writer.indent -= 1;
                                try self.writer.writeLine("}");
                            }
                        }
                    }
                    {
                        const fields = try struct_.getFields();
                        var fields_it = fields.iter();
                        while (fields_it.next()) |field| {
                            try self.print_field(field);
                        }
                    }

                    try self.writer.closeStruct();

                    try self.writer.closeStruct();
                },

                else => {},
            }
        }
    };
}

// Just using one file for now. We will add this back in later
const PathTable = struct {
    const PathMap = std.AutoHashMap(u64, []const u8);
    const Error = std.fmt.BufPrintError || Allocator.Error || capnp.Counter.Error;
    pathMap: PathMap,
    nodeIdMap: NodeIdMap,
    allocator: Allocator,

    pub fn init(nodeIdMap: NodeIdMap) PathTable {
        const allocator = nodeIdMap.allocator;
        return PathTable{ .pathMap = PathMap.init(allocator), .allocator = allocator, .nodeIdMap = nodeIdMap };
    }
    pub fn update(self: *PathTable, name: []const u8, nodeId: u64) Error!void {
        const node = self.nodeIdMap.get(nodeId).?;

        var path: []const u8 = "";
        if (self.pathMap.get(node.getScopeId())) |parentName| {
            path = try std.fmt.allocPrint(self.allocator, "{s}.{s}", .{ parentName, name });
        } else {
            path = try std.fmt.allocPrint(self.allocator, "{s}", .{name});
        }

        try self.pathMap.put(node.getId(), path);
        {
            var it = (try node.getNestedNodes()).iter();
            while (it.next()) |nestedNode| {
                try self.update(try nestedNode.getName(), nestedNode.getId());
            }
        }
        {
            var buffer = std.mem.zeroes([128]u8);
            switch (try node.which()) {
                .struct_ => |struct_| {
                    var field_it = (try struct_.getFields()).iter();
                    while (field_it.next()) |field| {
                        switch (try field.which()) {
                            .group => |group| {
                                const groupName = try std.fmt.bufPrint(&buffer, "_Group.{}", .{Capitalized.wrap(try field.getName())});
                                try self.update(groupName, group.getId());
                            },
                            else => {},
                        }
                    }
                },
                else => {},
            }
        }
    }

    pub fn get(self: PathTable, id: u64) ?[]const u8 {
        return self.pathMap.get(id);
    }

    pub fn updateFile(self: *PathTable, requestedFile: schema.CodeGeneratorRequest.RequestedFile.Reader) Error!void {
        try self.update("_Root", requestedFile.getId());
    }

    pub fn deinit(self: *PathTable) void {
        var it = self.pathMap.valueIterator();
        while (it.next()) |value| {
            self.allocator.free(value.*);
        }
        self.pathMap.deinit();
    }
};

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
    var reserved_names = std.StringHashMap(void).init(std.testing.allocator);
    defer reserved_names.deinit();
    try reserved_names.put("struct", {});
    try reserved_names.put("enum", {});
    try reserved_names.put("const", {});

    var pathTable = PathTable.init(hashMap);
    defer pathTable.deinit();

    {
        var it = (try s.getRequestedFiles()).iter();
        while (it.next()) |requestedFile| {
            try pathTable.updateFile(requestedFile);
        }
    }

    var transformer = Transformer(@TypeOf(out.writer)){
        .hashMap = hashMap,
        .writer = out,
        .allocator = std.testing.allocator,
        .reserved_names = reserved_names,
        .pathTable = pathTable,
    };

    {
        var it = (try s.getRequestedFiles()).iter();
        while (it.next()) |requestedFile| {
            try transformer.print_file(requestedFile);
        }
    }
}
