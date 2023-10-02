// We will define a Refactor functor here. This will take the WriterType as the parameter, and will be used throughout.

const schema = @import("schema.zig");
const std = @import("std");
const capnp = @import("capnp.zig");
const Allocator = std.mem.Allocator;

const NodeIdMap = std.AutoHashMap(u64, schema.Node.Reader);

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
                                const groupName = try std.fmt.bufPrint(&buffer, "_Group.{s}", .{try field.getName()});
                                try self.update(groupName, group.getTypeId());
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

fn Wrapper(comptime T: type, comptime F: anytype) type {
    return struct {
        value: T,

        pub fn format(self: @This(), comptime _: []const u8, _: std.fmt.FormatOptions, writer: anytype) !void {
            try F(self.value, writer);
        }
    };
}

pub fn wrap(value: anytype, comptime F: anytype) Wrapper(@TypeOf(value), F) {
    return .{ .value = value };
}

pub fn capitalize(str: []const u8, writer: anytype) !void {
    if (str.len == 0) return;
    try writer.print("{c}{s}", .{ std.ascii.toUpper(str[0]), str[1..] });
}

fn capitalized(x: []const u8) Wrapper([]const u8, capitalize) {
    return wrap(x, capitalize);
}

pub fn Refactor(comptime W: type) type {
    return struct {
        const WriterType = W;
        const E = W.Error || capnp.Error;
        const Self = @This();

        const Indenter = struct {
            level: usize = 0,

            pub fn write(self: Indenter, writer: W) E!void {
                for (0..self.level) |_| {
                    try writer.writeAll("    ");
                }
            }

            pub fn inc(self: *Indenter) void {
                self.level += 1;
            }

            pub fn dec(self: *Indenter) void {
                self.level -= 1;
            }
        };

        fn ZigType(comptime T: type) type {
            return struct {
                pub fn readerType(ctx: *WriteContext, _: schema.Type.Reader) E!void {
                    try ctx.writer.writeAll(@typeName(T));
                }
            };
        }

        const Void = struct {
            usingnamespace ZigType(void);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openGetter(try field.getName());
                {
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("return void{};\n");
                }
                try ctx.closeGetter();
            }
        };

        const Bool = struct {
            usingnamespace ZigType(bool);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openGetter(try field.getName());
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("return self.reader.readBoolField({d});\n", .{field.getSlot().?.getOffset()});
                }
                try ctx.closeGetter();
            }
        };

        fn Int(comptime T: type) type {
            return struct {
                usingnamespace ZigType(T);

                pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                    try ctx.openGetter(try field.getName());
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print(
                            "return self.reader.readIntField({s}, {});\n",
                            .{
                                @typeName(T),
                                field.getSlot().?.getOffset(),
                            },
                        );
                    }
                    try ctx.closeGetter();
                }
            };
        }

        fn Float(comptime T: type) type {
            return struct {
                usingnamespace ZigType(T);

                pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                    try ctx.openGetter(try field.getName());
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print(
                            "return self.reader.readFloatField({s}, {d});\n",
                            .{
                                @typeName(T),
                                field.getSlot().?.getOffset(),
                            },
                        );
                    }
                    try ctx.closeGetter();
                }
            };
        }

        const String = struct {
            usingnamespace ZigType([:0]const u8);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openGetter(try field.getName());
                {
                    try ctx.writeIndent();
                    try ctx.writer.print(
                        "return self.reader.readStringField({d});\n",
                        .{
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }
        };

        const Data = struct {
            usingnamespace ZigType([]const u8);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openGetter(try field.getName());
                {
                    try ctx.writeIndent();
                    try ctx.writer.print(
                        "return self.reader.readDataField({d});\n",
                        .{
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }
        };

        const List = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader) E!void {
                try ctx.writer.writeAll("capnp.ListReader(");
                try Self.readerType(ctx, try t.getList().?.getElementType());
                try ctx.writer.writeAll(")");
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openGetter(try field.getName());
                {
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("return self.reader.readListField(");
                    try Self.readerType(ctx, try (try field.getSlot().?.getType()).getList().?.getElementType());

                    try ctx.writer.print(
                        ", {d});\n",
                        .{
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }
        };

        const Struct = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader) E!void {
                try ctx.writer.writeAll(ctx.pathTable.get(t.getStruct().?.getTypeId()).?);
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                _ = field;
                try ctx.writer.writeAll("return void{{}};");
            }
        };

        const Enum = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader) E!void {
                try ctx.writer.writeAll(ctx.pathTable.get(t.getEnum().?.getTypeId()).?);
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                _ = field;
                try ctx.writer.writeAll("return void{};");
            }
        };

        const TypeRegistry = struct {
            const _void = Void;

            const _bool = Bool;

            const _text = String;
            const _data = Data;

            const _float32 = Float(f32);
            const _float64 = Float(f64);

            const _int64 = Int(i64);
            const _int32 = Int(i32);
            const _int16 = Int(i16);
            const _int8 = Int(i8);

            const _uint64 = Int(u64);
            const _uint32 = Int(u32);
            const _uint16 = Int(u16);
            const _uint8 = Int(u8);

            const _list = List;
            const _enum_ = Enum;
            const _struct_ = Struct;
            const _interface = _void;
            const _anyPointer = _void;

            pub fn get(comptime typ: schema.Type.Tag) type {
                return @field(TypeRegistry, "_" ++ @tagName(typ));
            }
        };

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()
        // THis would entail which just returning an enum(u16).

        //pub fn (comptime T: type, comptime T2: type) type {}

        pub const WriteContext = struct {
            writer: W,
            indenter: Indenter,
            pathTable: PathTable,

            pub fn writeIndent(self: *WriteContext) E!void {
                try self.indenter.write(self.writer);
            }

            pub fn openGetter(ctx: *WriteContext, x: []const u8) E!void {
                try ctx.writeIndent();
                try ctx.writer.print("pub fn get{}(self: @This()) {{\n", .{capitalized(x)});
                ctx.indenter.inc();
            }

            pub fn closeGetter(ctx: *WriteContext) E!void {
                ctx.indenter.dec();
                try ctx.writeIndent();
                try ctx.writer.writeAll("}");
            }
        };

        pub fn readerType(ctx: *WriteContext, reader: schema.Type.Reader) E!void {
            switch (reader.which()) {
                inline else => |t| {
                    try TypeRegistry.get(t).readerType(ctx, reader);
                },
            }
        }

        pub fn readerGetter(ctx: *WriteContext, reader: schema.Field.Reader) E!void {
            switch (reader.which()) {
                .slot => {
                    const t = try reader.getSlot().?.getType();
                    switch (t.which()) {
                        inline else => |typeTag| {
                            try TypeRegistry.get(typeTag).readerGetter(ctx, reader);
                        },
                    }
                },
                .group => {},
                else => {},
            }
        }
    };
}

