const std = @import("std");
const builtin = @import("builtin");

const native_endian = builtin.target.cpu.arch.endian();
const HalfUsize = @Type(.{ .int = .{ .signedness = .unsigned, .bits = @bitSizeOf(usize) / 2 } });

pub const BitWriter = struct {
    dest_writer: *std.io.Writer,
    bit_buffer: u8 = 0,
    bit_offset: u3 = 0,
    absolute_position: usize = 0,

    const Self = @This();

    pub fn writeBool(self: *Self, value: bool) !void {
        const bit_mask = @shlExact(@as(u8, 1), self.bit_offset);
        if (value) {
            self.bit_buffer |= bit_mask;
        } else {
            self.bit_buffer &= ~bit_mask;
        }
        if (self.bit_offset < 7) {
            self.bit_offset += 1;
        } else {
            try self.dest_writer.writeByte(self.bit_buffer);
            self.bit_offset = 0;
        }
        self.absolute_position += 1;
    }

    pub fn writeInt(self: *Self, comptime Type: type, value: Type) !void {
        if (native_endian != .little) {
            @compileError("This implementation works correctly only on architectures with little endian integers.");
        }
        const info = getIntInfo(Type);
        const unsigned_value: info.ValueType = @bitCast(value);
        var container: info.ContainerType = @intCast(unsigned_value);
        const container_bytes: *[info.container_size_in_bytes]u8 = @ptrCast(&container);
        container <<= self.bit_offset;
        const buffer_mask = ~(@as(u8, 0xFF) << self.bit_offset);
        const masked_buffer = self.bit_buffer & buffer_mask;
        container_bytes[0] |= masked_buffer;
        const number_of_bytes_to_write = (@as(usize, self.bit_offset) + info.value_size_in_bits) / std.mem.byte_size_in_bits;
        try self.dest_writer.writeAll(container_bytes[0..number_of_bytes_to_write]);
        self.bit_offset +%= (info.value_size_in_bits % std.mem.byte_size_in_bits);
        self.bit_buffer = container_bytes[number_of_bytes_to_write];
        self.absolute_position += info.value_size_in_bits;
    }

    pub fn writeFloat(self: *Self, comptime Type: type, value: Type) !void {
        const info = switch (@typeInfo(Type)) {
            .float => |*info| info,
            else => @compileError("Expecting Type to be a float type but got: " ++ @typeName(Type)),
        };
        const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = info.bits } });
        const int_value: IntType = @bitCast(value);
        return self.writeInt(IntType, int_value);
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        if (self.bit_offset == 0) {
            try self.dest_writer.writeAll(bytes);
            self.absolute_position += bytes.len * std.mem.byte_size_in_bits;
            return;
        }
        const half_words_count = bytes.len / @sizeOf(HalfUsize);
        const half_words = std.mem.bytesAsSlice(HalfUsize, bytes[0..(@sizeOf(HalfUsize) * half_words_count)]);
        for (half_words) |word| {
            try self.writeInt(HalfUsize, word);
        }
        const remainder = bytes[(@sizeOf(HalfUsize) * half_words_count)..bytes.len];
        for (remainder) |byte| {
            try self.writeInt(u8, byte);
        }
    }

    pub fn writeZeroes(self: *Self, number_of_bits: usize) !void {
        const buffer_mask = ~(@as(u8, 0xFF) << self.bit_offset);
        const masked_buffer = self.bit_buffer & buffer_mask;
        const bytes_to_write = (number_of_bits + self.bit_offset) / std.mem.byte_size_in_bits;
        if (bytes_to_write > 0) {
            try self.dest_writer.writeByte(masked_buffer);
            self.bit_buffer = 0;
            for (0..(bytes_to_write - 1)) |_| {
                try self.dest_writer.writeByte(0);
            }
        } else {
            self.bit_buffer = masked_buffer;
        }
        self.bit_offset +%= @intCast(number_of_bits % std.mem.byte_size_in_bits);
        self.absolute_position += number_of_bits;
    }

    pub fn flush(self: *Self) !void {
        if (self.bit_offset > 0) {
            try self.dest_writer.writeByte(self.bit_buffer);
            self.absolute_position += std.mem.byte_size_in_bits - @as(usize, self.bit_offset);
            self.bit_offset = 0;
        }
        try self.dest_writer.flush();
    }
};

