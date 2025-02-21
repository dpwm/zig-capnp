const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;

pub const Ptr = union(enum) {
    pub const Struct = packed struct(u64) {
        type: u2 = 0,
        offsetWords: i30,
        dataWords: u16,
        ptrWords: u16,
    };
    pub const List = packed struct(u64) {
        type: u2 = 1,
        offsetWords: i30,
        elementSize: u3,
        elementsOrWords: u29,
    };
    pub const InterSegment = packed struct(u64) {
        type: u2 = 2,
        double: bool,
        offset: u29,
        segment: u32,
    };
    pub const Capability = packed struct(u64) {
        type: u2 = 3,
        _: u30,
        index: u32,
    };
    const Type = packed struct(u64) {
        type: u2,
        _: u62,
    };
    null: void,
    struct_: Ptr.Struct,
    list: Ptr.List,
    inter_segment: Ptr.InterSegment,
    capability: Ptr.Capability,

    pub fn of_u64(ptr: u64) Ptr {
        if (ptr == 0) {
            return Ptr.null;
        }
        return switch (@as(Ptr.Type, @bitCast(ptr)).type) {
            0 => Ptr{ .struct_ = @bitCast(ptr) },
            1 => Ptr{ .list = @bitCast(ptr) },
            2 => Ptr{ .inter_segment = @bitCast(ptr) },
            3 => Ptr{ .capability = @bitCast(ptr) },
        };
    }

    pub fn to_u64(ptr: Ptr) u64 {
        var ptr_ = ptr;

        switch (ptr_) {
            .struct_ => |*struct_| {
                struct_.type = 0;
                return @bitCast(struct_.*);
            },
            .list => |*list| {
                list.type = 1;
                return @bitCast(list.*);
            },
            .inter_segment => |*inter_segment| {
                inter_segment.type = 2;
                return @bitCast(inter_segment.*);
            },
            .capability => |*capability| {
                capability.type = 3;
                return @bitCast(capability.*);
            },
            .null => {
                return 0;
            },
        }
    }
};

pub const Error = Counter.Error;

