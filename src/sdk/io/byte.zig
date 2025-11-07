const std = @import("std");
const builtin = @import("builtin");

pub const ByteWriter = struct {
    dest_writer: *std.io.Writer,
    endian: std.builtin.Endian = .little,
    absolute_position: usize = 0,

    const Self = @This();

    pub fn writeBool(self: *Self, value: bool) !void {
        const byte: u8 = switch (value) {
            false => 0,
            true => 1,
        };
        try self.dest_writer.writeByte(byte);
        self.absolute_position += 1;
    }

    pub fn writeInt(self: *Self, comptime Type: type, value: Type) !void {
        const info = switch (@typeInfo(Type)) {
            .int => |*info| info,
            else => @compileError("Expecting Type to be a int type but got: " ++ @typeName(Type)),
        };
        const write_bytes = comptime std.math.divCeil(comptime_int, info.bits, std.mem.byte_size_in_bits) catch {
            @compileError(std.fmt.comptimePrint(
                "Failed to ceil devide {} with {}.",
                .{ info.bits, std.mem.byte_size_in_bits },
            ));
        };
        const WriteType = @Type(.{ .int = .{
            .signedness = info.signedness,
            .bits = write_bytes * std.mem.byte_size_in_bits,
        } });
        const write_value: WriteType = @intCast(value);
        try self.dest_writer.writeInt(WriteType, write_value, self.endian);
        self.absolute_position += write_bytes;
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

    pub fn writeEnum(self: *Self, comptime Type: type, value: Type) !void {
        const info = switch (@typeInfo(Type)) {
            .@"enum" => |*info| info,
            else => @compileError("Expecting Type to be a enum type but got: " ++ @typeName(Type)),
        };
        const IntType = info.tag_type;
        const int_value: IntType = @intFromEnum(value);
        return self.writeInt(IntType, int_value);
    }

    pub fn writeBytes(self: *Self, bytes: []const u8) !void {
        try self.dest_writer.writeAll(bytes);
        self.absolute_position += bytes.len;
    }

    pub fn writeZeroes(self: *Self, number_of_bytes: usize) !void {
        for (0..number_of_bytes) |_| {
            try self.dest_writer.writeByte(0);
            self.absolute_position += 1;
        }
    }

    pub fn flush(self: *Self) !void {
        try self.dest_writer.flush();
    }
};

pub const ByteReader = struct {
    src_reader: *std.io.Reader,
    endian: std.builtin.Endian = .little,
    absolute_position: usize = 0,

    const Self = @This();

    pub fn readBool(self: *Self) !bool {
        const byte = try self.src_reader.takeByte();
        self.absolute_position += 1;
        return switch (byte) {
            0 => false,
            1 => true,
            else => error.InvalidValue,
        };
    }

    pub fn readInt(self: *Self, comptime Type: type) !Type {
        const info = switch (@typeInfo(Type)) {
            .int => |*info| info,
            else => @compileError("Expecting Type to be a int type but got: " ++ @typeName(Type)),
        };
        const read_bytes = comptime std.math.divCeil(comptime_int, info.bits, std.mem.byte_size_in_bits) catch {
            @compileError(std.fmt.comptimePrint(
                "Failed to ceil devide {} with {}.",
                .{ info.bits, std.mem.byte_size_in_bits },
            ));
        };
        const ReadType = @Type(.{ .int = .{
            .signedness = info.signedness,
            .bits = read_bytes * std.mem.byte_size_in_bits,
        } });
        const read_value = try self.src_reader.takeInt(ReadType, self.endian);
        self.absolute_position += read_bytes;
        return std.math.cast(Type, read_value) orelse error.InvalidValue;
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

    pub fn readEnum(self: *Self, comptime Type: type) !Type {
        const info = switch (@typeInfo(Type)) {
            .@"enum" => |*info| info,
            else => @compileError("Expecting Type to be a enum type but got: " ++ @typeName(Type)),
        };
        const IntType = info.tag_type;
        const int_value = try self.readInt(IntType);
        inline for (info.fields) |*field| {
            if (field.value == int_value) {
                return @enumFromInt(int_value);
            }
        }
        return error.InvalidValue;
    }

    pub fn readBytes(self: *Self, buffer: []u8) !void {
        try self.src_reader.readSliceAll(buffer);
        self.absolute_position += buffer.len;
    }

    pub fn skip(self: *Self, number_of_bytes: usize) !void {
        try self.src_reader.discardAll(number_of_bytes);
        self.absolute_position += number_of_bytes;
    }
};

const testing = std.testing;

test "ByteReader.readBool should read the same value that ByteWriter.writeBool wrote" {
    var buffer: [16]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
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
    var reader = ByteReader{ .src_reader = &src_reader };
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

test "ByteReader.readBool should return error.InvalidValue when the red byte is invalid value" {
    var buffer: [3]u8 = .{ 0, 1, 2 };
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(false, reader.readBool());
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(error.InvalidValue, reader.readBool());
}

test "ByteReader.readInt should read the same value that ByteWriter.writeInt wrote" {
    var buffer: [80]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
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
    var reader = ByteReader{ .src_reader = &src_reader };
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

test "ByteReader.readInt should return error.InvalidValue when the red bytes can not be casted to the int" {
    var buffer: [5]u8 = .{ 0, 1, 2, 3, 4 };
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(0, reader.readInt(u2));
    try testing.expectEqual(1, reader.readInt(u2));
    try testing.expectEqual(2, reader.readInt(u2));
    try testing.expectEqual(3, reader.readInt(u2));
    try testing.expectEqual(error.InvalidValue, reader.readInt(u2));
}

test "ByteReader.readFloat should read the same value that ByteWriter.writeFloat wrote" {
    var buffer: [14]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try writer.writeFloat(f16, 1.2);
    try writer.writeFloat(f32, -3.4);
    try writer.writeFloat(f64, 5.6);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(1.2, reader.readFloat(f16));
    try testing.expectEqual(-3.4, reader.readFloat(f32));
    try testing.expectEqual(5.6, reader.readFloat(f64));
}

test "ByteReader.readEnum should read the same value that ByteWriter.writeEnum wrote" {
    const Enum = enum { a, b, c };
    var buffer: [3]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try writer.writeEnum(Enum, .a);
    try writer.writeEnum(Enum, .b);
    try writer.writeEnum(Enum, .c);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(.a, reader.readEnum(Enum));
    try testing.expectEqual(.b, reader.readEnum(Enum));
    try testing.expectEqual(.c, reader.readEnum(Enum));
}

test "ByteReader.readEnum should return error.InvalidValue when the red bytes don't represent any enum variant" {
    const Enum = enum(u4) { a = 0, b = 1, c = 2 };
    var buffer: [5]u8 = .{ 0, 1, 2, 3, 4 };
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(.a, reader.readEnum(Enum));
    try testing.expectEqual(.b, reader.readEnum(Enum));
    try testing.expectEqual(.c, reader.readEnum(Enum));
    try testing.expectEqual(error.InvalidValue, reader.readEnum(Enum));
    try testing.expectEqual(error.InvalidValue, reader.readEnum(Enum));
}

test "BitReader.readBytes should read the same value that ByteWriter.writeBytes wrote" {
    var buffer: [9]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try writer.writeBytes("123");
    try writer.writeBytes("456");
    try writer.writeBytes("789");
    try writer.flush();

    var bytes: [3]u8 = undefined;
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("123", &bytes);
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("456", &bytes);
    try reader.readBytes(&bytes);
    try testing.expectEqualStrings("789", &bytes);
}

test "ByteWriter.writeZeroes should write correct number of zero bytes" {
    var buffer: [20]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(true);
    try writer.writeZeroes(1);
    try writer.writeBool(true);
    try writer.writeZeroes(2);
    try writer.writeBool(true);
    try writer.writeZeroes(4);
    try writer.writeBool(true);
    try writer.writeZeroes(8);
    try writer.writeBool(true);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u8));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u16));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u32));
    try testing.expectEqual(true, reader.readBool());
    try testing.expectEqual(0, reader.readInt(u64));
    try testing.expectEqual(true, reader.readBool());
}

