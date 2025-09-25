const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const os = @import("../os/root.zig");
const dx12 = @import("root.zig");

pub fn Context(comptime buffer_count: usize, comptime svr_heap_size: usize) type {
    return struct {
        allocator: std.mem.Allocator,
        rtv_descriptor_heap: *w32.ID3D12DescriptorHeap,
        srv_descriptor_heap: *w32.ID3D12DescriptorHeap,
        srv_allocator: *dx12.DescriptorHeapAllocator(svr_heap_size),
        buffer_contexts: [buffer_count]BufferContext,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();

        pub fn init(
            allocator: std.mem.Allocator,
            device: *const w32.ID3D12Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) !Self {
            var rtv_descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
            const rtv_result = device.CreateDescriptorHeap(&.{
                .Type = .RTV,
                .NumDescriptors = buffer_count,
                .Flags = .{},
                .NodeMask = 1,
            }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&rtv_descriptor_heap));
            if (dx12.Error.from(rtv_result)) |err| {
                misc.error_context.new("{}", .{err});
                misc.error_context.append("ID3D12Device.CreateDescriptorHeap returned a failure value.", .{});
                misc.error_context.append("Failed to create RTV descriptor heap.", .{});
                return error.Dx12Error;
            }
            errdefer _ = rtv_descriptor_heap.IUnknown.Release();

            var srv_descriptor_heap: *w32.ID3D12DescriptorHeap = undefined;
            const srv_result = device.CreateDescriptorHeap(&.{
                .Type = .CBV_SRV_UAV,
                .NumDescriptors = svr_heap_size,
                .Flags = .{ .SHADER_VISIBLE = 1 },
                .NodeMask = 0,
            }, w32.IID_ID3D12DescriptorHeap, @ptrCast(&srv_descriptor_heap));
            if (dx12.Error.from(srv_result)) |err| {
                misc.error_context.new("{}", .{err});
                misc.error_context.append("ID3D12Device.CreateDescriptorHeap returned a failure value.", .{});
                misc.error_context.append("Failed to create SRV descriptor heap.", .{});
                return error.Dx12Error;
            }
            errdefer _ = srv_descriptor_heap.IUnknown.Release();

            const srv_allocator = allocator.create(dx12.DescriptorHeapAllocator(svr_heap_size)) catch |err| {
                misc.error_context.new("Failed to allocate a SRV allocator.", .{});
                return err;
            };
            errdefer allocator.destroy(srv_allocator);
            srv_allocator.* = .{
                .cpu_start = dx12.getCpuDescriptorHandleForHeapStart(srv_descriptor_heap),
                .gpu_start = dx12.getGpuDescriptorHandleForHeapStart(srv_descriptor_heap),
                .increment = device.GetDescriptorHandleIncrementSize(.CBV_SRV_UAV),
            };

            var buffer_contexts: [buffer_count]BufferContext = undefined;
            inline for (0..buffer_contexts.len) |index| {
                buffer_contexts[index] = BufferContext.init(
                    device,
                    swap_chain,
                    rtv_descriptor_heap,
                    index,
                ) catch |err| {
                    misc.error_context.append("Failed to create buffer context with index: {}", .{index});
                    return err;
                };
                errdefer buffer_contexts[index].deinit();
            }

            const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

            return .{
                .allocator = allocator,
                .rtv_descriptor_heap = rtv_descriptor_heap,
                .srv_descriptor_heap = srv_descriptor_heap,
                .srv_allocator = srv_allocator,
                .buffer_contexts = buffer_contexts,
                .test_allocation = test_allocation,
            };
        }

        pub fn deinit(self: *const Self) void {
            inline for (self.buffer_contexts) |context| {
                context.deinit();
            }

            self.allocator.destroy(self.srv_allocator);
            _ = self.srv_descriptor_heap.IUnknown.Release();
            _ = self.rtv_descriptor_heap.IUnknown.Release();

            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn deinitBufferContexts(self: *const Self) void {
            inline for (self.buffer_contexts) |buffer_context| {
                buffer_context.deinit();
            }
        }

        pub fn reinitBufferContexts(
            self: *Self,
            device: *const w32.ID3D12Device,
            swap_chain: *const w32.IDXGISwapChain,
        ) !void {
            inline for (0..self.buffer_contexts.len) |index| {
                self.buffer_contexts[index] = dx12.BufferContext.init(
                    device,
                    swap_chain,
                    self.rtv_descriptor_heap,
                    index,
                ) catch |err| {
                    misc.error_context.append("Failed to reinitialize buffer context with index: {}", .{index});
                    return err;
                };
            }
        }
    };
}

