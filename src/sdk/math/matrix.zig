const std = @import("std");
const imgui = @import("imgui");
const math = @import("root.zig");

pub const matrix_tag = opaque {};

pub fn Matrix(comptime size: usize, comptime Element: type) type {
    if (@typeInfo(Element) != .int and @typeInfo(Element) != .float) {
        @compileError("Expected a int or float type argument but got type: " ++ @typeName(Element));
    }
    return extern struct {
        array: Array,

        const Self = @This();
        pub const Array = [size][size]Element;
        pub const Flat = [size * size]Element;
        pub const Coords = switch (size) {
            0 => void,
            1 => extern struct { xx: Element },
            2 => extern struct { xx: Element, xy: Element, yx: Element, yy: Element },
            3 => extern struct {
                xx: Element,
                xy: Element,
                xz: Element,
                yx: Element,
                yy: Element,
                yz: Element,
                zx: Element,
                zy: Element,
                zz: Element,
            },
            4 => extern struct {
                xx: Element,
                xy: Element,
                xz: Element,
                xw: Element,
                yx: Element,
                yy: Element,
                yz: Element,
                yw: Element,
                zx: Element,
                zy: Element,
                zz: Element,
                zw: Element,
                wx: Element,
                wy: Element,
                wz: Element,
                ww: Element,
            },
            else => void,
        };

        pub const tag = matrix_tag;
        pub const identity = block: {
            var array: Array = undefined;
            for (0..size) |i| {
                for (0..size) |j| {
                    array[i][j] = if (i == j) 1 else 0;
                }
            }
            break :block Self.fromArray(array);
        };
        pub const zero = Self.fill(0);

        pub fn fromArray(array: Array) Self {
            return .{ .array = array };
        }

        pub fn fromFlat(flat: Flat) Self {
            return @bitCast(flat);
        }

        pub fn fromCoords(coords: Coords) Self {
            if (size > 4) {
                @compileError("This operation is not defined for matrices larger then 4x4.");
            }
            return @bitCast(coords);
        }

        pub fn fill(value: Element) Self {
            const row = [1]Element{value} ** size;
            const array = [1]([size]Element){row} ** size;
            return .{ .array = array };
        }

        pub fn toFlat(self: Self) Flat {
            return @bitCast(self);
        }

        pub fn asFlat(self: *Self) *Flat {
            return @ptrCast(self);
        }

        pub fn asConstFlat(self: *const Self) *const Flat {
            return @ptrCast(self);
        }

        pub fn toCoords(self: Self) Coords {
            if (size > 4) {
                @compileError("This operation is not defined for matrices larger then 4x4.");
            }
            return @bitCast(self);
        }

        pub fn asCoords(self: *Self) *Coords {
            if (size > 4) {
                @compileError("This operation is not defined for matrices larger then 4x4.");
            }
            return @ptrCast(self);
        }

        pub fn asConstCoords(self: *const Self) *const Coords {
            if (size > 4) {
                @compileError("This operation is not defined for matrices larger then 4x4.");
            }
            return @ptrCast(self);
        }

        pub fn transpose(self: Self) Self {
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[i][j] = self.array[j][i];
                }
            }
            return result;
        }

        pub fn minorMatrix(self: Self, comptime row: usize, comptime col: usize) Matrix(size - 1, Element) {
            if (row >= size or col >= size) {
                @compileError(std.fmt.comptimePrint(
                    "Invalid matrix coordinates ({}, {}) for a {}x{} matrix.",
                    .{ row, col, size, size },
                ));
            }
            var result: Matrix(size - 1, Element) = undefined;
            inline for (0..size) |i| {
                const result_i = if (i < row) i else if (i > row) i - 1 else continue;
                inline for (0..size) |j| {
                    const result_j = if (j < col) j else if (j > col) j - 1 else continue;
                    result.array[result_i][result_j] = self.array[i][j];
                }
            }
            return result;
        }

        pub fn determinant(self: Self) Element {
            const a = &self.array;
            switch (size) {
                0 => return 1,
                1 => return a[0][0],
                2 => return a[0][0] * a[1][1] - a[0][1] * a[1][0],
                3 => return a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
                    a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
                    a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0]),
                4 => return a[0][3] * a[1][2] * a[2][1] * a[3][0] - a[0][2] * a[1][3] * a[2][1] * a[3][0] -
                    a[0][3] * a[1][1] * a[2][2] * a[3][0] + a[0][1] * a[1][3] * a[2][2] * a[3][0] +
                    a[0][2] * a[1][1] * a[2][3] * a[3][0] - a[0][1] * a[1][2] * a[2][3] * a[3][0] -
                    a[0][3] * a[1][2] * a[2][0] * a[3][1] + a[0][2] * a[1][3] * a[2][0] * a[3][1] +
                    a[0][3] * a[1][0] * a[2][2] * a[3][1] - a[0][0] * a[1][3] * a[2][2] * a[3][1] -
                    a[0][2] * a[1][0] * a[2][3] * a[3][1] + a[0][0] * a[1][2] * a[2][3] * a[3][1] +
                    a[0][3] * a[1][1] * a[2][0] * a[3][2] - a[0][1] * a[1][3] * a[2][0] * a[3][2] -
                    a[0][3] * a[1][0] * a[2][1] * a[3][2] + a[0][0] * a[1][3] * a[2][1] * a[3][2] +
                    a[0][1] * a[1][0] * a[2][3] * a[3][2] - a[0][0] * a[1][1] * a[2][3] * a[3][2] -
                    a[0][2] * a[1][1] * a[2][0] * a[3][3] + a[0][1] * a[1][2] * a[2][0] * a[3][3] +
                    a[0][2] * a[1][0] * a[2][1] * a[3][3] - a[0][0] * a[1][2] * a[2][1] * a[3][3] -
                    a[0][1] * a[1][0] * a[2][2] * a[3][3] + a[0][0] * a[1][1] * a[2][2] * a[3][3],
                else => {},
            }
            var sum: Element = 0;
            inline for (0..size) |i| {
                const sign = if (i % 2 == 0) 1 else -1;
                const element = self.array[i][0];
                const minor = self.minorMatrix(i, 0).determinant();
                sum += sign * element * minor;
            }
            return sum;
        }

        pub fn inverse(self: Self) ?Self {
            const det = self.determinant();
            if (det == 0) {
                return null;
            }
            const a = &self.array;
            switch (size) {
                0 => return Self.zero(),
                1 => return Self.fill(1 / det),
                2 => return Self.fromArray(.{
                    .{ a[1][1] / det, -a[0][1] / det },
                    .{ -a[1][0] / det, a[0][0] / det },
                }),
                3 => return Self.fromArray(.{
                    .{
                        (a[1][1] * a[2][2] - a[1][2] * a[2][1]) / det,
                        (a[0][2] * a[2][1] - a[0][1] * a[2][2]) / det,
                        (a[0][1] * a[1][2] - a[0][2] * a[1][1]) / det,
                    },
                    .{
                        (a[1][2] * a[2][0] - a[1][0] * a[2][2]) / det,
                        (a[0][0] * a[2][2] - a[0][2] * a[2][0]) / det,
                        (a[0][2] * a[1][0] - a[0][0] * a[1][2]) / det,
                    },
                    .{
                        (a[1][0] * a[2][1] - a[1][1] * a[2][0]) / det,
                        (a[0][1] * a[2][0] - a[0][0] * a[2][1]) / det,
                        (a[0][0] * a[1][1] - a[0][1] * a[1][0]) / det,
                    },
                }),
                4 => return Self.fromArray(.{
                    .{
                        (a[1][1] * (a[2][2] * a[3][3] - a[2][3] * a[3][2]) -
                            a[1][2] * (a[2][1] * a[3][3] - a[2][3] * a[3][1]) +
                            a[1][3] * (a[2][1] * a[3][2] - a[2][2] * a[3][1])) / det,
                        -(a[0][1] * (a[2][2] * a[3][3] - a[2][3] * a[3][2]) -
                            a[0][2] * (a[2][1] * a[3][3] - a[2][3] * a[3][1]) +
                            a[0][3] * (a[2][1] * a[3][2] - a[2][2] * a[3][1])) / det,
                        (a[0][1] * (a[1][2] * a[3][3] - a[1][3] * a[3][2]) -
                            a[0][2] * (a[1][1] * a[3][3] - a[1][3] * a[3][1]) +
                            a[0][3] * (a[1][1] * a[3][2] - a[1][2] * a[3][1])) / det,
                        -(a[0][1] * (a[1][2] * a[2][3] - a[1][3] * a[2][2]) -
                            a[0][2] * (a[1][1] * a[2][3] - a[1][3] * a[2][1]) +
                            a[0][3] * (a[1][1] * a[2][2] - a[1][2] * a[2][1])) / det,
                    },
                    .{
                        -(a[1][0] * (a[2][2] * a[3][3] - a[2][3] * a[3][2]) -
                            a[1][2] * (a[2][0] * a[3][3] - a[2][3] * a[3][0]) +
                            a[1][3] * (a[2][0] * a[3][2] - a[2][2] * a[3][0])) / det,
                        (a[0][0] * (a[2][2] * a[3][3] - a[2][3] * a[3][2]) -
                            a[0][2] * (a[2][0] * a[3][3] - a[2][3] * a[3][0]) +
                            a[0][3] * (a[2][0] * a[3][2] - a[2][2] * a[3][0])) / det,
                        -(a[0][0] * (a[1][2] * a[3][3] - a[1][3] * a[3][2]) -
                            a[0][2] * (a[1][0] * a[3][3] - a[1][3] * a[3][0]) +
                            a[0][3] * (a[1][0] * a[3][2] - a[1][2] * a[3][0])) / det,
                        (a[0][0] * (a[1][2] * a[2][3] - a[1][3] * a[2][2]) -
                            a[0][2] * (a[1][0] * a[2][3] - a[1][3] * a[2][0]) +
                            a[0][3] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])) / det,
                    },
                    .{
                        (a[1][0] * (a[2][1] * a[3][3] - a[2][3] * a[3][1]) -
                            a[1][1] * (a[2][0] * a[3][3] - a[2][3] * a[3][0]) +
                            a[1][3] * (a[2][0] * a[3][1] - a[2][1] * a[3][0])) / det,
                        -(a[0][0] * (a[2][1] * a[3][3] - a[2][3] * a[3][1]) -
                            a[0][1] * (a[2][0] * a[3][3] - a[2][3] * a[3][0]) +
                            a[0][3] * (a[2][0] * a[3][1] - a[2][1] * a[3][0])) / det,
                        (a[0][0] * (a[1][1] * a[3][3] - a[1][3] * a[3][1]) -
                            a[0][1] * (a[1][0] * a[3][3] - a[1][3] * a[3][0]) +
                            a[0][3] * (a[1][0] * a[3][1] - a[1][1] * a[3][0])) / det,
                        -(a[0][0] * (a[1][1] * a[2][3] - a[1][3] * a[2][1]) -
                            a[0][1] * (a[1][0] * a[2][3] - a[1][3] * a[2][0]) +
                            a[0][3] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])) / det,
                    },
                    .{
                        -(a[1][0] * (a[2][1] * a[3][2] - a[2][2] * a[3][1]) -
                            a[1][1] * (a[2][0] * a[3][2] - a[2][2] * a[3][0]) +
                            a[1][2] * (a[2][0] * a[3][1] - a[2][1] * a[3][0])) / det,
                        (a[0][0] * (a[2][1] * a[3][2] - a[2][2] * a[3][1]) -
                            a[0][1] * (a[2][0] * a[3][2] - a[2][2] * a[3][0]) +
                            a[0][2] * (a[2][0] * a[3][1] - a[2][1] * a[3][0])) / det,
                        -(a[0][0] * (a[1][1] * a[3][2] - a[1][2] * a[3][1]) -
                            a[0][1] * (a[1][0] * a[3][2] - a[1][2] * a[3][0]) +
                            a[0][2] * (a[1][0] * a[3][1] - a[1][1] * a[3][0])) / det,
                        (a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) -
                            a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0]) +
                            a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])) / det,
                    },
                }),
                else => {},
            }
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    const sign = if ((i + j) % 2 == 0) 1 else -1;
                    const minor = self.minorMatrix(i, j).determinant();
                    result.array[j][i] = sign * minor / det;
                }
            }
            return result;
        }

        pub fn add(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[i][j] = self.array[i][j] + other.array[i][j];
                }
            }
            return result;
        }

        pub fn subtract(self: Self, other: Self) Self {
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[i][j] = self.array[i][j] - other.array[i][j];
                }
            }
            return result;
        }

        pub fn multiply(self: Self, other: Self) Self {
            var result = zero;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    inline for (0..size) |k| {
                        result.array[i][j] += self.array[i][k] * other.array[k][j];
                    }
                }
            }
            return result;
        }

        pub fn scalarMultiply(self: Self, value: Element) Self {
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[i][j] = self.array[i][j] * value;
                }
            }
            return result;
        }

        pub fn scalarDivide(self: Self, value: Element) Self {
            var result: Self = undefined;
            inline for (0..size) |i| {
                inline for (0..size) |j| {
                    result.array[i][j] = self.array[i][j] / value;
                }
            }
            return result;
        }

        pub fn fromTranslation(translation: math.Vector(size - 1, Element)) Self {
            var result = identity;
            inline for (0..size - 1) |i| {
                result.array[size - 1][i] = translation.array[i];
            }
            return result;
        }

        pub fn translate(self: Self, translation: math.Vector(size - 1, Element)) Self {
            const matrix = Self.fromTranslation(translation);
            return self.multiply(matrix);
        }

        pub fn fromScale(scaling: math.Vector(size - 1, Element)) Self {
            var result = identity;
            inline for (0..size - 1) |i| {
                result.array[i][i] = scaling.array[i];
            }
            return result;
        }

        pub fn scale(self: Self, scaling: math.Vector(size - 1, Element)) Self {
            const matrix = Self.fromScale(scaling);
            return self.multiply(matrix);
        }

        pub fn fromXRotation(rotation: Element) Self {
            if (size < 3) {
                @compileError("This operation is only defined for 3x3 or larger matrices.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = identity;
            result.array[1][1] = cos;
            result.array[1][2] = sin;
            result.array[2][1] = -sin;
            result.array[2][2] = cos;
            return result;
        }

        pub fn rotateX(self: Self, rotation: Element) Self {
            const matrix = Self.fromXRotation(rotation);
            return self.multiply(matrix);
        }

        pub fn fromYRotation(rotation: Element) Self {
            if (size < 3) {
                @compileError("This operation is only defined for 3x3 or larger matrices.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = identity;
            result.array[0][0] = cos;
            result.array[0][2] = sin;
            result.array[2][0] = -sin;
            result.array[2][2] = cos;
            return result;
        }

        pub fn rotateY(self: Self, rotation: Element) Self {
            const matrix = Self.fromYRotation(rotation);
            return self.multiply(matrix);
        }

        pub fn fromZRotation(rotation: Element) Self {
            if (size < 2) {
                @compileError("This operation is only defined for 2x2 or larger matrices.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            var result = identity;
            result.array[0][0] = cos;
            result.array[0][1] = sin;
            result.array[1][0] = -sin;
            result.array[1][1] = cos;
            return result;
        }

        pub fn rotateZ(self: Self, rotation: Element) Self {
            const matrix = Self.fromZRotation(rotation);
            return self.multiply(matrix);
        }

        pub fn fromRotationAround(vector: math.Vector(3, Element), rotation: Element) Self {
            if (size < 3) {
                @compileError("This operation is only defined for 3x3 or larger matrices.");
            }
            const cos = std.math.cos(rotation);
            const sin = std.math.sin(rotation);
            const axis = if (!vector.isZero(0)) vector.normalize() else block: {
                std.log.warn(
                    "When creating a rotate around matrix, the supplied vector {f} was zero. " ++
                        "Using fallback rotation axis.",
                    .{vector},
                );
                break :block math.Vector(3, Element).plus_x;
            };
            const x = axis.array[0];
            const y = axis.array[1];
            const z = axis.array[2];
            var result = identity;
            result.array[0][0] = cos + x * x * (1 - cos);
            result.array[0][1] = y * x * (1 - cos) + z * sin;
            result.array[0][2] = z * x * (1 - cos) - y * sin;
            result.array[1][0] = x * y * (1 - cos) - z * sin;
            result.array[1][1] = cos + y * y * (1 - cos);
            result.array[2][1] = y * z * (1 - cos) - x * sin;
            result.array[2][0] = x * z * (1 - cos) + y * sin;
            result.array[1][2] = z * y * (1 - cos) + x * sin;
            result.array[2][2] = cos + z * z * (1 - cos);
            return result;
        }

        pub fn rotateAround(self: Self, vector: math.Vector(3, Element), rotation: Element) Self {
            const matrix = Self.fromRotationAround(vector, rotation);
            return self.multiply(matrix);
        }

        pub fn fromLookAt(
            eye: math.Vector(3, Element),
            target: math.Vector(3, Element),
            up: math.Vector(3, Element),
        ) Self {
            if (size != 4) {
                @compileError("This operation is only defined for 4x4 matrices.");
            }

            const fallback_forward = math.Vector(3, Element).plus_x;
            const fallback_up = math.Vector(3, Element).plus_z;

            var direction = target.subtract(eye);
            if (direction.isZero(0)) {
                std.log.warn(
                    "When creating a look at matrix, the supplied eye vector {f} was equal to the target vector {f}. " ++
                        "Using fallback look direction.",
                    .{ eye, target },
                );
                direction = fallback_forward;
            }
            const z = direction.normalize();

            const normalized_up = if (!up.isZero(0)) up.normalize() else block: {
                std.log.warn(
                    "When creating a look at matrix, the supplied up vector {f} was zero. Using fallback up direction.",
                    .{up},
                );
                break :block fallback_up;
            };
            var z_cross_up = z.cross(normalized_up);
            if (z_cross_up.isZero(0)) {
                std.log.warn(
                    "When creating a look at matrix, the supplied up vector {f} was colinear with the look direction {f}. " ++
                        "Using fallback up direction.",
                    .{ up, direction },
                );
                z_cross_up = z.cross(fallback_up);
                if (z_cross_up.isZero(0)) {
                    z_cross_up = z.cross(fallback_up);
                }
            }
            const x = z_cross_up.normalize();

            const y = x.cross(z);

            return Self.fromArray(.{
                .{ x.x(), y.x(), z.x(), 0 },
                .{ x.y(), y.y(), z.y(), 0 },
                .{ x.z(), y.z(), z.z(), 0 },
                .{ -x.dot(eye), -y.dot(eye), -z.dot(eye), 1 },
            });
        }

        pub fn lookAt(
            self: Self,
            eye: math.Vector(3, Element),
            target: math.Vector(3, Element),
            up: math.Vector(3, Element),
        ) Self {
            const matrix = Self.fromLookAt(eye, target, up);
            return self.multiply(matrix);
        }

        pub fn fromOrthographic(
            left: Element,
            right: Element,
            bottom: Element,
            top: Element,
            near: Element,
            far: Element,
        ) Self {
            if (size != 4) {
                @compileError("This operation is only defined for 4x4 matrices.");
            }
            const fallback = Self.fromArray(.{
                .{ 0.0, 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 0.0, 10.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            });
            if (left == right) {
                std.log.warn(
                    "When creating a orthographic matrix, the supplied left value {} was equal to right {}. " ++
                        "Returning fallback value.",
                    .{ left, right },
                );
                return fallback;
            }
            if (bottom == top) {
                std.log.warn(
                    "When creating a orthographic matrix, the supplied bottom value {} was equal to top {}. " ++
                        "Returning fallback value.",
                    .{ bottom, top },
                );
                return fallback;
            }
            if (near == far) {
                std.log.warn(
                    "When creating a orthographic matrix, the supplied near value {} was equal to far {}. " ++
                        "Returning fallback value.",
                    .{ near, far },
                );
                return fallback;
            }
            const width = right - left;
            const height = top - bottom;
            const depth = far - near;
            return Self.fromArray(.{
                .{ 2.0 / width, 0.0, 0.0, 0.0 },
                .{ 0.0, 2.0 / height, 0.0, 0.0 },
                .{ 0.0, 0.0, 1.0 / depth, 0.0 },
                .{ -(right + left) / width, -(top + bottom) / height, -near / depth, 1.0 },
            });
        }

        pub fn orthographic(
            self: Self,
            left: Element,
            right: Element,
            bottom: Element,
            top: Element,
            near: Element,
            far: Element,
        ) Self {
            const matrix = Self.fromOrthographic(left, right, bottom, top, near, far);
            return self.multiply(matrix);
        }

        pub fn fromFrustum(
            left: Element,
            right: Element,
            bottom: Element,
            top: Element,
            near: Element,
            far: Element,
        ) Self {
            if (size != 4) {
                @compileError("This operation is only defined for 4x4 matrices.");
            }
            const fallback = Self.fromArray(.{
                .{ 0.0, 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 0.0, 0.0 },
                .{ 0.0, 0.0, 0.0, 10.0 },
                .{ 0.0, 0.0, 0.0, 1.0 },
            });
            if (left == right) {
                std.log.warn(
                    "When creating a frustum matrix, the supplied left value {} was equal to right {}. " ++
                        "Returning fallback value.",
                    .{ left, right },
                );
                return fallback;
            }
            if (bottom == top) {
                std.log.warn(
                    "When creating a frustum matrix, the supplied bottom value {} was equal to top {}. " ++
                        "Returning fallback value.",
                    .{ bottom, top },
                );
                return fallback;
            }
            if (near == far) {
                std.log.warn(
                    "When creating a frustum matrix, the supplied near value {} was equal to far {}. " ++
                        "Returning fallback value.",
                    .{ near, far },
                );
                return fallback;
            }
            const width = right - left;
            const height = top - bottom;
            const depth = far - near;

            const a = (2.0 * near) / width;
            const b = (2.0 * near) / height;
            const c = (right + left) / width;
            const d = (top + bottom) / height;
            const e = far / depth;
            const f = (-near * far) / depth;

            return Self.fromArray(.{
                .{ a, 0.0, 0.0, 0.0 },
                .{ 0.0, b, 0.0, 0.0 },
                .{ c, d, e, 1.0 },
                .{ 0.0, 0.0, f, 0.0 },
            });
        }

        pub fn frustum(
            self: Self,
            left: Element,
            right: Element,
            bottom: Element,
            top: Element,
            near: Element,
            far: Element,
        ) Self {
            const matrix = Self.fromFrustum(left, right, bottom, top, near, far);
            return self.multiply(matrix);
        }

        pub fn fromPerspective(
            vertical_fov: Element,
            aspect_ratio: Element,
            near: Element,
            far: Element,
        ) Self {
            const min_fov = 1 * std.math.rad_per_deg;
            const max_fov = 179 * std.math.rad_per_deg;
            const fov = if (vertical_fov >= min_fov and vertical_fov <= max_fov) vertical_fov else block: {
                std.log.warn(
                    "When creating a perspective matrix, the supplied vertical fov {} was out of bounds. " ++
                        "Clamping the fov back into bounds.",
                    .{vertical_fov},
                );
                break :block std.math.clamp(vertical_fov, min_fov, max_fov);
            };
            const half_tan = std.math.tan(fov / 2);
            const top = near * half_tan;
            const bottom = -top;
            const right = top * aspect_ratio;
            const left = -right;
            return Self.fromFrustum(left, right, bottom, top, near, far);
        }

        pub fn perspective(
            self: Self,
            vertical_fov: Element,
            aspect_ratio: Element,
            near: Element,
            far: Element,
        ) Self {
            const matrix = Self.fromPerspective(vertical_fov, aspect_ratio, near, far);
            return self.multiply(matrix);
        }

        pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
            inline for (0..size) |i| {
                try writer.writeByte('|');
                inline for (0..size) |j| {
                    try writer.print("{}", .{self.array[i][j]});
                    if (j < size - 1) {
                        try writer.writeAll(", ");
                    }
                }
                try writer.writeByte('|');
                if (i < size - 1) {
                    try writer.writeByte('\n');
                }
            }
        }

        pub fn jsonStringify(self: *const Self, jsonWriter: anytype) !void {
            try jsonWriter.write(self.asConstFlat());
        }

        pub fn jsonParse(allocator: std.mem.Allocator, source: anytype, options: std.json.ParseOptions) !Self {
            const flat = try std.json.innerParse(Flat, allocator, source, options);
            return fromFlat(flat);
        }
    };
}

const testing = std.testing;

test "identity should have correct value" {
    const matrix = Matrix(4, f32).identity;
    try testing.expectEqual([4][4]f32{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    }, matrix.array);
}

test "zero should have correct value" {
    const matrix = Matrix(4, f32).zero;
    try testing.expectEqual([4][4]f32{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
    }, matrix.array);
}

test "fromArray should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    }, matrix.array);
}

test "fromFlat should return correct value" {
    const matrix = Matrix(4, f32).fromFlat(.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 });
    try testing.expectEqual([4][4]f32{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    }, matrix.array);
}

test "fromCoords should return correct value" {
    const matrix = Matrix(4, f32).fromCoords(.{
        .xx = 1,
        .xy = 2,
        .xz = 3,
        .xw = 4,
        .yx = 5,
        .yy = 6,
        .yz = 7,
        .yw = 8,
        .zx = 9,
        .zy = 10,
        .zz = 11,
        .zw = 12,
        .wx = 13,
        .wy = 14,
        .wz = 15,
        .ww = 16,
    });
    try testing.expectEqual([4][4]f32{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    }, matrix.array);
}

test "fill should return correct value" {
    const matrix = Matrix(4, f32).fill(5);
    try testing.expectEqual([4][4]f32{
        .{ 5, 5, 5, 5 },
        .{ 5, 5, 5, 5 },
        .{ 5, 5, 5, 5 },
        .{ 5, 5, 5, 5 },
    }, matrix.array);
}

test "toFlat should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(.{ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16 }, matrix.toFlat());
}

test "asFlat should return correct value" {
    var matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(&matrix.array[0][0], &matrix.asFlat()[0]);
    try testing.expectEqual(&matrix.array[0][1], &matrix.asFlat()[1]);
    try testing.expectEqual(&matrix.array[0][2], &matrix.asFlat()[2]);
    try testing.expectEqual(&matrix.array[0][3], &matrix.asFlat()[3]);
    try testing.expectEqual(&matrix.array[1][0], &matrix.asFlat()[4]);
    try testing.expectEqual(&matrix.array[1][1], &matrix.asFlat()[5]);
    try testing.expectEqual(&matrix.array[1][2], &matrix.asFlat()[6]);
    try testing.expectEqual(&matrix.array[1][3], &matrix.asFlat()[7]);
    try testing.expectEqual(&matrix.array[2][0], &matrix.asFlat()[8]);
    try testing.expectEqual(&matrix.array[2][1], &matrix.asFlat()[9]);
    try testing.expectEqual(&matrix.array[2][2], &matrix.asFlat()[10]);
    try testing.expectEqual(&matrix.array[2][3], &matrix.asFlat()[11]);
    try testing.expectEqual(&matrix.array[3][0], &matrix.asFlat()[12]);
    try testing.expectEqual(&matrix.array[3][1], &matrix.asFlat()[13]);
    try testing.expectEqual(&matrix.array[3][2], &matrix.asFlat()[14]);
    try testing.expectEqual(&matrix.array[3][3], &matrix.asFlat()[15]);
}

test "asConstFlat should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(&matrix.array[0][0], &matrix.asConstFlat()[0]);
    try testing.expectEqual(&matrix.array[0][1], &matrix.asConstFlat()[1]);
    try testing.expectEqual(&matrix.array[0][2], &matrix.asConstFlat()[2]);
    try testing.expectEqual(&matrix.array[0][3], &matrix.asConstFlat()[3]);
    try testing.expectEqual(&matrix.array[1][0], &matrix.asConstFlat()[4]);
    try testing.expectEqual(&matrix.array[1][1], &matrix.asConstFlat()[5]);
    try testing.expectEqual(&matrix.array[1][2], &matrix.asConstFlat()[6]);
    try testing.expectEqual(&matrix.array[1][3], &matrix.asConstFlat()[7]);
    try testing.expectEqual(&matrix.array[2][0], &matrix.asConstFlat()[8]);
    try testing.expectEqual(&matrix.array[2][1], &matrix.asConstFlat()[9]);
    try testing.expectEqual(&matrix.array[2][2], &matrix.asConstFlat()[10]);
    try testing.expectEqual(&matrix.array[2][3], &matrix.asConstFlat()[11]);
    try testing.expectEqual(&matrix.array[3][0], &matrix.asConstFlat()[12]);
    try testing.expectEqual(&matrix.array[3][1], &matrix.asConstFlat()[13]);
    try testing.expectEqual(&matrix.array[3][2], &matrix.asConstFlat()[14]);
    try testing.expectEqual(&matrix.array[3][3], &matrix.asConstFlat()[15]);
}

