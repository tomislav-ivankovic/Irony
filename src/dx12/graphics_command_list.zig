const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const dx12 = @import("root.zig");

pub const GraphicsCommandList = struct {
    raw: *w32.ID3D12GraphicsCommandList,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn create(
        device: *const w32.ID3D12Device,
        command_allocator: *w32.ID3D12CommandAllocator,
    ) !Self {
        var command_list: *w32.ID3D12GraphicsCommandList = undefined;
        const return_code = device.ID3D12Device_CreateCommandList(
            0,
            .DIRECT,
            command_allocator,
            null,
            w32.IID_ID3D12GraphicsCommandList,
            @ptrCast(&command_list),
        );
        if (return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12Device.CreateCommandList returned: {}",
                .{return_code},
            );
            return error.Dx12Error;
        }
        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};
        return .{
            .raw = command_list,
            .test_allocation = test_allocation,
        };
    }

    pub fn destroy(self: *const Self) !void {
        const return_code = self.raw.IUnknown_Release();
        if (return_code != w32.S_OK) {
            misc.errorContext().newFmt(
                error.Dx12Error,
                "ID3D12CommandAllocator.Release returned: {}",
                .{return_code},
            );
            return error.Dx12Error;
        }
        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }
};

const testing = std.testing;

test "create and destroy should succeed" {
    const context = try dx12.TestingContext.init();
    defer context.deinit();
    const allocator = try dx12.CommandAllocator.create(context.device);
    defer allocator.destroy() catch @panic("Failed to destroy command allocator.");
    const command_list = try GraphicsCommandList.create(context.device, allocator.raw);
    defer command_list.destroy() catch @panic("Failed to destroy command list.");
}
