const std = @import("std");
const w32 = @import("win32").everything;
const testing = std.testing;

pub fn DllMain(
    module_handle: w32.HINSTANCE,
    forward_reason: u32,
    reserved: *anyopaque,
) callconv(std.os.windows.WINAPI) w32.BOOL {
    _ = module_handle;
    _ = reserved;
    switch (forward_reason) {
        w32.DLL_PROCESS_ATTACH => return 1,
        w32.DLL_PROCESS_DETACH => return 1,
        else => return 0,
    }
}
