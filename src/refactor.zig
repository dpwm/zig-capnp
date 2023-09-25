// We will define a Refactor functor here. This will take the WriterType as the parameter, and will be used throughout.

const schema = @import("schema.zig");
const std = @import("std");
const capnp = @import("capnp.zig");

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
                // TODO: stub
                _ = t;
            }
        };

        const Enum = struct {
            pub fn readerType(t: Type) E!void {
                // TODO: stub
                _ = t;
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
            const _enum = Enum;
            const _struct_ = Struct;
            const _interface = _void;
            const _enum_ = _void;
            const _anyPointer = _void;
        };

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()
        // THis would entail which just returning an enum(u16).

        //pub fn (comptime T: type, comptime T2: type) type {}

        pub const Type = struct {
            reader: schema.Type.Reader,
            writer: W,

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
                };
            }
        };

        pub const Field = struct {
            reader: schema.Field.Reader,
            writer: W,

            pub fn readerGetterBody(self: Type) E!void {
                _ = self;
            }

            pub fn withTypeReader(self: Field, reader: schema.Type.Reader) Type {
                return .{
                    .reader = reader,
                    .writer = self.writer,
                };
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

    const typ = (M.Type{ .reader = s, .writer = writer });

    try typ.readerType();

    try std.testing.expectEqualStrings("void", fbs.getWritten());
}
