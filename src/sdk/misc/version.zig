const std = @import("std");
const build_info = @import("build_info");
const misc = @import("../misc/root.zig");

pub const Version = struct {
    major: Element,
    minor: Element,
    patch: Element,
    snapshot: bool,

    const Self = @This();
    const Element = u8;

    pub const current = Self.comptimeParse(build_info.version);

    pub fn fetchLatest(allocator: std.mem.Allocator) !Self {
        var client = std.http.Client{ .allocator = allocator };
        defer client.deinit();

        const uri_string = build_info.home_page ++ "/releases/latest";
        const uri = comptime std.Uri.parse(uri_string) catch {
            @compileError("Invalid URI: " ++ uri_string);
        };
        var request = client.request(.GET, uri, .{
            .extra_headers = &.{
                .{ .name = "Accept", .value = "application/json" },
                .{ .name = "X-GitHub-Api-Version", .value = "2022-11-28" },
            },
        }) catch |err| {
            misc.error_context.new("Failed to open connection to: {s}", .{uri_string});
            return err;
        };
        defer request.deinit();

        request.sendBodiless() catch |err| {
            misc.error_context.new("Failed to send GET request to: {s}", .{uri_string});
            return err;
        };

        var redirect_buffer: [1024]u8 = undefined;
        var response = request.receiveHead(&redirect_buffer) catch |err| {
            misc.error_context.new("Failed to receive response from: {s}", .{uri_string});
            return err;
        };
        const status = response.head.status;
        if (status != .ok) {
            if (status.phrase()) |phrase| {
                misc.error_context.new("Server responded with status: {s}", .{phrase});
            } else {
                misc.error_context.new("Server responded with status code: {}", .{@intFromEnum(status)});
            }
            return error.BadResponseStatus;
        }

        var transfer_buffer: [1024]u8 = undefined;
        var decompress: std.http.Decompress = undefined;
        var decompress_buffer: [
            @max(std.compress.zstd.default_window_len, std.compress.flate.max_window_len)
        ]u8 = undefined;
        const body = response.readerDecompressing(
            &transfer_buffer,
            &decompress,
            &decompress_buffer,
        ).allocRemaining(allocator, .limited(1_000_000)) catch |err| {
            misc.error_context.new("Failed to read the response body.", .{});
            return err;
        };
        defer allocator.free(body);

        const Body = struct { tag_name: []const u8 };
        const parsed = std.json.parseFromSlice(Body, allocator, body, .{ .ignore_unknown_fields = true }) catch |err| {
            misc.error_context.new("Failed to parse the response body as JSON: {s}", .{body});
            return err;
        };
        defer parsed.deinit();

        const version_string: []const u8 = parsed.value.tag_name;
        return Version.parse(version_string) catch |err| {
            misc.error_context.append("Failed to parse version string: {s}", .{version_string});
            return err;
        };
    }

    pub fn parse(string: []const u8) !Self {
        var current_index: usize = 0;

        const major_start_index = current_index;
        while (true) {
            if (current_index >= string.len) {
                const fmt = "Failed to find the end of major version in version string: {s}";
                const args = .{string};
                if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
                misc.error_context.new(fmt, args);
                return error.Incomplete;
            }
            if (string[current_index] == '.') {
                break;
            }
            current_index += 1;
        }
        const major_string = string[major_start_index..current_index];
        const major = std.fmt.parseInt(Element, major_string, 10) catch |err| {
            const fmt = "Failed to parse the major version \"{s}\" in version string: {s}";
            const args = .{ major_string, string };
            if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
            misc.error_context.new(fmt, args);
            return err;
        };
        current_index += 1;

        const minor_start_index = current_index;
        while (true) {
            if (current_index >= string.len) {
                const fmt = "Failed to find the end of minor version in version string: {s}";
                const args = .{string};
                if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
                misc.error_context.new(fmt, args);
                return error.Incomplete;
            }
            if (string[current_index] == '.') {
                break;
            }
            current_index += 1;
        }
        const minor_string = string[minor_start_index..current_index];
        const minor = std.fmt.parseInt(Element, minor_string, 10) catch |err| {
            const fmt = "Failed to parse the minor version \"{s}\" in version string: {s}";
            const args = .{ minor_string, string };
            if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
            misc.error_context.new(fmt, args);
            return err;
        };
        current_index += 1;

        const patch_start_index = current_index;
        while (current_index < string.len and string[current_index] != '-') {
            current_index += 1;
        }
        const patch_string = string[patch_start_index..current_index];
        const patch = std.fmt.parseInt(Element, patch_string, 10) catch |err| {
            const fmt = "Failed to parse the patch version \"{s}\" in version string: {s}";
            const args = .{ patch_string, string };
            if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
            misc.error_context.new(fmt, args);
            return err;
        };

        const snapshot = if (current_index < string.len) block: {
            const snapshot_string = string[current_index..string.len];
            if (!std.mem.eql(u8, snapshot_string, "-SNAPSHOT")) {
                const fmt = "Expecting \"-SNAPSHOT\" but got \"{s}\" in version string: {s}";
                const args = .{ snapshot_string, string };
                if (@inComptime()) @compileError(std.fmt.comptimePrint(fmt, args));
                misc.error_context.new(fmt, args);
                return error.InvalidSnapshotString;
            }
            break :block true;
        } else false;

        return .{
            .major = major,
            .minor = minor,
            .patch = patch,
            .snapshot = snapshot,
        };
    }

    pub inline fn comptimeParse(comptime string: []const u8) Self {
        comptime return parse(string) catch unreachable;
    }

    pub fn order(lhs: Self, rhs: Self) std.math.Order {
        if (lhs.major < rhs.major) return .lt;
        if (lhs.major > rhs.major) return .gt;
        if (lhs.minor < rhs.minor) return .lt;
        if (lhs.minor > rhs.minor) return .gt;
        if (lhs.patch < rhs.patch) return .lt;
        if (lhs.patch > rhs.patch) return .gt;
        if (lhs.snapshot and !rhs.snapshot) return .lt;
        if (!lhs.snapshot and rhs.snapshot) return .gt;
        return .eq;
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.print("{}.{}.{}", .{ self.major, self.minor, self.patch });
        if (self.snapshot) {
            try writer.writeAll("-SNAPSHOT");
        }
    }
};

