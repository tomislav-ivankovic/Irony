const std = @import("std");
const zstd = @import("zstd");
const misc = @import("../misc/root.zig");

pub const ZstdEncoder = struct {
    vtable: std.Io.Writer.VTable,
    des_writer: *std.Io.Writer,
    allocator: std.mem.Allocator,
    zstd_allocator: *ZstdAllocator,
    ctx: *zstd.ZSTD_CCtx,
    input_buffer: []u8,
    output_buffer: []u8,

    const Self = @This();

    pub fn init(
        allocator: std.mem.Allocator,
        des_writer: *std.Io.Writer,
        compression_level: c_int,
    ) !Self {
        const zstd_allocator = allocator.create(ZstdAllocator) catch |err| {
            misc.error_context.new("Failed to allocate zstd allocator.", .{});
            return err;
        };
        errdefer allocator.destroy(zstd_allocator);
        zstd_allocator.* = .{ .allocator = allocator };

        const ctx = zstd.ZSTD_createCCtx_advanced(zstd_allocator.interface()) orelse {
            misc.error_context.new("Failed to create zstd compression context.", .{});
            return error.ZstdError;
        };
        errdefer {
            const free_result = zstd.ZSTD_freeCCtx(ctx);
            if (resultToError(free_result)) |_| {
                std.log.err(
                    "While recovering from error, failed to free zstd compression context. Cause: {s}",
                    .{resultToString(free_result)},
                );
            }
        }

        const level_result = zstd.ZSTD_CCtx_setParameter(ctx, zstd.ZSTD_c_compressionLevel, compression_level);
        if (resultToError(level_result)) |err| {
            misc.error_context.new("{s}", .{resultToString(level_result)});
            misc.error_context.append("Failed to set compression level to: {}", .{compression_level});
            return err;
        }

        const checksum_result = zstd.ZSTD_CCtx_setParameter(ctx, zstd.ZSTD_c_checksumFlag, 1);
        if (resultToError(checksum_result)) |err| {
            misc.error_context.new("{s}", .{resultToString(checksum_result)});
            misc.error_context.append("Failed to set checksum flag to 1.", .{});
            return err;
        }

        const input_buffer = allocator.alloc(u8, zstd.ZSTD_CStreamInSize()) catch |err| {
            misc.error_context.new("Failed to allocate input buffer.", .{});
            return err;
        };
        errdefer allocator.free(input_buffer);

        const output_buffer = allocator.alloc(u8, zstd.ZSTD_CStreamOutSize()) catch |err| {
            misc.error_context.new("Failed to allocate output buffer.", .{});
            return err;
        };
        errdefer allocator.free(output_buffer);

        return .{
            .vtable = .{
                .drain = drain,
                .flush = flush,
            },
            .des_writer = des_writer,
            .allocator = allocator,
            .zstd_allocator = zstd_allocator,
            .ctx = ctx,
            .input_buffer = input_buffer,
            .output_buffer = output_buffer,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.output_buffer);
        self.allocator.free(self.input_buffer);
        const ctx_result = zstd.ZSTD_freeCCtx(self.ctx);
        if (resultToError(ctx_result)) |_| {
            std.log.err("Failed to free zstd compression context. Cause: {s}", .{resultToString(ctx_result)});
        }
        self.allocator.destroy(self.zstd_allocator);
    }

    pub fn writer(self: *Self) std.Io.Writer {
        return .{
            .vtable = &self.vtable,
            .buffer = self.input_buffer,
        };
    }

    fn drain(w: *std.Io.Writer, data: []const []const u8, splat: usize) std.Io.Writer.Error!usize {
        const self: *Self = @constCast(@fieldParentPtr("vtable", w.vtable));
        var consumed: usize = 0;
        consumed += try self.consume(w.buffer[0..w.end]);
        w.end = 0;
        if (data.len == 0) {
            return consumed;
        }
        for (data[0..(data.len - 1)]) |chunk| {
            consumed += try self.consume(chunk);
        }
        const last_chunk = data[data.len - 1];
        for (0..splat) |_| {
            consumed += try self.consume(last_chunk);
        }
        return consumed;
    }

    fn flush(w: *std.Io.Writer) std.Io.Writer.Error!void {
        const self: *Self = @constCast(@fieldParentPtr("vtable", w.vtable));
        var input = zstd.ZSTD_inBuffer{
            .src = w.buffer.ptr,
            .pos = 0,
            .size = w.end,
        };
        while (true) {
            var output = zstd.ZSTD_outBuffer{
                .dst = self.output_buffer.ptr,
                .pos = 0,
                .size = self.output_buffer.len,
            };
            const result = zstd.ZSTD_compressStream2(self.ctx, &output, &input, zstd.ZSTD_e_end);
            if (resultToError(result)) |err| {
                misc.error_context.new("{s}", .{resultToString(result)});
                misc.error_context.append("ZSTD_compressStream2 returned an error result: {}", .{result});
                misc.error_context.logError(err);
                return error.WriteFailed;
            }
            if (output.pos > 0) {
                try self.des_writer.writeAll(self.output_buffer[0..output.pos]);
            }
            if (result == 0) {
                break;
            }
        }
        try self.des_writer.flush();
    }

    fn consume(self: *Self, data: []const u8) std.Io.Writer.Error!usize {
        var input = zstd.ZSTD_inBuffer{
            .src = data.ptr,
            .pos = 0,
            .size = data.len,
        };
        while (input.pos < input.size) {
            var output = zstd.ZSTD_outBuffer{
                .dst = self.output_buffer.ptr,
                .pos = 0,
                .size = self.output_buffer.len,
            };
            const result = zstd.ZSTD_compressStream2(self.ctx, &output, &input, zstd.ZSTD_e_continue);
            if (resultToError(result)) |err| {
                misc.error_context.new("{s}", .{resultToString(result)});
                misc.error_context.append("ZSTD_compressStream2 returned an error result: {}", .{result});
                misc.error_context.logError(err);
                return error.WriteFailed;
            }
            if (output.pos > 0) {
                try self.des_writer.writeAll(self.output_buffer[0..output.pos]);
            }
        }
        return input.pos;
    }
};

