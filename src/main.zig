const std = @import("std");
const testing = std.testing;

export fn add(a: i32, b: i32) i32 {
    return a + b;
}

fn readPackedBits(data: u64, comptime lsb_offset: u6, comptime T: type) T {
    const len = @bitSizeOf(T);
    const UT: type = @Type(.{
        .Int = .{ .signedness = .unsigned, .bits = len },
    });

    const x = data >> lsb_offset;
    return @bitCast(@as(UT, @truncate(x)));
}

const ELEMENTS: usize = 1;
const BITS: usize = 1;
const WORDS: usize = 1;
const BYTES: usize = 1;

const StructReader = struct {
    segments: [][]u8,
    segment: u32,
    offsetWords: u29,
    dataWords: u16,
    ptrWords: u16,

    pub fn readIntField(self: StructReader, comptime T: type, offset: u32) T {
        const byteSize = @bitSizeOf(T) >> 3;
        const byteOffset = offset * byteSize;
        const offsetBytes: u32 = 8 * self.offsetWords + byteOffset;
        return std.mem.readIntNative(T, self.segments[self.segment][offsetBytes..][0..byteSize]);
    }
};

const Date = struct {
    const Reader = struct {
        reader: StructReader,

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

test "basic data manipulation" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_date_20230714.bin", .{});
    defer file.close();

    var buf = std.mem.zeroes([24]u8);
    const n = try file.read(buf[0..]);

    try testing.expectEqual(@as(usize, 24), n);

    const nsegs = std.mem.readIntNative(u32, buf[0..4]);
    _ = nsegs;
    const seg0 = std.mem.readIntNative(u32, buf[4..8]);
    _ = seg0;
    // std.debug.print("\nnsegs: {}, seg0: {}\n", .{ nsegs, seg0 });

    const ptr = std.mem.readIntNative(u64, buf[8..16]);

    const a = readPackedBits(ptr, 0, u2);
    try testing.expectEqual(@as(u2, 0), a);

    const b = readPackedBits(ptr, 0, i30);
    try testing.expectEqual(@as(i30, 0), b);

    const c = readPackedBits(ptr, 32, u16);
    try testing.expectEqual(@as(u16, 1), c);

    const d = readPackedBits(ptr, 48, u16);
    try testing.expectEqual(@as(u16, 0), d);

    const data = std.mem.readIntNative(u64, buf[16..24]);
    const year = readPackedBits(data, 0, i16);
    const month = readPackedBits(data, 16, u8);
    const day = readPackedBits(data, 24, u8);

    try testing.expectEqual(@as(i16, 2023), year);
    try testing.expectEqual(@as(u8, 7), month);
    try testing.expectEqual(@as(u8, 14), day);

    try testing.expect(add(3, 7) == 10);
}

const Message = struct {
    segments: [][]u8 = undefined,

    pub fn fromFile(file: std.fs.File, allocator: std.mem.Allocator) !Message {
        var buffer: [4]u8 = undefined;

        std.debug.assert(4 == try file.read(buffer[0..4]));

        const segmentCount = 1 + std.mem.readIntNative(u32, buffer[0..4]);

        // std.debug.print("segmentCount = {}\n", .{segmentCount});

        var segmentLengthsBuffer = try allocator.alloc(u8, 4 * segmentCount * BYTES);
        defer allocator.free(segmentLengthsBuffer);
        std.debug.assert(segmentLengthsBuffer.len == try file.read(segmentLengthsBuffer));

        const segments = try allocator.alloc([]u8, segmentCount * ELEMENTS);

        for (0..segmentCount) |i| {
            const segmentWords = std.mem.readIntNative(u32, segmentLengthsBuffer[i * 4 ..][0..4]);
            segments[i] = try allocator.alloc(u8, segmentWords * 8 * BYTES);
            std.debug.assert(segments[i].len == try file.read(segments[i]));
        }
        if (segmentCount & 1 == 0) {
            try file.seekBy(4);
        }
        return Message{ .segments = segments };
    }

    pub fn deinit(self: *Message, allocator: std.mem.Allocator) void {
        for (self.segments) |segment| {
            allocator.free(segment);
        }
        allocator.free(self.segments);
    }

    pub fn getRootStruct(self: *Message, comptime T: type) T.Reader {
        const ptr = std.mem.readIntNative(u64, self.segments[0][0..8]);

        const a = readPackedBits(ptr, 0, u2);
        const b = readPackedBits(ptr, 0, i30);
        const c = readPackedBits(ptr, 32, u16);
        const d = readPackedBits(ptr, 48, u16);

        std.debug.assert(a == 0);

        return T.Reader{ .reader = StructReader{ .segments = self.segments, .segment = 0, .offsetWords = @intCast(b + 1), .dataWords = c, .ptrWords = d } };
    }
};

test "simple struct unpacking" {
    var file = try std.fs.cwd().openFile("capnp-tests/01_simple_struct_date_20230714.bin", .{});
    defer file.close();

    var message = try Message.fromFile(file, std.testing.allocator);
    defer message.deinit(std.testing.allocator);
    const s = message.getRootStruct(Date);

    try std.testing.expectEqual(@as(i16, 2023), s.getYear());
    try std.testing.expectEqual(@as(u8, 7), s.getMonth());
    try std.testing.expectEqual(@as(u8, 14), s.getDay());
}