test "toCoords should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(Matrix(4, f32).Coords{
        .xx = 1,
        .xy = 2,
        .xz = 3,
        .xw = 4,
        .yx = 5,
        .yy = 6,
        .yz = 7,
        .yw = 8,
        .zx = 9,
        .zy = 10,
        .zz = 11,
        .zw = 12,
        .wx = 13,
        .wy = 14,
        .wz = 15,
        .ww = 16,
    }, matrix.toCoords());
}

test "asCoords should return correct value" {
    var matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(&matrix.array[0][0], &matrix.asCoords().xx);
    try testing.expectEqual(&matrix.array[0][1], &matrix.asCoords().xy);
    try testing.expectEqual(&matrix.array[0][2], &matrix.asCoords().xz);
    try testing.expectEqual(&matrix.array[0][3], &matrix.asCoords().xw);
    try testing.expectEqual(&matrix.array[1][0], &matrix.asCoords().yx);
    try testing.expectEqual(&matrix.array[1][1], &matrix.asCoords().yy);
    try testing.expectEqual(&matrix.array[1][2], &matrix.asCoords().yz);
    try testing.expectEqual(&matrix.array[1][3], &matrix.asCoords().yw);
    try testing.expectEqual(&matrix.array[2][0], &matrix.asCoords().zx);
    try testing.expectEqual(&matrix.array[2][1], &matrix.asCoords().zy);
    try testing.expectEqual(&matrix.array[2][2], &matrix.asCoords().zz);
    try testing.expectEqual(&matrix.array[2][3], &matrix.asCoords().zw);
    try testing.expectEqual(&matrix.array[3][0], &matrix.asCoords().wx);
    try testing.expectEqual(&matrix.array[3][1], &matrix.asCoords().wy);
    try testing.expectEqual(&matrix.array[3][2], &matrix.asCoords().wz);
    try testing.expectEqual(&matrix.array[3][3], &matrix.asCoords().ww);
}

