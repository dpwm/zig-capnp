const std = @import("std");
const testing = std.testing;

pub fn readPackedBits(data: u64, comptime lsb_offset: u6, comptime T: type) T {
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

pub const StructReader = struct {
    segments: [][]u8,
    segment: u32,
    offsetWords: u29,
    dataWords: u16,
    ptrWords: u16,

    pub fn readIntField(self: StructReader, comptime T: type, offset: u32) T {
        const byteSize = @bitSizeOf(T) >> 3;
        const byteOffset = offset * byteSize;
        const offsetBytes: u32 = 8 * self.offsetWords + byteOffset;
        return std.mem.readIntLittle(T, self.segments[self.segment][offsetBytes..][0..byteSize]);
    }

    pub fn print(self: StructReader) void {
        std.debug.print("{{ segment={}, offsetWords={}, dataWords={}, ptrWords={} }}\n", .{ self.segment, self.offsetWords, self.dataWords, self.ptrWords });
    }

    pub fn readListField(self: StructReader, comptime T: type, ptrNo: u16) ListReader(T) {
        std.debug.assert(ptrNo < self.ptrWords);
        const offsetWords = self.offsetWords + self.dataWords + ptrNo;

        // TODO This **must** be boundschecked. But for now…
        return ListReader(T).fromPointer(self.segments, self.segment, offsetWords);
    }

    pub fn readCompositeListField(self: StructReader, comptime T: type, ptrNo: u16) CompositeListReader(T) {
        std.debug.assert(ptrNo < self.ptrWords);
        const offsetWords = self.offsetWords + self.dataWords + ptrNo;

        // TODO This **must** be boundschecked. But for now…
        return CompositeListReader(T).fromPointer(self.segments, self.segment, offsetWords);
    }

    pub fn readStringField(self: StructReader, ptrNo: u16) []u8 {
        std.debug.assert(ptrNo < self.ptrWords);
        const offsetWords = self.offsetWords + self.dataWords + ptrNo;

        const listReader = ListReader(u8).fromPointer(self.segments, self.segment, offsetWords);
        return listReader.getString();
    }
};


pub fn ListReader(comptime T: type) type {
    return struct {
        const Self = @This();

        segments: [][]u8,
        segment: u32,
        offsetWords: u29,

        elementSize: u3,
        length: u29,

        pub fn fromPointer(segments: [][]u8, segment: u32, offsetWords: u29) Self {
            // for now, ignore the possibility that this may be a far pointer.
            const ptr = std.mem.readIntLittle(u64, segments[segment][offsetWords * 8 * BYTES ..][0 .. 8 * BYTES]);

            const a = readPackedBits(ptr, 0, u2);
            const b = readPackedBits(ptr, 2, i30);
            const c = readPackedBits(ptr, 32, u3);
            const d = readPackedBits(ptr, 35, u29);

            const startOffsetWords: u29 = @intCast(@as(i30, (@intCast(offsetWords))) + 1 + b);
            //std.debug.print("offsetWords={}, startOffsetWords={}, b={}\n", .{ offsetWords, startOffsetWords, b });

            std.debug.assert(a == 1);

            const typeName = @typeName(T);

            if (std.mem.eql(u8, typeName, "u8")) {
                std.debug.assert(c == 2);
            }

            return Self{
                .segments = segments,
                .segment = segment,
                .offsetWords = startOffsetWords,

                .elementSize = c,
                .length = d,
            };
        }
        pub fn get(self: Self, ix: u32) T {
            std.debug.assert(ix < self.length);
            const byteSize = @sizeOf(T);
            const byteOffset: u32 = 8 * self.offsetWords + ix * byteSize;

            const buf = self.segments[self.segment][byteOffset..][0..byteSize];
            return std.mem.readIntLittle(T, buf);
        }
        pub fn getString(self: Self) []u8 {
            comptime std.debug.assert(T == u8);
            return self.segments[self.segment][8 * self.offsetWords ..][0 .. self.length - 1];
        }
    };
}

pub fn ListIterator(comptime T: type, comptime U: type) type {
    return struct {
        const Self = @This();
        reader: T,
        ix: u29 = 0,

        pub fn next(self: *Self) ?U {
            if (self.ix < self.reader.length) {
                const out = self.reader.get(self.ix);
                self.ix += 1;
                return out;
            } else {
                return null;
            }
        }
    };
}

pub fn CompositeListReader(comptime T: type) type {
    return struct {
        const Self = @This();

        segments: [][]u8,
        segment: u32,
        offsetWords: u29,

        elementSize: u3,
        length: u29,

        dataWords: u16,
        ptrWords: u16,

        pub fn fromPointer(segments: [][]u8, segment: u32, offsetWords: u29) Self {
            // for now, ignore the possibility that this may be a far pointer.
            const ptr = std.mem.readIntLittle(u64, segments[segment][offsetWords * 8 * BYTES ..][0 .. 8 * BYTES]);

            const a = readPackedBits(ptr, 0, u2);
            const b = readPackedBits(ptr, 2, i30);
            const c = readPackedBits(ptr, 32, u3);
            const d = readPackedBits(ptr, 35, u29);
            _ = d;

            const headerOffsetWords: u29 = @intCast(@as(i30, (@intCast(offsetWords))) + 1 + b);

            const ptr2 = std.mem.readIntLittle(u64, segments[segment][headerOffsetWords * 8 * BYTES ..][0 .. 8 * BYTES]);

            const a2 = readPackedBits(ptr2, 0, u2);
            std.debug.assert(a2 == 0);
            const b2 = readPackedBits(ptr2, 2, i30);
            const c2 = readPackedBits(ptr2, 32, u16);
            const d2 = readPackedBits(ptr2, 48, u16);

            std.debug.assert(a == 1);

            return Self{
                .segments = segments,
                .segment = segment,
                .offsetWords = headerOffsetWords + 1,

                .elementSize = c,
                .length = @intCast(b2),

                .dataWords = c2,
                .ptrWords = d2,
            };
        }

        pub fn iter(self: Self) ListIterator(Self, T.Reader) {
            return ListIterator(Self, T.Reader){
                .reader = self,
                .ix = 0,
            };
        }

        pub fn get(self: Self, ix: u32) T.Reader {
            std.debug.assert(ix < self.length);
            const wordSize = self.ptrWords + self.dataWords;
            const offsetWords: u29 = @intCast(self.offsetWords + ix * wordSize);

            return T.Reader{
                .reader = StructReader{
                    .segments = self.segments,
                    .segment = self.segment,
                    .offsetWords = offsetWords,
                    .dataWords = self.dataWords,
                    .ptrWords = self.ptrWords,
                },
            };
        }
    };
}


pub const Message = struct {
    segments: [][]u8 = undefined,

    pub fn fromFile(file: std.fs.File, allocator: std.mem.Allocator) !Message {
        var buffer: [4]u8 = undefined;

        std.debug.assert(4 == try file.read(buffer[0..4]));

        const segmentCount = 1 + std.mem.readIntLittle(u32, buffer[0..4]);

        // std.debug.print("segmentCount = {}\n", .{segmentCount});

        var segmentLengthsBuffer = try allocator.alloc(u8, 4 * segmentCount * BYTES);
        defer allocator.free(segmentLengthsBuffer);
        std.debug.assert(segmentLengthsBuffer.len == try file.read(segmentLengthsBuffer));

        const segments = try allocator.alloc([]u8, segmentCount * ELEMENTS);

        for (0..segmentCount) |i| {
            const segmentWords = std.mem.readIntLittle(u32, segmentLengthsBuffer[i * 4 ..][0..4]);
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
        const ptr = std.mem.readIntLittle(u64, self.segments[0][0..8]);

        const a = readPackedBits(ptr, 0, u2);
        const b = readPackedBits(ptr, 2, i30);
        const c = readPackedBits(ptr, 32, u16);
        const d = readPackedBits(ptr, 48, u16);

        std.debug.assert(a == 0);

        return T.Reader{ .reader = StructReader{ .segments = self.segments, .segment = 0, .offsetWords = @intCast(b + 1), .dataWords = c, .ptrWords = d ,}, };
    }
};