pub const Counter = struct {
    count: usize = 0,
    limit: usize,

    pub const Error = error{
        LimitExceeded,
    };

    pub fn increment(self: *Counter, x: usize) Counter.Error!void {
        self.count += x;

        if (self.count >= self.limit) {
            return Counter.Error.LimitExceeded;
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
        return if (@sizeOf(T) * offset < boundWords << 3) std.mem.readInt(T, self.segments[self.segment][pos..][0..@sizeOf(T)], .little) else 0;
    }

    pub fn readInt(self: ReadContext, comptime T: type, offset: u32) T {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return std.mem.readInt(T, self.segments[self.segment][pos..][0..@sizeOf(T)], .little);
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
        if (length == 0) return "";
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

    pub fn format(value: ReadContext, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("{{segments = {}, segment = {}, offsetWords = {}}}", .{ value.segments.len, value.segment, value.offsetWords });
    }
};

const ELEMENTS: usize = 1;
const BITS: usize = 1;
const WORDS: usize = 1;
const BYTES: usize = 1;

pub const AnyPointerReader = struct {
    context: ReadContext,
    ptr: Ptr,

    pub fn fromReadContext(context: ReadContext) Counter.Error!AnyPointerReader {
        var _context = context;
        const ptr = try _context.readPtr();

        return AnyPointerReader{
            .context = _context,
            .ptr = ptr,
        };
    }
};

pub const StructReader = struct {
    context: ReadContext,
    dataWords: u16,
    ptrWords: u16,

    pub fn readIntField(self: StructReader, comptime T: type, offset: u32) T {
        return self.context.readIntWithBound(T, offset, self.dataWords);
    }

    pub fn readBoolField(self: StructReader, comptime offset: u32) bool {
        const bucket: u29 = comptime offset / 8;
        const shift: u3 = comptime offset % 8;

        return self.readIntField(u8, bucket) >> shift == 1;
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

    pub fn readFloatField(self: StructReader, comptime T: type, offset: u32) T {
        const U = comptime switch (T) {
            f32 => u32,
            f64 => u64,
            else => unreachable,
        };
        return @bitCast(self.readIntField(U, offset));
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

    pub fn format(value: StructReader, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: anytype) !void {
        _ = options;
        _ = fmt;
        try writer.print("{{context = {}, dataWords = {}, ptrWords = {}}}", .{ value.context, value.dataWords, value.ptrWords });
    }
};

pub const StructBuilder = struct {
    context: BuildContext,
    dataWords: u16,
    ptrWords: u16,

    pub fn readIntField(self: StructBuilder, comptime T: type, offset: u32) T {
        return self.context.readIntWithBound(T, offset, self.dataWords);
    }

    pub fn writeIntField(self: StructBuilder, comptime T: type, offset: u32, value: T) void {
        return self.context.writeInt(T, offset, value);
    }

    pub fn buildPtrField(self: StructBuilder, comptime T: type, offset: u29) T {
        var ptr = self.context;
        ptr.relativeWords(self.dataWords + offset);
        return T.fromBuildContext(ptr);
    }

    pub fn readFloatField(self: StructBuilder, comptime T: type, offset: u32) T {
        const U = comptime switch (T) {
            f32 => u32,
            f64 => u64,
            else => unreachable,
        };
        return @bitCast(self.readIntField(U, offset));
    }

    pub fn writeFloatField(self: StructBuilder, comptime T: type, offset: u32, value: T) void {
        const U = comptime switch (T) {
            f32 => u32,
            f64 => u64,
            else => unreachable,
        };
        return self.writeIntField(U, offset, @bitCast(value));
    }

    pub fn readBoolField(self: StructBuilder, comptime offset: u32) bool {
        const bucket: u29 = comptime offset / 8;
        const shift: u3 = comptime offset % 8;

        return self.readIntField(u8, bucket) >> shift == 1;
    }

    pub fn writeBoolField(self: StructBuilder, comptime offset: u32, value: bool) void {
        const bucket: u29 = comptime offset / 8;
        const shift: u3 = comptime offset % 8;
        const mask: u8 = comptime @as(u8, 1) << shift;

        const old = self.readIntField(u8, bucket);

        self.context.writeInt(u8, bucket, ~mask & old | if (value) mask else 0);
    }
};

pub const Struct = struct {
    pub const Builder = StructBuilder;
    pub const Reader = StructReader;
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
            switch (try _context.readPtr()) {
                .list => |list| {
                    if (T == u8) {
                        std.debug.assert(list.elementSize == 2);
                    }

                    return Self{
                        .context = _context,
                        .elementSize = list.elementSize,
                        .length = list.elementsOrWords,
                    };
                },
                .null => {
                    return Self{
                        .context = context,
                        .elementSize = 0,
                        .length = 0,
                    };
                },
                else => unreachable,
            }
            const list = (try _context.readPtr()).list;
            _ = list;

            //std.debug.print("offsetWords={}, startOffsetWords={}, b={}\n", .{ offsetWords, startOffsetWords, b });

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

pub fn ListBuilder(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: BuildContext,
        context: ?BuildContext,

        elementSize: u3 = switch (T) {
            void => 0,
            bool => 1,
            u8, i8 => 2,
            u16, i16 => 3,
            u32, i32, f32 => 4,
            u64, i64, f64 => 5,
            else => unreachable,
        },
        length: u29,

        pub fn fromBuildContext(ptr: BuildContext) Self {

            // For now, just assert pointer is empty.
            std.debug.assert(ptr.readInt(u64, 0) == 0);

            return Self{ .ptr = ptr, .context = null, .length = 0 };
        }

        pub fn init(self: *Self, length: u29) Allocator.Error!void {
            // Initialize the array.
            std.debug.assert(self.length == 0);

            const sizeInWords = switch (self.elementSize) {
                0 => 0,
                1 => (length + 63) / 64,
                2 => (length + 7) / 8,
                3 => (length + 3) / 4,
                4 => (length + 1) / 2,
                5 => length,
                else => unreachable,
            };

            self.context = try self.ptr.builder.alloc(self.ptr.segment, sizeInWords);

            std.debug.assert(self.context.?.segment == self.ptr.segment);
            const offsetWords: i30 = @intCast(self.context.?.offsetWords - self.ptr.offsetWords - 1);

            self.length = length;

            self.ptr.writePtr(Ptr{ .list = .{ .offsetWords = offsetWords, .elementsOrWords = length, .elementSize = self.elementSize } });
        }

        pub fn set(self: *Self, index: u32, value: T) void {
            if (self.context) |context| {
                context.writeInt(T, index, value);
            } else {
                return undefined;
            }
        }

        pub fn get(self: Self, ix: u32) T {
            std.debug.assert(ix < self.length);
            return self.context.?.readInt(T, ix);
        }
    };
}

pub fn List(comptime T: type) type {
    switch (@typeInfo(T)) {
        .@"struct" => {
            return struct {
                pub const Builder = CompositeListBuilder(T);
                pub const Reader = CompositeListReader(T);
            };
        },

        else => {},
    }
    return struct {
        pub const Builder = ListBuilder(T);
        pub const Reader = ListReader(T);
    };
}

pub fn CompositeListBuilder(comptime T: type) type {
    return struct {
        const Self = @This();

        ptr: BuildContext,
        context: ?BuildContext,

        length: u29,

        pub fn fromBuildContext(ptr: BuildContext) Self {

            // For now, just assert pointer is empty.
            std.debug.assert(ptr.readInt(u64, 0) == 0);

            return Self{ .ptr = ptr, .context = null, .length = 0 };
        }

        pub fn init(self: *Self, length: u29) Allocator.Error!void {
            // Initialize the array.
            std.debug.assert(self.length == 0);

            const sizeInWords: u29 = (T._Metadata.ptrWords + T._Metadata.dataWords) * length;

            var structPtr = try self.ptr.builder.alloc(self.ptr.segment, 1 + sizeInWords);
            self.context = structPtr;
            self.context.?.offsetWords += 1;

            structPtr.writePtr(Ptr{ .struct_ = .{ .offsetWords = length, .dataWords = T._Metadata.dataWords, .ptrWords = T._Metadata.ptrWords } });

            std.debug.assert(structPtr.segment == self.ptr.segment);
            const offsetWords: i30 = @intCast(structPtr.offsetWords - self.ptr.offsetWords - 1);

            self.length = length;

            self.ptr.writePtr(Ptr{ .list = .{ .offsetWords = offsetWords, .elementsOrWords = sizeInWords, .elementSize = 7 } });
        }

        pub fn get(self: Self, ix: u32) T.Builder {
            std.debug.assert(ix < self.length);
            var _context = self.context.?;
            _context.relativeWords(@intCast((T._Metadata.ptrWords + T._Metadata.dataWords) * ix));

            return T.Builder{
                .builder = StructBuilder{
                    .context = _context,
                    .dataWords = T._Metadata.dataWords,
                    .ptrWords = T._Metadata.ptrWords,
                },
            };
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

        context: ?ReadContext,

        elementSize: u3,
        length: u29,

        dataWords: u16,
        ptrWords: u16,

        pub const empty = Self{ .context = null, .elementSize = 0, .length = 0, .dataWords = 0, .ptrWords = 0 };

        pub fn fromReadContext(context: ReadContext) Counter.Error!Self {
            // for now, ignore the possibility that this may be a far pointer.
            var _context = context;

            switch (try _context.readPtr()) {
                .list => |list_ptr| {
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
                },
                .null => {
                    return Self{
                        .context = _context,
                        .elementSize = 0,
                        .length = 0,
                        .dataWords = 0,
                        .ptrWords = 0,
                    };
                },
                else => unreachable,
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

            var _context = self.context.?;
            _context.relativeWords(@intCast((self.ptrWords + self.dataWords) * ix));

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

        const segmentCount = 1 + std.mem.readInt(u32, buffer[0..4], .little);

        // std.debug.print("segmentCount = {}\n", .{segmentCount});

        var segmentLengthsBuffer = try allocator.alloc(u8, 4 * segmentCount * BYTES);
        defer allocator.free(segmentLengthsBuffer);
        std.debug.assert(segmentLengthsBuffer.len == try file.read(segmentLengthsBuffer));

        const segments = try allocator.alloc([]u8, segmentCount * ELEMENTS);

        for (0..segmentCount) |i| {
            const segmentWords = std.mem.readInt(u32, segmentLengthsBuffer[i * 4 ..][0..4], .little);
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

pub const BuildContext = struct {
    builder: *MessageBuilder,
    segments: *[][]u8,
    segment: u32,
    offsetWords: u29,

    pub fn offsetBytes(self: BuildContext) u32 {
        return self.offsetWords << 3;
    }

    pub fn readIntWithBound(self: BuildContext, comptime T: type, offset: u32, boundWords: u29) T {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return if (@sizeOf(T) * offset < boundWords << 3) std.mem.readInt(T, self.segments.*[self.segment][pos..][0..@sizeOf(T)], .little) else 0;
    }

    pub fn readInt(self: BuildContext, comptime T: type, offset: u32) T {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return std.mem.readInt(T, self.segments.*[self.segment][pos..][0..@sizeOf(T)], .little);
    }

    pub fn writeInt(self: BuildContext, comptime T: type, offset: u32, value: T) void {
        const pos = self.offsetBytes() + @sizeOf(T) * offset;
        return std.mem.writeInt(T, self.segments.*[self.segment][pos..][0..@sizeOf(T)], value, .little);
    }

    pub fn writePtr(self: *BuildContext, ptr: Ptr) void {
        self.writeInt(u64, 0, ptr.to_u64());
    }

    pub fn allocStruct(self: *BuildContext, dataWords: u16, ptrWords: u16) Allocator.Error!StructBuilder {
        const builderCtx = try self.builder.alloc(self.segment, ptrWords + dataWords);
        self.writePtr(Ptr{ .struct_ = .{ .offsetWords = 0, .ptrWords = ptrWords, .dataWords = dataWords } });
        return StructBuilder{ .context = builderCtx, .ptrWords = ptrWords, .dataWords = dataWords };
    }

    pub fn relativeWords(self: *BuildContext, dx: i30) void {
        self.offsetWords = @intCast(dx + self.offsetWords);
    }
};

pub const StructMetadata = struct {
    ptrWords: u16,
    dataWords: u16,
};

pub const MessageBuilder = struct {
    allocator: Allocator = std.heap.page_allocator,
    allocShift: u5 = 16, // For consistency.
    segmentStore: [16][]u8 = std.mem.zeroes([16][]u8),
    segmentShifts: [16]u5 = std.mem.zeroes([16]u5),
    segments: [][]u8 = std.mem.zeroes([][]u8),

    pub fn init(self: *MessageBuilder) Allocator.Error!void {
        _ = try self.expandAssert(1);
    }

    inline fn segmentLimit(self: MessageBuilder, segment: u32) u32 {
        return (@as(u32, 1)) << self.segmentShifts[segment];
    }

    pub fn expandAssert(self: *MessageBuilder, min_bytes: u32) Allocator.Error!u32 {
        const n: u32 = @intCast(self.segments.len);
        if (n == self.segmentShifts.len) return Allocator.Error.OutOfMemory;
        const allocShift: u5 = @max(self.allocShift, @as(u5, @intCast(std.math.log2_int_ceil(u32, min_bytes))));
        const allocBytes: u32 = @as(u32, 1) << allocShift;
        self.segmentStore[n] = try self.allocator.alloc(u8, allocBytes);
        self.segmentStore[n].len = 0;
        self.segmentShifts[n] = allocShift;
        self.allocShift += 1;
        self.segments = self.segmentStore[0 .. n + 1];
        return n;
    }

    pub fn allocAssert(self: *MessageBuilder, segment: u32, bytes: u32) BuildContext {
        defer self.segments[segment].len += bytes;
        const seg = self.segments[segment];
        @memset(seg.ptr[seg.len .. seg.len + bytes], 0);
        return .{ .builder = self, .segments = &self.segments, .segment = segment, .offsetWords = @intCast(seg.len >> 3) };
    }
    /// try to allocate in the given segment.
    pub fn alloc(self: *MessageBuilder, segment: u32, words: u32) Allocator.Error!BuildContext {
        const bytes: u32 = words << 3;
        if (segment < self.segments.len and self.segments[segment].len + bytes < self.segmentLimit(segment)) {
            return self.allocAssert(segment, bytes);
        } else {
            var best_ix: u32 = 0;
            var best_spare: i64 = -1;

            for (self.segments, 0..) |seg, n_| {
                const n: u32 = @intCast(n_);
                if (n == segment) continue;
                const spare: i64 = self.segmentLimit(n) - (@as(u32, @intCast(seg.len)) + bytes);
                if (spare > best_spare) {
                    best_spare = spare;
                    best_ix = n;
                }
            }

            if (best_spare < 0) {
                const seg = try self.expandAssert(bytes);
                return self.allocAssert(seg, bytes);
            } else {
                return self.allocAssert(best_ix, bytes);
            }
        }
    }

    pub fn deinit(self: *MessageBuilder) void {
        for (self.segments, 0..) |*segment, n| {
            segment.len = self.segmentLimit(@as(u32, @intCast(n)));
            self.allocator.free(segment.*);
        }
    }

    pub fn toReader(self: MessageBuilder) Message {
        return Message{ .segments = self.segments };
    }

    pub fn initRootStruct(self: *MessageBuilder, comptime T: type) Allocator.Error!T.Builder {
        var ctx = try self.alloc(0, 1);
        return T.Builder{ .builder = try ctx.allocStruct(T._Metadata.dataWords, T._Metadata.ptrWords) };
    }
};

test "test MessageBuilder" {
    var builder = MessageBuilder{ .allocator = std.testing.allocator };
    try builder.init();
    defer builder.deinit();
    try std.testing.expectEqual(@as(usize, 1), builder.segments.len);

    {
        const context = try builder.alloc(0, 1024);
        try std.testing.expectEqual(@as(u32, 0), context.segment);
        try std.testing.expectEqual(@as(u32, 0), context.offsetWords);
        try std.testing.expectEqual(@as(usize, 8192), context.segments.*[0].len);
    }

    {
        const context = try builder.alloc(0, 1024);
        try std.testing.expectEqual(@as(u32, 0), context.segment);
        try std.testing.expectEqual(@as(u32, 1024), context.offsetWords);
        try std.testing.expectEqual(@as(usize, 16384), context.segments.*[0].len);
    }

    {
        const context = try builder.alloc(0, 8192 * 2);
        try std.testing.expectEqual(@as(u32, 1), context.segment);
        try std.testing.expectEqual(@as(u32, 0), context.offsetWords);
        try std.testing.expectEqual(@as(usize, 8192 * 2 * 8), context.segments.*[1].len);
    }

    {
        const context = try builder.alloc(1, 1024);
        try std.testing.expectEqual(@as(u32, 0), context.segment);
        try std.testing.expectEqual(@as(u32, 2048), context.offsetWords);
        try std.testing.expectEqual(@as(usize, 8192 * 3), context.segments.*[0].len);
    }
}
