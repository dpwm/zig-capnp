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

fn capitalize(str: []const u8, writer: anytype) !void {
    if (str.len == 0) return;
    try writer.print("{c}{s}", .{ std.ascii.toUpper(str[0]), str[1..] });
}

fn capitalized(x: []const u8) Wrapper([]const u8, capitalize) {
    return wrap(x, capitalize);
}

fn concatFn(values: [2][]const u8, writer: anytype) !void {
    for (values) |value| {
        try writer.print("{s}", .{value});
    }
}

fn concat(value: [2][]const u8) Wrapper([2][]const u8, concatFn) {
    return .{ .value = value };
}

const getter_type = enum {
    reader,
    builder,

    pub fn toString(self: getter_type) []const u8 {
        return @tagName(self);
    }
};

const type_context = enum {
    base,
    reader_getter,
    builder_getter,
};

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

        const TypedContext = struct {
            ctx: *WriteContext,
            typ: schema.Type.Reader,
            gt: type_context,
            with_error: bool,
        };

        fn typedFn(ctx: TypedContext, writer: anytype) @TypeOf(writer).Error!void {
            const out = writeType(ctx.ctx, ctx.typ, ctx.gt, ctx.with_error);

            return out catch |err| switch (err) {
                error.LimitExceeded => {
                    return void{};
                },
                else => |e| {
                    return e;
                },
            };
        }

        fn typed(value: TypedContext) Wrapper(TypedContext, typedFn) {
            return .{ .value = value };
        }

        fn ZigType(comptime T: type) type {
            return struct {
                pub fn readerType(ctx: *WriteContext, _: schema.Type.Reader, _: getter_type) E!void {
                    try ctx.writer.writeAll(@typeName(T));
                }

                pub fn builderType(ctx: *WriteContext, _: schema.Type.Reader) E!void {
                    try ctx.writer.writeAll(@typeName(T));
                }
            };
        }

        const Void = struct {
            usingnamespace ZigType(void);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("return void{};\n");
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openSetter(try field.getName(), "void", "void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("return;\n");
                }

                try ctx.closeSetter();
            }
        };

        const Bool = struct {
            usingnamespace ZigType(bool);

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("return self.{s}.readBoolField({d});\n", .{ gt.toString(), field.getSlot().?.getOffset() });
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openSetter(try field.getName(), "bool", "void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("self.builder.setBoolField({d}, value);\n", .{field.getSlot().?.getOffset()});
                }

                try ctx.closeSetter();
            }
        };

        fn Int(comptime T: type) type {
            return struct {
                usingnamespace ZigType(T);

                pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                    try ctx.openGetter(field, gt);
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print(
                            "return self.{s}.readIntField({s}, {});\n",
                            .{
                                gt.toString(),
                                @typeName(T),
                                field.getSlot().?.getOffset(),
                            },
                        );
                    }
                    try ctx.closeGetter();
                }

                pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                    try ctx.openSetter(try field.getName(), @typeName(T), "void");
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print("self.builder.setIntField({s}, {d}, value);\n", .{ @typeName(T), field.getSlot().?.getOffset() });
                    }

                    try ctx.closeSetter();
                }
            };
        }

        fn Float(comptime T: type) type {
            return struct {
                usingnamespace ZigType(T);

                pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                    try ctx.openGetter(field, gt);
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print(
                            "return self.{s}.readFloatField({s}, {d});\n",
                            .{
                                gt.toString(),
                                @typeName(T),
                                field.getSlot().?.getOffset(),
                            },
                        );
                    }
                    try ctx.closeGetter();
                }

                pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                    try ctx.openSetter(try field.getName(), @typeName(T), "void");
                    {
                        try ctx.writeIndent();
                        try ctx.writer.print("self.builder.setFloatField({s}, {d}, value);\n", .{ @typeName(T), field.getSlot().?.getOffset() });
                    }

                    try ctx.closeSetter();
                }
            };
        }

        const String = struct {
            pub fn readerType(ctx: *WriteContext, _: schema.Type.Reader, gt: getter_type) E!void {
                switch (gt) {
                    .reader => try ctx.writer.writeAll("capnp.Error![:0]const u8"),
                    .builder => try ctx.writer.writeAll("[:0]const u8"),
                }
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();
                    try ctx.writer.print(
                        "return self.{s}.readStringField({d});\n",
                        .{
                            gt.toString(),
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openSetter(try field.getName(), "[:0]const u8", "capnp.Error!void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("try self.builder.setTextField({d}, value);\n", .{field.getSlot().?.getOffset()});
                }

                try ctx.closeSetter();
            }
        };

        const Data = struct {
            pub fn readerType(ctx: *WriteContext, _: schema.Type.Reader, gt: getter_type) E!void {
                switch (gt) {
                    .reader => try ctx.writer.writeAll("capnp.Error![]const u8"),
                    .builder => try ctx.writer.writeAll("[]const u8"),
                }
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();
                    try ctx.writer.print(
                        "return self.{s}.readDataField({d});\n",
                        .{
                            gt.toString(),
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openSetter(try field.getName(), "[]const u8", "capnp.Error!void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("try self.builder.setDataField({d}, value);\n", .{field.getSlot().?.getOffset()});
                }

                try ctx.closeSetter();
            }
        };

        const List = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader, gt: getter_type) E!void {
                switch (gt) {
                    .reader => {
                        try ctx.writer.writeAll("capnp.List(");
                        try Self.readerType(ctx, try t.getList().?.getElementType(), gt);
                        try ctx.writer.writeAll(").Reader");
                    },
                    .builder => {
                        try ctx.writer.writeAll("capnp.List(");
                        try Self.readerType(ctx, try t.getList().?.getElementType(), gt);
                        try ctx.writer.writeAll(").Builder");
                    },
                }
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();

                    try ctx.writer.print(
                        "return self.{s}.readListField({}, {d});\n",
                        .{
                            gt.toString(),
                            typed(.{ .typ = try (try field.getSlot().?.getType()).getList().?.getElementType(), .ctx = ctx, .gt = gt, .with_error = true }),
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                try ctx.openSetter(try field.getName(), "", "capnp.Error!void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("try self.builder.setDataField({d}, value);\n", .{field.getSlot().?.getOffset()});
                }

                try ctx.closeSetter();
            }
        };

        const Struct = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader, gt: getter_type) E!void {
                switch (gt) {
                    .reader => {
                        try ctx.writer.print("capnp.Error!{s}.Reader", .{ctx.pathTable.get(t.getStruct().?.getTypeId()).?});
                    },
                    .builder => {
                        try ctx.writer.print("capnp.Error!{s}.Builder", .{ctx.pathTable.get(t.getStruct().?.getTypeId()).?});
                    },
                }
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                try ctx.openGetter(field, gt);
                {
                    try ctx.writeIndent();
                    try ctx.writer.print(
                        "return self.reader.readStructField({s}, {d});\n",
                        .{
                            ctx.pathTable.get((try field.getSlot().?.getType()).getStruct().?.getTypeId()).?,
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
                try ctx.closeGetter();
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                const path = ctx.pathTable.get((try field.getSlot().?.getType()).getStruct().?.getTypeId()).?;
                try ctx.openSetter(try field.getName(), concat([_][]const u8{ path, ".Reader" }), "capnp.Error!void");
                {
                    try ctx.writeIndent();
                    try ctx.writer.print("return self.builder.setStructField({s}, {d}, value);\n", .{ path, field.getSlot().?.getOffset() });
                }
                try ctx.closeGetter();
            }

            pub fn builderType(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                _ = field;
                _ = ctx;
            }
        };

        const Enum = struct {
            pub fn readerType(ctx: *WriteContext, t: schema.Type.Reader, gt: getter_type) E!void {
                _ = gt;
                try ctx.writer.writeAll(ctx.pathTable.get(t.getEnum().?.getTypeId()).?);
            }

            pub fn readerGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                _ = gt;
                _ = field;
                try ctx.writer.writeAll("return void{};");
            }

            pub fn builderSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
                _ = field;
                _ = ctx;
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

            pub fn openGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                const name = try field.getName();
                const typ = try field.getSlot().?.getType();
                try ctx.writeIndent();
                try ctx.writer.print("pub fn get{}(self: @This()) {} {{\n", .{ capitalized(name), typed(.{
                    .ctx = ctx,
                    .typ = typ,
                    .gt = switch (gt) {
                        .reader => .reader_getter,
                        .builder => .builder_getter,
                    },
                    .with_error = gt == .reader,
                }) });
                ctx.indenter.inc();
            }

            pub fn openSetter(ctx: *WriteContext, name: []const u8, typ: anytype, rtyp: anytype) E!void {
                try ctx.writeIndent();
                try ctx.writer.print("pub fn set{s}(self: @This(), value: {s}) {s} {{\n", .{ capitalized(name), typ, rtyp });
                ctx.indenter.inc();
            }

            pub fn closeGetter(ctx: *WriteContext) E!void {
                ctx.indenter.dec();
                try ctx.writeIndent();
                try ctx.writer.writeAll("}");
            }

            const closeSetter = closeGetter;
        };

        fn zigNameHelper(comptime name: []const u8, comptime n: usize) []const u8 {
            return name[0..1] ++ name[n..];
        }

        pub fn writeType(ctx: *WriteContext, reader: schema.Type.Reader, gt: type_context, with_error: bool) E!void {
            if (with_error) {
                switch (reader.which()) {
                    .list, .data, .text, .struct_ => {
                        try ctx.writer.writeAll("capnp.Error!");
                    },
                    else => {},
                }
            }
            const out = switch (reader.which()) {
                .void => "void",
                .bool => "bool",
                inline .int8, .int16, .int32, .int64 => |x| zigNameHelper(@tagName(x), 3),
                inline .uint8, .uint16, .uint32, .uint64 => |x| zigNameHelper(@tagName(x), 4),
                inline .float32, .float64 => |x| zigNameHelper(@tagName(x), 5),
                .text => "[:0]const u8",
                .data => "[]const u8",
                .list => {
                    try ctx.writer.writeAll("capnp.List(");
                    try writeType(ctx, try reader.getList().?.getElementType(), .base, true);
                    try ctx.writer.writeAll(")");
                    try ctx.writer.writeAll(switch (gt) {
                        .base => "",
                        .reader_getter => "Reader",
                        .builder_getter => "Builder",
                    });
                    return;
                },
                .enum_ => ctx.pathTable.get(reader.getEnum().?.getTypeId()).?,
                .struct_ => ctx.pathTable.get(reader.getStruct().?.getTypeId()).?,
                .interface => undefined,
                .anyPointer => "capnp.AnyPointer",
            };
            try ctx.writer.writeAll(out);
        }

        pub fn writeGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
            const target = gt.toString();

            switch (field.which()) {
                .slot => {
                    const slot = field.getSlot().?;
                    const t = try slot.getType();

                    try ctx.openGetter(field, gt);
                    try ctx.writeIndent();

                    switch (t.which()) {
                        .void => {
                            {
                                try ctx.writer.writeAll("return void{};\n");
                            }
                        },
                        .bool => {
                            try ctx.writer.print("return self.{s}.readBoolField({d});\n", .{ target, slot.getOffset() });
                        },
                        inline .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64 => |typeTag| {
                            const typeTagName = @tagName(typeTag);

                            try ctx.writer.print(
                                "return self.{s}.readIntField({s}, {});\n",
                                .{
                                    target,
                                    zigNameHelper(typeTagName, if (typeTagName[0] == 'u') 4 else 3),
                                    slot.getOffset(),
                                },
                            );
                        },
                        inline .float32, .float64 => |typeTag| {
                            try ctx.writer.print(
                                "return self.{s}.readFloatField({s}, {d});\n",
                                .{
                                    target,
                                    zigNameHelper(@tagName(typeTag), 5),
                                    field.getSlot().?.getOffset(),
                                },
                            );
                        },
                        .text => {
                            try ctx.writer.print(
                                "return self.{s}.readStringField({d});\n",
                                .{
                                    gt.toString(),
                                    field.getSlot().?.getOffset(),
                                },
                            );
                        },
                        .data => {
                            try ctx.writer.print(
                                "return self.{s}.readDataField({d});\n",
                                .{
                                    gt.toString(),
                                    field.getSlot().?.getOffset(),
                                },
                            );
                        },
                        else => {},
                    }
                    try ctx.closeGetter();
                },
                .group => {
                    try ctx.writer.writeAll(ctx.pathTable.get(field.getGroup().?.getTypeId()).?);
                },
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

    try M.writeType(&ctx, reader, .reader_getter, true);

    try std.testing.expectEqualStrings("void", fbs.getWritten());
}

test "writeReaderGetterReturnType" {
    var buf: [128]u8 = std.mem.zeroes([128]u8);
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

    fbs.reset();
    try M.writeType(&ctx, try fields.get(0).getSlot().?.getType(), .reader_getter, true);
    try std.testing.expectEqualStrings("void", fbs.getWritten());

    fbs.reset();
    try M.writeType(&ctx, try fields.get(1).getSlot().?.getType(), .reader_getter, true);
    try std.testing.expectEqualStrings("bool", fbs.getWritten());
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
    try M.writeType(&ctx, try reader.getSlot().?.getType(), .reader_getter, true);

    // try std.testing.expectEqualStrings("i32", fbs.getWritten());

    fbs.reset();
    try M.writeGetter(&ctx, reader, .reader);
    try std.testing.expectEqualStrings("pub fn get(self: @This()) i32 {\n    return self.reader.readIntField(i32, 3);\n}", fbs.getWritten());
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

    try pathTable.pathMap.put(0x0, try std.testing.allocator.dupe(u8, "_Root.TestStruct"));

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
        .pathTable = pathTable,
    };

    const reader = try message.getRootStruct(schema.Node);
    const fields = try reader.getStruct().?.getFields();
    const reader_getters = .{
        "pub fn getVoid(self: @This()) void {\n    return void{};\n}",
        "pub fn getBool(self: @This()) bool {\n    return self.reader.readBoolField(0);\n}",
        "pub fn getInt32(self: @This()) i32 {\n    return self.reader.readIntField(i32, 0);\n}",
        "pub fn getFloat32(self: @This()) f32 {\n    return self.reader.readFloatField(f32, 0);\n}",
        "pub fn getText(self: @This()) capnp.Error![:0]const u8 {\n    return self.reader.readStringField(0);\n}",
        "pub fn getData(self: @This()) capnp.Error![]const u8 {\n    return self.reader.readDataField(0);\n}",
        //"pub fn getInt32List(self: @This()) capnp.List(i32).Reader {\n    return self.reader.readListField(i32, 0);\n}",
        //"pub fn getStruct(self: @This()) capnp.Error!_Root.TestStruct.Reader {\n    return self.reader.readStructField(_Root.TestStruct, 0);\n}",
    };

    inline for (0.., reader_getters) |i, getterText| {
        const field = fields.get(i);
        // debugging info
        // std.debug.print("Reader: {}\n", .{field});
        fbs.reset();
        try M.writeGetter(&ctx, field, .reader);
        try std.testing.expectEqualStrings(getterText, fbs.getWritten());
    }

    const builder_getters = .{
        "pub fn getVoid(self: @This()) void {\n    return void{};\n}",
        "pub fn getBool(self: @This()) bool {\n    return self.builder.readBoolField(0);\n}",
        "pub fn getInt32(self: @This()) i32 {\n    return self.builder.readIntField(i32, 0);\n}",
        "pub fn getFloat32(self: @This()) f32 {\n    return self.builder.readFloatField(f32, 0);\n}",
        "pub fn getText(self: @This()) [:0]const u8 {\n    return self.builder.readStringField(0);\n}",
        "pub fn getData(self: @This()) []const u8 {\n    return self.builder.readDataField(0);\n}",
        //"pub fn getInt32List(self: @This()) capnp.List(i32).Builder {\n    return self.builder.readListField(i32, 0);\n}",
        //"pub fn getStruct(self: @This()) capnp.Error!_Root.TestStruct.Builder {\n    return self.reader.readStructField(_Root.TestStruct, 0);\n}",
    };

    inline for (0.., builder_getters) |i, getterText| {
        const field = fields.get(i);
        fbs.reset();
        try M.writeGetter(&ctx, field, .builder);
        try std.testing.expectEqualStrings(getterText, fbs.getWritten());
    }

    const builder_setters = .{
        "pub fn setVoid(self: @This(), value: void) void {\n    return;\n}",
        "pub fn setBool(self: @This(), value: bool) void {\n    self.builder.setBoolField(0, value);\n}",
        "pub fn setInt32(self: @This(), value: i32) void {\n    self.builder.setIntField(i32, 0, value);\n}",
        "pub fn setFloat32(self: @This(), value: f32) void {\n    self.builder.setFloatField(f32, 0, value);\n}",
        "pub fn setText(self: @This(), value: [:0]const u8) capnp.Error!void {\n    try self.builder.setTextField(0, value);\n}",
        "pub fn setData(self: @This(), value: []const u8) capnp.Error!void {\n    try self.builder.setDataField(0, value);\n}",
        //        "pub fn setInt32List(self: @This(), value: ) capnp.Error!void {\n    return self.builder.setListField(i32, value);\n}",
        //        "pub fn setStruct(self: @This(), value: _Root.TestStruct.Reader) capnp.Error!void {\n    return self.builder.setStructField(_Root.TestStruct, 0, value);\n}",
    };
    _ = builder_setters;
}

//    inline for (0.., builder_setters) |i, setterText| {
//        const field = fields.get(i);
//        fbs.reset();
//        try M.builderSetter(&ctx, field);
//        try std.testing.expectEqualStrings(setterText, fbs.getWritten());
//    }
