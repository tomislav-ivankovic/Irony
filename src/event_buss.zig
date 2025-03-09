const std = @import("std");
const w32 = @import("win32").everything;
const dx12 = @import("dx12/root.zig");
const misc = @import("misc/root.zig");

pub const EventBuss = struct {
    gpa: std.heap.GeneralPurposeAllocator(.{}),
    dx12_leftovers: ?dx12.Leftovers,

    const Self = @This();

    pub fn init(
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) Self {
        _ = window;
        _ = command_queue;
        _ = swap_chain;

        const gpa = std.heap.GeneralPurposeAllocator(.{}){};

        std.log.debug("Initializing DX12 leftovers...", .{});
        const dx12_leftovers = if (dx12.Leftovers.init(device)) |leftovers| block: {
            std.log.info("DX12 leftovers initialized.", .{});
            break :block leftovers;
        } else |err| block: {
            misc.errorContext().append(err, "Failed to initialize DX12 leftovers.");
            misc.errorContext().logError();
            break :block null;
        };

        return .{
            .gpa = gpa,
            .dx12_leftovers = dx12_leftovers,
        };
    }

    pub fn deinit(
        self: *Self,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = window;
        _ = device;
        _ = command_queue;
        _ = swap_chain;

        std.log.debug("De-initializing DX12 leftovers...", .{});
        if (self.dx12_leftovers) |leftovers| {
            leftovers.deinit();
            std.log.info("DX12 leftovers de-initialized.", .{});
        } else {
            std.log.debug("Nothing to de-initialize.", .{});
        }

        switch (self.gpa.deinit()) {
            .ok => {},
            .leak => std.log.err("GPA detected a memory leak.", .{}),
        }
    }

    pub fn update(
        self: *Self,
        window: w32.HWND,
        device: *const w32.ID3D12Device,
        command_queue: *const w32.ID3D12CommandQueue,
        swap_chain: *const w32.IDXGISwapChain,
    ) void {
        _ = self;
        _ = window;
        _ = device;
        _ = command_queue;
        _ = swap_chain;
    }
};
