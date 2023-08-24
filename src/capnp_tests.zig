const std = @import("std");
const capnp = @import("capnp.zig");
const testing = std.testing;

pub const Date = struct {
    pub const _Metadata = capnp.StructMetadata{
        .dataWords = 1,
        .ptrWords = 0,
    };

    pub const Reader = struct {
        reader: capnp.Struct.Reader,

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

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn getYear(self: Builder) i16 {
            return self.builder.readIntField(i16, 0);
        }

        pub fn getMonth(self: Builder) u8 {
            return self.builder.readIntField(u8, 2);
        }

        pub fn getDay(self: Builder) u8 {
            return self.builder.readIntField(u8, 3);
        }

        pub fn setYear(self: Builder, value: i16) void {
            return self.builder.writeIntField(i16, 0, value);
        }

        pub fn setMonth(self: Builder, value: u8) void {
            return self.builder.writeIntField(u8, 2, value);
        }

        pub fn setDay(self: Builder, value: u8) void {
            return self.builder.writeIntField(u8, 3, value);
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
    var builder = capnp.MessageBuilder{ .allocator = std.testing.allocator };
    try builder.init();
    defer builder.deinit();

    var date = try builder.initRootStruct(Date);

    try std.testing.expectEqual(@as(u32, 1), date.builder.context.offsetWords);

    date.setDay(14);
    date.setMonth(7);
    date.setYear(2023);

    try std.testing.expectEqual(@as(i16, 2023), date.getYear());
    try std.testing.expectEqual(@as(u8, 7), date.getMonth());
    try std.testing.expectEqual(@as(u8, 14), date.getDay());
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

pub const Lists = struct {
    pub const _Metadata = capnp.StructMetadata{
        .ptrWords = 1,
        .dataWords = 0,
    };

    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub fn getU8(self: Reader) capnp.Counter.Error!capnp.List(u8).Reader {
            return self.reader.readPtrField(capnp.List(u8).Reader, 0);
        }
    };

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn getU8(self: Builder) capnp.List(u8).Builder {
            return self.builder.buildPtrField(capnp.List(u8).Builder, 0);
        }
    };
};

pub const CompositeLists = struct {
    pub const _Metadata = capnp.StructMetadata{
        .ptrWords = 1,
        .dataWords = 0,
    };
    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub fn getDates(self: Reader) capnp.Counter.Error!capnp.List(Date).Reader {
            return self.reader.readPtrField(capnp.List(Date).Reader, 0);
        }
    };

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn getDates(self: Builder) capnp.List(Date).Builder {
            return self.builder.buildPtrField(capnp.List(Date).Builder, 0);
        }
    };
};

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

