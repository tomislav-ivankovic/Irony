const std = @import("std");
const xz = @import("xz");
const misc = @import("../misc/root.zig");

pub const XzEncoder = struct {
    vtable: std.io.Writer.VTable,
    des_writer: *std.io.Writer,
    lzma_allocator: LzmaAllocator,
    lzma_stream: xz.lzma_stream,
    flushed: bool,

    const Self = @This();
    const chunk_size = 4096;

    pub fn init(allocator: std.mem.Allocator, des_writer: *std.io.Writer) !Self {
        var lzma_allocator = LzmaAllocator.init(allocator);
        errdefer lzma_allocator.deinit();

        var options = xz.lzma_options_lzma{};
        const options_result = xz.lzma_lzma_preset(&options, xz.LZMA_PRESET_EXTREME);
        if (lzmaResultToError(options_result)) |err| {
            misc.error_context.new("{s}", .{lzmaResultToDescription(options_result)});
            misc.error_context.append("lzma_lzma_preset returned a error result: {}", .{options_result});
            return err;
        }

        var lzma_stream = xz.lzma_stream{};
        lzma_stream.allocator = &lzma_allocator.interface();
        const filters = [2]xz.lzma_filter{
            .{ .id = xz.LZMA_FILTER_LZMA2, .options = &options },
            .{ .id = xz.LZMA_VLI_UNKNOWN, .options = null },
        };
        const stream_result = xz.lzma_stream_encoder(&lzma_stream, &filters, xz.LZMA_CHECK_CRC64);
        if (lzmaResultToError(stream_result)) |err| {
            misc.error_context.new("{s}", .{lzmaResultToDescription(stream_result)});
            misc.error_context.append("lzma_stream_encoder returned a error result: {}", .{stream_result});
            return err;
        }
        errdefer xz.lzma_end(&lzma_stream);

        return .{
            .vtable = .{
                .drain = drain,
                .flush = flush,
            },
            .des_writer = des_writer,
            .lzma_allocator = lzma_allocator,
            .lzma_stream = lzma_stream,
            .flushed = false,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lzma_stream.allocator = &self.lzma_allocator.interface();
        xz.lzma_end(&self.lzma_stream);
        self.lzma_allocator.deinit();
    }

    pub fn writer(self: *Self, buffer: []u8) std.io.Writer {
        return .{
            .vtable = &self.vtable,
            .buffer = buffer,
        };
    }

    fn drain(w: *std.io.Writer, data: []const []const u8, splat: usize) std.io.Writer.Error!usize {
        const self: *Self = @constCast(@fieldParentPtr("vtable", w.vtable));
        self.lzma_stream.allocator = &self.lzma_allocator.interface();

        if (self.flushed) {
            return error.WriteFailed;
        }

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

    fn flush(w: *std.io.Writer) std.io.Writer.Error!void {
        const self: *Self = @constCast(@fieldParentPtr("vtable", w.vtable));
        self.lzma_stream.allocator = &self.lzma_allocator.interface();

        if (self.flushed) {
            return;
        }
        self.flushed = true;

        _ = try self.consume(w.buffer[0..w.end]);

        const stream = &self.lzma_stream;
        var buffer: [chunk_size]u8 = undefined;
        while (true) {
            stream.next_out = &buffer;
            stream.avail_out = buffer.len;
            const result = xz.lzma_code(stream, xz.LZMA_FINISH);
            if (result != xz.LZMA_STREAM_END) {
                if (lzmaResultToError(result)) |err| {
                    misc.error_context.new("{s}", .{lzmaResultToDescription(result)});
                    misc.error_context.append("lzma_code returned a error result: {}", .{result});
                    misc.error_context.logError(err);
                    return error.WriteFailed;
                }
            }
            const out_size = buffer.len - stream.avail_out;
            if (out_size > 0) {
                try self.des_writer.writeAll(buffer[0..out_size]);
            }
            if (result == xz.LZMA_STREAM_END) {
                break;
            }
        }

        try self.des_writer.flush();
    }

    fn consume(self: *Self, data: []const u8) std.io.Writer.Error!usize {
        const stream = &self.lzma_stream;
        stream.next_in = data.ptr;
        stream.avail_in = data.len;
        var buffer: [chunk_size]u8 = undefined;
        while (stream.avail_in > 0) {
            stream.next_out = &buffer;
            stream.avail_out = buffer.len;
            const result = xz.lzma_code(stream, xz.LZMA_RUN);
            if (result != xz.LZMA_STREAM_END) {
                if (lzmaResultToError(result)) |err| {
                    misc.error_context.new("{s}", .{lzmaResultToDescription(result)});
                    misc.error_context.append("lzma_code returned a error result: {}", .{result});
                    misc.error_context.logError(err);
                    return error.WriteFailed;
                }
            }
            const output_size = buffer.len - stream.avail_out;
            if (output_size > 0) {
                try self.des_writer.writeAll(buffer[0..output_size]);
            }
        }
        return data.len - stream.avail_in;
    }
};

pub const XzDecoder = struct {
    vtable: std.io.Reader.VTable,
    src_reader: *std.io.Reader,
    lzma_allocator: LzmaAllocator,
    lzma_stream: xz.lzma_stream,
    input_buffer: [chunk_size]u8,
    input_leftovers_len: usize,
    output_buffer: [chunk_size]u8,
    output_leftovers_start: usize,
    output_leftovers_len: usize,

    const Self = @This();
    const chunk_size = 4096;

    pub fn init(allocator: std.mem.Allocator, src_reader: *std.io.Reader) !Self {
        var lzma_allocator = LzmaAllocator.init(allocator);
        errdefer lzma_allocator.deinit();

        var lzma_stream = xz.lzma_stream{};
        lzma_stream.allocator = &lzma_allocator.interface();
        const stream_result = xz.lzma_stream_decoder(&lzma_stream, std.math.maxInt(u64), xz.LZMA_CONCATENATED);
        if (lzmaResultToError(stream_result)) |err| {
            misc.error_context.new("{s}", .{lzmaResultToDescription(stream_result)});
            misc.error_context.append("lzma_stream_decoder returned a error result: {}", .{stream_result});
            return err;
        }
        errdefer xz.lzma_end(&lzma_stream);

        return .{
            .vtable = .{
                .stream = stream,
            },
            .src_reader = src_reader,
            .lzma_allocator = lzma_allocator,
            .lzma_stream = lzma_stream,
            .input_buffer = undefined,
            .input_leftovers_len = 0,
            .output_buffer = undefined,
            .output_leftovers_start = 0,
            .output_leftovers_len = 0,
        };
    }

    pub fn deinit(self: *Self) void {
        self.lzma_stream.allocator = &self.lzma_allocator.interface();
        xz.lzma_end(&self.lzma_stream);
        self.lzma_allocator.deinit();
    }

    pub fn reader(self: *Self, buffer: []u8) std.io.Reader {
        return .{
            .vtable = &self.vtable,
            .buffer = buffer,
            .seek = 0,
            .end = 0,
        };
    }

    fn stream(r: *std.io.Reader, w: *std.io.Writer, limit: std.io.Limit) std.io.Reader.StreamError!usize {
        const self: *Self = @constCast(@fieldParentPtr("vtable", r.vtable));
        self.lzma_stream.allocator = &self.lzma_allocator.interface();

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
            const input_finished = read_size < non_leftover_buffer.len;
            const available_input_size = self.input_leftovers_len + read_size;

            self.lzma_stream.next_in = &self.input_buffer[0];
            self.lzma_stream.avail_in = available_input_size;
            self.lzma_stream.next_out = &self.output_buffer[0];
            self.lzma_stream.avail_out = self.output_buffer.len;

            const action: xz.lzma_action = if (input_finished) xz.LZMA_FINISH else xz.LZMA_RUN;
            const result = xz.lzma_code(&self.lzma_stream, action);
            if (result != xz.LZMA_STREAM_END and lzmaResultToError(result) != null) {
                return error.ReadFailed;
            }

            self.input_leftovers_len = self.lzma_stream.avail_in;
            if (self.input_leftovers_len > 0) {
                const start = available_input_size - self.input_leftovers_len;
                const len = self.input_leftovers_len;
                std.mem.copyForwards(
                    u8,
                    self.input_buffer[0..len],
                    self.input_buffer[start..(start + len)],
                );
            }

            const output_size = self.output_buffer.len - self.lzma_stream.avail_out;
            if (output_size > 0) {
                const write_size = @min(output_size, total_out_limit - total_out);
                if (write_size > 0) {
                    try w.writeAll(self.output_buffer[0..write_size]);
                    total_out += write_size;
                }
                self.output_leftovers_start = write_size;
                self.output_leftovers_len = output_size - write_size;
            }

            if (result == xz.LZMA_STREAM_END) {
                if (total_out == 0) {
                    return error.EndOfStream;
                }
                break;
            }
        }

        return total_out;
    }
};

const LzmaAllocator = struct {
    allocator: std.mem.Allocator,
    map: std.AutoHashMap([*]align(alignment) u8, usize),

    const Self = @This();
    const alignment = @alignOf(std.c.max_align_t);

    pub fn init(allocator: std.mem.Allocator) Self {
        return .{
            .allocator = allocator,
            .map = .init(allocator),
        };
    }

    pub fn deinit(self: *Self) void {
        self.map.deinit();
    }

    pub fn interface(self: *Self) xz.lzma_allocator {
        return .{
            .alloc = alloc,
            .free = free,
            .@"opaque" = self,
        };
    }

    fn alloc(@"opaque": ?*anyopaque, len: usize, size: usize) callconv(.c) ?*anyopaque {
        const self: *Self = @ptrCast(@alignCast(@"opaque"));
        const total_size = len * size;
        const slice = self.allocator.alignedAlloc(u8, std.mem.Alignment.fromByteUnits(alignment), total_size) catch {
            return null;
        };
        self.map.put(slice.ptr, slice.len) catch {
            self.allocator.free(slice);
            return null;
        };
        return slice.ptr;
    }

    fn free(@"opaque": ?*anyopaque, ptr: ?*anyopaque) callconv(.c) void {
        const self: *Self = @ptrCast(@alignCast(@"opaque"));
        if (ptr == null) {
            return;
        }
        const aligned: [*]align(alignment) u8 = @ptrCast(@alignCast(ptr));
        const entry = self.map.fetchRemove(aligned) orelse {
            std.log.err("XZ utils attempted to free a address that's not allocated: 0x{X}", .{@intFromPtr(ptr)});
            return;
        };
        const total_size = entry.value;
        const slice = aligned[0..total_size];
        self.allocator.free(slice);
    }
};

fn lzmaResultToError(result: xz.lzma_ret) ?anyerror {
    return switch (result) {
        xz.LZMA_OK => null,
        xz.LZMA_STREAM_END => error.LzmaStreamEnd,
        xz.LZMA_NO_CHECK => error.LzmaNoCheck,
        xz.LZMA_UNSUPPORTED_CHECK => error.LzmaUnsupportedCheck,
        xz.LZMA_GET_CHECK => null,
        xz.LZMA_MEM_ERROR => error.LzmaMemError,
        xz.LZMA_MEMLIMIT_ERROR => error.MemLimitError,
        xz.LZMA_FORMAT_ERROR => error.LzmaFormatError,
        xz.LZMA_OPTIONS_ERROR => error.LzmaOptionsError,
        xz.LZMA_DATA_ERROR => error.LzmaDataError,
        xz.LZMA_BUF_ERROR => error.LzmaBufError,
        xz.LZMA_PROG_ERROR => error.LzmaProgError,
        xz.LZMA_SEEK_NEEDED => null,
        else => error.Unknown,
    };
}

fn lzmaResultToDescription(result: xz.lzma_ret) [:0]const u8 {
    return switch (result) {
        xz.LZMA_OK => "Operation completed successfully.",
        xz.LZMA_STREAM_END => "End of stream was reached.",
        xz.LZMA_NO_CHECK => "Input stream has no integrity check.",
        xz.LZMA_UNSUPPORTED_CHECK => "Cannot calculate the integrity check",
        xz.LZMA_GET_CHECK => "Integrity check type is now available.",
        xz.LZMA_MEM_ERROR => "Cannot allocate memory.",
        xz.LZMA_MEMLIMIT_ERROR => "Memory usage limit was reached",
        xz.LZMA_FORMAT_ERROR => "File format not recognized.",
        xz.LZMA_OPTIONS_ERROR => "Invalid or unsupported options.",
        xz.LZMA_DATA_ERROR => "Data is corrupt.",
        xz.LZMA_BUF_ERROR => "No progress is possible",
        xz.LZMA_PROG_ERROR => "Programming error",
        xz.LZMA_SEEK_NEEDED => "Request to change the input file position.",
        else => "Unknown error.",
    };
}

const testing = std.testing;

test "XzDecoder should decode the same values that the XzEncoder encoded" {
    errdefer |err| misc.error_context.logError(err);
    var buffer: [64]u8 = undefined;

    var dest_writer = std.io.Writer.Allocating.init(testing.allocator);
    defer dest_writer.deinit();
    var encoder = try XzEncoder.init(testing.allocator, &dest_writer.writer);
    defer encoder.deinit();

    var writter = encoder.writer(&buffer);
    for (0..100) |i| {
        try writter.writeInt(usize, i, .little);
    }
    try writter.flush();

    const encoded = try dest_writer.toOwnedSlice();
    defer testing.allocator.free(encoded);

    var src_reader = std.io.Reader.fixed(encoded);
    var decoder = try XzDecoder.init(testing.allocator, &src_reader);
    defer decoder.deinit();
    var reader = decoder.reader(&buffer);

    for (0..100) |i| {
        try testing.expectEqual(i, reader.takeInt(usize, .little));
    }
}