test "ByteReader.skip should skip correct number of bytes" {
    var buffer: [20]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try writer.writeBool(true);
    try writer.writeZeroes(1);
    try writer.writeBool(true);
    try writer.writeZeroes(2);
    try writer.writeBool(true);
    try writer.writeZeroes(4);
    try writer.writeBool(true);
    try writer.writeZeroes(8);
    try writer.writeBool(true);
    try writer.flush();

    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(1);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(2);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(4);
    try testing.expectEqual(true, reader.readBool());
    try reader.skip(8);
    try testing.expectEqual(true, reader.readBool());
}

test "BitWriter.absolute_position and BitReader.absolute_position should have correct values" {
    var buffer: [12]u8 = undefined;

    var dest_writer = std.io.Writer.fixed(&buffer);
    var writer = ByteWriter{ .dest_writer = &dest_writer };
    try testing.expectEqual(0, writer.absolute_position);
    try writer.writeBool(false);
    try testing.expectEqual(1, writer.absolute_position);
    try writer.writeInt(u3, 0);
    try testing.expectEqual(2, writer.absolute_position);
    try writer.writeFloat(f32, 0);
    try testing.expectEqual(6, writer.absolute_position);
    try writer.writeBytes(&.{ 0, 0, 0 });
    try testing.expectEqual(9, writer.absolute_position);
    try writer.writeZeroes(3);
    try testing.expectEqual(12, writer.absolute_position);
    try writer.flush();
    try testing.expectEqual(12, writer.absolute_position);

    var bytes: [3]u8 = undefined;
    var src_reader = std.io.Reader.fixed(&buffer);
    var reader = ByteReader{ .src_reader = &src_reader };
    try testing.expectEqual(0, reader.absolute_position);
    _ = try reader.readBool();
    try testing.expectEqual(1, reader.absolute_position);
    _ = try reader.readInt(u3);
    try testing.expectEqual(2, reader.absolute_position);
    _ = try reader.readFloat(f32);
    try testing.expectEqual(6, reader.absolute_position);
    try reader.readBytes(&bytes);
    try testing.expectEqual(9, reader.absolute_position);
    try reader.skip(3);
    try testing.expectEqual(12, reader.absolute_position);
}