const testing = std.testing;

test "parse should correctly parse valid version strings" {
    try testing.expectEqual(
        Version{ .major = 1, .minor = 2, .patch = 3, .snapshot = false },
        Version.parse("1.2.3"),
    );
    try testing.expectEqual(
        Version{ .major = 12, .minor = 34, .patch = 56, .snapshot = true },
        Version.parse("12.34.56-SNAPSHOT"),
    );
}

test "parse should return error when parsing invalid version strings" {
    try testing.expectEqual(error.Incomplete, Version.parse(""));
    try testing.expectEqual(error.Incomplete, Version.parse("12"));
    try testing.expectEqual(error.Incomplete, Version.parse("12.34"));
    try testing.expectEqual(error.InvalidCharacter, Version.parse(".."));
    try testing.expectEqual(error.InvalidCharacter, Version.parse(".34.56"));
    try testing.expectEqual(error.InvalidCharacter, Version.parse("12..56"));
    try testing.expectEqual(error.InvalidCharacter, Version.parse("12.34."));
    try testing.expectEqual(error.InvalidCharacter, Version.parse("a2.34.56"));
    try testing.expectEqual(error.InvalidCharacter, Version.parse("12.3b.45"));
    try testing.expectEqual(error.InvalidCharacter, Version.parse("12.34.c5"));
    try testing.expectEqual(error.InvalidSnapshotString, Version.parse("12.34.45-"));
    try testing.expectEqual(error.InvalidSnapshotString, Version.parse("12.34.45-abc"));
}

test "order should compare two versions correctly" {
    try testing.expectEqual(.lt, Version.order(try .parse("9.9.9"), try .parse("10.0.0")));
    try testing.expectEqual(.gt, Version.order(try .parse("10.0.0"), try .parse("9.9.9")));
    try testing.expectEqual(.lt, Version.order(try .parse("1.9.9"), try .parse("1.10.0")));
    try testing.expectEqual(.gt, Version.order(try .parse("1.10.0"), try .parse("1.9.9")));
    try testing.expectEqual(.lt, Version.order(try .parse("1.2.9"), try .parse("1.2.10")));
    try testing.expectEqual(.gt, Version.order(try .parse("1.2.10"), try .parse("1.2.9")));
    try testing.expectEqual(.lt, Version.order(try .parse("1.2.3-SNAPSHOT"), try .parse("1.2.3")));
    try testing.expectEqual(.gt, Version.order(try .parse("1.2.3"), try .parse("1.2.3-SNAPSHOT")));
    try testing.expectEqual(.eq, Version.order(try .parse("1.2.3"), try .parse("1.2.3")));
    try testing.expectEqual(.eq, Version.order(try .parse("1.2.3-SNAPSHOT"), try .parse("1.2.3-SNAPSHOT")));
}

test "should format correctly" {
    const test_cases = [_]([]const u8){
        "1.2.3",
        "12.34.45",
        "67.78.90-SNAPSHOT",
    };
    for (test_cases) |expected| {
        const pattern = try Version.parse(expected);
        const string = try std.fmt.allocPrint(testing.allocator, "{f}", .{pattern});
        defer testing.allocator.free(string);
        try testing.expectEqualStrings(expected, string);
    }
}
