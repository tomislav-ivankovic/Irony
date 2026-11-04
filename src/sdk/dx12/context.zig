const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");
const math = @import("../math/root.zig");
const dx12 = @import("root.zig");

pub const HostContext = struct {
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
};

pub const ManagedContext = struct {
    allocator: std.mem.Allocator,
    rtv_descriptor_heap: *w32.ID3D12DescriptorHeap,
    dsv_descriptor_heap: *w32.ID3D12DescriptorHeap,
    srv_descriptor_heap: *w32.ID3D12DescriptorHeap,
    srv_allocator: *dx12.DescriptorHeapAllocator(srv_heap_size),
    buffer_contexts_buffer: [max_buffer_count]BufferContext,
    buffer_contexts_len: usize,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();
    const max_buffer_count = 4;
    const srv_heap_size = 64;

    pub fn init(allocator: std.mem.Allocator, host_context: *const dx12.HostContext) !Self {
        var swap_chain_desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
        const desc_result = host_context.swap_chain.GetDesc(&swap_chain_desc);
        if (dx12.Error.from(desc_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGISwapChain.GetDesc returned a failure value.", .{});
            misc.error_context.append("Failed to find the back buffer count.", .{});
            return error.Dx12Error;
        }
        const buffer_count = swap_chain_desc.BufferCount;
        if (buffer_count > max_buffer_count) {
            misc.error_context.new(
                "Number of buffers {} exceeds the maximum allowed: {}",
                .{ buffer_count, max_buffer_count },
            );
            return error.Dx12Error;
        }

        var rtv_descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
        const rtv_result = host_context.device.CreateDescriptorHeap(&.{
            .Type = .RTV,
            .NumDescriptors = buffer_count,
            .Flags = .{},
            .NodeMask = 1,
        }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&rtv_descriptor_heap));
        if (dx12.Error.from(rtv_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateDescriptorHeap returned a failure value.", .{});
            misc.error_context.append("Failed to create RTV descriptor heap.", .{});
            return error.Dx12Error;
        }
        errdefer _ = rtv_descriptor_heap.IUnknown.Release();

        var dsv_descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
        const dsv_result = host_context.device.CreateDescriptorHeap(&.{
            .Type = .DSV,
            .NumDescriptors = buffer_count,
            .Flags = .{},
            .NodeMask = 0,
        }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&dsv_descriptor_heap));
        if (dx12.Error.from(dsv_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateDescriptorHeap returned a failure value.", .{});
            misc.error_context.append("Failed to create DSV descriptor heap.", .{});
            return error.Dx12Error;
        }
        errdefer _ = dsv_descriptor_heap.IUnknown.Release();

        var srv_descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
        const srv_result = host_context.device.CreateDescriptorHeap(&.{
            .Type = .CBV_SRV_UAV,
            .NumDescriptors = srv_heap_size,
            .Flags = .{ .SHADER_VISIBLE = 1 },
            .NodeMask = 0,
        }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&srv_descriptor_heap));
        if (dx12.Error.from(srv_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateDescriptorHeap returned a failure value.", .{});
            misc.error_context.append("Failed to create SRV descriptor heap.", .{});
            return error.Dx12Error;
        }
        errdefer _ = srv_descriptor_heap.IUnknown.Release();

        const srv_allocator = allocator.create(dx12.DescriptorHeapAllocator(srv_heap_size)) catch |err| {
            misc.error_context.new("Failed to allocate an SRV allocator.", .{});
            return err;
        };
        errdefer allocator.destroy(srv_allocator);
        srv_allocator.* = .{
            .cpu_start = dx12.getCpuDescriptorHandleForHeapStart(srv_descriptor_heap),
            .gpu_start = dx12.getGpuDescriptorHandleForHeapStart(srv_descriptor_heap),
            .increment = host_context.device.GetDescriptorHandleIncrementSize(.CBV_SRV_UAV),
        };

        var buffer_contexts_buffer: [max_buffer_count]BufferContext = undefined;
        var buffer_contexts_len: usize = 0;
        errdefer {
            const saved = misc.error_context.save();
            defer misc.error_context.restore(&saved);
            for (0..buffer_contexts_len) |index| {
                buffer_contexts_buffer[index].deinit();
            }
        }
        for (0..buffer_count) |index| {
            buffer_contexts_buffer[index] = BufferContext.init(
                host_context.device,
                host_context.swap_chain,
                rtv_descriptor_heap,
                dsv_descriptor_heap,
                @intCast(index),
            ) catch |err| {
                misc.error_context.append("Failed to create buffer context with index: {}", .{index});
                return err;
            };
            buffer_contexts_len += 1;
        }

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .allocator = allocator,
            .rtv_descriptor_heap = rtv_descriptor_heap,
            .dsv_descriptor_heap = dsv_descriptor_heap,
            .srv_descriptor_heap = srv_descriptor_heap,
            .srv_allocator = srv_allocator,
            .buffer_contexts_buffer = buffer_contexts_buffer,
            .buffer_contexts_len = buffer_contexts_len,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *Self) void {
        for (self.getBufferContexts()) |*context| {
            context.deinit();
        }

        self.allocator.destroy(self.srv_allocator);
        _ = self.srv_descriptor_heap.IUnknown.Release();
        _ = self.dsv_descriptor_heap.IUnknown.Release();
        _ = self.rtv_descriptor_heap.IUnknown.Release();

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }

    pub fn deinitBufferContexts(self: *Self) void {
        for (self.getBufferContexts()) |*context| {
            context.deinit();
        }
    }

    pub fn reinitBufferContexts(self: *Self, host_context: *const dx12.HostContext) !void {
        for (self.getBufferContexts(), 0..) |*context, index| {
            context.* = dx12.BufferContext.init(
                host_context.device,
                host_context.swap_chain,
                self.rtv_descriptor_heap,
                self.dsv_descriptor_heap,
                @intCast(index),
            ) catch |err| {
                misc.error_context.append("Failed to re-initialize buffer context with index: {}", .{index});
                return err;
            };
        }
    }

    pub fn getBufferContexts(self: *Self) []BufferContext {
        return self.buffer_contexts_buffer[0..self.buffer_contexts_len];
    }
};

pub const BufferContext = struct {
    command_allocator: *w32.ID3D12CommandAllocator,
    command_list: *w32.ID3D12GraphicsCommandList,
    resource: *w32.ID3D12Resource,
    rtv_descriptor_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    dsv_descriptor_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    fence: *w32.ID3D12Fence,
    fence_value: u64,
    fence_event: w32.HANDLE,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(
        device: *const w32.ID3D12Device,
        swap_chain: *const w32.IDXGISwapChain,
        rtv_descriptor_heap: *w32.ID3D12DescriptorHeap,
        dsv_descriptor_heap: *w32.ID3D12DescriptorHeap,
        index: u32,
    ) !Self {
        var command_allocator: *w32.ID3D12CommandAllocator = undefined;
        const allocator_result = device.CreateCommandAllocator(
            .DIRECT,
            w32.IID_ID3D12CommandAllocator,
            @ptrCast(&command_allocator),
        );
        if (dx12.Error.from(allocator_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateCommandAllocator returned a failure value.", .{});
            misc.error_context.append("Failed to create command allocator.", .{});
            return error.Dx12Error;
        }
        errdefer _ = command_allocator.IUnknown.Release();

        var command_list: *w32.ID3D12GraphicsCommandList = undefined;
        const list_result = device.CreateCommandList(
            0,
            .DIRECT,
            command_allocator,
            null,
            w32.IID_ID3D12GraphicsCommandList,
            @ptrCast(&command_list),
        );
        if (dx12.Error.from(list_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateCommandList returned a failure value.", .{});
            misc.error_context.append("Failed to create command list.", .{});
            return error.Dx12Error;
        }
        errdefer _ = command_list.IUnknown.Release();

        const close_result = command_list.Close();
        if (dx12.Error.from(close_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12GraphicsCommandList.Close returned a failure value.", .{});
            misc.error_context.append("Failed to close command list.", .{});
            return error.Dx12Error;
        }

        var resource: *w32.ID3D12Resource = undefined;
        const resource_result = swap_chain.GetBuffer(index, w32.IID_ID3D12Resource, @ptrCast(&resource));
        if (dx12.Error.from(resource_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGISwapChain.GetBuffer returned a failure value.", .{});
            misc.error_context.append("Failed to get buffer resource.", .{});
            return error.Dx12Error;
        }
        errdefer _ = resource.IUnknown.Release();

        const rtv_heap_start = dx12.getCpuDescriptorHandleForHeapStart(rtv_descriptor_heap);
        const rtv_increment_size = device.GetDescriptorHandleIncrementSize(.RTV);
        const rtv_descriptor_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{
            .ptr = rtv_heap_start.ptr + (index * rtv_increment_size),
        };
        device.CreateRenderTargetView(resource, null, rtv_descriptor_handle);

        const dsv_heap_start = dx12.getCpuDescriptorHandleForHeapStart(dsv_descriptor_heap);
        const dsv_increment_size = device.GetDescriptorHandleIncrementSize(.DSV);
        const dsv_descriptor_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{
            .ptr = dsv_heap_start.ptr + (index * dsv_increment_size),
        };

        var fence: *w32.ID3D12Fence = undefined;
        const fence_result = device.CreateFence(0, .{}, w32.IID_ID3D12Fence, @ptrCast(&fence));
        if (dx12.Error.from(fence_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Device.CreateFence returned a failure value.", .{});
            misc.error_context.append("Failed to create the fence.", .{});
            return error.Dx12Error;
        }
        errdefer _ = fence.IUnknown.Release();

        const fence_event = w32.CreateEventW(null, 0, 0, null) orelse {
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("CreateEventW returned null.", .{});
            misc.error_context.append("Failed to create the fence event.", .{});
            return error.OsError;
        };
        errdefer {
            const saved = misc.error_context.save();
            defer misc.error_context.restore(&saved);
            const success = w32.CloseHandle(fence_event);
            if (success == 0) {
                misc.error_context.new("{f}", .{os.Error.getLast()});
                misc.error_context.append("CloseHandle returned 0.", .{});
                misc.error_context.logError(error.OsError);
            }
        }

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .command_allocator = command_allocator,
            .command_list = command_list,
            .rtv_descriptor_handle = rtv_descriptor_handle,
            .dsv_descriptor_handle = dsv_descriptor_handle,
            .resource = resource,
            .fence = fence,
            .fence_value = 0,
            .fence_event = fence_event,
            .test_allocation = test_allocation,
        };
    }

    pub fn deinit(self: *const Self) void {
        const close_success = w32.CloseHandle(self.fence_event);
        if (close_success == 0) {
            misc.error_context.new("{f}", .{os.Error.getLast()});
            misc.error_context.append("CloseHandle returned 0.", .{});
            misc.error_context.append("Failed to close fence event.", .{});
            misc.error_context.logError(error.OsError);
        }
        _ = self.fence.IUnknown.Release();
        _ = self.resource.IUnknown.Release();
        _ = self.command_list.IUnknown.Release();
        _ = self.command_allocator.IUnknown.Release();

        if (builtin.is_test) {
            std.testing.allocator.destroy(self.test_allocation);
        }
    }
};

pub const Context = struct {
    window: w32.HWND,
    device: *const w32.ID3D12Device,
    command_queue: *const w32.ID3D12CommandQueue,
    swap_chain: *const w32.IDXGISwapChain,
    rtv_descriptor_heap: *w32.ID3D12DescriptorHeap,
    srv_descriptor_heap: *w32.ID3D12DescriptorHeap,
    srv_allocator: *dx12.DescriptorHeapAllocator(ManagedContext.srv_heap_size),
    buffer_contexts: []BufferContext,

    const Self = @This();

    pub fn fromHostAndManaged(host_context: *const HostContext, managed_context: *ManagedContext) Self {
        return .{
            .window = host_context.window,
            .device = host_context.device,
            .command_queue = host_context.command_queue,
            .swap_chain = host_context.swap_chain,
            .rtv_descriptor_heap = managed_context.rtv_descriptor_heap,
            .srv_descriptor_heap = managed_context.srv_descriptor_heap,
            .srv_allocator = managed_context.srv_allocator,
            .buffer_contexts = managed_context.getBufferContexts(),
        };
    }

    pub fn beforeRender(self: *Self) !*BufferContext {
        const swap_chain_3: *const w32.IDXGISwapChain3 = @ptrCast(self.swap_chain);
        const buffer_index = swap_chain_3.GetCurrentBackBufferIndex();
        if (buffer_index >= self.buffer_contexts.len) {
            misc.error_context.new(
                "IDXGISwapChain3.GetCurrentBackBufferIndex returned: {}",
                .{buffer_index},
            );
            misc.error_context.append(
                "Buffer index {} out of bounds. Buffer contexts length is: {}",
                .{ buffer_index, self.buffer_contexts.len },
            );
            return error.IndexOutOfBounds;
        }
        const buffer_context = &self.buffer_contexts[buffer_index];

        while (buffer_context.fence.GetCompletedValue() < buffer_context.fence_value) {
            _ = w32.WaitForSingleObject(buffer_context.fence_event, 10);
        }

        const allocator_result = buffer_context.command_allocator.Reset();
        if (dx12.Error.from(allocator_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12CommandAllocator.Reset returned a failure value.", .{});
            return error.Dx12Error;
        }

        const list_result = buffer_context.command_list.Reset(buffer_context.command_allocator, null);
        if (dx12.Error.from(list_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12GraphicsCommandList.Reset returned a failure value.", .{});
            return error.Dx12Error;
        }

        buffer_context.command_list.ResourceBarrier(1, &.{.{
            .Type = .TRANSITION,
            .Flags = .{ .BEGIN_ONLY = 1 },
            .Anonymous = .{ .Transition = .{
                .pResource = buffer_context.resource,
                .Subresource = w32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = w32.D3D12_RESOURCE_STATE_PRESENT,
                .StateAfter = w32.D3D12_RESOURCE_STATE_RENDER_TARGET,
            } },
        }});

        buffer_context.command_list.OMSetRenderTargets(1, &buffer_context.rtv_descriptor_handle, 0, null);

        var heaps = [1](?*w32.ID3D12DescriptorHeap){self.srv_descriptor_heap};
        buffer_context.command_list.SetDescriptorHeaps(1, &heaps);

        return buffer_context;
    }

    pub fn afterRender(self: *Self, buffer_context: *BufferContext) !void {
        buffer_context.command_list.ResourceBarrier(1, &.{.{
            .Type = .TRANSITION,
            .Flags = .{ .END_ONLY = 1 },
            .Anonymous = .{ .Transition = .{
                .pResource = buffer_context.resource,
                .Subresource = w32.D3D12_RESOURCE_BARRIER_ALL_SUBRESOURCES,
                .StateBefore = w32.D3D12_RESOURCE_STATE_RENDER_TARGET,
                .StateAfter = w32.D3D12_RESOURCE_STATE_PRESENT,
            } },
        }});

        const list_result = buffer_context.command_list.Close();
        if (dx12.Error.from(list_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12GraphicsCommandList.Close returned a failure value.", .{});
            return error.Dx12Error;
        }

        var lists = [1](?*w32.ID3D12CommandList){@ptrCast(buffer_context.command_list)};
        self.command_queue.ExecuteCommandLists(1, &lists);

        const next_fence_value = buffer_context.fence_value +% 1;

        const signal_result = self.command_queue.Signal(buffer_context.fence, next_fence_value);
        if (dx12.Error.from(signal_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12CommandQueue.Signal returned a failure value.", .{});
            return error.Dx12Error;
        }
        buffer_context.fence_value = next_fence_value;

        const set_event_result = buffer_context.fence.SetEventOnCompletion(
            buffer_context.fence_value,
            buffer_context.fence_event,
        );
        if (dx12.Error.from(set_event_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12Fence.SetEventOnCompletion returned a failure value.", .{});
            return error.Dx12Error;
        }
    }

    pub fn waitForGpu(self: *const Self) void {
        for (self.buffer_contexts) |*buffer_context| {
            while (buffer_context.fence.GetCompletedValue() < buffer_context.fence_value) {
                _ = w32.WaitForSingleObject(buffer_context.fence_event, 10);
            }
        }
    }

    pub fn getBackBufferSize(self: *const Self) !math.Vector(2, u32) {
        var swap_chain_desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
        const result = self.swap_chain.GetDesc(&swap_chain_desc);
        if (dx12.Error.from(result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGISwapChain.GetDesc returned a failure value.", .{});
            return error.Dx12Error;
        }
        return .fromArray(.{
            swap_chain_desc.BufferDesc.Width,
            swap_chain_desc.BufferDesc.Height,
        });
    }

    pub fn setViewports(
        self: *const Self,
        buffer_context: *const dx12.BufferContext,
        viewports: []const w32.D3D12_VIEWPORT,
    ) void {
        _ = self;
        buffer_context.command_list.RSSetViewports(@intCast(viewports.len), viewports.ptr);
    }

    pub fn setScissorRectangles(
        self: *const Self,
        buffer_context: *const dx12.BufferContext,
        rectangles: []const w32.RECT,
    ) void {
        _ = self;
        buffer_context.command_list.RSSetScissorRects(@intCast(rectangles.len), rectangles.ptr);
    }

    pub fn setDefaultViewportsAndScissors(self: *const Self, buffer_context: *const dx12.BufferContext) !void {
        const size = self.getBackBufferSize() catch |err| {
            misc.error_context.append("Failed to get back buffer size.", .{});
            return err;
        };
        self.setViewports(buffer_context, &.{.{
            .TopLeftX = 0,
            .TopLeftY = 0,
            .Width = @floatFromInt(size.x()),
            .Height = @floatFromInt(size.y()),
            .MinDepth = 0,
            .MaxDepth = 1,
        }});
        self.setScissorRectangles(buffer_context, &.{.{
            .left = 0,
            .top = 0,
            .right = @intCast(size.x()),
            .bottom = @intCast(size.y()),
        }});
    }

    pub fn setDepthBuffer(
        self: *const Self,
        buffer_context: *const dx12.BufferContext,
        depth_buffer_maybe: ?*w32.ID3D12Resource,
    ) !void {
        const depth_buffer = depth_buffer_maybe orelse {
            buffer_context.command_list.OMSetRenderTargets(
                1,
                &buffer_context.rtv_descriptor_handle,
                0,
                null,
            );
            return;
        };

        // Bypass for this issue: https://github.com/marlersoft/zigwin32/issues/6
        const getResourceDesc: *const fn (
            self: *const w32.ID3D12Resource,
            out: *w32.D3D12_RESOURCE_DESC,
        ) callconv(.winapi) void = @ptrCast(depth_buffer.vtable.GetDesc);
        var depth_buffer_desc: w32.D3D12_RESOURCE_DESC = undefined;
        getResourceDesc(depth_buffer, &depth_buffer_desc);
        if (depth_buffer_desc.Dimension != .TEXTURE2D) {
            misc.error_context.new(
                "Expected depth buffer to be a 2D texture but got: {s}",
                .{@tagName(depth_buffer_desc.Dimension)},
            );
            return error.Dx12Error;
        }
        const depth_buffer_size = math.Vector(2, u32).fromArray(.{
            @intCast(depth_buffer_desc.Width),
            depth_buffer_desc.Height,
        });
        const back_buffer_size = self.getBackBufferSize() catch |err| {
            misc.error_context.append("Failed to get back buffer size.", .{});
            return err;
        };
        if (!std.meta.eql(depth_buffer_size, back_buffer_size)) {
            misc.error_context.new(
                "Depth buffer size {f} does not match the back buffer size {f}.",
                .{ depth_buffer_size, back_buffer_size },
            );
            return error.SizeMismatch;
        }

        const dsv_desc = w32.D3D12_DEPTH_STENCIL_VIEW_DESC{
            .Format = switch (depth_buffer_desc.Format) {
                .R32G8X24_TYPELESS => .D32_FLOAT_S8X24_UINT,
                .R24G8_TYPELESS => .D24_UNORM_S8_UINT,
                .R32_TYPELESS => .D32_FLOAT,
                .R16_TYPELESS => .D16_UNORM,
                else => {
                    misc.error_context.new("Unexpected depth buffer format: {s}", .{@tagName(depth_buffer_desc.Format)});
                    return error.Dx12Error;
                },
            },
            .ViewDimension = .TEXTURE2D,
            .Flags = .{},
            .Anonymous = .{ .Texture2D = .{ .MipSlice = 0 } },
        };
        self.device.CreateDepthStencilView(depth_buffer, &dsv_desc, buffer_context.dsv_descriptor_handle);
        buffer_context.command_list.OMSetRenderTargets(
            1,
            &buffer_context.rtv_descriptor_handle,
            0,
            &buffer_context.dsv_descriptor_handle,
        );
    }
};

const testing = std.testing;

test "ManagedContext init and deinit should succeed" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
}

test "Context beforeRender and afterRender should succeed" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.setDefaultViewportsAndScissors(buffer_context);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}

test "ManagedContext deinitBufferContexts and reinitBufferContexts should succeed" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.setDefaultViewportsAndScissors(buffer_context);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
    managed_context.deinitBufferContexts();
    try managed_context.reinitBufferContexts(&host_context);
    for (0..10) |_| {
        const buffer_context = try context.beforeRender();
        try context.setDefaultViewportsAndScissors(buffer_context);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}

test "Context.getBackBufferSize should return correct value" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    const size = try context.getBackBufferSize();
    try testing.expectEqual(200, size.x());
    try testing.expectEqual(100, size.y());
}
