const std = @import("std");
const capnp = @import("capnp.zig");
const testing = std.testing;

pub const Date = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getYear(self: Reader) i16 {
            return self.reader.readIntField(i16, 0);
        }

        pub fn getMonth(self: Reader) u8 {
            return self.reader.readIntField(u8, 2);
        }

        pub fn getDay(self: Reader) u8 {
            return self.reader.readIntField(u8, 3);
        }
    };
};
pub const Lists = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getU8(self: Reader) capnp.Counter.Error!capnp.ListReader(u8) {
            return self.reader.readPtrField(capnp.ListReader(u8), 0);
        }
    };
};

pub const CompositeLists = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getDates(self: Reader) capnp.Counter.Error!capnp.CompositeListReader(Date) {
            return self.reader.readPtrField(capnp.CompositeListReader(Date), 0);
        }
    };
};

test "simple struct unpacking" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_date_20230714.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);
    const s = try message.getRootStruct(Date);
    //std.debug.print("{}\n", .{s});

    try std.testing.expectEqual(@as(i16, 2023), s.getYear());
    try std.testing.expectEqual(@as(u8, 7), s.getMonth());
    try std.testing.expectEqual(@as(u8, 14), s.getDay());
}

test "simple struct packing" {
    var message = try capnp.MessageBuilder.init(std.testing.allocator);
    defer message.deinit();
}

test "simple struct unpacking (negative year)" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_datem_20230714.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);
    const s = try message.getRootStruct(Date);

    try std.testing.expectEqual(@as(i16, -2023), s.getYear());
    try std.testing.expectEqual(@as(u8, 7), s.getMonth());
    try std.testing.expectEqual(@as(u8, 14), s.getDay());
}

test "struct of lists" {
    var file = try std.fs.cwd().openFile("capnp-tests/02_simple_lists.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(Lists);

    const xs = try s.getU8();
    for (0..xs.length) |i| {
        const j: u32 = @intCast(i);
        try std.testing.expectEqual(j, xs.get(j));
    }
}

test "struct of composite list" {
    var file = try std.fs.cwd().openFile("capnp-tests/03_composite_lists.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(CompositeLists);

    var it = (try s.getDates()).iter();

    while (it.next()) |x| {
        std.debug.print("year={}\n", .{x.getYear()});
    }
}

pub const UnionTest = struct {
    pub const _Tag = union(enum) {
        void,
        int32: i32,
        _other: u16,
    };

    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn which(self: Reader) _Tag {
            const t = self.reader.readIntField(u16, 0);
            return switch (t) {
                0 => .void,
                1 => .{ .int32 = self.reader.readIntField(i32, 1) },
                else => .{ ._other = t },
            };
        }

        pub fn getInt32(self: Reader) u32 {
            std.debug.assert(self.getTag() == .int32);
            return self.reader.readIntField(i32, 1);
        }
    };
};

pub const ULists = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getUnionTests(self: Reader) capnp.Counter.Error!capnp.CompositeListReader(UnionTest) {
            return self.reader.readPtrField(capnp.CompositeListReader(UnionTest), 0);
        }
    };
};

test "struct with union" {
    var file = try std.fs.cwd().openFile("capnp-tests/04_unions.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(ULists);
    var it = (try s.getUnionTests()).iter();
    while (it.next()) |x| {
        std.debug.print("{}\n", .{x.which()});
    }
}

pub const Defaults = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getInt32(self: Reader) i32 {
            return 17 ^ self.reader.readIntField(i32, 0);
        }
    };
};

test "default values" {
    var file = try std.fs.cwd().openFile("capnp-tests/05_default_values.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(Defaults);
    try std.testing.expectEqual(
        @as(i32, 17),
        s.getInt32(),
    );
    // TODO: default for pointers. This is easier than it seems!
}

pub const BitsAndFloats = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getFloat32(self: Reader) f32 {
            return self.reader.readFloatField(f32, 0);
        }

        pub fn getFloat64(self: Reader) f64 {
            return self.reader.readFloatField(f64, 1);
        }

        pub fn getBit(self: Reader) bool {
            return self.reader.readBooleanField(32);
        }
    };
};

test "bits and floats" {
    var file = try std.fs.cwd().openFile("capnp-tests/07_bits_and_floats.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = try message.getRootStruct(BitsAndFloats);
    try std.testing.expectEqual(
        @as(f32, 3.141),
        s.getFloat32(),
    );
    try std.testing.expectEqual(
        @as(f64, 3.14159),
        s.getFloat64(),
    );
    try std.testing.expectEqual(true, s.getBit());

    // TODO: default for pointers. This is easier than it seems!
}