pub const BufferContext = struct {
    command_allocator: *w32.ID3D12CommandAllocator,
    command_list: *w32.ID3D12GraphicsCommandList,
    resource: *w32.ID3D12Resource,
    rtv_descriptor_handle: w32.D3D12_CPU_DESCRIPTOR_HANDLE,
    fence: *w32.ID3D12Fence,
    fence_value: u64,
    fence_event: w32.HANDLE,
    test_allocation: if (builtin.is_test) *u8 else void,

    const Self = @This();

    pub fn init(
        device: *const w32.ID3D12Device,
        swap_chain: *const w32.IDXGISwapChain,
        rtv_descriptor_heap: *w32.ID3D12DescriptorHeap,
        index: u32,
    ) !Self {
        var command_allocator: *w32.ID3D12CommandAllocator = undefined;
        const allocator_result = device.CreateCommandAllocator(
            .DIRECT,
            w32.IID_ID3D12CommandAllocator,
            @ptrCast(&command_allocator),
        );
        if (dx12.Error.from(allocator_result)) |err| {
            misc.error_context.new("{}", .{err});
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
            misc.error_context.new("{}", .{err});
            misc.error_context.append("ID3D12Device.CreateCommandList returned a failure value.", .{});
            misc.error_context.append("Failed to create command list.", .{});
            return error.Dx12Error;
        }
        errdefer _ = command_list.IUnknown.Release();

        const close_result = command_list.Close();
        if (dx12.Error.from(close_result)) |err| {
            misc.error_context.new("{}", .{err});
            misc.error_context.append("ID3D12GraphicsCommandList.Close returned a failure value.", .{});
            misc.error_context.append("Failed to close command list.", .{});
            return error.Dx12Error;
        }

        var resource: *w32.ID3D12Resource = undefined;
        const resource_result = swap_chain.GetBuffer(index, w32.IID_ID3D12Resource, @ptrCast(&resource));
        if (dx12.Error.from(resource_result)) |err| {
            misc.error_context.new("{}", .{err});
            misc.error_context.append("IDXGISwapChain.GetBuffer returned a failure value.", .{});
            misc.error_context.append("Failed to get buffer resource.", .{});
            return error.Dx12Error;
        }
        errdefer _ = resource.IUnknown.Release();

        const rtv_heap_start = dx12.getCpuDescriptorHandleForHeapStart(rtv_descriptor_heap);
        const rtv_increment_size = device.GetDescriptorHandleIncrementSize(.RTV);
        const rtv_descriptor_handle = w32.D3D12_CPU_DESCRIPTOR_HANDLE{
            .ptr = rtv_heap_start.ptr + index * rtv_increment_size,
        };
        device.CreateRenderTargetView(resource, null, rtv_descriptor_handle);

        var fence: *w32.ID3D12Fence = undefined;
        const fence_result = device.CreateFence(0, .{}, w32.IID_ID3D12Fence, @ptrCast(&fence));
        if (dx12.Error.from(fence_result)) |err| {
            misc.error_context.new("{}", .{err});
            misc.error_context.append("ID3D12Device.CreateFence returned a failure value.", .{});
            misc.error_context.append("Failed to create the fence.", .{});
            return error.Dx12Error;
        }
        errdefer _ = fence.IUnknown.Release();

        const fence_event = w32.CreateEventW(null, 0, 0, null) orelse {
            misc.error_context.new("{}", .{os.Error.getLast()});
            misc.error_context.append("CreateEventW returned null.", .{});
            misc.error_context.append("Failed to create the fence event.", .{});
            return error.OsError;
        };
        errdefer {
            const success = w32.CloseHandle(fence_event);
            if (success == 0) {
                misc.error_context.new("{}", .{os.Error.getLast()});
                misc.error_context.append("CloseHandle returned 0.", .{});
                misc.error_context.logError(error.OsError);
            }
        }

        const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

        return .{
            .command_allocator = command_allocator,
            .command_list = command_list,
            .rtv_descriptor_handle = rtv_descriptor_handle,
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
            misc.error_context.new("{}", .{os.Error.getLast()});
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

pub fn beforeRender(
    comptime buffer_count: usize,
    comptime srv_heap_size: usize,
    context: *Context(buffer_count, srv_heap_size),
    swap_chain: *const w32.IDXGISwapChain,
) !*BufferContext {
    const swap_chain_3: *const w32.IDXGISwapChain3 = @ptrCast(swap_chain);
    const buffer_index = swap_chain_3.GetCurrentBackBufferIndex();
    if (buffer_index >= buffer_count) {
        misc.error_context.new(
            "IDXGISwapChain3.GetCurrentBackBufferIndex returned: {}",
            .{buffer_index},
        );
        misc.error_context.append(
            "Buffer index {} out of bounds. Buffer count is: {}",
            .{ buffer_index, buffer_count },
        );
        return error.IndexOutOfBounds;
    }
    const buffer_context = &context.buffer_contexts[buffer_index];

    while (buffer_context.fence.GetCompletedValue() < buffer_context.fence_value) {
        _ = w32.WaitForSingleObject(buffer_context.fence_event, 10);
    }

    const allocator_result = buffer_context.command_allocator.Reset();
    if (dx12.Error.from(allocator_result)) |err| {
        misc.error_context.new("{}", .{err});
        misc.error_context.append("ID3D12CommandAllocator.Reset returned a failure value.", .{});
        return error.Dx12Error;
    }

    const list_result = buffer_context.command_list.Reset(buffer_context.command_allocator, null);
    if (dx12.Error.from(list_result)) |err| {
        misc.error_context.new("{}", .{err});
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

    var heaps = [1](?*w32.ID3D12DescriptorHeap){context.srv_descriptor_heap};
    buffer_context.command_list.SetDescriptorHeaps(1, &heaps);

    return buffer_context;
}

pub fn afterRender(
    buffer_context: *BufferContext,
    command_queue: *const w32.ID3D12CommandQueue,
) !void {
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
        misc.error_context.new("{}", .{err});
        misc.error_context.append("ID3D12GraphicsCommandList.Close returned a failure value.", .{});
        return error.Dx12Error;
    }

    var lists = [1](?*w32.ID3D12CommandList){@ptrCast(buffer_context.command_list)};
    command_queue.ExecuteCommandLists(1, &lists);

    const next_fence_value = buffer_context.fence_value +% 1;

    const signal_result = command_queue.Signal(buffer_context.fence, next_fence_value);
    if (dx12.Error.from(signal_result)) |err| {
        misc.error_context.new("{}", .{err});
        misc.error_context.append("ID3D12CommandQueue.Signal returned a failure value.", .{});
        return error.Dx12Error;
    }
    buffer_context.fence_value = next_fence_value;

    const set_event_result = buffer_context.fence.SetEventOnCompletion(
        buffer_context.fence_value,
        buffer_context.fence_event,
    );
    if (dx12.Error.from(set_event_result)) |err| {
        misc.error_context.new("{}", .{err});
        misc.error_context.append("ID3D12Fence.SetEventOnCompletion returned a failure value.", .{});
        return error.Dx12Error;
    }
}

const testing = std.testing;

test "init and deinit should succeed" {
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const context = try Context(3, 64).init(testing.allocator, testing_context.device, testing_context.swap_chain);
    defer context.deinit();
}

test "beforeRender and afterRender should succeed" {
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    var context = try Context(3, 64).init(testing.allocator, testing_context.device, testing_context.swap_chain);
    defer context.deinit();
    for (0..10) |_| {
        const buffer_context = try beforeRender(3, 64, &context, testing_context.swap_chain);
        try afterRender(buffer_context, testing_context.command_queue);
    }
}

test "deinitBufferContexts and reinitBufferContexts should succeed" {
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    var context = try Context(3, 64).init(testing.allocator, testing_context.device, testing_context.swap_chain);
    defer context.deinit();
    for (0..10) |_| {
        const buffer_context = try beforeRender(3, 64, &context, testing_context.swap_chain);
        try afterRender(buffer_context, testing_context.command_queue);
    }
    context.deinitBufferContexts();
    try context.reinitBufferContexts(testing_context.device, testing_context.swap_chain);
    for (0..10) |_| {
        const buffer_context = try beforeRender(3, 64, &context, testing_context.swap_chain);
        try afterRender(buffer_context, testing_context.command_queue);
    }
}
