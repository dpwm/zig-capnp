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
    return @bitCast(T, @truncate(UT, x));
}

test "basic add functionality" {
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

    // const data = std.mem.readIntNative(u64, buf[16..24]);

    try testing.expect(add(3, 7) == 10);
}