test "asConstCoords should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(&matrix.array[0][0], &matrix.asConstCoords().xx);
    try testing.expectEqual(&matrix.array[0][1], &matrix.asConstCoords().xy);
    try testing.expectEqual(&matrix.array[0][2], &matrix.asConstCoords().xz);
    try testing.expectEqual(&matrix.array[0][3], &matrix.asConstCoords().xw);
    try testing.expectEqual(&matrix.array[1][0], &matrix.asConstCoords().yx);
    try testing.expectEqual(&matrix.array[1][1], &matrix.asConstCoords().yy);
    try testing.expectEqual(&matrix.array[1][2], &matrix.asConstCoords().yz);
    try testing.expectEqual(&matrix.array[1][3], &matrix.asConstCoords().yw);
    try testing.expectEqual(&matrix.array[2][0], &matrix.asConstCoords().zx);
    try testing.expectEqual(&matrix.array[2][1], &matrix.asConstCoords().zy);
    try testing.expectEqual(&matrix.array[2][2], &matrix.asConstCoords().zz);
    try testing.expectEqual(&matrix.array[2][3], &matrix.asConstCoords().zw);
    try testing.expectEqual(&matrix.array[3][0], &matrix.asConstCoords().wx);
    try testing.expectEqual(&matrix.array[3][1], &matrix.asConstCoords().wy);
    try testing.expectEqual(&matrix.array[3][2], &matrix.asConstCoords().wz);
    try testing.expectEqual(&matrix.array[3][3], &matrix.asConstCoords().ww);
}

