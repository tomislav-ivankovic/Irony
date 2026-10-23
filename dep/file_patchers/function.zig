const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        return error.WrongNumberOfArguments;
    }
    const path = args[1];
    const declaration = args[2];
    const replacement_body = args[3];

    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    var write_buffer: [4096]u8 = undefined;
    var std_writer = std.Io.File.stdout().writer(io, &write_buffer);
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
