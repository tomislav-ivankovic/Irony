const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const dx11 = @import("root.zig");

pub const HostContext = struct {
    window: w32.HWND,
    device: *const w32.ID3D11Device,
    device_context: *const w32.ID3D11DeviceContext,
    swap_chain: *const w32.IDXGISwapChain,
};

pub const ManagedContext = struct {
    buffer_context: BufferContext,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(allocator: std.mem.Allocator, host_context: *const dx11.HostContext) !Self {
        _ = allocator;

        const buffer_context = BufferContext.init(host_context.device, host_context.swap_chain) catch |err| {
            misc.error_context.append("Failed to create buffer context.", .{});
            return err;
        };
        errdefer buffer_context.deinit();

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{ .buffer_context = buffer_context, .test_allocation = test_allocation };
    }

    pub fn deinit(self: *Self) void {
        self.buffer_context.deinit();

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    pub fn deinitBufferContexts(self: *Self) void {
        self.buffer_context.deinit();
    }

    pub fn reinitBufferContexts(self: *Self, host_context: *const dx11.HostContext) !void {
        self.buffer_context = BufferContext.init(host_context.device, host_context.swap_chain) catch |err| {
            misc.error_context.append("Failed to create buffer context.", .{});
            return err;
        };
    }
};

pub const BufferContext = struct {
    render_target_view: *w32.ID3D11RenderTargetView,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(device: *const w32.ID3D11Device, swap_chain: *const w32.IDXGISwapChain) !Self {
        var back_buffer: *w32.ID3D11Resource = undefined;
        const buffer_result = swap_chain.GetBuffer(0, w32.IID_ID3D11Texture2D, @ptrCast(&back_buffer));
        if (dx11.Error.from(buffer_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGISwapChain.GetBuffer returned a failure value.", .{});
            misc.error_context.append("Failed to get back buffer.", .{});
            return error.Dx11Error;
        }
        defer _ = back_buffer.IUnknown.Release();

        var render_target_view: *w32.ID3D11RenderTargetView = undefined;
        const rtv_result = device.CreateRenderTargetView(back_buffer, null, &render_target_view);
        if (dx11.Error.from(rtv_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D11Device.CreateRenderTargetView returned a failure value.", .{});
            misc.error_context.append("Failed to create render target view.", .{});
            return error.Dx11Error;
        }
        errdefer _ = render_target_view.IUnknown.Release();

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{ .render_target_view = render_target_view, .test_allocation = test_allocation };
    }

    pub fn deinit(self: *const Self) void {
        _ = self.render_target_view.IUnknown.Release();

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }
};

pub const Context = struct {
    window: w32.HWND,
    device: *const w32.ID3D11Device,
    device_context: *const w32.ID3D11DeviceContext,
    swap_chain: *const w32.IDXGISwapChain,
    buffer_context: *BufferContext,

    const Self = @This();

    pub fn fromHostAndManaged(host_context: *const HostContext, managed_context: *ManagedContext) Self {
        return .{
            .window = host_context.window,
            .device = host_context.device,
            .device_context = host_context.device_context,
            .swap_chain = host_context.swap_chain,
            .buffer_context = &managed_context.buffer_context,
        };
    }

    pub fn beforeRender(self: *const Self) error{Dx11Error}!*BufferContext {
        var views = [1](?*w32.ID3D11RenderTargetView){self.buffer_context.render_target_view};
        self.device_context.OMSetRenderTargets(views.len, &views, null);
        return self.buffer_context;
    }

    pub fn afterRender(self: *const Self, buffer_context: *BufferContext) error{Dx11Error}!void {
        _ = self;
        _ = buffer_context;
    }
};

const testing = std.testing;

test "ManagedContext init and deinit should succeed" {
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
}

test "Context beforeRender and afterRender should succeed" {
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.afterRender(buffer_context);
    }
}

test "ManagedContext deinitBufferContexts and reinitBufferContexts should succeed" {
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.afterRender(buffer_context);
    }
    managed_context.deinitBufferContexts();
    try managed_context.reinitBufferContexts(&host_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.afterRender(buffer_context);
    }
}