test "transpose should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 1, 5, 9, 13 },
        .{ 2, 6, 10, 14 },
        .{ 3, 7, 11, 15 },
        .{ 4, 8, 12, 16 },
    }, matrix.transpose().array);
}

test "minorMatrix should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual([3][3]f32{
        .{ 1, 2, 4 },
        .{ 9, 10, 12 },
        .{ 13, 14, 16 },
    }, matrix.minorMatrix(1, 2).array);
}

test "determinant should return correct value when 2D matrix" {
    const matrix_1 = Matrix(2, f32).fromArray(.{
        .{ 1, 2 },
        .{ 3, 4 },
    });
    try testing.expectEqual(-2, matrix_1.determinant());
    const matrix_2 = Matrix(2, f32).fromArray(.{
        .{ 1, 2 },
        .{ 4, 3 },
    });
    try testing.expectEqual(-5, matrix_2.determinant());
}

test "determinant should return correct value when 3D matrix" {
    const matrix_1 = Matrix(3, f32).fromArray(.{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 },
        .{ 7, 8, 9 },
    });
    try testing.expectEqual(0, matrix_1.determinant());
    const matrix_2 = Matrix(3, f32).fromArray(.{
        .{ 1, 2, 3 },
        .{ 8, 9, 4 },
        .{ 7, 6, 5 },
    });
    try testing.expectEqual(-48, matrix_2.determinant());
}

