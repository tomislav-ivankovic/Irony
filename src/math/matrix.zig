const std = @import("std");
const imgui = @import("imgui");

pub fn Matrix(comptime size: usize, comptime Element: type) type {
    if (@typeInfo(Element) != .int and @typeInfo(Element) != .float) {
        @compileError("Expected a int or float type argument but got type: " ++ @typeName(Element));
    }
    return extern struct {
        array: [size][size]Element,

        const Self = @This();

        pub fn fromArray(array: [size][size]Element) Self {
            return .{ .array = array };
        }

        pub fn identity() Self {
            return comptime block: {
                var array: [size][size]Element = undefined;
                for (0..size) |i| {
                    for (0..size) |j| {
                        array[i][j] = if (i == j) 1 else 0;
                    }
                }
                break :block .{ .array = array };
            };
        }

        pub fn zero() Self {
            const row = [1]Element{0} ** size;
            const array = [1]([size]Element){row} ** size;
            return .{ .array = array };
        }

        pub fn fill(value: Element) Self {
            const row = [1]Element{value} ** size;
            const array = [1]([size]Element){row} ** size;
            return .{ .array = array };
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
            var result = Self.zero();
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
    };
}

const testing = std.testing;

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

test "identity should return correct value" {
    const matrix = Matrix(4, f32).identity();
    try testing.expectEqual([4][4]f32{
        .{ 1, 0, 0, 0 },
        .{ 0, 1, 0, 0 },
        .{ 0, 0, 1, 0 },
        .{ 0, 0, 0, 1 },
    }, matrix.array);
}

test "zero should return correct value" {
    const matrix = Matrix(4, f32).zero();
    try testing.expectEqual([4][4]f32{
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
        .{ 0, 0, 0, 0 },
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
    try testing.expectEqual(null, matrix_1.inverse());
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
    try testing.expectEqual(null, matrix_1.inverse());
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
    try testing.expectEqual(null, matrix_1.inverse());
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
