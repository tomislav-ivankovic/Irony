const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const math = @import("../math/root.zig");
const dx12 = @import("root.zig");

pub fn Shader(Vertex: type, Index: type, Constants: type) type {
    return struct {
        primitive_topology: w32.D3D_PRIMITIVE_TOPOLOGY,
        root_signature: *w32.ID3D12RootSignature,
        pipeline_state: *w32.ID3D12PipelineState,
        vertex_buffers: BufferSet,
        index_buffers: BufferSet,
        constant_buffers: BufferSet,
        vertex_count: u32,
        index_count: u32,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();
        const BufferSet = struct {
            buffers: [max_back_buffer_count]?Buffer = @splat(null),
            current_index: usize = 0,
            last_back_buffer_index: u32 = 0,
        };
        const Buffer = struct {
            resource: *w32.ID3D12Resource,
            size: u32,
            mapped_data: [*]u8,
        };
        const max_back_buffer_count = 4;

        pub fn init(context: *const dx12.Context, config: *const dx12.ShaderConfig) !Self {
            const device = context.device;

            const vertex_blob = compile(config.source_code, "vs_main", "vs_5_0") catch |err| {
                misc.error_context.append("Failed to compile vertex_shader.", .{});
                return err;
            };
            defer _ = vertex_blob.IUnknown.Release();

            const pixel_blob = compile(config.source_code, "ps_main", "ps_5_0") catch |err| {
                misc.error_context.append("Failed to compile.", .{});
                return err;
            };
            defer _ = pixel_blob.IUnknown.Release();

            const geometry_blob = switch (config.use_geometry_shader) {
                true => compile(config.source_code, "gs_main", "gs_5_0") catch |err| {
                    misc.error_context.append("Failed to compile.", .{});
                    return err;
                },
                false => null,
            };
            defer if (geometry_blob) |blob| {
                _ = blob.IUnknown.Release();
            };

            var reflection: *w32.ID3D12ShaderReflection = undefined;
            const reflect_result = w32.D3DReflect(
                @ptrCast(vertex_blob.GetBufferPointer()),
                vertex_blob.GetBufferSize(),
                w32.IID_ID3D12ShaderReflection,
                @ptrCast(&reflection),
            );
            if (dx12.Error.from(reflect_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3DReflect returned a failure value.", .{});
                return error.Dx12Error;
            }
            defer _ = reflection.IUnknown.Release();

            checkVertexLayout(Vertex, reflection) catch |err| {
                misc.error_context.append("Vertex layout check failed.", .{});
                return err;
            };
            checkConstantsLayout(Constants, reflection) catch |err| {
                misc.error_context.append("Constants layout check failed.", .{});
                return err;
            };

            const params = w32.D3D12_ROOT_PARAMETER{
                .ParameterType = .CBV,
                .Anonymous = .{ .Descriptor = .{
                    .ShaderRegister = 0,
                    .RegisterSpace = 0,
                } },
                .ShaderVisibility = .ALL,
            };
            const root_signature_desc = w32.D3D12_VERSIONED_ROOT_SIGNATURE_DESC{
                .Version = w32.D3D_ROOT_SIGNATURE_VERSION_1_0,
                .Anonymous = .{ .Desc_1_0 = .{
                    .NumParameters = switch (Constants) {
                        void => 0,
                        else => 1,
                    },
                    .pParameters = switch (Constants) {
                        void => null,
                        else => &params,
                    },
                    .NumStaticSamplers = 0,
                    .pStaticSamplers = null,
                    .Flags = .{ .ALLOW_INPUT_ASSEMBLER_INPUT_LAYOUT = 1 },
                } },
            };
            var root_signature_blob_maybe: ?*w32.ID3DBlob = null;
            var error_blob: ?*w32.ID3DBlob = null;
            const serialize_result = w32.D3D12SerializeVersionedRootSignature(
                &root_signature_desc,
                &root_signature_blob_maybe,
                &error_blob,
            );
            defer if (error_blob) |blob| {
                _ = blob.IUnknown.Release();
            };
            if (dx12.Error.from(serialize_result)) |err| {
                misc.error_context.clear();
                if (error_blob) |blob| {
                    const base: [*c]u8 = @ptrCast(blob.GetBufferPointer());
                    const compile_error = std.mem.sliceTo(base[0..blob.GetBufferSize()], 0);
                    misc.error_context.append("{s}", .{compile_error});
                }
                misc.error_context.append("{f}", .{err});
                misc.error_context.append("D3D12SerializeRootSignature returned a failure value.", .{});
                return error.Dx12Error;
            }
            const root_signature_blob = root_signature_blob_maybe orelse {
                misc.error_context.new("D3D12SerializeRootSignature returned a null pointer to the blob.", .{});
                return error.Dx12Error;
            };
            defer _ = root_signature_blob.IUnknown.Release();

            var root_signature: *w32.ID3D12RootSignature = undefined;
            const signature_result = device.CreateRootSignature(
                0,
                @ptrCast(root_signature_blob.GetBufferPointer()),
                root_signature_blob.GetBufferSize(),
                w32.IID_ID3D12RootSignature,
                @ptrCast(&root_signature),
            );
            if (dx12.Error.from(signature_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D12Device.CreateRootSignature returned a failure value.", .{});
                return error.Dx12Error;
            }
            errdefer _ = root_signature.IUnknown.Release();

            const pipeline_state_desc = w32.D3D12_GRAPHICS_PIPELINE_STATE_DESC{
                .pRootSignature = root_signature,
                .VS = .{
                    .pShaderBytecode = vertex_blob.GetBufferPointer(),
                    .BytecodeLength = vertex_blob.GetBufferSize(),
                },
                .PS = .{
                    .pShaderBytecode = pixel_blob.GetBufferPointer(),
                    .BytecodeLength = pixel_blob.GetBufferSize(),
                },
                .DS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
                .HS = .{ .pShaderBytecode = null, .BytecodeLength = 0 },
                .GS = if (geometry_blob) |blob| .{
                    .pShaderBytecode = blob.GetBufferPointer(),
                    .BytecodeLength = blob.GetBufferSize(),
                } else .{ .pShaderBytecode = null, .BytecodeLength = 0 },
                .StreamOutput = .{
                    .pSODeclaration = null,
                    .NumEntries = 0,
                    .pBufferStrides = null,
                    .NumStrides = 0,
                    .RasterizedStream = 0,
                },
                .BlendState = config.blend.toNative(),
                .SampleMask = 0xFFFFFFFF,
                .RasterizerState = config.rasterizer.toNative(),
                .DepthStencilState = config.getNativeDepthStencil(),
                .InputLayout = getInputLayoutDesc(Vertex),
                .IBStripCutValue = .DISABLED,
                .PrimitiveTopologyType = config.primitive_topology.toNativeType(),
                .NumRenderTargets = 1,
                .RTVFormats = [1]w32.DXGI_FORMAT{.R8G8B8A8_UNORM} ++ @as([7]w32.DXGI_FORMAT, @splat(.UNKNOWN)),
                .DSVFormat = .D32_FLOAT,
                .SampleDesc = .{ .Count = 1, .Quality = 0 },
                .NodeMask = 0,
                .CachedPSO = .{ .pCachedBlob = null, .CachedBlobSizeInBytes = 0 },
                .Flags = .{},
            };
            var pipeline_state: *w32.ID3D12PipelineState = undefined;
            const state_result = device.CreateGraphicsPipelineState(
                &pipeline_state_desc,
                w32.IID_ID3D12PipelineState,
                @ptrCast(&pipeline_state),
            );
            if (dx12.Error.from(state_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D12Device.CreateGraphicsPipelineState returned a failure value.", .{});
                return error.Dx12Error;
            }
            errdefer _ = pipeline_state.IUnknown.Release();

            const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

            return .{
                .primitive_topology = config.primitive_topology.toNative(),
                .root_signature = root_signature,
                .pipeline_state = pipeline_state,
                .vertex_buffers = .{},
                .index_buffers = .{},
                .constant_buffers = .{},
                .vertex_count = 0,
                .index_count = 0,
                .test_allocation = test_allocation,
            };
        }

        pub fn deinit(self: *const Self, context: *const dx12.Context) void {
            context.waitForGpu();
            for (&self.constant_buffers.buffers) |buffer_maybe| {
                if (buffer_maybe) |*buffer| {
                    _ = buffer.resource.IUnknown.Release();
                }
            }
            for (&self.index_buffers.buffers) |buffer_maybe| {
                if (buffer_maybe) |*buffer| {
                    _ = buffer.resource.IUnknown.Release();
                }
            }
            for (&self.vertex_buffers.buffers) |buffer_maybe| {
                if (buffer_maybe) |*buffer| {
                    _ = buffer.resource.IUnknown.Release();
                }
            }
            _ = self.pipeline_state.IUnknown.Release();
            _ = self.root_signature.IUnknown.Release();

            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn setVertices(self: *Self, context: *const dx12.Context, vertices: []const Vertex) !void {
            setBufferData(Vertex, context, &self.vertex_buffers, vertices, .vertex) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
            self.vertex_count = @intCast(vertices.len);
        }

        pub fn setIndices(self: *Self, context: *const dx12.Context, indices: []const Index) !void {
            if (Index == void) {
                @compileError("This function is not defined for indices of type void.");
            }
            setBufferData(Index, context, &self.index_buffers, indices, .index) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
            self.index_count = @intCast(indices.len);
        }

        pub fn setConstants(self: *Self, context: *const dx12.Context, constants: *const Constants) !void {
            if (Constants == void) {
                @compileError("This function is not defined for constants of type void.");
            }
            setBufferData(Constants, context, &self.constant_buffers, constants[0..1], .constant) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
        }

        pub fn draw(self: *const Self, context: *const dx12.Context, buffer_context: *const dx12.BufferContext) !void {
            _ = context;
            const command_list = buffer_context.command_list;

            const vertex_buffer_maybe = self.vertex_buffers.buffers[self.vertex_buffers.current_index];
            const index_buffer_maybe = self.index_buffers.buffers[self.index_buffers.current_index];
            const constant_buffer_maybe = self.constant_buffers.buffers[self.constant_buffers.current_index];

            const vertex_buffer = vertex_buffer_maybe orelse {
                misc.error_context.new("Vertices never set.", .{});
                return error.MissingVertices;
            };
            if (Index != void and index_buffer_maybe == null) {
                misc.error_context.new("Indices never set.", .{});
                return error.MissingIndices;
            }
            if (Constants != void and constant_buffer_maybe == null) {
                misc.error_context.new("Constants never set.", .{});
                return error.MissingConstants;
            }

            command_list.SetGraphicsRootSignature(self.root_signature);
            command_list.SetPipelineState(self.pipeline_state);
            command_list.IASetPrimitiveTopology(self.primitive_topology);
            if (constant_buffer_maybe) |*buffer| {
                command_list.SetGraphicsRootConstantBufferView(
                    0,
                    buffer.resource.GetGPUVirtualAddress(),
                );
            }
            const vertex_view = w32.D3D12_VERTEX_BUFFER_VIEW{
                .BufferLocation = vertex_buffer.resource.GetGPUVirtualAddress(),
                .SizeInBytes = vertex_buffer.size,
                .StrideInBytes = @sizeOf(Vertex),
            };
            command_list.IASetVertexBuffers(0, 1, (&vertex_view)[0..1]);

            const format: w32.DXGI_FORMAT = switch (Index) {
                void => {
                    command_list.DrawInstanced(self.vertex_count, 1, 0, 0);
                    return;
                },
                u16 => .R16_UINT,
                u32 => .R32_UINT,
                else => @compileError("Expecting Index to be void, u16 or u32 but got: " ++ @typeName(Index)),
            };
            const index_buffer = index_buffer_maybe.?;
            command_list.IASetIndexBuffer(&.{
                .BufferLocation = index_buffer.resource.GetGPUVirtualAddress(),
                .SizeInBytes = index_buffer.size,
                .Format = format,
            });
            command_list.DrawIndexedInstanced(self.index_count, 1, 0, 0, 0);
        }

        fn setBufferData(
            comptime Element: type,
            context: *const dx12.Context,
            buffer_set: *BufferSet,
            data: []const Element,
            buffer_type: enum { vertex, index, constant },
        ) !void {
            const device = context.device;

            var swap_chain_desc: w32.DXGI_SWAP_CHAIN_DESC = undefined;
            const swap_chain_result = context.swap_chain.GetDesc(&swap_chain_desc);
            if (dx12.Error.from(swap_chain_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("IDXGISwapChain.GetDesc returned a failure value.", .{});
                return error.Dx12Error;
            }
            const back_buffer_count = swap_chain_desc.BufferCount;
            if (back_buffer_count > max_back_buffer_count) {
                misc.error_context.new(
                    "Back buffer count {} exceeds maximum allowed: {}",
                    .{ back_buffer_count, max_back_buffer_count },
                );
                return error.Dx12Error;
            }
            const swap_chain_3: *const w32.IDXGISwapChain3 = @ptrCast(context.swap_chain);
            const back_buffer_index = swap_chain_3.GetCurrentBackBufferIndex();

            const next_index = switch (back_buffer_index == buffer_set.last_back_buffer_index) {
                true => buffer_set.current_index,
                false => switch (buffer_set.current_index + 1 < back_buffer_count) {
                    true => buffer_set.current_index + 1,
                    false => 0,
                },
            };

            const len = std.math.cast(u32, data.len) orelse {
                misc.error_context.new("Overflow while casting vertices length.", .{});
                return error.Overflow;
            };
            const bytes_needed = std.math.mul(u32, len, @sizeOf(Element)) catch |err| {
                misc.error_context.new("Overflow while calculating bytes needed.", .{});
                return err;
            };

            const buffer_maybe = &buffer_set.buffers[next_index];
            if (buffer_maybe.*) |*buffer| {
                if (bytes_needed > buffer.size) {
                    _ = buffer.resource.IUnknown.Release();
                    buffer_maybe.* = null;
                }
            }

            const buffer = buffer_maybe.* orelse block: {
                errdefer misc.error_context.append("Failed to (re)allocate the buffer.", .{});
                const size = switch (buffer_type) {
                    .vertex, .index => std.math.ceilPowerOfTwo(u32, @max(bytes_needed, 1024)) catch std.math.maxInt(u32),
                    .constant => b: {
                        if (@sizeOf(Constants) > std.math.maxInt(u32) - 255) {
                            misc.error_context.new("Overflow while calculating size.", .{});
                            return error.Overflow;
                        }
                        break :b std.mem.alignForward(u32, bytes_needed, 256);
                    },
                };

                const props = w32.D3D12_HEAP_PROPERTIES{
                    .Type = .UPLOAD,
                    .CPUPageProperty = .UNKNOWN,
                    .MemoryPoolPreference = .UNKNOWN,
                    .CreationNodeMask = 0,
                    .VisibleNodeMask = 0,
                };
                const desc = w32.D3D12_RESOURCE_DESC{
                    .Dimension = .BUFFER,
                    .Alignment = 0,
                    .Width = size,
                    .Height = 1,
                    .DepthOrArraySize = 1,
                    .MipLevels = 1,
                    .Format = .UNKNOWN,
                    .SampleDesc = .{ .Count = 1, .Quality = 0 },
                    .Layout = .ROW_MAJOR,
                    .Flags = .{},
                };
                var resource: *w32.ID3D12Resource = undefined;
                const resource_result = device.CreateCommittedResource(
                    &props,
                    .{},
                    &desc,
                    w32.D3D12_RESOURCE_STATE_GENERIC_READ,
                    null,
                    w32.IID_ID3D12Resource,
                    @ptrCast(&resource),
                );
                if (dx12.Error.from(resource_result)) |err| {
                    misc.error_context.new("{f}", .{err});
                    misc.error_context.append("ID3D12Device.CreateCommittedResource returned a failure value.", .{});
                    return error.Dx12Error;
                }

                var mapped_maybe: ?*anyopaque = null;
                const map_result = resource.Map(0, &.{ .Begin = 0, .End = 0 }, &mapped_maybe);
                if (dx12.Error.from(map_result)) |err| {
                    misc.error_context.new("{f}", .{err});
                    misc.error_context.append("ID3D12Resource.Map returned a failure value.", .{});
                    return error.Dx12Error;
                }
                const mapped = mapped_maybe orelse {
                    misc.error_context.new("ID3D12Resource.Map returned a null pointer to data.", .{});
                    return error.Dx12Error;
                };

                const buffer = Buffer{
                    .resource = resource,
                    .size = size,
                    .mapped_data = @ptrCast(mapped),
                };
                buffer_maybe.* = buffer;
                break :block buffer;
            };

            if (buffer_type == .constant) {
                @memset(buffer.mapped_data[0..buffer.size], 0);
            }
            @memcpy(buffer.mapped_data, std.mem.sliceAsBytes(data));
            buffer_set.current_index = next_index;
            buffer_set.last_back_buffer_index = back_buffer_index;
        }
    };
}

fn compile(source_code: [:0]const u8, entry_point: [:0]const u8, target: [:0]const u8) !*w32.ID3DBlob {
    var shader_blob: ?*w32.ID3DBlob = null;
    var error_blob: ?*w32.ID3DBlob = null;
    const result = w32.D3DCompile(
        source_code.ptr,
        source_code.len,
        null,
        null,
        null,
        entry_point,
        target,
        w32.D3DCOMPILE_PACK_MATRIX_ROW_MAJOR,
        0,
        &shader_blob,
        &error_blob,
    );
    errdefer if (shader_blob) |blob| {
        _ = blob.IUnknown.Release();
    };
    defer if (error_blob) |blob| {
        _ = blob.IUnknown.Release();
    };
    if (dx12.Error.from(result)) |err| {
        misc.error_context.clear();
        if (error_blob) |blob| {
            const base: [*c]u8 = @ptrCast(blob.GetBufferPointer());
            const compile_error = std.mem.sliceTo(base[0..blob.GetBufferSize()], 0);
            misc.error_context.append("{s}", .{compile_error});
        }
        misc.error_context.append("{f}", .{err});
        misc.error_context.append("D3DCompile returned a failure value.", .{});
        return error.Dx12Error;
    }
    return shader_blob orelse {
        misc.error_context.new("D3DCompile returned a null pointer to result blob.", .{});
        return error.Dx12Error;
    };
}

inline fn getInputLayoutDesc(comptime Vertex: type) w32.D3D12_INPUT_LAYOUT_DESC {
    const final = comptime block: {
        const info = switch (@typeInfo(Vertex)) {
            .@"struct" => |*info| info,
            else => @compileError("Expecting Vertex to be a struct type but got: " ++ @typeName(Vertex)),
        };
        if (info.layout != .@"extern") {
            @compileError(std.fmt.comptimePrint(
                "Expecting vertex struct {s} to have extern layout but got: {s}",
                .{ @typeName(Vertex), @tagName(info.layout) },
            ));
        }
        if (@sizeOf(Vertex) % 16 != 0) {
            @compileError(std.fmt.comptimePrint(
                "Expecting size of vertex struct {s} to be divisible with 16 but got: {}",
                .{ @typeName(Vertex), @sizeOf(Vertex) },
            ));
        }
        var result: [info.field_names.len]w32.D3D12_INPUT_ELEMENT_DESC = undefined;
        var len: usize = 0;
        for (info.field_names, info.field_types) |field_name, Field| {
            if (field_name.len == 0 or field_name[0] == '_') {
                continue;
            }
            result[len] = .{
                .SemanticName = field_name,
                .SemanticIndex = 0,
                .Format = getInputParameterInfo(Field).type_format,
                .InputSlot = 0,
                .AlignedByteOffset = @offsetOf(Vertex, field_name),
                .InputSlotClass = .VERTEX_DATA,
                .InstanceDataStepRate = 0,
            };
            len += 1;
        }
        break :block result[0..len].*;
    };
    return .{
        .pInputElementDescs = &final[0],
        .NumElements = final.len,
    };
}

fn checkVertexLayout(comptime Vertex: type, reflection: *const w32.ID3D12ShaderReflection) !void {
    const info = switch (@typeInfo(Vertex)) {
        .@"struct" => |*info| info,
        else => @compileError("Expecting Vertex to be a struct type but got: " ++ @typeName(Vertex)),
    };
    if (info.layout != .@"extern") {
        @compileError(std.fmt.comptimePrint(
            "Expecting vertex struct {s} to have extern layout but got: {s}",
            .{ @typeName(Vertex), @tagName(info.layout) },
        ));
    }

    var shader_desc: w32.D3D12_SHADER_DESC = undefined;
    const shader_result = reflection.GetDesc(&shader_desc);
    if (dx12.Error.from(shader_result)) |err| {
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("ID3D12ShaderReflection.GetDesc returned a failure value.", .{});
        return error.Dx12Error;
    }

    for (0..shader_desc.InputParameters) |gpu_parameter_index| {
        var gpu_parameter: w32.D3D12_SIGNATURE_PARAMETER_DESC = undefined;
        const parameter_result = reflection.GetInputParameterDesc(@intCast(gpu_parameter_index), &gpu_parameter);
        if (dx12.Error.from(parameter_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12ShaderReflection.GetInputParameterDesc returned a failure value.", .{});
            misc.error_context.append("Check failed for GPU input parameter at index: {}", .{gpu_parameter_index});
            return error.Dx12Error;
        }
        const gpu_name_start = gpu_parameter.SemanticName orelse {
            misc.error_context.new("Input parameter has no semantic name.", .{});
            misc.error_context.append("Check failed for GPU input parameter at index: {}", .{gpu_parameter_index});
            return error.Dx12Error;
        };
        const gpu_name = std.mem.sliceTo(gpu_name_start, 0);
        errdefer misc.error_context.append("Check failed for GPU input parameter: {s}", .{gpu_name});

        inline for (info.field_names, info.field_types) |cpu_name, CpuType| {
            if (std.mem.eql(u8, cpu_name, gpu_name)) {
                const cpu_parameter = getInputParameterInfo(CpuType);
                if (gpu_parameter.ComponentType != cpu_parameter.component_type) {
                    misc.error_context.new(
                        "GPU component type {s} does not match the CPU component type: {s}",
                        .{ @tagName(gpu_parameter.ComponentType), @tagName(cpu_parameter.component_type) },
                    );
                    return error.Dx12Error;
                }
                if (@popCount(gpu_parameter.Mask) != cpu_parameter.component_count) {
                    misc.error_context.new(
                        "GPU component count {} does not match the CPU component count: {}",
                        .{ @popCount(gpu_parameter.Mask), cpu_parameter.component_count },
                    );
                    return error.Dx12Error;
                }
                break;
            }
        } else {
            misc.error_context.new("Failed to find CPU struct field that matches GPU input parameter.", .{});
            return error.Dx12Error;
        }
    }

    const number_of_cpu_fields = comptime block: {
        var result: usize = 0;
        for (info.field_names) |field_name| {
            if (field_name.len != 0 and field_name[0] != '_') {
                result += 1;
            }
        }
        break :block result;
    };
    if (shader_desc.InputParameters != number_of_cpu_fields) {
        misc.error_context.new(
            "Found {} vertex parameters on the GPU side while the CPU side contains only {} vertex fields.",
            .{ shader_desc.InputParameters, number_of_cpu_fields },
        );
        return error.Dx12Error;
    }
}

fn checkConstantsLayout(comptime Constants: type, reflection: *const w32.ID3D12ShaderReflection) !void {
    const cpu_names: []const [:0]const u8, const cpu_types: []const type = switch (@typeInfo(Constants)) {
        .void => .{ &.{}, &.{} },
        .@"struct" => |*info| block: {
            if (info.layout != .@"extern") {
                @compileError(std.fmt.comptimePrint(
                    "Expecting constants struct {s} to have extern layout but got: {s}",
                    .{ @typeName(Constants), @tagName(info.layout) },
                ));
            }
            break :block .{ info.field_names, info.field_types };
        },
        else => @compileError("Expecting Constants to be a struct type but got: " ++ @typeName(Constants)),
    };

    const gpu_constants = reflection.GetConstantBufferByName("Constants") orelse {
        if (cpu_names.len == 0) {
            return;
        }
        misc.error_context.new("Failed to find cbuffer called Constants inside the shader.", .{});
        return error.Dx12Error;
    };

    var number_of_cpu_fields: usize = 0;
    inline for (cpu_names, cpu_types) |cpu_name, cpu_type| {
        errdefer misc.error_context.append("Check failed for CPU field: {s}", .{cpu_name});
        if (cpu_name.len == 0 or cpu_name[0] == '_') {
            continue;
        }
        const gpu_variable = gpu_constants.GetVariableByName(cpu_name) orelse {
            misc.error_context.append("Failed to find a GPU variable with matching name.", .{});
            return error.Dx12Error;
        };
        var gpu_variable_desc: w32.D3D12_SHADER_VARIABLE_DESC = undefined;
        const desc_result = gpu_variable.GetDesc(&gpu_variable_desc);
        if (dx12.Error.from(desc_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D12ShaderReflectionVariable.GetDesc returned a failure value.", .{});
            return error.Dx12Error;
        }
        if (gpu_variable_desc.StartOffset != @offsetOf(Constants, cpu_name)) {
            misc.error_context.new(
                "GPU offset {} does not match the CPU offset: {}",
                .{ gpu_variable_desc.StartOffset, @offsetOf(Constants, cpu_name) },
            );
            return error.Dx12Error;
        }
        if (gpu_variable_desc.Size != @sizeOf(cpu_type)) {
            misc.error_context.new(
                "GPU size {} does not match the CPU size: {}",
                .{ gpu_variable_desc.Size, @sizeOf(cpu_type) },
            );
            return error.Dx12Error;
        }
        number_of_cpu_fields += 1;
    }

    var gpu_constants_desc: w32.D3D12_SHADER_BUFFER_DESC = undefined;
    const desc_result = gpu_constants.GetDesc(&gpu_constants_desc);
    if (dx12.Error.from(desc_result)) |err| {
        if (cpu_names.len == 0) {
            return;
        }
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("ID3D12ShaderReflectionConstantBuffer.GetDesc returned a failure value.", .{});
        return error.Dx12Error;
    }
    if (gpu_constants_desc.Variables != number_of_cpu_fields) {
        misc.error_context.new(
            "Found {} constant variables on the GPU side while the CPU side contains only {} constant fields.",
            .{ gpu_constants_desc.Variables, number_of_cpu_fields },
        );
        return error.Dx12Error;
    }
}

const InputParameterInfo = struct {
    type_format: w32.DXGI_FORMAT,
    component_type: w32.D3D_REGISTER_COMPONENT_TYPE,
    component_count: usize,
};

inline fn getInputParameterInfo(comptime Type: type) InputParameterInfo {
    const info = struct {
        inline fn call(
            type_format: w32.DXGI_FORMAT,
            component_type: w32.D3D_REGISTER_COMPONENT_TYPE,
            component_count: usize,
        ) InputParameterInfo {
            return .{
                .type_format = type_format,
                .component_type = component_type,
                .component_count = component_count,
            };
        }
    }.call;
    const u_type = w32.D3D_REGISTER_COMPONENT_TYPE._REGISTER_COMPONENT_UINT32;
    const i_type = w32.D3D_REGISTER_COMPONENT_TYPE._REGISTER_COMPONENT_SINT32;
    const f_type = w32.D3D_REGISTER_COMPONENT_TYPE._REGISTER_COMPONENT_FLOAT32;
    return switch (Type) {
        u8 => info(.R8_UINT, u_type, 1),
        [1]u8 => info(.R8_UINT, u_type, 1),
        [2]u8 => info(.R8G8_UINT, u_type, 2),
        [3]u8 => info(.R8G8B8_UINT, u_type, 3),
        [4]u8 => info(.R8G8B8A8_UINT, u_type, 4),
        math.Vector(1, u8) => info(.R8_UINT, u_type, 1),
        math.Vector(2, u8) => info(.R8G8_UINT, u_type, 2),
        math.Vector(3, u8) => info(.R8G8B8_UINT, u_type, 3),
        math.Vector(4, u8) => info(.R8G8B8A8_UINT, u_type, 4),
        i8 => info(.R8_SINT, i_type, 1),
        [1]i8 => info(.R8_SINT, i_type, 1),
        [2]i8 => info(.R8G8_SINT, i_type, 2),
        [3]i8 => info(.R8G8B8_SINT, i_type, 3),
        [4]i8 => info(.R8G8B8A8_SINT, i_type, 4),
        math.Vector(1, i8) => info(.R8_SINT, i_type, 1),
        math.Vector(2, i8) => info(.R8G8_SINT, i_type, 2),
        math.Vector(3, i8) => info(.R8G8B8_SINT, i_type, 3),
        math.Vector(4, i8) => info(.R8G8B8A8_SINT, i_type, 4),
        u16 => info(.R16_UINT, u_type, 1),
        [1]u16 => info(.R16_UINT, u_type, 1),
        [2]u16 => info(.R16G16_UINT, u_type, 2),
        [3]u16 => info(.R16G16B16_UINT, u_type, 3),
        [4]u16 => info(.R16G16B16A16_UINT, u_type, 4),
        math.Vector(1, u16) => info(.R16_UINT, u_type, 1),
        math.Vector(2, u16) => info(.R16G16_UINT, u_type, 2),
        math.Vector(3, u16) => info(.R16G16B16_UINT, u_type, 3),
        math.Vector(4, u16) => info(.R16G16B16A16_UINT, u_type, 4),
        i16 => info(.R16_SINT, i_type, 1),
        [1]i16 => info(.R16_SINT, i_type, 1),
        [2]i16 => info(.R16G16_SINT, i_type, 2),
        [3]i16 => info(.R16G16B16_SINT, i_type, 3),
        [4]i16 => info(.R16G16B16A16_SINT, i_type, 4),
        math.Vector(1, i16) => info(.R16_SINT, i_type, 1),
        math.Vector(2, i16) => info(.R16G16_SINT, i_type, 2),
        math.Vector(3, i16) => info(.R16G16B16_SINT, i_type, 3),
        math.Vector(4, i16) => info(.R16G16B16A16_SINT, i_type, 4),
        f16 => info(.R16_FLOAT, f_type, 1),
        [1]f16 => info(.R16_FLOAT, f_type, 1),
        [2]f16 => info(.R16G16_FLOAT, f_type, 2),
        [3]f16 => info(.R16G16B16_FLOAT, f_type, 3),
        [4]f16 => info(.R16G16B16A16_FLOAT, f_type, 4),
        math.Vector(1, f16) => info(.R16_FLOAT, f_type, 1),
        math.Vector(2, f16) => info(.R16G16_FLOAT, f_type, 2),
        math.Vector(3, f16) => info(.R16G16B16_FLOAT, f_type, 3),
        math.Vector(4, f16) => info(.R16G16B16A16_FLOAT, f_type, 4),
        u32 => info(.R32_UINT, u_type, 1),
        [1]u32 => info(.R32_UINT, u_type, 1),
        [2]u32 => info(.R32G32_UINT, u_type, 2),
        [3]u32 => info(.R32G32B32_UINT, u_type, 3),
        [4]u32 => info(.R32G32B32A32_UINT, u_type, 4),
        math.Vector(1, u32) => info(.R32_UINT, u_type, 1),
        math.Vector(2, u32) => info(.R32G32_UINT, u_type, 2),
        math.Vector(3, u32) => info(.R32G32B32_UINT, u_type, 3),
        math.Vector(4, u32) => info(.R32G32B32A32_UINT, u_type, 4),
        i32 => info(.R32_SINT, i_type, 1),
        [1]i32 => info(.R32_SINT, i_type, 1),
        [2]i32 => info(.R32G32_SINT, i_type, 2),
        [3]i32 => info(.R32G32B32_SINT, i_type, 3),
        [4]i32 => info(.R32G32B32A32_SINT, i_type, 4),
        math.Vector(1, i32) => info(.R32_SINT, i_type, 1),
        math.Vector(2, i32) => info(.R32G32_SINT, i_type, 2),
        math.Vector(3, i32) => info(.R32G32B32_SINT, i_type, 3),
        math.Vector(4, i32) => info(.R32G32B32A32_SINT, i_type, 4),
        f32 => info(.R32_FLOAT, f_type, 1),
        [1]f32 => info(.R32_FLOAT, f_type, 1),
        [2]f32 => info(.R32G32_FLOAT, f_type, 2),
        [3]f32 => info(.R32G32B32_FLOAT, f_type, 3),
        [4]f32 => info(.R32G32B32A32_FLOAT, f_type, 4),
        math.Vector(1, f32) => info(.R32_FLOAT, f_type, 1),
        math.Vector(2, f32) => info(.R32G32_FLOAT, f_type, 2),
        math.Vector(3, f32) => info(.R32G32B32_FLOAT, f_type, 3),
        math.Vector(4, f32) => info(.R32G32B32A32_FLOAT, f_type, 4),
        else => @compileError("Unsupported vertex attribute type: " ++ @typeName(Type)),
    };
}

const testing = std.testing;

test "should succeed in drawing a shader with only vertices" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float3 position : position;
        \\    float4 color : color;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\    float4 color: COLOR;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position.xyz = vertex.position;
        \\    pixel.position.w = 1;
        \\    pixel.color = vertex.color;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    return pixel.color;
        \\}
    ;
    const Vertex = extern struct {
        position: math.Vec3,
        _padding: f32 = 0,
        color: math.Vec4,
    };

    var shader = try Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code });
    defer shader.deinit(&context);

    for (0..10) |frame| {
        if (frame % 2 == 0) {
            const f: f32 = @floatFromInt(frame);
            try shader.setVertices(&context, &.{
                .{ .position = .fromArray(.{ f * (-0.1), f * (-0.1), 0.5 }), .color = .fromArray(.{ 1, 0, 0, 1 }) },
                .{ .position = .fromArray(.{ f * 0.1, f * (-0.1), 0 }), .color = .fromArray(.{ 0, 1, 0, 1 }) },
                .{ .position = .fromArray(.{ 0, f * 0.1, 0 }), .color = .fromArray(.{ 0, 0, 1, 1 }) },
            });
        }
        const buffer_context = try context.beforeRender();
        try context.setDefaultViewportsAndScissors(buffer_context);
        try shader.draw(&context, buffer_context);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}

test "should succeed in drawing a shader with vertices, indices and constants" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float3 position : position;
        \\    float4 color : color;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\    float4 color: COLOR;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float4x4 world_to_clip;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position.xyz = vertex.position;
        \\    pixel.position.w = 1;
        \\    pixel.position = mul(pixel.position, world_to_clip);
        \\    pixel.color = vertex.color;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    return pixel.color;
        \\}
    ;
    const Vertex = extern struct {
        position: math.Vec3,
        _padding: f32 = 0,
        color: math.Vec4,
    };
    const Constants = extern struct {
        world_to_clip: math.Mat4,
    };

    var shader = try Shader(Vertex, u16, Constants).init(&context, &.{ .source_code = source_code });
    defer shader.deinit(&context);

    for (0..10) |frame| {
        if (frame % 2 == 0) {
            const f: f32 = @floatFromInt(frame);
            try shader.setVertices(&context, &.{
                .{ .position = .fromArray(.{ f * (-0.1), f * (-0.1), 0.5 }), .color = .fromArray(.{ 1, 0, 0, 1 }) },
                .{ .position = .fromArray(.{ f * 0.1, f * (-0.1), 0 }), .color = .fromArray(.{ 0, 1, 0, 1 }) },
                .{ .position = .fromArray(.{ 0, f * 0.1, 0 }), .color = .fromArray(.{ 0, 0, 1, 1 }) },
            });
            try shader.setIndices(&context, &.{ 0, 1, 2 });
            try shader.setConstants(&context, &.{ .world_to_clip = .identity });
        }
        const buffer_context = try context.beforeRender();
        try context.setDefaultViewportsAndScissors(buffer_context);
        try shader.draw(&context, buffer_context);
        try context.afterRender(buffer_context);
        try testing_context.present();
    }
}

test "init should error when source code has syntax error" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const Vertex = extern struct { vec: math.Vec4 };
    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = "syntax error" }),
    );
}

