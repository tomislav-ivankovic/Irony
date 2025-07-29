const std = @import("std");
const imgui = @import("imgui");
const math = @import("root.zig");

pub const vector_tag = opaque {};

pub fn Vector(comptime size: usize, comptime Element: type) type {
    if (@typeInfo(Element) != .int and @typeInfo(Element) != .float) {
        @compileError("Expected a int or float type argument but got type: " ++ @typeName(Element));
    }
    return extern struct {
        array: Array,

        const Self = @This();
        pub const Array = [size]Element;
        pub const Coords = switch (size) {
            0 => void,
            1 => extern struct { x: Element },
            2 => extern struct { x: Element, y: Element },
            3 => extern struct { x: Element, y: Element, z: Element },
            else => extern struct { x: Element, y: Element, z: Element, w: Element },
        };
        pub const Color = switch (size) {
            0 => void,
            1 => extern struct { r: Element },
            2 => extern struct { r: Element, g: Element },
            3 => extern struct { r: Element, g: Element, b: Element },
            else => extern struct { r: Element, g: Element, b: Element, a: Element },
        };

        pub const tag = vector_tag;
        pub const zero = Self.fill(0);
        pub const ones = Self.fill(1);
        pub const plus_x = Self.fromAxis(0);
        pub const plus_y = Self.fromAxis(1);
        pub const plus_z = Self.fromAxis(2);
        pub const plus_w = Self.fromAxis(3);
        pub const minus_x = plus_x.negate();
        pub const minus_y = plus_y.negate();
        pub const minus_z = plus_z.negate();
        pub const minus_w = plus_w.negate();

        pub fn fromArray(array: Array) Self {
            return .{ .array = array };
        }

        pub fn fromCoords(coords: Coords) Self {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @bitCast(coords);
        }

        pub fn fromColor(color: Color) Self {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @bitCast(color);
        }

        pub fn fill(value: Element) Self {
            return .{ .array = [1]Element{value} ** size };
        }

        pub fn fromAxis(comptime axis_index: usize) Self {
            if (axis_index >= size) {
                @compileError(std.fmt.comptimePrint(
                    "Vector of size {} does not have a {} axis.",
                    .{ size, axis_index },
                ));
            }
            var array: Array = undefined;
            inline for (0..size) |i| {
                array[i] = if (i == axis_index) 1 else 0;
            }
            return .{ .array = array };
        }

        pub fn toCoords(self: Self) Coords {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @bitCast(self);
        }

        pub fn asCoords(self: *Self) *Coords {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @ptrCast(self);
        }

        pub fn asConstCoords(self: *const Self) *const Coords {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @ptrCast(self);
        }

        pub fn toColor(self: Self) Color {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @bitCast(self);
        }

        pub fn asColor(self: *Self) *Color {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @ptrCast(self);
        }

        pub fn asConstColor(self: *const Self) *const Color {
            if (size > 4) {
                @compileError("This operation is not defined for vectors larger then 4D.");
            }
            return @ptrCast(self);
        }

        pub fn x(self: Self) Element {
            if (size < 1) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a X component.", .{size}));
            }
            return self.array[0];
        }

        pub fn y(self: Self) Element {
            if (size < 2) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a Y component.", .{size}));
            }
            return self.array[1];
        }

        pub fn z(self: Self) Element {
            if (size < 3) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a Z component.", .{size}));
            }
            return self.array[2];
        }

        pub fn w(self: Self) Element {
            if (size < 4) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a W component.", .{size}));
            }
            return self.array[3];
        }

        pub fn r(self: Self) Element {
            if (size < 1) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a R component.", .{size}));
            }
            return self.array[0];
        }

        pub fn g(self: Self) Element {
            if (size < 2) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a G component.", .{size}));
            }
            return self.array[1];
        }

        pub fn b(self: Self) Element {
            if (size < 3) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a B component.", .{size}));
            }
            return self.array[2];
        }

        pub fn a(self: Self) Element {
            if (size < 4) {
                @compileError(std.fmt.comptimePrint("Vector of size {} does not have a A component.", .{size}));
            }
            return self.array[3];
        }

        pub fn swizzle(self: Self, comptime query: []const u8) Vector(query.len, Element) {
            var array: [query.len]Element = undefined;
            inline for (query, 0..) |character, query_index| {
                const self_index = switch (character) {
                    'x', 'X', 'r', 'R' => 0,
                    'y', 'Y', 'g', 'G' => 1,
                    'z', 'Z', 'b', 'B' => 2,
                    'w', 'W', 'a', 'A' => 3,
                    '0'...'9' => character - '0',
                    else => @compileError(std.fmt.comptimePrint("Invalid swizzle character: '{c}'", .{character})),
                };
                if (self_index >= size) {
                    @compileError(std.fmt.comptimePrint(
                        "Vector of size {} does not have a '{c}' component.",
                        .{ size, character },
                    ));
                }
                array[query_index] = self.array[self_index];
            }
            return .{ .array = array };
        }

        pub fn extend(self: Self, value: Element) Vector(size + 1, Element) {
            return .{ .array = self.array ++ [1]Element{value} };
        }

        pub fn shrink(self: Self, comptime new_size: usize) Vector(new_size, Element) {
            if (new_size > size) {
                @compileError(std.fmt.comptimePrint(
                    "Can not shrink a vector from size {} to size {}.",
                    .{ size, new_size },
                ));
            }
            var array: [new_size]Element = undefined;
            inline for (0..new_size) |index| {
                array[index] = self.array[index];
            }
            return .{ .array = array };
        }

        const ImVec = switch (Element) {
            f32 => switch (size) {
                1 => imgui.ImVec1,
                2 => imgui.ImVec2,
                4 => imgui.ImVec4,
                else => void,
            },
            i16 => switch (size) {
                2 => imgui.ImVec2ih,
                else => void,
            },
            else => void,
        };

        pub fn fromImVec(vec: ImVec) Self {
            if (ImVec == void) {
                @compileError("Imgui does not have a type that is equivalent to: " ++ @typeName(Self));
            }
            return @bitCast(vec);
        }

        pub fn toImVec(self: Self) ImVec {
            if (ImVec == void) {
                @compileError("Imgui does not have a type that is equivalent to: " ++ @typeName(Self));
            }
            return @bitCast(self);
        }

        pub fn asImVec(self: *Self) *ImVec {
            if (ImVec == void) {
                @compileError("Imgui does not have a type that is equivalent to: " ++ @typeName(Self));
            }
            return @ptrCast(self);
        }

        pub fn asConstImVec(self: *const Self) *const ImVec {
            if (ImVec == void) {
                @compileError("Imgui does not have a type that is equivalent to: " ++ @typeName(Self));
            }
            return @ptrCast(self);
        }

        pub fn lengthSquared(self: Self) Element {
            var result: Element = 0;
            inline for (self.array) |element| {
                result += element * element;
            }
            return result;
        }

        pub fn length(self: Self) Element {
            const squared = self.lengthSquared();
            return std.math.sqrt(squared);
        }

        pub fn normalize(self: Self) Self {
            const len = self.length();
            if (len == 0) {
                std.log.warn("Attempting to normalize a zero vector {}. Skipping normalization.", .{self});
                return self;
            }
            return self.scaleDown(len);
        }

        pub fn isNormalized(self: Self, tolerance: Element) bool {
            const lenSquared = self.lengthSquared();
            return std.math.approxEqAbs(Element, lenSquared, 1, tolerance);
        }

        pub fn isZero(self: Self, tolerance: Element) bool {
            const lenSquared = self.lengthSquared();
            return std.math.approxEqAbs(Element, lenSquared, 0, tolerance);
        }

        pub fn scale(self: Self, value: Element) Self {
            var result: Self = undefined;
            inline for (self.array, 0..) |element, index| {
                result.array[index] = element * value;
            }
            return result;
        }

        pub fn scaleDown(self: Self, value: Element) Self {
            var result: Self = undefined;
            inline for (self.array, 0..) |element, index| {
                result.array[index] = element / value;
            }
            return result;
        }

        pub fn negate(self: Self) Self {
            var result: Self = undefined;
            inline for (self.array, 0..) |element, index| {
                result.array[index] = -element;
            }
            return result;
        }

        pub fn add(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element + other_element;
            }
            return result;
        }

        pub fn subtract(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element - other_element;
            }
            return result;
        }

        pub fn multiply(self: Self, matrix: math.Matrix(size, Element)) Self {
            var result = zero;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[j] += self.array[i] * matrix.array[i][j];
                }
            }
            return result;
        }

        pub fn multiplyElements(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element * other_element;
            }
            return result;
        }

        pub fn divideElements(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element / other_element;
            }
            return result;
        }

        pub fn minElements(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = @min(self_element, other_element);
            }
            return result;
        }

        pub fn maxElements(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = @max(self_element, other_element);
            }
            return result;
        }

        pub fn lerpElements(self: Self, other: Self, t: Element) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = std.math.lerp(self_element, other_element, t);
            }
            return result;
        }

        pub fn dot(self: Self, other: Self) Element {
            var result: Element = 0;
            inline for (self.array, other.array) |self_element, other_element| {
                result += self_element * other_element;
            }
            return result;
        }

        pub fn cross(self: Self, other: Self) switch (size) {
            2 => Element,
            3 => Self,
            else => @compileError(std.fmt.comptimePrint(
                "Cross product is not defined for vectors of size: {}",
                .{size},
            )),
        } {
            return switch (size) {
                2 => (self.x() * other.y()) - (self.y() * other.x()),
                3 => Self.fromArray(.{
                    self.y() * other.z() - self.z() * other.y(),
                    self.z() * other.x() - self.x() * other.z(),
                    self.x() * other.y() - self.y() * other.x(),
                }),
                else => @compileError(std.fmt.comptimePrint(
                    "Cross product is not defined for vectors of size: {}",
                    .{size},
                )),
            };
        }

        pub fn distanceSquaredTo(self: Self, other: Self) Element {
            return other.subtract(self).lengthSquared();
        }

        pub fn distanceTo(self: Self, other: Self) Element {
            return other.subtract(self).length();
        }

        pub fn angleTo(self: Self, other: Self) Element {
            const dot_product = self.dot(other);
            const self_len = self.length();
            const other_len = other.length();
            if (self_len == 0 or other_len == 0) {
                std.log.warn(
                    "Attempting to find angle between vectors {} and {}. However, one of the vectors is zero." ++
                        "Returning fallback angle 0.",
                    .{ self, other },
                );
                return 0;
            }
            const cos_angle = dot_product / (self_len * other_len);
            const clamped = std.math.clamp(cos_angle, -1, 1);
            return std.math.acos(clamped);
        }

        pub fn projectOnto(self: Self, other: Self) Self {
            const dot_product = self.dot(other);
            const other_len_squared = other.lengthSquared();
            if (other_len_squared == 0) {
                std.log.warn(
                    "Attempting to project a vector {} onto a zero vector {}. Skipping projection.",
                    .{ self, other },
                );
                return self;
            }
            return other.scale(dot_product).scaleDown(other_len_squared);
        }

        pub fn rotateX(self: Self, rotation: Element) Self {
            if (size < 3) {
                @compileError("This operation is only defined for 3D or larger vectors.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = self;
            result.array[1] = (cos * self.array[1]) + (-sin * self.array[2]);
            result.array[2] = (sin * self.array[1]) + (cos * self.array[2]);
            return result;
        }

        pub fn rotateY(self: Self, rotation: Element) Self {
            if (size < 3) {
                @compileError("This operation is only defined for 3D or larger vectors.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = self;
            result.array[0] = (cos * self.array[0]) + (-sin * self.array[2]);
            result.array[2] = (sin * self.array[0]) + (cos * self.array[2]);
            return result;
        }

        pub fn rotateZ(self: Self, rotation: Element) Self {
            if (size < 2) {
                @compileError("This operation is only defined for 2D or larger vectors.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = self;
            result.array[0] = (cos * self.array[0]) + (-sin * self.array[1]);
            result.array[1] = (sin * self.array[0]) + (cos * self.array[1]);
            return result;
        }

        pub fn rotateAround(self: Self, other: Self, rotation: Element) Self {
            const axis = other.normalize();
            const cross_product = axis.cross(self);
            const dot_product = axis.dot(self);
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            return self.scale(cos).add(cross_product.scale(sin)).add(axis.scale(dot_product * (1 - cos)));
        }

        pub fn pointTransform(self: Self, matrix: math.Matrix(size + 1, Element)) Self {
            const homogeneous_input = self.extend(1);
            const homogeneous_result = homogeneous_input.multiply(matrix);
            var homogeneous_coordinate = homogeneous_result.array[size];
            if (homogeneous_coordinate == 0) {
                std.log.warn(
                    "After point transformation of {}, the resulting vector {} has a zero homogeneous coordinate." ++
                        "Using fallback homogeneous coordinate value of 1. The transformation matrix was:\n{}",
                    .{ self, homogeneous_result, matrix },
                );
                homogeneous_coordinate = 1;
            }
            return homogeneous_result.shrink(size).scaleDown(homogeneous_coordinate);
        }

        pub fn directionTransform(self: Self, matrix: math.Matrix(size + 1, Element)) Self {
            const homogeneous_input = self.extend(0);
            const homogeneous_result = homogeneous_input.multiply(matrix);
            return homogeneous_result.shrink(size);
        }

        pub fn format(
            self: Self,
            comptime fmt: []const u8,
            options: std.fmt.FormatOptions,
            writer: anytype,
        ) !void {
            _ = options;
            if (fmt.len != 0) {
                @compileError(std.fmt.comptimePrint(
                    "Invalid vector format {{{s}}}. The only allowed format for vectors is {{}}.",
                    .{fmt},
                ));
            }
            try writer.writeByte('{');
            inline for (self.array, 0..) |element, index| {
                try writer.print("{}", .{element});
                if (index < size - 1) {
                    try writer.writeAll(", ");
                }
            }
            try writer.writeByte('}');
        }
    };
}

const testing = std.testing;

test "zero should have correct value" {
    const vec = Vector(4, f32).zero;
    try testing.expectEqual(.{ 0, 0, 0, 0 }, vec.array);
}

test "ones should have correct value" {
    const vec = Vector(4, f32).ones;
    try testing.expectEqual(.{ 1, 1, 1, 1 }, vec.array);
}

test "fromArray should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.array);
}

test "fromCoords should return correct value" {
    const vec = Vector(4, f32).fromCoords(.{ .x = 1, .y = 2, .z = 3, .w = 4 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.array);
}

test "fromColor should return correct value" {
    const vec = Vector(4, f32).fromColor(.{ .r = 1, .g = 2, .b = 3, .a = 4 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.array);
}

test "fill should return correct value" {
    const vec = Vector(4, f32).fill(123);
    try testing.expectEqual(.{ 123, 123, 123, 123 }, vec.array);
}

test "fromAxis should return correct value" {
    const vec = Vector(4, f32).fromAxis(2);
    try testing.expectEqual(.{ 0, 0, 1, 0 }, vec.array);
}

test "toCoords should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(Vector(4, f32).Coords{ .x = 1, .y = 2, .z = 3, .w = 4 }, vec.toCoords());
}

test "asCoords should return correct value" {
    var vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(&vec.array[0], &vec.asCoords().x);
    try testing.expectEqual(&vec.array[1], &vec.asCoords().y);
    try testing.expectEqual(&vec.array[2], &vec.asCoords().z);
    try testing.expectEqual(&vec.array[3], &vec.asCoords().w);
}

test "asConstCoords should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(&vec.array[0], &vec.asConstCoords().x);
    try testing.expectEqual(&vec.array[1], &vec.asConstCoords().y);
    try testing.expectEqual(&vec.array[2], &vec.asConstCoords().z);
    try testing.expectEqual(&vec.array[3], &vec.asConstCoords().w);
}

test "toColor should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(Vector(4, f32).Color{ .r = 1, .g = 2, .b = 3, .a = 4 }, vec.toColor());
}

test "asColor should return correct value" {
    var vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(&vec.array[0], &vec.asColor().r);
    try testing.expectEqual(&vec.array[1], &vec.asColor().g);
    try testing.expectEqual(&vec.array[2], &vec.asColor().b);
    try testing.expectEqual(&vec.array[3], &vec.asColor().a);
}

test "asConstColor should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(&vec.array[0], &vec.asConstColor().r);
    try testing.expectEqual(&vec.array[1], &vec.asConstColor().g);
    try testing.expectEqual(&vec.array[2], &vec.asConstColor().b);
    try testing.expectEqual(&vec.array[3], &vec.asConstColor().a);
}

test "x,y,z,w should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(1, vec.x());
    try testing.expectEqual(2, vec.y());
    try testing.expectEqual(3, vec.z());
    try testing.expectEqual(4, vec.w());
}

