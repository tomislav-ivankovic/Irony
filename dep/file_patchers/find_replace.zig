const std = @import("std");

pub fn main(init: std.process.Init) !void {
    const io = init.io;

    const args = try init.minimal.args.toSlice(init.arena.allocator());
    if (args.len != 4) {
        return error.WrongNumberOfArguments;
    }
    const path = args[1];
    const find = args[2];
    const replace = args[3];

    var file = try std.Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var file_reader = file.reader(io, &read_buffer);
    const reader = &file_reader.interface;

    var write_buffer: [4096]u8 = undefined;
    var std_writer = std.Io.File.stdout().writer(io, &write_buffer);
    const writer = &std_writer.interface;

    var find_index: usize = 0;
    var replace_count: usize = 0;
    while (true) {
        const byte = reader.takeByte() catch |err| switch (err) {
            error.EndOfStream => break,
            else => return err,
        };
        if (byte == find[find_index]) {
            find_index += 1;
            if (find_index == find.len) {
                try writer.writeAll(replace);
                replace_count += 1;
                find_index = 0;
            }
        } else {
            try writer.writeAll(find[0..find_index]);
            try writer.writeByte(byte);
            find_index = 0;
        }
    }
    try writer.writeAll(find[0..find_index]);

    try writer.flush();

    if (replace_count <= 0) {
        return error.NoMatchesFound;
    }
}