pub const BitReader = struct {
    src_reader: *std.io.Reader,
    bit_offset: u3 = 0,
    absolute_position: usize = 0,

    const Self = @This();

    pub fn readBool(self: *Self) !bool {
        const byte = try self.src_reader.peekByte();
        const mask = @shlExact(@as(u8, 1), self.bit_offset);
        const masked_byte = byte & mask;
        const value = masked_byte != 0;
        if (self.bit_offset < 7) {
            self.bit_offset += 1;
        } else {
            self.src_reader.toss(1);
            self.bit_offset = 0;
        }
        self.absolute_position += 1;
        return value;
    }

    pub fn readInt(self: *Self, comptime Type: type) !Type {
        if (native_endian != .little) {
            @compileError("This implementation works correctly only on architectures with little endian integers.");
        }
        const info = getIntInfo(Type);
        var container: info.ContainerType = undefined;
        const container_bytes: *[info.container_size_in_bytes]u8 = @ptrCast(&container);
        if (self.src_reader.peekArray(info.container_size_in_bytes) catch null) |slice| {
            container_bytes.* = slice.*;
        } else if (self.src_reader.peekArray(info.container_size_in_bytes - 1)) |slice| {
            container_bytes.* = slice.* ++ .{0};
        } else |err| return err;
        container >>= self.bit_offset;
        const mask = ~((~@as(info.ContainerType, 0)) << info.value_size_in_bits);
        container &= mask;
        const unsigned_value: info.ValueType = @intCast(container);
        const value: Type = @bitCast(unsigned_value);
        const bytes_to_toss = (@as(usize, self.bit_offset) + info.value_size_in_bits) / std.mem.byte_size_in_bits;
        self.src_reader.toss(bytes_to_toss);
        self.bit_offset +%= (info.value_size_in_bits % std.mem.byte_size_in_bits);
        self.absolute_position += info.value_size_in_bits;
        return value;
    }

    pub fn readFloat(self: *Self, comptime Type: type) !Type {
        const info = switch (@typeInfo(Type)) {
            .float => |*info| info,
            else => @compileError("Expecting Type to be a float type but got: " ++ @typeName(Type)),
        };
        const IntType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = info.bits } });
        const int_value = try self.readInt(IntType);
        return @bitCast(int_value);
    }

    pub fn readBytes(self: *Self, buffer: []u8) !void {
        if (self.bit_offset == 0) {
            try self.src_reader.readSliceAll(buffer);
            self.absolute_position += buffer.len * std.mem.byte_size_in_bits;
            return;
        }
        const half_words_count = buffer.len / @sizeOf(HalfUsize);
        const half_words = std.mem.bytesAsSlice(HalfUsize, buffer[0..(@sizeOf(HalfUsize) * half_words_count)]);
        for (half_words) |*half_word| {
            half_word.* = try self.readInt(HalfUsize);
        }
        const remainder = buffer[(@sizeOf(HalfUsize) * half_words_count)..buffer.len];
        for (remainder) |*byte| {
            byte.* = try self.readInt(u8);
        }
    }

    pub fn skip(self: *Self, number_of_bits: usize) !void {
        const bytes_to_skip = (number_of_bits + self.bit_offset) / std.mem.byte_size_in_bits;
        try self.src_reader.discardAll(bytes_to_skip);
        self.bit_offset +%= @intCast(number_of_bits % std.mem.byte_size_in_bits);
        self.absolute_position += number_of_bits;
    }
};

const IntInfo = struct {
    ValueType: type,
    value_size_in_bits: comptime_int,
    value_size_in_bytes: comptime_int,
    ContainerType: type,
    container_size_in_bits: comptime_int,
    container_size_in_bytes: comptime_int,
};

