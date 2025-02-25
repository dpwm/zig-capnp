// We will define a Refactor functor here. This will take the WriterType as the parameter, and will be used throughout.

const schema = @import("schema.zig");
const std = @import("std");
const capnp = @import("capnp.zig");

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

const keywords: [3][]const u8 = .{ "struct", "enum", "const" };

fn isKeyword(name: []const u8) bool {
    const hashed = std.hash.Wyhash.hash(0, name);
    for (keywords) |keyword| {
        if (std.hash.Wyhash.hash(0, keyword) == hashed) {
            if (std.mem.eql(u8, keyword, name))
                return true;
        }
    }
    return false;
}

fn writeReplaceKeyword(name: []const u8, writer: anytype) !void {
    if (isKeyword(name)) {
        try writer.writeAll("@\"");
        try writer.writeAll(name);
        try writer.writeAll("\"");
    } else {
        try writer.writeAll(name);
    }
}

// This is effectively like a functor (a parametrerized module) in OCaml.
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

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()
        // THis would entail which just returning an enum(u16).

        //pub fn (comptime T: type, comptime T2: type) type {}

        pub const WriteContext = struct {
            writer: W,
            indenter: Indenter,
            nodes: capnp.CompositeListReader(schema.Node) = capnp.CompositeListReader(schema.Node).empty,

            pub fn getNodeById(self: *WriteContext, id: u64) schema.Node.Reader {
                // Scan through looking for nodes. This is O(N), but could be O(1) if a problem.
                for (0..self.nodes.length) |i| {
                    const node = self.nodes.get(@intCast(i));
                    if (node.getId() == id) {
                        return node;
                    }
                } else {
                    std.debug.print("Node {} not found\n", .{id});
                    @panic("getNodeById: Node not found");
                }
                // We panic if the node is not present. After all, what else can we do?

            }

            fn writeNodeNameById(self: *WriteContext, id: u64) !void {
                try self.writeNodeName(self.getNodeById(id));
            }

            fn writeNodeName(self: *WriteContext, node: schema.Node.Reader) !void {
                // cppFullName first checks scopeID isn’t zero,

                var current_node = node;
                var ancestors = std.BoundedArray(u64, 64).init(0) catch @panic("writeNodeName: imposible");

                ancestors.appendAssumeCapacity(current_node.getId());
                var scope_id = current_node.getScopeId();

                //  We need to do this in the main

                // Get all ancestors
                while (scope_id != 0) {
                    ancestors.append(scope_id) catch @panic("writeNodeName: stack overflow");
                    current_node = self.getNodeById(scope_id);
                    scope_id = current_node.getScopeId();
                }

                // ASSUME This works because files should always be the outermost scope.
                if (current_node.which() == .file) {
                    // try self.writer.print("{s}", .{try node.getDisplayName()});
                    try self.writer.writeAll("_Root");
                }

                // todo check if file and give sane error message etc
                //
                _ = ancestors.pop();

                while (ancestors.popOrNull()) |child_node_id| {
                    var is_field = false;
                    const parent_nested_nodes = try current_node.getNestedNodes();
                    const scope_name: []const u8 = result: for (0..parent_nested_nodes.length) |i| {
                        const nested_node = parent_nested_nodes.get(@intCast(i));
                        if (nested_node.getId() == child_node_id) {
                            break :result try nested_node.getName();
                        }
                    } else {
                        // It must be a group from a field
                        const fields = try current_node.getStruct().?.getFields();
                        for (0..fields.length) |i| {
                            const field = fields.get(@intCast(i));
                            if (field.getGroup()) |group| {
                                if (group.getTypeId() == child_node_id) {
                                    is_field = true;
                                    break :result try field.getName();
                                }
                            }
                        }
                        @panic("No link from parent to child – this should never happen");
                    };

                    try self.writer.writeAll(".");
                    if (is_field) {
                        try writeReplaceKeyword(scope_name, self.writer);
                    } else {
                        try self.writer.writeAll(scope_name);
                    }
                    current_node = self.getNodeById(child_node_id);
                }
            }

            pub fn writeIndent(self: *WriteContext) E!void {
                try self.indenter.write(self.writer);
            }

            pub fn openGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
                const name = try field.getName();
                try ctx.writeIndent();
                const tgt: type_context = switch (gt) {
                    .reader => .reader_getter,
                    .builder => .builder_getter,
                };
                switch (field.which()) {
                    .slot => {
                        const typ = try field.getSlot().?.getType();
                        try ctx.writer.print("pub fn get{}(self: @This()) ", .{capitalized(name)});
                        try writeType(ctx, typ, tgt, true);
                        try ctx.writer.writeAll(" {\n");
                    },
                    .group => {
                        try ctx.writer.print("pub fn get{}(self: @This()) ", .{capitalized(name)});
                        try ctx.writeNodeNameById(field.getGroup().?.getTypeId());
                        try ctx.writer.writeAll(" {\n");
                    },
                    else => {},
                }
                ctx.indenter.inc();
            }

            pub fn openSetter(ctx: *WriteContext, name: []const u8, typ: anytype, rtyp: anytype) E!void {
                try ctx.writeIndent();
                try ctx.writer.print("pub fn set{s}(self: @This(), value: {s}) {s} {{\n", .{ capitalized(name), typ, rtyp });
                ctx.indenter.inc();
            }

            pub fn openVoidSetter(ctx: *WriteContext, name: []const u8) E!void {
                try ctx.writeIndent();
                try ctx.writer.print("pub fn set{s}(self: @This()) void {{\n", .{capitalized(name)});
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
                    try writeType(ctx, try reader.getList().?.getElementType(), .base, false);
                    try ctx.writer.writeAll(")");
                    try ctx.writer.writeAll(switch (gt) {
                        .base => "",
                        .reader_getter => ".Reader",
                        .builder_getter => ".Builder",
                    });
                    return;
                },
                .enum_ => {
                    try ctx.writeNodeNameById(reader.getEnum().?.getTypeId());
                    return;
                },
                .struct_ => {
                    try ctx.writeNodeNameById(reader.getStruct().?.getTypeId());
                    try ctx.writer.writeAll(switch (gt) {
                        .base => "",
                        .reader_getter => ".Reader",
                        .builder_getter => ".Builder",
                    });
                    return;
                },
                .interface => undefined,
                .anyPointer => "capnp.AnyPointer",
            };
            try ctx.writer.writeAll(out);
        }

        pub fn writeNode(ctx: *WriteContext, name: []const u8, node: schema.Node.Reader) E!void {
            switch (node.which()) {
                .file => {
                    try ctx.writer.print("// {s}\n", .{name});
                    try ctx.writer.writeAll("// This file is automatically generated. DO NOT EDIT.\n\n");
                    try ctx.writer.writeAll("const _Root = @This();\nconst capnp = @import(\"capnp.zig\");\n\n");

                    const nested_nodes = try node.getNestedNodes();
                    for (0..nested_nodes.length) |i| {
                        const nested_node = nested_nodes.get(@intCast(i));
                        try writeNode(ctx, try nested_node.getName(), ctx.getNodeById(nested_node.getId()));
                    }
                },

                .@"enum" => {
                    try ctx.writeIndent();
                    try ctx.writer.print("const {s} = enum {{\n", .{name});
                    ctx.indenter.inc();

                    const enumerants = try node.getEnum().?.getEnumerants();
                    for (0..enumerants.length) |i| {
                        const enumerant = enumerants.get(@intCast(i));
                        try ctx.writeIndent();
                        try ctx.writer.print("{s},\n", .{try enumerant.getName()});
                    }

                    try ctx.writeIndent();
                    ctx.indenter.dec();
                    try ctx.writer.writeAll("};\n");
                },

                .interface => {
                    // not yet implemented
                },

                .@"const" => {},

                .annotation => {},

                .@"struct" => {
                    try ctx.writeIndent();
                    try ctx.writer.print("const {s} = struct {{\n", .{name});
                    ctx.indenter.inc();

                    try ctx.writeIndent();
                    try ctx.writer.writeAll("const Reader = struct {\n");
                    ctx.indenter.inc();

                    const fields = try node.getStruct().?.getFields();

                    if (node.getStruct().?.getDiscriminantCount() > 0) {
                        try ctx.writeIndent();
                        try ctx.writer.writeAll("const Tag = enum(u16) {\n");
                        ctx.indenter.inc();

                        for (0..fields.length) |i| {
                            const field = fields.get(@intCast(i));
                            if (field.getDiscriminantValue() == 0xffff) continue;
                            try ctx.writeIndent();
                            try writeReplaceKeyword(try field.getName(), ctx.writer);
                            try ctx.writer.print(" = {},\n", .{field.getDiscriminantValue()});
                        }

                        ctx.indenter.dec();
                        try ctx.writeIndent();
                        try ctx.writer.writeAll("};\n\n");
                    }

                    for (0..fields.length) |i| {
                        try writeGetter(ctx, fields.get(@intCast(i)), .reader);
                        try ctx.writer.writeAll("\n\n");
                    }

                    // Nested nodes
                    const nested_nodes = try node.getNestedNodes();
                    for (0..nested_nodes.length) |i| {
                        const nested_node = nested_nodes.get(@intCast(i));
                        try writeNode(ctx, try nested_node.getName(), ctx.getNodeById(nested_node.getId()));
                    }

                    ctx.indenter.dec();
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("};\n");

                    try ctx.writeIndent();
                    try ctx.writer.writeAll("const Builder = struct {\n");
                    ctx.indenter.inc();

                    for (0..fields.length) |i| {
                        try writeGetter(ctx, fields.get(@intCast(i)), .builder);
                        try ctx.writer.writeAll("\n\n");
                        try writeSetter(ctx, fields.get(@intCast(i)));
                        try ctx.writer.writeAll("\n\n");
                    }

                    ctx.indenter.dec();
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("};\n");

                    ctx.indenter.dec();
                    try ctx.writeIndent();
                    try ctx.writer.writeAll("};\n");
                },
                _ => {
                    @panic("Unknown node type");
                },
            }
        }

        pub fn writeGetter(ctx: *WriteContext, field: schema.Field.Reader, gt: getter_type) E!void {
            const target = gt.toString();

            try ctx.openGetter(field, gt);
            try ctx.writeIndent();

            switch (field.which()) {
                .slot => {
                    const slot = field.getSlot().?;
                    const t = try slot.getType();

                    switch (t.which()) {
                        .void => {
                            {
                                try ctx.writer.writeAll("return self.reader.readVoid();\n");
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
                        .list => {
                            try ctx.writer.print(
                                "return self.{s}.readListField({}, {d});\n",
                                .{
                                    gt.toString(),
                                    typed(.{ .typ = try (try field.getSlot().?.getType()).getList().?.getElementType(), .ctx = ctx, .gt = switch (gt) {
                                        .reader => .reader_getter,
                                        .builder => .builder_getter,
                                    }, .with_error = false }),
                                    field.getSlot().?.getOffset(),
                                },
                            );
                        },
                        .struct_ => {
                            try ctx.writer.writeAll("return self.reader.readStructField(");
                            try ctx.writeNodeNameById((try field.getSlot().?.getType()).getStruct().?.getTypeId());
                            try ctx.writer.print(", {d});\n", .{field.getSlot().?.getOffset()});
                        },
                        .anyPointer => {
                            switch (gt) {
                                .reader => try ctx.writer.print("return self.reader.readAnyPointer({});\n", .{field.getSlot().?.getOffset()}),
                                .builder => try ctx.writer.print("return self.builder.writeAnyPointer({});\n", .{field.getSlot().?.getOffset()}),
                            }
                        },
                        else => {},
                    }
                },
                .group => {
                    if (field.getGroup().?.getTypeId() == 0) {
                        std.debug.print("Problem with group {s} {}\n", .{ try field.getName(), field.getGroup().?.getTypeId() });
                        @panic("ERROR");
                    }

                    switch (gt) {
                        .reader => try ctx.writer.writeAll("return .{ .reader = self.reader };\n"),
                        .builder => try ctx.writer.writeAll("return .{ .builder = self.builder };\n"),
                    }

                    // try ctx.writeIndent();
                    // try ctx.writeNodeNameById(field.getGroup().?.getTypeId());
                },
                else => {},
            }
            try ctx.closeGetter();
        }

        pub fn writeSetter(ctx: *WriteContext, field: schema.Field.Reader) E!void {
            switch (field.which()) {
                .slot => {
                    const slot = field.getSlot().?;
                    const t = try slot.getType();

                    switch (t.which()) {
                        .void => {
                            try ctx.openVoidSetter(try field.getName());
                            try ctx.writeIndent();
                            try ctx.writer.writeAll("_ = self; return;\n");
                            try ctx.closeSetter();
                        },

                        .bool => {
                            try ctx.openSetter(try field.getName(), "bool", "void");
                            try ctx.writeIndent();
                            try ctx.writer.print("self.builder.setBoolField({d}, value);\n", .{slot.getOffset()});
                            try ctx.closeSetter();
                        },

                        inline .int8, .int16, .int32, .int64, .uint8, .uint16, .uint32, .uint64 => |typeTag| {
                            const typeTagName = @tagName(typeTag);
                            const zigTypeName = zigNameHelper(typeTagName, if (typeTagName[0] == 'u') 4 else 3);

                            try ctx.openSetter(try field.getName(), zigTypeName, "void");
                            try ctx.writeIndent();

                            try ctx.writer.print(
                                "self.builder.setIntField({s}, {d}, value);\n",
                                .{
                                    zigTypeName,
                                    slot.getOffset(),
                                },
                            );
                            try ctx.closeSetter();
                        },

                        inline .float32, .float64 => |typeTag| {
                            const typeTagName = @tagName(typeTag);
                            const zigTypeName = zigNameHelper(typeTagName, 5);

                            try ctx.openSetter(try field.getName(), zigTypeName, "void");
                            try ctx.writeIndent();

                            try ctx.writer.print(
                                "self.builder.setFloatField({s}, {d}, value);\n",
                                .{
                                    zigTypeName,
                                    slot.getOffset(),
                                },
                            );
                            try ctx.closeSetter();
                        },

                        .text => {
                            try ctx.openSetter(try field.getName(), "[:0]const u8", "capnp.Error!void");
                            try ctx.writeIndent();
                            try ctx.writer.print("try self.builder.setTextField({d}, value);\n", .{slot.getOffset()});
                            try ctx.closeSetter();
                        },

                        .data => {
                            try ctx.openSetter(try field.getName(), "[]const u8", "capnp.Error!void");
                            try ctx.writeIndent();
                            try ctx.writer.print("try self.builder.setDataField({d}, value);\n", .{slot.getOffset()});
                            try ctx.closeSetter();
                        },

                        .list => {
                            const elementType = try t.getList().?.getElementType();
                            try ctx.openSetter(try field.getName(), typed(.{ .ctx = ctx, .gt = .reader_getter, .typ = t, .with_error = false }), "capnp.Error!void");
                            try ctx.writeIndent();
                            try ctx.writer.print("return self.builder.setListField({}, {d}, value);\n", .{ typed(.{ .ctx = ctx, .gt = .base, .typ = elementType, .with_error = false }), slot.getOffset() });
                            try ctx.closeSetter();
                        },

                        .struct_ => {
                            try ctx.openSetter(try field.getName(), typed(.{ .ctx = ctx, .gt = .reader_getter, .typ = t, .with_error = false }), "capnp.Error!void");
                            try ctx.writeIndent();

                            try ctx.writer.print("return self.builder.setStructField({}, {d}, value);\n", .{ typed(.{ .ctx = ctx, .gt = .base, .typ = t, .with_error = false }), slot.getOffset() });
                            try ctx.closeSetter();
                        },

                        .anyPointer => {
                            try ctx.openSetter(try field.getName(), "capnp.AnyPointerReader", "capnp.Error!void");
                            try ctx.writeIndent();
                            try ctx.writer.print("return self.builder.setAnyPointerField({d}, value);", .{field.getSlot().?.getOffset()});
                            try ctx.closeSetter();
                        },

                        else => {},
                    }
                },
                .group => {
                    if (field.getGroup().?.getTypeId() == 0) {
                        std.debug.print("Problem with group {s} {}\n", .{ try field.getName(), field.getGroup().?.getTypeId() });
                        @panic("ERROR");
                    }

                    // Write nothing
                    // try ctx.writeIndent();
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

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
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

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
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

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
    };

    const reader = try message.getRootStruct(schema.Field);
    try M.writeType(&ctx, try reader.getSlot().?.getType(), .reader_getter, true);

    // try std.testing.expectEqualStrings("i32", fbs.getWritten());

    fbs.reset();
    try M.writeGetter(&ctx, reader, .reader);
    try std.testing.expectEqualStrings("pub fn get(self: @This()) i32 {\n    return self.reader.readIntField(i32, 3);\n}", fbs.getWritten());
}

test "compiler" {
    // var buf = std.mem.zeroes([65 * 1024]u8);
    // var fbs = std.io.fixedBufferStream(&buf);
    // const writer = fbs.writer();
    // const writer = std.io.getStdOut().writer();
    //
    const outf = try std.fs.cwd().createFile("/dev/shm/testoutput.zig", .{});
    const writer = outf.writer();

    const M = Refactor(@TypeOf(writer));

    var file = try std.fs.cwd().openFile("capnp-tests/06_schema.capnp.original.1.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const request = try message.getRootStruct(schema.CodeGeneratorRequest);

    const nodes = try request.getNodes();

    var ctx = M.WriteContext{
        .writer = writer,
        .indenter = M.Indenter{},
        .nodes = nodes,
    };

    const files = try request.getRequestedFiles();
    const requested_file = ctx.getNodeById(files.get(@intCast(0)).getId());

    std.debug.print("file_id = {x}\n", .{requested_file.getId()});

    // for (0..nodes.length) |i| {
    //     const node = nodes.get(@intCast(i));
    //     try ctx.writeNodeName(node);
    //     try ctx.writer.writeAll("\n");
    // }
    try M.writeNode(&ctx, "", requested_file);
}
