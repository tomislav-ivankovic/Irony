const std = @import("std");

pub const Input = packed struct (u13) {
    forward: bool = false,
    back: bool = false,
    up: bool = false,
    down: bool = false,
    left: bool = false,
    right: bool = false,
    button_1: bool = false,
    button_2: bool = false,
    button_3: bool = false,
    button_4: bool = false,
    special_style: bool = false,
    rage: bool = false,
    heat: bool = false,

    const Self = @This();

    pub fn clean(self: Self) Self {
        var cleaned = self;
        if (cleaned.forward and cleaned.back) {
            cleaned.forward = false;
            cleaned.back = false;
        }
        if (cleaned.up and cleaned.down) {
            cleaned.up = false;
            cleaned.down = false;
        }
        if (cleaned.left and cleaned.right) {
            cleaned.left = false;
            cleaned.right = false;
        }
        return cleaned;
    }

    pub fn equalsIgnoringLeftRight(self: Self, other: Self) bool {
        var s = self;
        s.left = false;
        s.right = false;
        var o = other;
        o.left = false;
        o.right = false;
        return s == o;
    }

    pub fn parse(string: []const u8) Self {
        var self = Self{};
        var iterator = (std.unicode.Utf8View{ .bytes = string }).iterator();
        while (iterator.nextCodepointSlice()) |codepoint| {
            if (codepoint.len != 1) {
                continue;
            }
            switch (codepoint[0]) {
                'f', 'F' => self.forward = true,
                'b', 'B' => self.back = true,
                'u', 'U' => self.up = true,
                'd', 'D' => self.down = true,
                '1' => self.button_1 = true,
                '2' => self.button_2 = true,
                '3' => self.button_3 = true,
                '4' => self.button_4 = true,
                's', 'S' => self.special_style = true,
                'r', 'R' => self.rage = true,
                'h', 'H' => self.heat = true,
                else => {},
            }
        }
        return self.clean();
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.up and !self.down) {
            try writer.writeByte('u');
        }
        if (self.down and !self.up) {
            try writer.writeByte('d');
        }
        if (self.forward and !self.back) {
            try writer.writeByte('f');
        }
        if (self.back and !self.forward) {
            try writer.writeByte('b');
        }
        var is_first = true;
        if (self.button_1) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('1');
            is_first = false;
        }
        if (self.button_2) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('2');
            is_first = false;
        }
        if (self.button_3) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('3');
            is_first = false;
        }
        if (self.button_4) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('4');
            is_first = false;
        }
        if (self.special_style) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeAll("SS");
            is_first = false;
        }
        if (self.rage) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('R');
            is_first = false;
        }
        if (self.heat) {
            if (!is_first) {
                try writer.writeByte('+');
            }
            try writer.writeByte('H');
            is_first = false;
        }
    }
};

const testing = std.testing;

test "clean should remove simultaneous opposite directional inputs" {
    try testing.expectEqual(
        Input{ .forward = true, .right = true, .button_1 = true },
        (Input{ .up = true, .down = true, .forward = true, .right = true, .button_1 = true }).clean(),
    );
    try testing.expectEqual(
        Input{ .up = true, .right = true, .button_2 = true },
        (Input{ .up = true, .forward = true, .back = true, .right = true, .button_2 = true }).clean(),
    );
    try testing.expectEqual(
        Input{ .up = true, .forward = true, .button_3 = true },
        (Input{ .up = true, .forward = true, .left = true, .right = true, .button_3 = true }).clean(),
    );
}

test "equalsIgnoringLeftRight should return correct true only if every flag except left or right are equal" {
    try testing.expectEqual(true, Input.equalsIgnoringLeftRight(
        Input{ .forward = true, .left = true, .button_1 = true, .heat = true },
        Input{ .forward = true, .left = true, .button_1 = true, .heat = true },
    ));
    try testing.expectEqual(true, Input.equalsIgnoringLeftRight(
        Input{ .forward = true, .left = true, .button_1 = true, .heat = true },
        Input{ .forward = true, .right = true, .button_1 = true, .heat = true },
    ));
    try testing.expectEqual(false, Input.equalsIgnoringLeftRight(
        Input{ .forward = true, .left = true, .button_1 = true, .heat = true },
        Input{ .forward = true, .left = true, .button_1 = true, .rage = true },
    ));
}

test "parse should return correct value" {
    try testing.expectEqual(
        Input{ .down = true, .back = true, .button_1 = true, .button_2 = true },
        Input.parse("db1+2"),
    );
    try testing.expectEqual(
        Input{ .up = true, .forward = true, .button_3 = true, .button_4 = true },
        Input.parse("uf3+4"),
    );
    try testing.expectEqual(
        Input{ .special_style = true, .heat = true, .rage = true },
        Input.parse("SS+H+R"),
    );
    try testing.expectEqual(
        Input{ .down = true, .back = true, .button_1 = true, .button_2 = true, .special_style = true },
        Input.parse(".d B,12-s\n"),
    );
}

test "should format correctly" {
    const input_1 = Input{ .down = true, .back = true, .button_1 = true, .button_2 = true };
    const input_2 = Input{ .up = true, .forward = true, .button_3 = true, .button_4 = true };
    const input_3 = Input{ .special_style = true, .heat = true, .rage = true };
    const string = try std.fmt.allocPrint(testing.allocator, "{f}, {f}, {f}", .{ input_1, input_2, input_3 });
    defer testing.allocator.free(string);
    try testing.expectEqualStrings("db1+2, uf3+4, SS+R+H", string);
}
