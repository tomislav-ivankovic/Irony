const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const math = @import("../math/root.zig");
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
    gpu_state: ?GpuState,

    const Self = @This();

    pub fn fromHostAndManaged(host_context: *const HostContext, managed_context: *ManagedContext) Self {
        return .{
            .window = host_context.window,
            .device = host_context.device,
            .device_context = host_context.device_context,
            .swap_chain = host_context.swap_chain,
            .buffer_context = &managed_context.buffer_context,
            .gpu_state = null,
        };
    }

    pub fn beforeRender(self: *Self) !*BufferContext {
        var views = [1](?*w32.ID3D11RenderTargetView){self.buffer_context.render_target_view};
        self.device_context.OMSetRenderTargets(views.len, &views, null);

        if (self.gpu_state != null) {
            misc.error_context.new("Unexpected already captured GPU state. Probably called beforeRender twice.", .{});
            return error.UnexpectedState;
        }
        self.gpu_state = .capture(self.device_context);

        return self.buffer_context;
    }

    pub fn afterRender(self: *Self, buffer_context: *BufferContext) !void {
        _ = buffer_context;
        if (self.gpu_state) |*gpu_state| {
            gpu_state.restore(self.device_context);
            gpu_state.release();
            self.gpu_state = null;
        } else {
            misc.error_context.new("Unexpected missing GPU state. Probably did not call beforeRender.", .{});
            return error.UnexpectedState;
        }
    }

    pub fn waitForGpu(self: *const Self) void {
        _ = self;
    }

    pub fn getBackBufferSize(self: *const Self) !math.Vector(2, u32) {
        var swap_chain_desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
        const result = self.swap_chain.GetDesc(&swap_chain_desc);
        if (dx11.Error.from(result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("IDXGISwapChain.GetDesc returned a failure value.", .{});
            return error.Dx11Error;
        }
        return .fromArray(.{
            swap_chain_desc.BufferDesc.Width,
            swap_chain_desc.BufferDesc.Height,
        });
    }

    pub fn setViewports(
        self: *const Self,
        buffer_context: *const dx11.BufferContext,
        viewports: []const w32.D3D11_VIEWPORT,
    ) void {
        _ = buffer_context;
        self.device_context.RSSetViewports(@intCast(viewports.len), viewports.ptr);
    }

    pub fn setScissorRectangles(
        self: *const Self,
        buffer_context: *const dx11.BufferContext,
        rectangles: []const w32.RECT,
    ) void {
        _ = buffer_context;
        self.device_context.RSSetScissorRects(@intCast(rectangles.len), rectangles.ptr);
    }

    pub fn setDefaultViewportsAndScissors(self: *const Self, buffer_context: *const dx11.BufferContext) !void {
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
        buffer_context: *const dx11.BufferContext,
        depth_buffer_maybe: ?*w32.ID3D11Texture2D,
    ) !void {
        const depth_buffer = depth_buffer_maybe orelse {
            var render_target_views = [1]?*w32.ID3D11RenderTargetView{buffer_context.render_target_view};
            self.device_context.OMSetRenderTargets(render_target_views.len, &render_target_views, null);
            return;
        };

        var depth_buffer_desc: w32.D3D11_TEXTURE2D_DESC = undefined;
        depth_buffer.GetDesc(&depth_buffer_desc);
        const depth_buffer_size = math.Vector(2, u32).fromArray(.{
            depth_buffer_desc.Width,
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

        const dsv_desc = w32.D3D11_DEPTH_STENCIL_VIEW_DESC{
            .Format = switch (depth_buffer_desc.Format) {
                .R32G8X24_TYPELESS => .D32_FLOAT_S8X24_UINT,
                .R24G8_TYPELESS => .D24_UNORM_S8_UINT,
                .R32_TYPELESS => .D32_FLOAT,
                .R16_TYPELESS => .D16_UNORM,
                else => {
                    misc.error_context.new("Unexpected depth buffer format: {s}", .{@tagName(depth_buffer_desc.Format)});
                    return error.Dx11Error;
                },
            },
            .ViewDimension = .TEXTURE2D,
            .Flags = 0,
            .Anonymous = .{ .Texture2D = .{ .MipSlice = 0 } },
        };
        var depth_stencil_view: *w32.ID3D11DepthStencilView = undefined;
        const result = self.device.CreateDepthStencilView(&depth_buffer.ID3D11Resource, &dsv_desc, &depth_stencil_view);
        if (dx11.Error.from(result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D11Device.CreateDepthStencilView returned a failure value.", .{});
            return error.Dx11Error;
        }
        defer _ = depth_stencil_view.IUnknown.Release();

        var render_target_views = [1]?*w32.ID3D11RenderTargetView{buffer_context.render_target_view};
        self.device_context.OMSetRenderTargets(render_target_views.len, &render_target_views, depth_stencil_view);
    }
};

const GpuState = struct {
    blend_state: ?*w32.ID3D11BlendState,
    blend_factor: [4]f32,
    sample_mask: u32,
    depth_stencil_state: ?*w32.ID3D11DepthStencilState,
    depth_stencil_ref: u32,
    rasterizer_state: ?*w32.ID3D11RasterizerState,
    topology: w32.D3D_PRIMITIVE_TOPOLOGY,
    vertex_buffers: [w32.D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]?*w32.ID3D11Buffer,
    vertex_strides: [w32.D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]u32,
    vertex_offsets: [w32.D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT]u32,
    vertex_constant_buffers: [w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT]?*w32.ID3D11Buffer,
    pixel_constant_buffers: [w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT]?*w32.ID3D11Buffer,
    geometry_constant_buffers: [w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT]?*w32.ID3D11Buffer,
    vertex_shader: ?*w32.ID3D11VertexShader,
    pixel_shader: ?*w32.ID3D11PixelShader,
    geometry_shader: ?*w32.ID3D11GeometryShader,
    input_layout: ?*w32.ID3D11InputLayout,
    number_of_viewports: u32,
    viewports: [w32.D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE]w32.D3D11_VIEWPORT,
    number_of_scissor_rects: u32,
    scissor_rects: [w32.D3D11_VIEWPORT_AND_SCISSORRECT_OBJECT_COUNT_PER_PIPELINE]w32.RECT,

    const Self = @This();

    pub fn capture(device_context: *const w32.ID3D11DeviceContext) Self {
        var self: Self = .{
            .blend_state = null,
            .blend_factor = .{ 0, 0, 0, 0 },
            .sample_mask = 0,
            .depth_stencil_state = null,
            .depth_stencil_ref = 0,
            .rasterizer_state = null,
            .topology = ._PRIMITIVE_TOPOLOGY_UNDEFINED,
            .vertex_buffers = @splat(null),
            .vertex_strides = @splat(0),
            .vertex_offsets = @splat(0),
            .vertex_constant_buffers = @splat(null),
            .pixel_constant_buffers = @splat(null),
            .geometry_constant_buffers = @splat(null),
            .vertex_shader = null,
            .pixel_shader = null,
            .geometry_shader = null,
            .input_layout = null,
            .number_of_viewports = 0,
            .viewports = @splat(.{
                .TopLeftX = 0,
                .TopLeftY = 0,
                .Width = 0,
                .Height = 0,
                .MinDepth = 0,
                .MaxDepth = 0,
            }),
            .number_of_scissor_rects = 0,
            .scissor_rects = @splat(.{
                .left = 0,
                .top = 0,
                .right = 0,
                .bottom = 0,
            }),
        };
        device_context.OMGetBlendState(
            &self.blend_state,
            &self.blend_factor[0],
            &self.sample_mask,
        );
        device_context.OMGetDepthStencilState(
            &self.depth_stencil_state,
            &self.depth_stencil_ref,
        );
        device_context.RSGetState(&self.rasterizer_state);
        device_context.IAGetPrimitiveTopology(&self.topology);
        device_context.IAGetVertexBuffers(
            0,
            w32.D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT,
            &self.vertex_buffers,
            &self.vertex_strides,
            &self.vertex_offsets,
        );
        device_context.VSGetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.vertex_constant_buffers,
        );
        device_context.PSGetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.pixel_constant_buffers,
        );
        device_context.GSGetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.geometry_constant_buffers,
        );
        device_context.VSGetShader(&self.vertex_shader, null, null);
        device_context.PSGetShader(&self.pixel_shader, null, null);
        device_context.GSGetShader(&self.geometry_shader, null, null);
        device_context.IAGetInputLayout(&self.input_layout);
        device_context.RSGetViewports(&self.number_of_viewports, null);
        device_context.RSGetViewports(&self.number_of_viewports, &self.viewports);
        device_context.RSGetScissorRects(&self.number_of_scissor_rects, null);
        device_context.RSGetScissorRects(&self.number_of_scissor_rects, &self.scissor_rects);
        return self;
    }

    pub fn release(self: *Self) void {
        if (self.blend_state) |blend_state| {
            _ = blend_state.IUnknown.Release();
            self.blend_state = null;
        }
        if (self.depth_stencil_state) |depth_stencil_state| {
            _ = depth_stencil_state.IUnknown.Release();
            self.depth_stencil_state = null;
        }
        if (self.rasterizer_state) |rasterizer_state| {
            _ = rasterizer_state.IUnknown.Release();
            self.rasterizer_state = null;
        }
        for (&self.vertex_buffers) |*buffer_maybe| {
            if (buffer_maybe.*) |buffer| {
                _ = buffer.IUnknown.Release();
                buffer_maybe.* = null;
            }
        }
        for (&self.vertex_constant_buffers) |*buffer_maybe| {
            if (buffer_maybe.*) |buffer| {
                _ = buffer.IUnknown.Release();
                buffer_maybe.* = null;
            }
        }
        for (&self.pixel_constant_buffers) |*buffer_maybe| {
            if (buffer_maybe.*) |buffer| {
                _ = buffer.IUnknown.Release();
                buffer_maybe.* = null;
            }
        }
        for (&self.geometry_constant_buffers) |*buffer_maybe| {
            if (buffer_maybe.*) |buffer| {
                _ = buffer.IUnknown.Release();
                buffer_maybe.* = null;
            }
        }
        if (self.vertex_shader) |vertex_shader| {
            _ = vertex_shader.IUnknown.Release();
            self.vertex_shader = null;
        }
        if (self.pixel_shader) |pixel_shader| {
            _ = pixel_shader.IUnknown.Release();
            self.pixel_shader = null;
        }
        if (self.geometry_shader) |geometry_shader| {
            _ = geometry_shader.IUnknown.Release();
            self.geometry_shader = null;
        }
        if (self.input_layout) |input_layout| {
            _ = input_layout.IUnknown.Release();
            self.input_layout = null;
        }
    }

    pub fn restore(self: *Self, device_context: *const w32.ID3D11DeviceContext) void {
        device_context.OMSetBlendState(self.blend_state, &self.blend_factor[0], self.sample_mask);
        device_context.OMSetDepthStencilState(self.depth_stencil_state, self.depth_stencil_ref);
        device_context.RSSetState(self.rasterizer_state);
        device_context.IASetPrimitiveTopology(self.topology);
        device_context.IASetVertexBuffers(
            0,
            w32.D3D11_IA_VERTEX_INPUT_RESOURCE_SLOT_COUNT,
            &self.vertex_buffers,
            &self.vertex_strides,
            &self.vertex_offsets,
        );
        device_context.VSSetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.vertex_constant_buffers,
        );
        device_context.PSSetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.pixel_constant_buffers,
        );
        device_context.GSSetConstantBuffers(
            0,
            w32.D3D11_COMMONSHADER_CONSTANT_BUFFER_API_SLOT_COUNT,
            &self.geometry_constant_buffers,
        );
        device_context.VSSetShader(self.vertex_shader, null, 0);
        device_context.PSSetShader(self.pixel_shader, null, 0);
        device_context.GSSetShader(self.geometry_shader, null, 0);
        device_context.IASetInputLayout(self.input_layout);
        device_context.RSSetViewports(self.number_of_viewports, &self.viewports);
        device_context.RSSetScissorRects(self.number_of_scissor_rects, &self.scissor_rects);
    }
};

const testing = std.testing;

test "ManagedContext init and deinit should succeed" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
}

test "Context beforeRender and afterRender should succeed" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
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
    const testing_context = try dx11.TestingContext.init();
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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    const context = Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);
    const size = try context.getBackBufferSize();
    try testing.expectEqual(200, size.x());
    try testing.expectEqual(100, size.y());
}