test "r,g,b,a should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(1, vec.r());
    try testing.expectEqual(2, vec.g());
    try testing.expectEqual(3, vec.b());
    try testing.expectEqual(4, vec.a());
}

test "swizzle should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 4, 3, 2, 1 }, vec.swizzle("wzyx").array);
    try testing.expectEqual(.{ 4, 3, 2, 1 }, vec.swizzle("abgr").array);
    try testing.expectEqual(.{ 4, 3, 2, 1 }, vec.swizzle("3210").array);
    try testing.expectEqual(.{1}, vec.swizzle("x").array);
    try testing.expectEqual(.{ 1, 2 }, vec.swizzle("xy").array);
    try testing.expectEqual(.{ 1, 2, 3 }, vec.swizzle("xyz").array);
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.swizzle("xyzw").array);
    try testing.expectEqual(.{ 1, 1, 2, 2, 3, 3, 4, 4 }, vec.swizzle("xxyyzzww").array);
}

test "extend should return correct value" {
    const vec = Vector(3, f32).fromArray(.{ 1, 2, 3 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.extend(4).array);
}

test "shrink should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 1, 2, 3 }, vec.shrink(3).array);
}

test "fromImVec should return correct value" {
    try testing.expectEqual(
        .{1},
        Vector(1, f32).fromImVec(imgui.ImVec1{ .x = 1 }).array,
    );
    try testing.expectEqual(
        .{ 1, 2 },
        Vector(2, f32).fromImVec(imgui.ImVec2{ .x = 1, .y = 2 }).array,
    );
    try testing.expectEqual(
        .{ 1, 2, 3, 4 },
        Vector(4, f32).fromImVec(imgui.ImVec4{ .x = 1, .y = 2, .z = 3, .w = 4 }).array,
    );
    try testing.expectEqual(
        .{ 1, 2 },
        Vector(2, i16).fromImVec(imgui.ImVec2ih{ .x = 1, .y = 2 }).array,
    );
}