test "struct of lists (writing)" {
    var builder = capnp.MessageBuilder{ .allocator = std.testing.allocator };
    try builder.init();
    defer builder.deinit();

    {
        var lists = try builder.initRootStruct(Lists);

        var list = lists.getU8();
        try list.init(10);

        for (0..10) |i| {
            list.set(@intCast(i), @intCast(i));
            try std.testing.expectEqual(@as(u8, @intCast(i)), list.get(@intCast(i)));
        }
    }
    {
        var reader = builder.toReader();
        var lists = try reader.getRootStruct(Lists);

        var list = try lists.getU8();
        for (0..10) |i| {
            try std.testing.expectEqual(@as(u8, @intCast(i)), list.get(@as(u32, @intCast(i))));
        }
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

test "struct of composite list (writing)" {
    var builder = capnp.MessageBuilder{ .allocator = std.testing.allocator };
    try builder.init();
    defer builder.deinit();
    {
        var lists = try builder.initRootStruct(CompositeLists);

        var list = lists.getDates();
        try list.init(10);

        for (0..10) |i| {
            list.get(@intCast(i)).setYear(@intCast(i));
        }
    }

    {
        var reader = builder.toReader();
        var lists = try reader.getRootStruct(CompositeLists);
        var list = try lists.getDates();

        for (0..10) |i| {
            try std.testing.expectEqual(@as(i16, @intCast(i)), list.get(@intCast(i)).getYear());
        }
    }
}

pub const UnionTest = struct {
    pub const _Metadata = capnp.StructMetadata{
        .dataWords = 1,
        .ptrWords = 0,
    };
    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub const _Tag = union(enum) {
            void,
            int32: i32,
            _other: u16,
        };

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

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub const _Tag = union(enum) {
            void,
            int32: i32,
            _: u16,
        };

        pub fn setVoid(self: *Builder) void {
            self.builder.writeIntField(u16, 0, 0);
        }

        pub fn setInt32(self: *Builder, value: i32) void {
            self.builder.writeIntField(u16, 0, 1);
            self.builder.writeIntField(i32, 1, value);
        }

        pub fn which(self: *Builder) _Tag {
            const t = self.builder.readIntField(u16, 0);
            return switch (t) {
                0 => .void,
                1 => .{ .int32 = self.builder.readIntField(i32, 1) },
                else => .{ ._ = t },
            };
        }
    };
};

pub const ULists = struct {
    pub const _Metadata = capnp.StructMetadata{
        .dataWords = 0,
        .ptrWords = 1,
    };

    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub fn getUnionTests(self: Reader) capnp.Counter.Error!capnp.CompositeListReader(UnionTest) {
            return self.reader.readPtrField(capnp.CompositeListReader(UnionTest), 0);
        }
    };

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn getUnionTests(self: *Builder) capnp.CompositeListBuilder(UnionTest) {
            return self.builder.buildPtrField(capnp.CompositeListBuilder(UnionTest), 0);
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

test "struct with union (building)" {
    var message = capnp.MessageBuilder{ .allocator = std.testing.allocator };

    try message.init();
    defer message.deinit();

    var lists = try message.initRootStruct(ULists);

    var list = lists.getUnionTests();
    try list.init(3);

    {
        var x = list.get(0);
        x.setInt32(77);
        try std.testing.expectEqual(UnionTest.Builder._Tag{ .int32 = 77 }, x.which());
    }
    {
        var x = list.get(1);
        x.setInt32(88);
        try std.testing.expectEqual(UnionTest.Builder._Tag{ .int32 = 88 }, x.which());

        x.setVoid();
        try std.testing.expectEqual(UnionTest.Builder._Tag.void, x.which());
    }
    {
        var x = list.get(2);
        x.setInt32(99);
        try std.testing.expectEqual(UnionTest.Builder._Tag{ .int32 = 99 }, x.which());
    }
}

pub const Defaults = struct {
    pub const _Metadata = capnp.StructMetadata{
        .dataWords = 1,
        .ptrWords = 0,
    };
    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub fn getInt32(self: Reader) i32 {
            return 17 ^ self.reader.readIntField(i32, 0);
        }
    };

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn setInt32(self: Builder, value: i32) void {
            return self.builder.writeIntField(i32, 0, value ^ 17);
        }

        pub fn getInt32(self: Builder) i32 {
            return 17 ^ self.builder.readIntField(i32, 0);
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

test "default values (build)" {
    var message = capnp.MessageBuilder{ .allocator = std.testing.allocator };

    try message.init();
    defer message.deinit();

    var s = try message.initRootStruct(Defaults);

    s.setInt32(100);
    try std.testing.expectEqual(@as(i32, 100), s.getInt32());
}

pub const BitsAndFloats = struct {
    pub const _Metadata = capnp.StructMetadata{ .ptrWords = 0, .dataWords = 2 };

    pub const Reader = struct {
        reader: capnp.Struct.Reader,

        pub fn getFloat32(self: Reader) f32 {
            return self.reader.readFloatField(f32, 0);
        }

        pub fn getFloat64(self: Reader) f64 {
            return self.reader.readFloatField(f64, 1);
        }

        pub fn getBit(self: Reader) bool {
            return self.reader.readBoolField(32);
        }
    };

    pub const Builder = struct {
        builder: capnp.Struct.Builder,

        pub fn getFloat32(self: Builder) f32 {
            return self.builder.readFloatField(f32, 0);
        }

        pub fn getFloat64(self: Builder) f64 {
            return self.builder.readFloatField(f64, 1);
        }

        pub fn setFloat32(self: Builder, value: f32) void {
            return self.builder.writeFloatField(f32, 0, value);
        }

        pub fn setFloat64(self: Builder, value: f64) void {
            return self.builder.writeFloatField(f64, 1, value);
        }

        pub fn getBit(self: Builder) bool {
            return self.builder.readBoolField(32);
        }

        pub fn setBit(self: Builder, value: bool) void {
            return self.builder.writeBoolField(32, value);
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

test "bits and floats (build)" {
    var message = capnp.MessageBuilder{ .allocator = std.testing.allocator };

    try message.init();
    defer message.deinit();

    var s = try message.initRootStruct(BitsAndFloats);

    s.setFloat32(23.0);
    try std.testing.expectEqual(@as(f32, 23.0), s.getFloat32());

    try std.testing.expectEqual(false, s.getBit());
    s.setBit(true);
    try std.testing.expectEqual(true, s.getBit());

    // TODO: default for pointers. This is easier than it seems!
}
