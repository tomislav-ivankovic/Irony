const std = @import("std");
const imgui = @import("imgui");

pub fn Vector(comptime size: usize, comptime Element: type) type {
    if (@typeInfo(Element) != .int and @typeInfo(Element) != .float) {
        @compileError("Expected a int or float type argument but got type: " ++ @typeName(Element));
    }
    return extern struct {
        array: [size]Element,

        const Self = @This();

        pub fn fromArray(array: [size]Element) Self {
            return .{ .array = array };
        }

        pub fn fill(value: Element) Self {
            return .{ .array = [1]Element{value} ** size };
        }

        pub fn zero() Self {
            return .{ .array = [1]Element{0} ** size };
        }

        pub fn ones() Self {
            return .{ .array = [1]Element{1} ** size };
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
                    @compileError(std.fmt.comptimePrint("Vector of size {} does not have a '{c}' component.", .{ size, character }));
                }
                array[query_index] = self.array[self_index];
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

        pub fn asImVecPointer(self: *Self) *ImVec {
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

        pub fn multiply(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element * other_element;
            }
            return result;
        }

        pub fn divide(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (self.array, other.array, 0..) |self_element, other_element, index| {
                result.array[index] = self_element / other_element;
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
            else => @compileError(std.fmt.comptimePrint("Cross product is not defined for vectors of size: {}", .{size})),
        } {
            return switch (size) {
                2 => (self.x() * other.y()) - (self.y() * other.x()),
                3 => Self.fromArray(.{
                    self.y() * other.z() - self.z() * other.y(),
                    self.z() * other.x() - self.x() * other.z(),
                    self.x() * other.y() - self.y() * other.x(),
                }),
                else => @compileError(std.fmt.comptimePrint("Cross product is not defined for vectors of size: {}", .{size})),
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
                return 0;
            }
            const cos_angle = dot_product / (self_len * other_len);
            const clamped = std.math.clamp(cos_angle, -1, 1);
            return std.math.acos(clamped);
        }

        pub fn projectOnto(self: Self, other: Self) Self {
            const dot_product = self.dot(other);
            const other_len_squared = other.lengthSquared();
            return other.scale(dot_product).scaleDown(other_len_squared);
        }
    };
}

const testing = std.testing;

test "fromArray should return correct value" {
    const vec = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 1, 2, 3, 4 }, vec.array);
}

test "fill should return correct value" {
    const vec = Vector(4, f32).fill(123);
    try testing.expectEqual(.{ 123, 123, 123, 123 }, vec.array);
}

test "zero should return correct value" {
    const vec = Vector(4, f32).zero();
    try testing.expectEqual(.{ 0, 0, 0, 0 }, vec.array);
}

test "ones should return correct value" {
    const vec = Vector(4, f32).ones();
    try testing.expectEqual(.{ 1, 1, 1, 1 }, vec.array);
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

test "asImVecPointer should return correct value" {
    var vec_1 = Vector(1, f32).fromArray(.{1});
    var vec_2 = Vector(2, f32).fromArray(.{ 1, 2 });
    var vec_4 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    var vec_2_i = Vector(2, i16).fromArray(.{ 1, 2 });
    try testing.expectEqual(&vec_1.array[0], &vec_1.asImVecPointer().x);
    try testing.expectEqual(&vec_2.array[0], &vec_2.asImVecPointer().x);
    try testing.expectEqual(&vec_2.array[1], &vec_2.asImVecPointer().y);
    try testing.expectEqual(&vec_4.array[0], &vec_4.asImVecPointer().x);
    try testing.expectEqual(&vec_4.array[1], &vec_4.asImVecPointer().y);
    try testing.expectEqual(&vec_4.array[2], &vec_4.asImVecPointer().z);
    try testing.expectEqual(&vec_4.array[3], &vec_4.asImVecPointer().w);
    try testing.expectEqual(&vec_2_i.array[0], &vec_2_i.asImVecPointer().x);
    try testing.expectEqual(&vec_2_i.array[1], &vec_2_i.asImVecPointer().y);
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
    const vec_2 = Vector(4, f32).zero();
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
    const vec_1 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    const vec_2 = Vector(4, f32).fromArray(.{ 5, 6, 7, 8 });
    try testing.expectEqual(.{ 5, 12, 21, 32 }, vec_1.multiply(vec_2).array);
}

test "divide should return correct value" {
    const vec_1 = Vector(4, f32).fromArray(.{ 5, 12, 21, 32 });
    const vec_2 = Vector(4, f32).fromArray(.{ 1, 2, 3, 4 });
    try testing.expectEqual(.{ 5, 6, 7, 8 }, vec_1.divide(vec_2).array);
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
