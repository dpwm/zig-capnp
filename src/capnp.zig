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

pub const Ptr = union(enum) {
    const Struct = packed struct(u64) {
        type: u2,
        offsetWords: i30,
        dataWords: u16,
        ptrWords: u16,
    };
    const List = packed struct(u64) {
        type: u2,
        offsetWords: i30,
        elementSize: u3,
        elementsOrWords: u29,
    };
    const InterSegment = packed struct(u64) {
        type: u2,
        double: bool,
        offset: u29,
        segment: u32,
    };
    const Capability = packed struct(u64) {
        type: u2,
        _: u30,
        index: u32,
    };
    const Type = packed struct(u64) {
        type: u2,
        _: u62,
    };

    struct_: Struct,
    list: List,
    inter_segment: InterSegment,
    capability: Capability,

    pub fn of_u64(ptr: u64) Ptr {
        return switch (@as(Ptr.Type, @bitCast(ptr)).type) {
            0 => Ptr{ .struct_ = @bitCast(ptr) },
            1 => Ptr{ .list = @bitCast(ptr) },
            2 => Ptr{ .inter_segment = @bitCast(ptr) },
            3 => Ptr{ .capability = @bitCast(ptr) },
        };
    }
};

pub const Counter = struct {
    count: usize = 0,
    limit: usize,

    pub const Error = error{
        LimitExceeded,
    };

    pub fn increment(self: *Counter, x: usize) Error!void {
        self.count += x;

        if (self.count >= self.limit) {
            return Error.LimitExceeded;
        }
    }
};

pub const ReadContext = struct {
    const Error = error{
        OutOfBounds,
    };

    segments: [][]u8,
    segment: u32,
    offsetWords: u29,

    depth_counter: Counter = Counter{ .limit = 64 },
    traversal_counter: *Counter,

    pub fn offsetBytes(self: ReadContext) u32 {
        // Zig’s slices do bounds checking for us.
        return self.offsetWords * 8;
    }

    pub fn relativeWords(self: *ReadContext, dx: i30) void {
        self.offsetWords = @intCast(dx + self.offsetWords);
    }

    pub fn readIntWithBound(self: ReadContext, comptime T: type, offset: u32, boundWords: u29) T {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return if (@sizeOf(T) * offset < boundWords << 3) std.mem.readIntLittle(T, self.segments[self.segment][pos..][0..@sizeOf(T)]) else 0;
    }

    pub fn readInt(self: ReadContext, comptime T: type, offset: u32) T {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return std.mem.readIntLittle(T, self.segments[self.segment][pos..][0..@sizeOf(T)]);
    }

    pub fn readPtrN(self: ReadContext) Ptr {
        return Ptr.of_u64(self.readInt(u64, 0));
    }

    pub fn readPtr(self: *ReadContext) Counter.Error!Ptr {
        const ptr = self.readPtrN();
        switch (ptr) {
            .struct_ => |x| {
                try self.depth_counter.increment(1);
                try self.traversal_counter.increment(x.dataWords + x.ptrWords);
                self.relativeWords(1 + x.offsetWords);
            },
            .list => |x| {
                try self.depth_counter.increment(1);
                // TODO: work out size of a list for traversal
                // try self.counters.traversal.increment();
                self.relativeWords(1 + x.offsetWords);
            },
            .inter_segment => |x| {
                try self.depth_counter.increment(1);
                if (x.double) {
                    unreachable;
                } else {
                    // TODO: explicitly check segment bounds
                    self.segment = x.segment;
                    self.offsetWords = x.offset;
                }
            },
            else => {},
        }
        return ptr;
    }

    pub fn readString(self: ReadContext, length: u32) []u8 {
        return self.segments[self.segment][self.offsetBytes()..][0 .. length - 1];
    }

    pub fn fromSegments(segments: [][]u8, traversal_counter: *Counter) ReadContext {
        return ReadContext{
            .segments = segments,
            .segment = 0,
            .offsetWords = 0,
            .traversal_counter = traversal_counter,
        };
    }
};