test "determinant should return correct value when 4D matrix" {
    const matrix_1 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(0, matrix_1.determinant());
    const matrix_2 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 12, 13, 14, 5 },
        .{ 11, 16, 15, 6 },
        .{ 10, 9, 8, 7 },
    });
    try testing.expectEqual(660, matrix_2.determinant());
}

test "determinant should return correct value when 5D matrix" {
    const matrix_1 = Matrix(5, f32).fromArray(.{
        .{ 1, 2, 3, 4, 5 },
        .{ 6, 7, 8, 9, 10 },
        .{ 11, 12, 13, 14, 15 },
        .{ 16, 17, 18, 19, 20 },
        .{ 21, 22, 23, 24, 25 },
    });
    try testing.expectEqual(0, matrix_1.determinant());
    const matrix_2 = Matrix(5, f32).fromArray(.{
        .{ 1, 2, 3, 4, 5 },
        .{ 16, 17, 18, 19, 6 },
        .{ 15, 24, 25, 20, 7 },
        .{ 14, 23, 22, 21, 8 },
        .{ 13, 12, 11, 10, 9 },
    });
    try testing.expectEqual(11760, matrix_2.determinant());
}

test "inverse should return correct value when 2D matrix" {
    const matrix_1 = Matrix(2, f32).fromArray(.{
        .{ 1, 2 },
        .{ 3, 4 },
    });
    try testing.expectEqual([2][2]f32{
        .{ -2, 1 },
        .{ 1.5, -0.5 },
    }, matrix_1.inverse().?.array);
    const matrix_2 = Matrix(2, f32).fromArray(.{
        .{ 1, 2 },
        .{ 4, 3 },
    });
    try testing.expectEqual([2][2]f32{
        .{ -0.6, 0.4 },
        .{ 0.8, -0.2 },
    }, matrix_2.inverse().?.array);
}