test "toImVec should return correct value" {
    try testing.expectEqual(
        imgui.ImVec1{ .x = 1 },
        Vector(1, f32).fromArray(.{1}).toImVec(),
    );
    try testing.expectEqual(
        imgui.ImVec2{ .x = 1, .y = 2 },
        Vector(2, f32).fromArray(.{ 1, 2 }).toImVec(),
    );
    try testing.expectEqual(
        imgui.ImVec4{ .x = 1, .y = 2, .z = 3, .w = 4 },
        Vector(4, f32).fromArray(.{ 1, 2, 3, 4 }).toImVec(),
    );
    try testing.expectEqual(
        imgui.ImVec2ih{ .x = 1, .y = 2 },
        Vector(2, i16).fromArray(.{ 1, 2 }).toImVec(),
    );
}

test "asImVec should return correct value" {
    var vec_1 = Vector(1, f32).fromArray(.{1});
    var vec_2 = Vector(2, f32).fromArray(.{ 1, 2 });
    var vec_4 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    var vec_2_i = Vector(2, i16).fromArray(.{ 1, 2 });
    try testing.expectEqual(&vec_1.array[0], &vec_1.asImVec().x);
    try testing.expectEqual(&vec_2.array[0], &vec_2.asImVec().x);
    try testing.expectEqual(&vec_2.array[1], &vec_2.asImVec().y);
    try testing.expectEqual(&vec_4.array[0], &vec_4.asImVec().x);
    try testing.expectEqual(&vec_4.array[1], &vec_4.asImVec().y);
    try testing.expectEqual(&vec_4.array[2], &vec_4.asImVec().z);
    try testing.expectEqual(&vec_4.array[3], &vec_4.asImVec().w);
    try testing.expectEqual(&vec_2_i.array[0], &vec_2_i.asImVec().x);
    try testing.expectEqual(&vec_2_i.array[1], &vec_2_i.asImVec().y);
}

