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

        pub fn getU8(self: Reader) capnp.ListReader(u8) {
            return self.reader.readListField(u8, 0);
        }
    };
};

pub const CompositeLists = struct {
    pub const Reader = struct {
        reader: capnp.StructReader,

        pub fn getDates(self: Reader) capnp.CompositeListReader(Date) {
            return self.reader.readCompositeListField(Date, 0);
        }
    };
};

test "basic data manipulation" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_date_20230714.bin", .{});
    defer file.close();

    var buf = std.mem.zeroes([24]u8);
    const n = try file.read(buf[0..]);

    try testing.expectEqual(@as(usize, 24), n);

    const nsegs = std.mem.readIntLittle(u32, buf[0..4]);
    _ = nsegs;
    const seg0 = std.mem.readIntLittle(u32, buf[4..8]);
    _ = seg0;
    // std.debug.print("\nnsegs: {}, seg0: {}\n", .{ nsegs, seg0 });

    const ptr = std.mem.readIntLittle(u64, buf[8..16]);

    const a = capnp.readPackedBits(ptr, 0, u2);
    try testing.expectEqual(@as(u2, 0), a);

    const b = capnp.readPackedBits(ptr, 0, i30);
    try testing.expectEqual(@as(i30, 0), b);

    const c = capnp.readPackedBits(ptr, 32, u16);
    try testing.expectEqual(@as(u16, 1), c);

    const d = capnp.readPackedBits(ptr, 48, u16);
    try testing.expectEqual(@as(u16, 0), d);

    const data = std.mem.readIntLittle(u64, buf[16..24]);
    const year = capnp.readPackedBits(data, 0, i16);
    const month = capnp.readPackedBits(data, 16, u8);
    const day = capnp.readPackedBits(data, 24, u8);

    try testing.expectEqual(@as(i16, 2023), year);
    try testing.expectEqual(@as(u8, 7), month);
    try testing.expectEqual(@as(u8, 14), day);
}

test "simple struct unpacking" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_date_20230714.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);
    const s = message.getRootStruct(Date);

    try std.testing.expectEqual(@as(i16, 2023), s.getYear());
    try std.testing.expectEqual(@as(u8, 7), s.getMonth());
    try std.testing.expectEqual(@as(u8, 14), s.getDay());
}

test "simple struct unpacking (negative year)" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_datem_20230714.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);
    const s = message.getRootStruct(Date);

    try std.testing.expectEqual(@as(i16, -2023), s.getYear());
    try std.testing.expectEqual(@as(u8, 7), s.getMonth());
    try std.testing.expectEqual(@as(u8, 14), s.getDay());
}

test "struct of lists" {
    var file = try std.fs.cwd().openFile("capnp-tests/02_simple_lists.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = message.getRootStruct(Lists);

    const xs = s.getU8();
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

    const s = message.getRootStruct(CompositeLists);

    var it = s.getDates().iter();

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

        pub fn getUnionTests(self: Reader) capnp.CompositeListReader(UnionTest) {
            return self.reader.readCompositeListField(UnionTest, 0);
        }
    };
};

test "struct with union" {
    var file = try std.fs.cwd().openFile("capnp-tests/04_unions.bin", .{});
    defer file.close();

    var message = try capnp.Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);

    const s = message.getRootStruct(ULists);
    var it = s.getUnionTests().iter();
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

    const s = message.getRootStruct(Defaults);
    try std.testing.expectEqual(
        @as(i32, 17),
        s.getInt32(),
    );
    // TODO: default for pointers. This is easier than it seems!
}
