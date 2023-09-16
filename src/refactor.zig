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

        // Idea: Create type combinators

        // Idea 2: simplify output. That way we don’t need to worry about errors when calling which()

        pub fn (comptime T: type, comptime T2: type) type {}

        const Type = struct {
            reader: schema.Type.Reader,
            writer: W,

            pub fn get(comptime typ: std.meta.Tag(schema.Type.Reader._Tag)) type {
                return switch (typ) {
                    .float32 => Z(f32),
                    .float64 => Z(f64),
                    else => Z(void),
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