test "asConstImVec should return correct value" {
    const vec_1 = Vector(1, f32).fromArray(.{1});
    const vec_2 = Vector(2, f32).fromArray(.{ 1, 2 });
    const vec_4 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2_i = Vector(2, i16).fromArray(.{ 1, 2 });
    try testing.expectEqual(&vec_1.array[0], &vec_1.asConstImVec().x);
    try testing.expectEqual(&vec_2.array[0], &vec_2.asConstImVec().x);
    try testing.expectEqual(&vec_2.array[1], &vec_2.asConstImVec().y);
    try testing.expectEqual(&vec_4.array[0], &vec_4.asConstImVec().x);
    try testing.expectEqual(&vec_4.array[1], &vec_4.asConstImVec().y);
    try testing.expectEqual(&vec_4.array[2], &vec_4.asConstImVec().z);
    try testing.expectEqual(&vec_4.array[3], &vec_4.asConstImVec().w);
    try testing.expectEqual(&vec_2_i.array[0], &vec_2_i.asConstImVec().x);
    try testing.expectEqual(&vec_2_i.array[1], &vec_2_i.asConstImVec().y);
}

test "lengthSquared should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(30, vec.lengthSquared());
}

test "length should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(std.math.sqrt(30.0), vec.length());
}

test "normalize should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const sqrt30: f32 = std.math.sqrt(30.0);
    try testing.expectEqual(.{ 1 / sqrt30, 2 / sqrt30, 3 / sqrt30, 4 / sqrt30 }, vec.normalize().array);
}

