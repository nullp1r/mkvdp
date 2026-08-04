const std = @import("std");
const embl = @import("embl.zig");

const Context = struct {
  io: std.Io,
  args: *std.process.Args.Iterator,
  stdout: *std.Io.Writer,
  stderr: *std.Io.Writer,
};

pub fn main(init: std.process.Init) !u8 {
  var args = try init.minimal.args.iterateAllocator(init.gpa);
  defer args.deinit();
  const arg0 = args.next().?;

  var stdout_buf: [0x400]u8 = undefined;
  var stdout: std.Io.File.Writer = .init(.stdout(), init.io, &stdout_buf);

  var stderr_buf: [0x400]u8 = undefined;
  var stderr: std.Io.File.Writer = .init(.stderr(), init.io, &stderr_buf);

  var ctx: Context = .{
    .io = init.io,
    .args = &args,
    .stdout = &stdout.interface,
    .stderr = &stderr.interface,
  };

  const code: u8 = if (run(&ctx)) 0 else |err| err: {
    switch (err) {
      error.Usage => try ctx.stderr.print("usage: {s} <seconds> <file>\n", .{arg0}),
      else => try ctx.stderr.print("error: {s}\n", .{@errorName(err)}),
    }
    break :err 1;
  };

  try ctx.stdout.flush();
  try ctx.stderr.flush();

  return code;
}

fn run(ctx: *Context) !void {
  const arg_seconds = ctx.args.next() orelse return error.Usage;
  const arg_file = ctx.args.next() orelse return error.Usage;

  const seconds = try std.fmt.parseFloat(f64, arg_seconds);

  try ctx.stderr.print("opening file… \x1b[3;2mpath:\x1b[22m {s}\x1b[23m\n", .{arg_file});
  var file = try std.Io.Dir.cwd().openFile(ctx.io, arg_file, .{ .mode = .read_write });
  defer file.close(ctx.io);

  const before = try setDuration(ctx, &file, seconds);
  try ctx.stderr.print("patched duration: " ++
    "\x1b[1;33m{}s\x1b[39;22m -> \x1b[1;32m{}s\x1b[39;22m" ++
    "\n", .{ before, seconds });
}

fn setDuration(ctx: *Context, file: *std.Io.File, seconds: f64) !f64 {
  var file_r_buf: [0x400]u8 = undefined;
  var file_r = file.reader(ctx.io, &file_r_buf);
  const fr = &file_r.interface;

  var file_w_buf: [0x400]u8 = undefined;
  var file_w = file.writer(ctx.io, &file_w_buf);
  const fw = &file_w.interface;

  var limit: u64 = std.math.maxInt(u64);
  var timecode_scale: f64 = 1e6;
  var duration_at: ?struct { pos: u64, len: u64 } = null;

  while (file_r.logicalPos() < limit) {
    const pos_head = file_r.logicalPos();
    const id, const len = embl.read.header(fr) catch |err|
      switch (err) { error.EndOfStream => break, else => return err };
    const pos_data = file_r.logicalPos();

    if (std.enums.tagName(embl.Id, id)) |name| {
      try ctx.stderr.print("found \x1b[1;34m{s}\x1b[39;22m " ++
        "\x1b[3m\x1b[2mhead:\x1b[22m {} \x1b[2mdata:\x1b[22m {} \x1b[2mlen:\x1b[22m {}\x1b[23m" ++
        "\n", .{ name, pos_head, pos_data, len });
    }

    switch (id) {
      embl.Id.Segment, embl.Id.Info => {
        limit = pos_data + len;
      },
      embl.Id.TimecodeScale => {
        const val = try embl.read.uint(fr, len);
        timecode_scale = @floatFromInt(val);
      },
      embl.Id.Duration => {
        duration_at = .{ .pos = pos_data, .len = len };
        try file_r.seekBy(@intCast(len));
      },
      else => {
        try file_r.seekBy(@intCast(len));
      },
    }
  }

  const dur = duration_at orelse return error.DurationNotFound;

  try file_r.seekTo(dur.pos);
  try file_w.seekTo(dur.pos);

  const new_val = 1e9 * seconds / timecode_scale;
  const old_val = try embl.read.float(fr, dur.len);
  try embl.write.float(fw, new_val, dur.len);
  try fw.flush();

  return timecode_scale * old_val / 1e9;
}