const ELEMENTS: usize = 1;
const BITS: usize = 1;
const WORDS: usize = 1;
const BYTES: usize = 1;

pub const StructReader = struct {
    context: ReadContext,
    dataWords: u16,
    ptrWords: u16,

    pub fn readIntField(self: StructReader, comptime T: type, offset: u32) T {
        return self.context.readIntWithBound(T, offset, self.dataWords);
    }

    pub fn readPtrField(self: StructReader, comptime T: type, ptrNo: u16) Counter.Error!T {
        if (ptrNo < self.ptrWords) {
            std.debug.assert(ptrNo < self.ptrWords);
            var context = self.context;
            context.relativeWords(self.dataWords + ptrNo);
            return try T.fromReadContext(context);
        } else {
            unreachable;
        }
    }

    pub fn readStringField(self: StructReader, ptrNo: u16) Counter.Error![]u8 {
        return (try self.readPtrField(ListReader(u8), ptrNo)).getString();
    }

    pub fn fromReadContext(context: ReadContext) Counter.Error!StructReader {
        var _context = context;
        const struct_ = (try _context.readPtr()).struct_;

        return StructReader{
            .context = _context,
            .dataWords = struct_.dataWords,
            .ptrWords = struct_.ptrWords,
        };
    }
};

pub fn ListReader(comptime T: type) type {
    return struct {
        const Self = @This();

        context: ReadContext,

        elementSize: u3,
        length: u29,

        pub fn fromReadContext(context: ReadContext) Counter.Error!Self {
            // for now, ignore the possibility that this may be a far pointer.
            var _context = context;
            const list = (try _context.readPtr()).list;

            //std.debug.print("offsetWords={}, startOffsetWords={}, b={}\n", .{ offsetWords, startOffsetWords, b });

            if (T == u8) {
                std.debug.assert(list.elementSize == 2);
            }

            return Self{
                .context = _context,
                .elementSize = list.elementSize,
                .length = list.elementsOrWords,
            };
        }
        pub fn get(self: Self, ix: u32) T {
            return self.context.readInt(T, ix);
        }
        pub fn getString(self: Self) []u8 {
            comptime std.debug.assert(T == u8);
            return self.context.readString(self.length);
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

        context: ReadContext,

        elementSize: u3,
        length: u29,

        dataWords: u16,
        ptrWords: u16,

        pub fn fromReadContext(context: ReadContext) Counter.Error!Self {
            // for now, ignore the possibility that this may be a far pointer.
            var _context = context;
            const list_ptr = (try _context.readPtr()).list;

            if (list_ptr.elementSize == 7) {
                const struct_ptr = _context.readPtrN().struct_;
                _context.relativeWords(1);

                return Self{
                    .context = _context,

                    .elementSize = list_ptr.elementSize,
                    .length = @intCast(struct_ptr.offsetWords),

                    .dataWords = struct_ptr.dataWords,
                    .ptrWords = struct_ptr.ptrWords,
                };
            } else {
                unreachable;
            }
        }

        pub fn iter(self: Self) ListIterator(Self, T.Reader) {
            return ListIterator(Self, T.Reader){
                .reader = self,
                .ix = 0,
            };
        }

        pub fn get(self: Self, ix: u32) T.Reader {
            std.debug.assert(ix < self.length);

            var _context = self.context;
            _context.relativeWords(self.ptrWords + self.dataWords);

            return T.Reader{
                .reader = StructReader{
                    .context = _context,
                    .dataWords = self.dataWords,
                    .ptrWords = self.ptrWords,
                },
            };
        }
    };
}

pub const Message = struct {
    segments: [][]u8 = undefined,
    traversal_counter: Counter = Counter{ .limit = 8 * 1024 * 1024 },

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

    pub fn getRootStruct(self: *Message, comptime T: type) Counter.Error!T.Reader {
        self.traversal_counter = Counter{ .limit = 8 * 1024 * 1024 };
        return T.Reader{ .reader = try StructReader.fromReadContext(ReadContext.fromSegments(self.segments, &self.traversal_counter)) };
    }
};