test "inverse should return correct value when 3D matrix" {
    const matrix_1 = Matrix(3, f32).fromArray(.{
        .{ 1, 2, 3 },
        .{ 4, 5, 6 },
        .{ 7, 8, 9 },
    });
    try testing.expect(matrix_1.inverse() == null);
    const matrix_2 = Matrix(3, f32).fromArray(.{
        .{ 1, 2, 3 },
        .{ 8, 9, 4 },
        .{ 7, 6, 5 },
    });
    try testing.expectEqual([3][3]f32{
        .{ -21.0 / 48.0, -8.0 / 48.0, 19.0 / 48.0 },
        .{ 12.0 / 48.0, 16.0 / 48.0, -20.0 / 48.0 },
        .{ 15.0 / 48.0, -8.0 / 48.0, 7.0 / 48.0 },
    }, matrix_2.inverse().?.array);
}

test "inverse should return correct value when 4D matrix" {
    const matrix_1 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expect(matrix_1.inverse() == null);
    const matrix_2 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 12, 13, 14, 5 },
        .{ 11, 16, 15, 6 },
        .{ 10, 9, 8, 7 },
    });
    try testing.expectEqual([4][4]f32{
        .{ -53.0 / 330.0, 44.0 / 330.0, -55.0 / 330.0, 46.0 / 330.0 },
        .{ -68.0 / 330.0, -121.0 / 330.0, 110.0 / 330.0, 31.0 / 330.0 },
        .{ 85.0 / 330.0, 110.0 / 330.0, -55.0 / 330.0, -80.0 / 330.0 },
        .{ 66.0 / 330.0, -33.0 / 330.0, 0.0 / 330.0, 33.0 / 330.0 },
    }, matrix_2.inverse().?.array);
}