test "simple" {
    var buf: [128]u8 = std.mem.zeroes([128]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const M = Refactor(@TypeOf(writer));

    var file = try std.fs.cwd().openFile("capnp-tests/08-schema-examples.void.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    var nodeTable = NodeIdMap.init(std.testing.allocator);
    defer nodeTable.deinit();

    var pathTable = PathTable.init(nodeTable);
    defer pathTable.deinit();

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
        .pathTable = pathTable,
    };

    const reader = try message.getRootStruct(schema.Type);
    try M.readerType(&ctx, reader);

    try std.testing.expectEqualStrings("void", fbs.getWritten());
}

test "field" {
    var buf: [128]u8 = std.mem.zeroes([128]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const M = Refactor(@TypeOf(writer));

    var file = try std.fs.cwd().openFile("capnp-tests/08-schema-examples.field1.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    var nodeTable = NodeIdMap.init(std.testing.allocator);
    defer nodeTable.deinit();

    var pathTable = PathTable.init(nodeTable);
    defer pathTable.deinit();

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
        .pathTable = pathTable,
    };

    const reader = try message.getRootStruct(schema.Field);
    try M.readerType(&ctx, try reader.getSlot().?.getType());

    // try std.testing.expectEqualStrings("i32", fbs.getWritten());

    fbs.reset();
    try M.readerGetter(&ctx, reader);
    try std.testing.expectEqualStrings("pub fn get(self: @This()) {\n    return self.reader.readIntField(i32, 3);\n}", fbs.getWritten());
}

test "node" {
    var buf = std.mem.zeroes([1024]u8);
    var fbs = std.io.fixedBufferStream(&buf);
    const writer = fbs.writer();

    const M = Refactor(@TypeOf(writer));

    var file = try std.fs.cwd().openFile("capnp-tests/08-schema-examples.node.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    var nodeTable = NodeIdMap.init(std.testing.allocator);
    defer nodeTable.deinit();

    var pathTable = PathTable.init(nodeTable);
    defer pathTable.deinit();

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
        .pathTable = pathTable,
    };

    const reader = try message.getRootStruct(schema.Node);
    const fields = try reader.getStruct().?.getFields();
    const slotTypes = .{
        .{ "void", "pub fn getVoid(self: @This()) {\n    return void{};\n}" },
        .{ "bool", "pub fn getBool(self: @This()) {\n    return self.reader.readBoolField(0);\n}" },
        .{ "i32", "pub fn getInt32(self: @This()) {\n    return self.reader.readIntField(i32, 0);\n}" },
        .{ "f32", "pub fn getFloat32(self: @This()) {\n    return self.reader.readFloatField(f32, 0);\n}" },
        .{ "[:0]const u8", "pub fn getText(self: @This()) {\n    return self.reader.readStringField(0);\n}" },
        .{ "[]const u8", "pub fn getData(self: @This()) {\n    return self.reader.readDataField(0);\n}" },
        .{ "capnp.ListReader(i32)", "pub fn getInt32List(self: @This()) {\n    return self.reader.readListField(i32, 0);\n}" },
    };
    inline for (0.., slotTypes) |i, slotType| {
        const field = fields.get(i);
        // debugging info
        // std.debug.print("Reader: {}\n", .{field});
        fbs.reset();
        try M.readerType(&ctx, try field.getSlot().?.getType());
        try std.testing.expectEqualStrings(slotType[0], fbs.getWritten());

        fbs.reset();
        try M.readerGetter(&ctx, field);
        try std.testing.expectEqualStrings(slotType[1], fbs.getWritten());
    }
}