fn getIntInfo(comptime Type: type) IntInfo {
    const type_info = switch (@typeInfo(Type)) {
        .int => |*info| info,
        else => @compileError("Expecting Type to be a integer type but got: " ++ @typeName(Type)),
    };
    const value_size_in_bits = type_info.bits;
    const value_size_in_bytes = std.math.divCeil(u16, value_size_in_bits, std.mem.byte_size_in_bits) catch {
        @compileError(std.fmt.comptimePrint(
            "Failed to ceil devide {} with {}.",
            .{ value_size_in_bits, std.mem.byte_size_in_bits },
        ));
    };
    const container_size_in_bytes = value_size_in_bytes + 1;
    const container_size_in_bits = container_size_in_bytes * std.mem.byte_size_in_bits;
    const ValueType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = value_size_in_bits } });
    const ContainerType = @Type(.{ .int = .{ .signedness = .unsigned, .bits = container_size_in_bits } });
    return .{
        .ValueType = ValueType,
        .value_size_in_bits = value_size_in_bits,
        .value_size_in_bytes = value_size_in_bytes,
        .ContainerType = ContainerType,
        .container_size_in_bits = container_size_in_bits,
        .container_size_in_bytes = container_size_in_bytes,
    };
}

const testing = std.testing;

test "BitReader.readBool should read the same value that BitWriter.writeBool wrote" {
    var buffer: [2]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(false);
    try writer.writeBool(true);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.writeBool(true);
    try writer.writeBool(true);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.writeBool(true);
    try writer.writeBool(true);
    try writer.writeBool(true);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.writeBool(false);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(false, reader.readBool());
}

test "BitReader.readInt should read the same value that BitWriter.writeInt wrote" {
    var buffer: [66]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeInt(u1, 1);
    try writer.writeInt(u2, 2);
    try writer.writeInt(i3, 3);
    try writer.writeInt(i4, -4);
    try writer.writeInt(u5, 5);
    try writer.writeInt(u6, 6);
    try writer.writeInt(i7, 7);
    try writer.writeInt(i8, -8);
    try writer.writeInt(u9, 9);
    try writer.writeInt(u10, 10);
    try writer.writeInt(i11, 11);
    try writer.writeInt(i12, -12);
    try writer.writeInt(u13, 13);
    try writer.writeInt(u14, 14);
    try writer.writeInt(i15, 15);
    try writer.writeInt(i16, -16);
    try writer.writeInt(u17, 17);
    try writer.writeInt(u18, 18);
    try writer.writeInt(i19, 19);
    try writer.writeInt(i20, -20);
    try writer.writeInt(u21, 21);
    try writer.writeInt(u22, 22);
    try writer.writeInt(i23, 23);
    try writer.writeInt(i24, -24);
    try writer.writeInt(u25, 25);
    try writer.writeInt(u26, 26);
    try writer.writeInt(i27, 27);
    try writer.writeInt(i28, -28);
    try writer.writeInt(u29, 29);
    try writer.writeInt(u30, 30);
    try writer.writeInt(i31, 31);
    try writer.writeInt(i32, -32);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(1, reader.readInt(u1));
    try testing.expectEqual(2, reader.readInt(u2));
    try testing.expectEqual(3, reader.readInt(i3));
    try testing.expectEqual(-4, reader.readInt(i4));
    try testing.expectEqual(5, reader.readInt(u5));
    try testing.expectEqual(6, reader.readInt(u6));
    try testing.expectEqual(7, reader.readInt(i7));
    try testing.expectEqual(-8, reader.readInt(i8));
    try testing.expectEqual(9, reader.readInt(u9));
    try testing.expectEqual(10, reader.readInt(u10));
    try testing.expectEqual(11, reader.readInt(i11));
    try testing.expectEqual(-12, reader.readInt(i12));
    try testing.expectEqual(13, reader.readInt(u13));
    try testing.expectEqual(14, reader.readInt(u14));
    try testing.expectEqual(15, reader.readInt(i15));
    try testing.expectEqual(-16, reader.readInt(i16));
    try testing.expectEqual(17, reader.readInt(u17));
    try testing.expectEqual(18, reader.readInt(u18));
    try testing.expectEqual(19, reader.readInt(i19));
    try testing.expectEqual(-20, reader.readInt(i20));
    try testing.expectEqual(21, reader.readInt(u21));
    try testing.expectEqual(22, reader.readInt(u22));
    try testing.expectEqual(23, reader.readInt(i23));
    try testing.expectEqual(-24, reader.readInt(i24));
    try testing.expectEqual(25, reader.readInt(u25));
    try testing.expectEqual(26, reader.readInt(u26));
    try testing.expectEqual(27, reader.readInt(i27));
    try testing.expectEqual(-28, reader.readInt(i28));
    try testing.expectEqual(29, reader.readInt(u29));
    try testing.expectEqual(30, reader.readInt(u30));
    try testing.expectEqual(31, reader.readInt(i31));
    try testing.expectEqual(-32, reader.readInt(i32));
}