test "init should error when vertex field is missing on CPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\    float4 color : color;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\    float4 color : COLOR;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.color = vertex.color;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    return pixel.color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex field is missing on GPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4, color: math.Vec4 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex input parameter has different component type on CPU compared to GPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vector(4, i32) };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex input parameter has different component count on CPU compared to GPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec3, _padding: f32 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field is missing on CPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float4x4 transform_1;
        \\    float4x4 transform_2;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.position = mul(pixel.position, transform_1);
        \\    pixel.position = mul(pixel.position, transform_2);
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };
    const Constants = extern struct { transform_1: math.Mat4 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field is missing on GPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float4x4 transform_1;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.position = mul(pixel.position, transform_1);
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };
    const Constants = extern struct { transform_1: math.Mat4, transform_2: math.Mat4 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field has different offset on GPU then on CPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float3 offset_1;
        \\    float3 offset_2;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.position.xyz += offset_1;
        \\    pixel.position.xyz += offset_2;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };
    const Constants = extern struct { offset_1: math.Vec3, offset_2: math.Vec3 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field has different size on GPU then on CPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float4x4 transform;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.position = mul(pixel.position, transform);
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };
    const Constants = extern struct { transform: math.Mat3 };

    try testing.expectError(
        error.Dx12Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "draw should error when vertices are not set" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };

    var shader = try Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code });
    defer shader.deinit(&context);

    const buffer_context = try context.beforeRender();
    defer context.afterRender(buffer_context) catch @panic("Failed to execute afterRender().");
    try context.setDefaultViewportsAndScissors(buffer_context);

    try testing.expectError(error.MissingVertices, shader.draw(&context, buffer_context));
}

