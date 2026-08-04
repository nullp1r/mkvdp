const std = @import("std");

pub const Id = enum(u32) {
  EBML = 0x1a45dfa3,
  Segment = 0x18538067,
  Info = 0x1549a966,
  TimecodeScale = 0x2ad7b1,
  Duration = 0x4489,
  _,
};

pub const read = struct {
  pub fn header(r: *std.Io.Reader) !struct { Id, u64 } {
    const id = try vint(r, true);
    const len = try vint(r, false);
    return .{ @enumFromInt(id), len };
  }

  pub fn vint(r: *std.Io.Reader, keep_marker: bool) !u64 {
    const first = try r.takeByte();
    const lz = @clz(first);
    if (lz > 7) return error.EbmlVintTooLarge;
    const marker = @as(u8, 0x80) >> @truncate(lz);
    const head = if (keep_marker) first else first ^ marker;
    const tail = try uint(r, lz);
    return @as(u64, head) << @as(u6, lz) * 8 | tail;
  }

  pub fn uint(r: *std.Io.Reader, len: u64) !u64 {
    if (len > 8) return error.EbmlUintTooLarge;
    if (len < 1) return 0;
    var buf = [_]u8{0} ** 8;
    try r.readSliceAll(buf[8 - len ..]);
    return std.mem.readInt(u64, &buf, .big);
  }

  pub fn float(r: *std.Io.Reader, len: u64) !f64 {
    return switch (len) {
      4 => @floatCast(@as(f32, @bitCast(@as(u32, @truncate(try r.takeInt(u32, .big)))))),
      8 => @bitCast(try r.takeInt(u64, .big)),
      else => error.EbmlUnsupportedFloatSize,
    };
  }
};

pub const write = struct {
  pub fn float(w: *std.Io.Writer, val: f64, len: u64) !void {
    switch (len) {
      4 => try w.writeInt(u32, @bitCast(@as(f32, @floatCast(val))), .big),
      8 => try w.writeInt(u64, @bitCast(val), .big),
      else => return error.EbmlUnsupportedFloatSize,
    }
  }
};