pub const ZstdDecoder = struct {
    vtable: std.Io.Reader.VTable,
    src_reader: *std.Io.Reader,
    allocator: std.mem.Allocator,
    zstd_allocator: *ZstdAllocator,
    ctx: *zstd.ZSTD_DCtx,
    input_buffer: []u8,
    input_leftovers_len: usize,
    output_buffer: []u8,
    output_leftovers_start: usize,
    output_leftovers_len: usize,
    in_error_state: bool,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, src_reader: *std.Io.Reader) !Self {
        const zstd_allocator = allocator.create(ZstdAllocator) catch |err| {
            misc.error_context.new("Failed to allocate zstd allocator.", .{});
            return err;
        };
        errdefer allocator.destroy(zstd_allocator);
        zstd_allocator.* = .{ .allocator = allocator };

        const ctx = zstd.ZSTD_createDCtx_advanced(zstd_allocator.interface()) orelse {
            misc.error_context.new("Failed to create zstd decompression context.", .{});
            return error.ZstdError;
        };
        errdefer {
            const free_result = zstd.ZSTD_freeDCtx(ctx);
            if (resultToError(free_result)) |_| {
                std.log.err(
                    "While recovering from error, failed to free zstd decompression context. Cause: {s}",
                    .{resultToString(free_result)},
                );
            }
        }

        const input_buffer = allocator.alloc(u8, zstd.ZSTD_DStreamInSize()) catch |err| {
            misc.error_context.new("Failed to allocate input buffer.", .{});
            return err;
        };
        errdefer allocator.free(input_buffer);

        const output_buffer = allocator.alloc(u8, zstd.ZSTD_DStreamOutSize()) catch |err| {
            misc.error_context.new("Failed to allocate output buffer.", .{});
            return err;
        };
        errdefer allocator.free(output_buffer);

        return .{
            .vtable = .{
                .stream = stream,
            },
            .src_reader = src_reader,
            .allocator = allocator,
            .zstd_allocator = zstd_allocator,
            .ctx = ctx,
            .input_buffer = input_buffer,
            .input_leftovers_len = 0,
            .output_buffer = output_buffer,
            .output_leftovers_start = 0,
            .output_leftovers_len = 0,
            .in_error_state = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.allocator.free(self.output_buffer);
        self.allocator.free(self.input_buffer);
        const ctx_result = zstd.ZSTD_freeDCtx(self.ctx);
        if (resultToError(ctx_result)) |_| {
            std.log.err("Failed to free zstd decompression context. Cause: {s}", .{resultToString(ctx_result)});
        }
        self.allocator.destroy(self.zstd_allocator);
    }

    pub fn reader(self: *Self, buffer: []u8) std.Io.Reader {
        return .{
            .vtable = &self.vtable,
            .buffer = buffer,
            .seek = 0,
            .end = 0,
        };
    }

    fn stream(r: *std.Io.Reader, w: *std.Io.Writer, limit: std.Io.Limit) std.Io.Reader.StreamError!usize {
        const self: *Self = @constCast(@fieldParentPtr("vtable", r.vtable));

        if (self.in_error_state) {
            return error.ReadFailed;
        }

        var total_out: usize = 0;
        const total_out_limit = limit.toInt() orelse std.math.maxInt(usize);

        const leftovers_write_size = @min(self.output_leftovers_len, total_out_limit - total_out);
        if (leftovers_write_size > 0) {
            const start = self.output_leftovers_start;
            try w.writeAll(self.output_buffer[start..(start + leftovers_write_size)]);
            self.output_leftovers_start += leftovers_write_size;
            self.output_leftovers_len -= leftovers_write_size;
            total_out += leftovers_write_size;
        }

        while (total_out < total_out_limit) {
            const non_leftover_buffer = self.input_buffer[self.input_leftovers_len..];
            const read_size = try self.src_reader.readSliceShort(non_leftover_buffer);

            var input = zstd.ZSTD_inBuffer{
                .src = self.input_buffer.ptr,
                .pos = 0,
                .size = self.input_leftovers_len + read_size,
            };
            var output = zstd.ZSTD_outBuffer{
                .dst = self.output_buffer.ptr,
                .pos = 0,
                .size = self.output_buffer.len,
            };

            const result = zstd.ZSTD_decompressStream(self.ctx, &output, &input);
            if (resultToError(result)) |err| {
                misc.error_context.new("{s}", .{resultToString(result)});
                misc.error_context.append("ZSTD_decompressStream returned an error result: {}", .{result});
                misc.error_context.logError(err);
                self.in_error_state = true;
                return error.ReadFailed;
            }

            self.input_leftovers_len = input.size - input.pos;
            if (self.input_leftovers_len > 0) {
                const start = input.pos;
                const len = self.input_leftovers_len;
                @memmove(self.input_buffer[0..len], self.input_buffer[start..(start + len)]);
            }

            const output_size = output.pos;
            if (output_size > 0) {
                const write_size = @min(output_size, total_out_limit - total_out);
                if (write_size > 0) {
                    try w.writeAll(self.output_buffer[0..write_size]);
                    total_out += write_size;
                }
                self.output_leftovers_start = write_size;
                self.output_leftovers_len = output_size - write_size;
            }

            if (read_size == 0 and output_size == 0) {
                break;
            }
        }

        if (total_out == 0) {
            return error.EndOfStream;
        }
        return total_out;
    }
};

