// We will define a Refactor functor here. This will take the WriterType as the parameter, and will be used throughout.

const schema = @import("schema.zig");
const std = @import("std");

pub fn Refactor(comptime W: type) type {
    return struct {
        const E = W.Error;

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
                pub fn readerType(t: Type) Type.Error!void {
                    try t.writer.writeAll(@typeName(T));
                }
            };
        }

        fn Float(comptime T: type) type {
            return struct {
                usingnamespace Z(T);

                pub fn readerGetterBody(t: Type) Type.Error!void {
                    try t.writer.print("self.builder.readFloatField({s}, )", .{@typeName(T)});
                }
            };
        }

        fn Int(comptime T: type) type {
            return struct {
                usingnamespace Z(T);

                pub fn readerGetterBody(t: Type) Type.Error!void {
                    try t.writer.print("self.builder.readIntField({s}, )", .{@typeName(T)});
                }
            };
        }

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

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()
        // THis would entail which just returning an enum(u16).

        //pub fn (comptime T: type, comptime T2: type) type {}

        const Type = struct {
            reader: schema.Type.Reader,
            writer: W,

            pub fn get(comptime typ: std.meta.Tag(schema.Type.Reader._Tag)) type {
                return switch (typ) {
                    inline else => |_, v| {
                        _ = v;
                    },
                };
            }

            pub fn readerType(self: @This()) Type.Error!void {
                switch (try self.reader.which()) {
                    inline else => |_, t| get(t).readerType(t),
                }
            }
        };
    };
}