test "isNormalized should return correct value" {
    const sqrt30: f32 = std.math.sqrt(30.0);
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 1 / sqrt30, 2 / sqrt30, 3 / sqrt30, 4 / sqrt30 });
    try testing.expectEqual(false, vec_1.isNormalized(0.00001));
    try testing.expectEqual(true, vec_2.isNormalized(0.00001));
}

test "isZero should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).zero;
    const vec_3 = Vector(4, f32).fromArray(.{ 0.000001, -0.000001, 0, 0 });
    try testing.expectEqual(false, vec_1.isZero(0.00001));
    try testing.expectEqual(true, vec_2.isZero(0.00001));
    try testing.expectEqual(true, vec_3.isZero(0.00001));
}

test "scale should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 5, 10, 15, 20 }, vec.scale(5).array);
    try testing.expectEqual(.{ -5, -10, -15, -20 }, vec.scale(-5).array);
}

test "scaleDown should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 5, 10, 15, 20 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.scaleDown(5).array);
    try testing.expectEqual(.{ -1, -2, -3, -4 }, vec.scaleDown(-5).array);
}

test "negate should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ -1, -2, -3, -4 }, vec.negate().array);
}

test "add should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ 6, 8, 10, 12 }, vec_1.add(vec_2).array);
}

test "subtract should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ -4, -4, -4, -4 }, vec_1.subtract(vec_2).array);
}