test "draw should error when indices are not set" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };

    var shader = try Shader(Vertex, u32, void).init(&context, &.{ .source_code = source_code });
    defer shader.deinit(&context);

    try shader.setVertices(&context, &.{
        .{ .position = .fromArray(.{ 0.1, 0.1, 0.1, 1.0 }) },
        .{ .position = .fromArray(.{ 0.2, 0.2, 0.2, 1.0 }) },
        .{ .position = .fromArray(.{ 0.3, 0.3, 0.3, 1.0 }) },
    });

    const buffer_context = try context.beforeRender();
    defer context.afterRender(buffer_context) catch @panic("Failed to execute afterRender().");
    try context.setDefaultViewportsAndScissors(buffer_context);

    try testing.expectError(error.MissingIndices, shader.draw(&context, buffer_context));
}

test "draw should error when constants are not set" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx12.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx12.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx12.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const source_code =
        \\struct Vertex {
        \\    float4 position : position;
        \\};
        \\struct Pixel {
        \\    float4 position: SV_POSITION;
        \\};
        \\cbuffer Constants : register(b0) {
        \\    float4x4 transform;
        \\}
        \\Pixel vs_main(Vertex vertex) {
        \\    Pixel pixel;
        \\    pixel.position = vertex.position;
        \\    pixel.position = mul(pixel.position, transform);
        \\    return pixel;
        \\}
        \\float4 ps_main(Pixel pixel) : SV_TARGET {
        \\    float4 color = { 1.0f, 1.0f, 1.0f, 1.0f };
        \\    return color;
        \\}
    ;
    const Vertex = extern struct { position: math.Vec4 };
    const Constants = extern struct { transform: math.Mat4 };

    var shader = try Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code });
    defer shader.deinit(&context);

    try shader.setVertices(&context, &.{
        .{ .position = .fromArray(.{ 0.1, 0.1, 0.1, 1.0 }) },
        .{ .position = .fromArray(.{ 0.2, 0.2, 0.2, 1.0 }) },
        .{ .position = .fromArray(.{ 0.3, 0.3, 0.3, 1.0 }) },
    });

    const buffer_context = try context.beforeRender();
    defer context.afterRender(buffer_context) catch @panic("Failed to execute afterRender().");
    try context.setDefaultViewportsAndScissors(buffer_context);

    try testing.expectError(error.MissingConstants, shader.draw(&context, buffer_context));
}
