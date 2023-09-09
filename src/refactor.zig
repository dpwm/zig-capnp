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

        const Void = struct {
            pub fn readerType(t: Type) Type.Error!void {
                try t.writer.writeAll("void");
            }
        };

        const Float32 = struct {
            pub fn readerType(t: Type) Type.Error!void {
                try t.writer.writeAll("f32");
            }
        };

        const Type = struct {
            reader: schema.Type.Reader,
            writer: W,

            pub fn get(comptime typ: std.meta.Tag(schema.Type.Reader._Tag)) type {
                return switch (typ) {
                    .float32 => Float32,
                    else => Void,
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