test "BitReader.readFloat should read the same value that BitWriter.writeFloat wrote" {
    var buffer: [15]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(false);
    try writer.writeFloat(f16, 1.2);
    try writer.writeBool(true);
    try writer.writeFloat(f32, -3.4);
    try writer.writeBool(false);
    try writer.writeFloat(f64, 5.6);
    try writer.writeBool(true);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(1.2, reader.readFloat(f16));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(-3.4, reader.readFloat(f32));
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(5.6, reader.readFloat(f64));
    try testing.expectEqual(true, reader.readBool());
}

test "BitReader.readBytes should read the same value that BitWriter.writeBytes wrote" {
    var buffer: [10]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeBytes("123");
    try writer.writeBool(false);
    try writer.writeBytes("456");
    try writer.writeBool(true);
    try writer.writeBytes("789");
    try writer.writeBool(false);
    try writer.flush();

    var bytes: [3]u8 = undefined;
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("123", &bytes);
    try testing.expectEqual(false, reader.readBool());
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("456", &bytes);
    try testing.expectEqual(true, reader.readBool());
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("789", &bytes);
    try testing.expectEqual(false, reader.readBool());
}

test "BitWriter.writeZeroes should write correct number of zeroes on correct positions" {
    var buffer: [9]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(true);
    try writer.writeZeroes(1);
    try writer.writeBool(true);
    try writer.writeZeroes(2);
    try writer.writeBool(true);
    try writer.writeZeroes(4);
    try writer.writeBool(true);
    try writer.writeZeroes(8);
    try writer.writeBool(true);
    try writer.writeZeroes(16);
    try writer.writeBool(true);
    try writer.writeZeroes(32);
    try writer.writeBool(true);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u1));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u2));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u4));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u8));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u16));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u32));
    try testing.expectEqual(true, reader.readBool());
}

test "BitReader.skip should skip correct number of bits" {
    var buffer: [9]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(true);
    try writer.writeZeroes(1);
    try writer.writeBool(true);
    try writer.writeZeroes(2);
    try writer.writeBool(true);
    try writer.writeZeroes(4);
    try writer.writeBool(true);
    try writer.writeZeroes(8);
    try writer.writeBool(true);
    try writer.writeZeroes(16);
    try writer.writeBool(true);
    try writer.writeZeroes(32);
    try writer.writeBool(true);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(1);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(2);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(4);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(8);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(16);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(32);
    try testing.expectEqual(true, reader.readBool());
}

test "BitWriter.absolute_position and BitReader.absolute_position should have correct values" {
    var buffer: [8]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = BitWriter{ .dest_writer = &dest_writer };
    try testing.expectEqual(0, writer.absolute_position);
    try writer.writeBool(false);
    try testing.expectEqual(1, writer.absolute_position);
    try writer.writeInt(u3, 0);
    try testing.expectEqual(4, writer.absolute_position);
    try writer.writeFloat(f32, 0);
    try testing.expectEqual(36, writer.absolute_position);
    try writer.writeBytes(&.{ 0, 0, 0 });
    try testing.expectEqual(60, writer.absolute_position);
    try writer.writeZeroes(3);
    try testing.expectEqual(63, writer.absolute_position);
    try writer.flush();
    try testing.expectEqual(64, writer.absolute_position);

    var bytes: [3]u8 = undefined;
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = BitReader{ .src_reader = &src_reader };
    try testing.expectEqual(0, reader.absolute_position);
    _ = try reader.readBool();
    try testing.expectEqual(1, reader.absolute_position);
    _ = try reader.readInt(u3);
    try testing.expectEqual(4, reader.absolute_position);
    _ = try reader.readFloat(f32);
    try testing.expectEqual(36, reader.absolute_position);
    try reader.readBytes(&bytes);
    try testing.expectEqual(60, reader.absolute_position);
    try reader.skip(3);
    try testing.expectEqual(63, reader.absolute_position);
}