test "multiply should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const matrix = math.Matrix(4, f32).fromArray(.{
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
        .{ 17, 18, 19, 20 },
    });
    try testing.expectEqual(.{ 130, 140, 150, 160 }, vec.multiply(matrix).array);
}

test "multiplyElements should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ 5, 12, 21, 32 }, vec_1.multiplyElements(vec_2).array);
}

test "divideElements should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 5, 12, 21, 32 });
    const vec_2 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 5, 6, 7, 8 }, vec_1.divideElements(vec_2).array);
}

test "minElements should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 4, 5, 8 });
    const vec_2 = Vector(4, f32).fromArray(.{ 2, 3, 6, 7 });
    try testing.expectEqual(.{ 1, 3, 5, 7 }, vec_1.minElements(vec_2).array);
}

test "maxElements should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 4, 5, 8 });
    const vec_2 = Vector(4, f32).fromArray(.{ 2, 3, 6, 7 });
    try testing.expectEqual(.{ 2, 4, 6, 8 }, vec_1.maxElements(vec_2).array);
}

test "lerpElements should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ 4, 5, 6, 7 }, vec_1.lerpElements(vec_2, 0.75).array);
}

test "dot should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(70, vec_1.dot(vec_2));
}

test "cross should return correct value when 2D vectors" {
    const vec_1 = Vector(2, f32).fromArray(.{ 1, 2 });
    const vec_2 = Vector(2, f32).fromArray(.{ 3, 4 });
    try testing.expectEqual(-2, vec_1.cross(vec_2));
}