const ZstdAllocator = struct {
    allocator: std.mem.Allocator,

    const Self = @This();
    const alignment = @alignOf(std.c.max_align_t);
    const header_size = std.mem.alignForward(usize, @sizeOf(usize), alignment);

    pub fn interface(self: *Self) zstd.ZSTD_customMem {
        return .{
            .customAlloc = alloc,
            .customFree = free,
            .@"opaque" = self,
        };
    }

    fn alloc(@"opaque": ?*anyopaque, size: usize) callconv(.c) ?*anyopaque {
        const self: *Self = @ptrCast(@alignCast(@"opaque"));
        const total_size = header_size + size;
        const data = self.allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(alignment), total_size) catch {
            return null;
        };
        const header: *usize = @ptrCast(data.ptr);
        header.* = size;
        return &data[header_size];
    }

    fn free(@"opaque": ?*anyopaque, pointer: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(@"opaque"));
        if (pointer == null) {
            return;
        }
        if (@intFromPtr(pointer) % alignment != 0) {
            std.log.err("ZSTD attempted to free a misaligned pointer: 0x{X}", .{@intFromPtr(pointer)});
            return;
        }
        const data: [*]align(alignment) u8 = @ptrFromInt(@intFromPtr(pointer) - header_size);
        const header: *usize = @ptrCast(data);
        const total_size = header_size + header.*;
        self.allocator.free(data[0..total_size]);
    }
};

fn resultToError(result: usize) ?error{ZstdError} {
    if (zstd.ZSTD_isError(result) != 0) {
        return error.ZstdError;
    } else {
        return null;
    }
}

fn resultToString(result: usize) [:0]const u8 {
    return std.mem.sliceTo(zstd.ZSTD_getErrorName(result), 0);
}

const testing = std.testing;

test "ZstdDecoder should decode the same values that the ZstdEncoder encoded" {
    var buffer: [64]u8 = undefined;

    var dest_writer = std.Io.Writer.Allocating.init(testing.allocator);
    defer dest_writer.deinit();
    var encoder = try ZstdEncoder.init(testing.allocator, &dest_writer.writer, 0);
    defer encoder.deinit();

    var writer = encoder.writer();
    for (0..100) |i| {
        try writer.writeInt(usize, i, .little);
    }
    try writer.flush();

    const encoded = try dest_writer.toOwnedSlice();
    defer testing.allocator.free(encoded);

    var src_reader = std.Io.Reader.fixed(encoded);
    var decoder = try ZstdDecoder.init(testing.allocator, &src_reader);
    defer decoder.deinit();
    var reader = decoder.reader(&buffer);

    for (0..100) |i| {
        try testing.expectEqual(i, reader.takeInt(usize, .little));
    }
}