test "inverse should return correct value when 5D matrix" {
    const matrix_1 = Matrix(5, f32).fromArray(.{
        .{ 1, 2, 3, 4, 5 },
        .{ 6, 7, 8, 9, 10 },
        .{ 11, 12, 13, 14, 15 },
        .{ 16, 17, 18, 19, 20 },
        .{ 21, 22, 23, 24, 25 },
    });
    try testing.expect(matrix_1.inverse() == null);
    const matrix_2 = Matrix(5, f32).fromArray(.{
        .{ 1, 2, 3, 4, 5 },
        .{ 16, 17, 18, 19, 6 },
        .{ 15, 24, 25, 20, 7 },
        .{ 14, 23, 22, 21, 8 },
        .{ 13, 12, 11, 10, 9 },
    });
    try testing.expectEqual([5][5]f32{
        .{ -291.0 / 2940.0, 252.0 / 2940.0, 0.0 / 2940.0, -294.0 / 2940.0, 255.0 / 2940.0 },
        .{ -660.0 / 2940.0, -560.0 / 2940.0, -490.0 / 2940.0, 980.0 / 2940.0, 250.0 / 2940.0 },
        .{ 528.0 / 2940.0, 154.0 / 2940.0, 980.0 / 2940.0, -1078.0 / 2940.0, -200.0 / 2940.0 },
        .{ 198.0 / 2940.0, 364.0 / 2940.0, -490.0 / 2940.0, 392.0 / 2940.0, -320.0 / 2940.0 },
        .{ 435.0 / 2940.0, -210.0 / 2940.0, 0.0 / 2940.0, 0.0 / 2940.0, 225.0 / 2940.0 },
    }, matrix_2.inverse().?.array);
}

test "add should return correct value" {
    const matrix_1 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const matrix_2 = Matrix(4, f32).fromArray(.{
        .{ 17, 18, 19, 20 },
        .{ 21, 22, 23, 24 },
        .{ 25, 26, 27, 28 },
        .{ 29, 30, 31, 32 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 18, 20, 22, 24 },
        .{ 26, 28, 30, 32 },
        .{ 34, 36, 38, 40 },
        .{ 42, 44, 46, 48 },
    }, matrix_1.add(matrix_2).array);
}

