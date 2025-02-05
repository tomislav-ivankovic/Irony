const std = @import("std");
const os = @import("os/root.zig");
const injector = @import("injector/root.zig");

const process_name = "TEKKEN8.exe";
const interval_ns = 1_000_000_000;

pub fn main() !void {
    injector.runProcessLoop(process_name, interval_ns, onProcessOpen, onProcessClose);
}

pub fn onProcessOpen(process: *const os.Process) void {
    _ = process;
}

pub fn onProcessClose(process: *const os.Process) void {
    _ = process;
}
