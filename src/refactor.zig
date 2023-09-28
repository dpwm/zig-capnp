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

pub fn Refactor(comptime W: type) type {
    return struct {
        const E = W.Error || capnp.Error;
        const Self = @This();

        const Indenter = struct {
            level: usize = 0,

            pub fn write(self: Indenter, writer: W) E!void {
                for (0..self.level) |_| {
                    try writer.writeAll("  ");
                }
            }

            pub fn inc(self: *Indenter) void {
                self.level += 1;
            }

            pub fn dec(self: *Indenter) void {
                self.level -= 1;
            }
        };

        fn Z(comptime T: type) type {
            return struct {
                pub fn readerType(t: Type) E!void {
                    try t.writer.writeAll(@typeName(T));
                }
            };
        }

        fn Float(comptime T: type) type {
            return struct {
                usingnamespace Z(T);

                pub fn readerGetterBody(field: Field) E!void {
                    try field.writer.print(
                        "self.reader.readFloatField({s}, {})",
                        .{
                            @typeName(T),
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
            };
        }

        fn Int(comptime T: type) type {
            return struct {
                usingnamespace Z(T);

                pub fn readerGetterBody(field: Field) E!void {
                    try field.writer.print(
                        "self.reader.readIntField({s}, {})",
                        .{
                            @typeName(T),
                            field.getSlot().?.getOffset(),
                        },
                    );
                }
            };
        }

        const List = struct {
            pub fn readerType(t: Type) E!void {
                try t.writer.writeAll("capnp.ListReader(");
                try t.withTypeReader(try t.reader.getList().?.getElementType()).readerType();
                try t.writer.writeAll(")");
            }
        };

        const Struct = struct {
            pub fn readerType(t: Type) E!void {
                try t.writer.writeAll(t.pathTable.get(t.reader.getStruct().?.getTypeId()).?);
            }
        };

        const Enum = struct {
            pub fn readerType(t: Type) E!void {
                try t.writer.writeAll(t.pathTable.get(t.reader.getEnum().?.getTypeId()).?);
            }
        };

        const TypeRegistry = struct {
            const _void = Z(void);

            const _bool = Z(bool);

            const _text = Z([:0]const u8);
            const _data = Z([]const u8);

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
        };

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()
        // THis would entail which just returning an enum(u16).

        //pub fn (comptime T: type, comptime T2: type) type {}

        pub const Type = struct {
            reader: schema.Type.Reader,
            writer: W,
            pathTable: *PathTable,

            pub fn get(comptime typ: schema.Type.Tag) type {
                return @field(TypeRegistry, "_" ++ @tagName(typ));
            }

            pub fn readerType(self: Type) E!void {
                switch (self.reader.which()) {
                    inline else => |t| {
                        try get(t).readerType(self);
                    },
                }
            }

            pub fn withTypeReader(self: Type, reader: schema.Type.Reader) Type {
                return .{
                    .reader = reader,
                    .writer = self.writer,
                    .pathTable = self.pathTable,
                };
            }
        };

        pub const Field = struct {
            reader: schema.Field.Reader,
            writer: W,
            pathTable: *PathTable,

            pub fn withTypeReader(self: Field, reader: schema.Type.Reader) Type {
                return .{
                    .reader = reader,
                    .writer = self.writer,
                    .pathTable = self.pathTable,
                };
            }

            pub fn readerGetterBody(self: Type) E!void {
                switch (self.reader.which()) {
                    .slot => {
                        const t = try self.reader.getSlot().?.getType();
                        switch (t.which()) {
                            inline else => |typeTag| {
                                Type.get(typeTag).readerGetterBody(self);
                            },
                        }
                    },
                }
            }
        };
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
    const s = try message.getRootStruct(schema.Type);

    var nodeTable = NodeIdMap.init(std.testing.allocator);
    defer nodeTable.deinit();

    var pathTable = PathTable.init(nodeTable);
    defer pathTable.deinit();

    const typ = (M.Type{
        .reader = s,
        .writer = writer,
        .pathTable = &pathTable,
    });

    try typ.readerType();

    try std.testing.expectEqualStrings("void", fbs.getWritten());
}