test "subtract should return correct value" {
    const matrix_1 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const matrix_2 = Matrix(4, f32).fromArray(.{
        .{ 17, 18, 19, 20 },
        .{ 21, 22, 23, 24 },
        .{ 25, 26, 27, 28 },
        .{ 29, 30, 31, 32 },
    });
    try testing.expectEqual([4][4]f32{
        .{ -16, -16, -16, -16 },
        .{ -16, -16, -16, -16 },
        .{ -16, -16, -16, -16 },
        .{ -16, -16, -16, -16 },
    }, matrix_1.subtract(matrix_2).array);
}

test "multiply should return correct value" {
    const matrix_1 = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const matrix_2 = Matrix(4, f32).fromArray(.{
        .{ 17, 18, 19, 20 },
        .{ 21, 22, 23, 24 },
        .{ 25, 26, 27, 28 },
        .{ 29, 30, 31, 32 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 250, 260, 270, 280 },
        .{ 618, 644, 670, 696 },
        .{ 986, 1028, 1070, 1112 },
        .{ 1354, 1412, 1470, 1528 },
    }, matrix_1.multiply(matrix_2).array);
}

test "scalarMultiply should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 5, 10, 15, 20 },
        .{ 25, 30, 35, 40 },
        .{ 45, 50, 55, 60 },
        .{ 65, 70, 75, 80 },
    }, matrix.scalarMultiply(5).array);
}

test "scalarDivide should return correct value" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 5, 10, 15, 20 },
        .{ 25, 30, 35, 40 },
        .{ 45, 50, 55, 60 },
        .{ 65, 70, 75, 80 },
    });
    try testing.expectEqual([4][4]f32{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    }, matrix.scalarDivide(5).array);
}

test "translate should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const translation = math.Vector(3, f32).fromArray(.{ 4, 5, 6 });
    const matrix = Matrix(4, f32).identity.translate(translation);
    try testing.expectEqual(.{ 5, 7, 9 }, vec.pointTransform(matrix).array);
}

test "scale should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const translation = math.Vector(3, f32).fromArray(.{ 4, 5, 6 });
    const matrix = Matrix(4, f32).identity.scale(translation);
    try testing.expectEqual(.{ 4, 10, 18 }, vec.pointTransform(matrix).array);
}

test "rotateX should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix = Matrix(4, f32).identity.rotateX(0.5 * std.math.pi);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(1, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(-3, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(2, transformed.z(), 0.00001);
}

test "rotateY should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix = Matrix(4, f32).identity.rotateY(0.5 * std.math.pi);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(-3, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(2, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(1, transformed.z(), 0.00001);
}

test "rotateZ should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix = Matrix(4, f32).identity.rotateZ(0.5 * std.math.pi);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(-2, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(1, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(3, transformed.z(), 0.00001);
}

test "rotateAround should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const around = math.Vector(3, f32).fromArray(.{ 1, 1, 1 });
    const matrix = Matrix(4, f32).identity.rotateAround(around, (2.0 / 3.0) * std.math.pi);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(3, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(1, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(2, transformed.z(), 0.00001);
}

test "lookAt should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const eye = math.Vector(3, f32).fromArray(.{ 4, 0, 0 });
    const target = math.Vector(3, f32).fromArray(.{ 4, 1, 0 });
    const up = math.Vector(3, f32).fromArray(.{ 0, 0, 1 });
    const matrix = Matrix(4, f32).identity.lookAt(eye, target, up);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(-3, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(3, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(2, transformed.z(), 0.00001);
}

test "orthographic should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 3 });
    const matrix = Matrix(4, f32).identity.orthographic(-4, 4, -4, 4, -4, 4);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(0.25, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(0.5, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(0.875, transformed.z(), 0.00001);
}

test "frustum should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 4 });
    const matrix = Matrix(4, f32).identity.frustum(-2, 2, -1, 1, 1, 5);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(0.125, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(0.5, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(15.0 / 16.0, transformed.z(), 0.00001);
}

test "perspective should return correct value" {
    const vec = math.Vector(3, f32).fromArray(.{ 1, 2, 4 });
    const matrix = Matrix(4, f32).identity.perspective(0.5 * std.math.pi, 2, 1, 5);
    const transformed = vec.pointTransform(matrix);
    try testing.expectApproxEqAbs(0.125, transformed.x(), 0.00001);
    try testing.expectApproxEqAbs(0.5, transformed.y(), 0.00001);
    try testing.expectApproxEqAbs(15.0 / 16.0, transformed.z(), 0.00001);
}

test "should format correctly" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const string = try std.fmt.allocPrint(testing.allocator, "{f}", .{matrix});
    defer testing.allocator.free(string);
    try testing.expectEqualStrings(
        "|1, 2, 3, 4|\n" ++
            "|5, 6, 7, 8|\n" ++
            "|9, 10, 11, 12|\n" ++
            "|13, 14, 15, 16|",
        string,
    );
}

test "should serialize to JSON correctly" {
    const matrix = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    const json = try std.json.Stringify.valueAlloc(testing.allocator, matrix, .{});
    defer testing.allocator.free(json);
    try testing.expectEqualStrings("[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]", json);
}

test "should deserialize from JSON correctly" {
    const json = "[1,2,3,4,5,6,7,8,9,10,11,12,13,14,15,16]";
    const parsed = try std.json.parseFromSlice(Matrix(4, f32), testing.allocator, json, .{});
    defer parsed.deinit();
    const expected = Matrix(4, f32).fromArray(.{
        .{ 1, 2, 3, 4 },
        .{ 5, 6, 7, 8 },
        .{ 9, 10, 11, 12 },
        .{ 13, 14, 15, 16 },
    });
    try testing.expectEqual(expected, parsed.value);
}
