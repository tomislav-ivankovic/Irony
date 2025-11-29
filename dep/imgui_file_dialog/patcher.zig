const std = @import("std");

const declaration = "std::string IGFD::Utils::RoundNumber(double vvalue, int n)";
const replacement_body =
    \\{
    \\    char format[16];
    \\    std::snprintf(format, sizeof(format), "%%.%df", n);
    \\    char buffer[128];
    \\    std::snprintf(buffer, sizeof(buffer), format, vvalue);
    \\    return std::string(buffer);
    \\}
;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    const allocator = gpa.allocator();
    const args = try std.process.argsAlloc(allocator);
    defer std.process.argsFree(allocator, args);
    if (args.len != 2) {
        return error.WrongNumberOfArguments;
    }
    const path = args[1];

    var file = try std.fs.cwd().openFile(path, .{});
    defer file.close();

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(&read_buffer);
    const reader = &file_reader.interface;

    var write_buffer: [4096]u8 = undefined;
    var std_writer = std.fs.File.stdout().writer(&write_buffer);
    const writer = &std_writer.interface;

    var search_index: usize = 0;
    while (true) {
        const byte = try reader.takeByte();
        try writer.writeByte(byte);
        if (byte != declaration[search_index]) {
            search_index = 0;
            continue;
        }
        search_index += 1;
        if (search_index == declaration.len) {
            break;
        }
    }

    try writer.writeAll(replacement_body);

    var first_bracket_found = false;
    var bracket_count: usize = 0;
    while (!first_bracket_found or bracket_count > 0) {
        const byte = try reader.takeByte();
        switch (byte) {
            '{' => {
                first_bracket_found = true;
                bracket_count += 1;
            },
            '}' => {
                if (bracket_count == 0) {
                    return error.UnexpectedBracket;
                }
                bracket_count -= 1;
            },
            else => {},
        }
    }

    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        try writer.writeByte(byte);
    }

    try writer.flush();
}