test "cross should return correct value when 3D vectors" {
    const vec_1 = Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const vec_2 = Vector(3, f32).fromArray(.{ 4, 5, 6 });
    try testing.expectEqual(.{ -3, 6, -3 }, vec_1.cross(vec_2).array);
}

test "distanceSquaredTo should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(64, vec_1.distanceSquaredTo(vec_2));
}

test "distanceTo should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(8, vec_1.distanceTo(vec_2));
}

test "angleTo should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectApproxEqAbs(0.250196, vec_1.angleTo(vec_2), 0.00001);
}

test "projectOnto should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ 175.0 / 87.0, 70.0 / 29.0, 245.0 / 87.0, 280.0 / 87.0 }, vec_1.projectOnto(vec_2).array);
}

test "rotateX should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const rotated = vec.rotateX(0.5 * std.math.pi);
    try testing.expectApproxEqAbs(1, rotated.x(), 0.00001);
    try testing.expectApproxEqAbs(-3, rotated.y(), 0.00001);
    try testing.expectApproxEqAbs(2, rotated.z(), 0.00001);
}

test "rotateY should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const rotated = vec.rotateY(0.5 * std.math.pi);
    try testing.expectApproxEqAbs(-3, rotated.x(), 0.00001);
    try testing.expectApproxEqAbs(2, rotated.y(), 0.00001);
    try testing.expectApproxEqAbs(1, rotated.z(), 0.00001);
}

test "rotateZ should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const rotated = vec.rotateZ(0.5 * std.math.pi);
    try testing.expectApproxEqAbs(-2, rotated.x(), 0.00001);
    try testing.expectApproxEqAbs(1, rotated.y(), 0.00001);
    try testing.expectApproxEqAbs(3, rotated.z(), 0.00001);
}

test "rotateAround should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const around = math.Vector(3, f32).fromArray(.{ 1, 1, 1 });
    const rotated = vec.rotateAround(around, (2.0 / 3.0) * std.math.pi);
    try testing.expectApproxEqAbs(3, rotated.x(), 0.00001);
    try testing.expectApproxEqAbs(1, rotated.y(), 0.00001);
    try testing.expectApproxEqAbs(2, rotated.z(), 0.00001);
}

test "pointTransform should return correct value" {
    const vec = Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix_1 = math.Matrix(4, f32).fromArray(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 1, 2, 3, 1 },
    });
    try testing.expectEqual(.{ 2, 4, 6 }, vec.pointTransform(matrix_1).array);
    const matrix_2 = math.Matrix(4, f32).fromArray(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 2, 0, 0 },
        .{ 0, 0, 3, 0 },
        .{ 0, 0, 0, 1 },
    });
    try testing.expectEqual(.{ 1, 4, 9 }, vec.pointTransform(matrix_2).array);
}

test "directionTransform should return correct value" {
    const vec = Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix_1 = math.Matrix(4, f32).fromArray(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 1, 2, 3, 1 },
    });
    try testing.expectEqual(.{ 1, 2, 3 }, vec.directionTransform(matrix_1).array);
    const matrix_2 = math.Matrix(4, f32).fromArray(.{
        .{ 1, 0, 0, 0 },
        .{ 0, 2, 0, 0 },
        .{ 0, 0, 3, 0 },
        .{ 0, 0, 0, 1 },
    });
    try testing.expectEqual(.{ 1, 4, 9 }, vec.directionTransform(matrix_2).array);
}

test "should format correctly" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const string = try std.fmt.allocPrint(testing.allocator, "{}", .{vec});
    defer testing.allocator.free(string);
    try testing.expectEqualStrings("{1e0, 2e0, 3e0, 4e0}", string);
}
