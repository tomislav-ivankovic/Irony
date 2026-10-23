const std = @import("std");
const builtin = @import("builtin");
const w32 = @import("win32").everything;
const misc = @import("../misc/root.zig");
const math = @import("../math/root.zig");
const dx11 = @import("root.zig");

pub fn Shader(Vertex: type, Index: type, Constants: type) type {
    return struct {
        primitive_topology: w32.D3D_PRIMITIVE_TOPOLOGY,
        vertex_shader: *w32.ID3D11VertexShader,
        geometry_shader: ?*w32.ID3D11GeometryShader,
        pixel_shader: *w32.ID3D11PixelShader,
        input_layout: *w32.ID3D11InputLayout,
        depth_stencil_state: *w32.ID3D11DepthStencilState,
        blend_state: *w32.ID3D11BlendState,
        rasterizer_state: *w32.ID3D11RasterizerState,
        vertex_buffer: ?Buffer,
        index_buffer: ?Buffer,
        constant_buffer: ?Buffer,
        vertex_count: u32,
        index_count: u32,
        test_allocation: if (builtin.is_test) *u8 else void,

        const Self = @This();
        const Buffer = struct {
            handle: *w32.ID3D11Buffer,
            size: u32,
        };

        pub fn init(context: *const dx11.Context, config: *const dx11.ShaderConfig) !Self {
            const device = context.device;

            const vertex_blob = compile(config.source_code, "vs_main", "vs_4_0") catch |err| {
                misc.error_context.append("Failed to compile vertex_shader.", .{});
                return err;
            };
            defer _ = vertex_blob.IUnknown.Release();

            const pixel_blob = compile(config.source_code, "ps_main", "ps_4_0") catch |err| {
                misc.error_context.append("Failed to compile.", .{});
                return err;
            };
            defer _ = pixel_blob.IUnknown.Release();

            const geometry_blob = switch (config.use_geometry_shader) {
                true => compile(config.source_code, "gs_main", "gs_4_0") catch |err| {
                    misc.error_context.append("Failed to compile.", .{});
                    return err;
                },
                false => null,
            };
            defer if (geometry_blob) |blob| {
                _ = blob.IUnknown.Release();
            };

            var reflection: *w32.ID3D11ShaderReflection = undefined;
            const reflect_result = w32.D3DReflect(
                @ptrCast(vertex_blob.GetBufferPointer()),
                vertex_blob.GetBufferSize(),
                w32.IID_ID3D11ShaderReflection,
                @ptrCast(&reflection),
            );
            if (dx11.Error.from(reflect_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3DReflect returned a failure value.", .{});
                return error.Dx11Error;
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

            var vertex_shader: *w32.ID3D11VertexShader = undefined;
            const vertex_result = device.CreateVertexShader(
                @ptrCast(vertex_blob.GetBufferPointer()),
                vertex_blob.GetBufferSize(),
                null,
                &vertex_shader,
            );
            if (dx11.Error.from(vertex_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreateVertexShader returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = vertex_shader.IUnknown.Release();

            var pixel_shader: *w32.ID3D11PixelShader = undefined;
            const pixel_result = device.CreatePixelShader(
                @ptrCast(pixel_blob.GetBufferPointer()),
                pixel_blob.GetBufferSize(),
                null,
                &pixel_shader,
            );
            if (dx11.Error.from(pixel_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreatePixelShader returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = pixel_shader.IUnknown.Release();

            const geometry_shader = if (geometry_blob) |blob| block: {
                var shader: *w32.ID3D11GeometryShader = undefined;
                const result = device.CreateGeometryShader(
                    @ptrCast(blob.GetBufferPointer()),
                    blob.GetBufferSize(),
                    null,
                    &shader,
                );
                if (dx11.Error.from(result)) |err| {
                    misc.error_context.new("{f}", .{err});
                    misc.error_context.append("ID3D11Device.CreateGeometryShader returned a failure value.", .{});
                    return error.Dx11Error;
                }
                break :block shader;
            } else null;
            errdefer if (geometry_shader) |shader| {
                _ = shader.IUnknown.Release();
            };

            const input_layout_desc = getInputLayoutDesc(Vertex);
            var input_layout: *w32.ID3D11InputLayout = undefined;
            const input_result = device.CreateInputLayout(
                input_layout_desc.ptr,
                input_layout_desc.len,
                @ptrCast(vertex_blob.GetBufferPointer()),
                vertex_blob.GetBufferSize(),
                &input_layout,
            );
            if (dx11.Error.from(input_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreateInputLayout returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = input_layout.IUnknown.Release();

            var depth_stencil_state: *w32.ID3D11DepthStencilState = undefined;
            const depth_stencil_result = device.CreateDepthStencilState(
                &config.getNativeDepthStencil(),
                &depth_stencil_state,
            );
            if (dx11.Error.from(depth_stencil_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreateDepthStencilState returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = depth_stencil_state.IUnknown.Release();

            var blend_state: *w32.ID3D11BlendState = undefined;
            const blend_result = device.CreateBlendState(&config.blend.toNative(), &blend_state);
            if (dx11.Error.from(blend_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreateBlendState returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = blend_state.IUnknown.Release();

            var rasterizer_state: *w32.ID3D11RasterizerState = undefined;
            const rasterizer_result = device.CreateRasterizerState(&config.rasterizer.toNative(), &rasterizer_state);
            if (dx11.Error.from(rasterizer_result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11Device.CreateRasterizerState returned a failure value.", .{});
                return error.Dx11Error;
            }
            errdefer _ = rasterizer_state.IUnknown.Release();

            const test_allocation = if (builtin.is_test) try std.testing.allocator.create(u8) else {};

            return .{
                .primitive_topology = config.primitive_topology.toNative(),
                .vertex_shader = vertex_shader,
                .pixel_shader = pixel_shader,
                .geometry_shader = geometry_shader,
                .input_layout = input_layout,
                .depth_stencil_state = depth_stencil_state,
                .blend_state = blend_state,
                .rasterizer_state = rasterizer_state,
                .vertex_buffer = null,
                .index_buffer = null,
                .constant_buffer = null,
                .vertex_count = 0,
                .index_count = 0,
                .test_allocation = test_allocation,
            };
        }

        pub fn deinit(self: *const Self, context: *const dx11.Context) void {
            context.waitForGpu();
            if (self.constant_buffer) |buffer| {
                _ = buffer.handle.IUnknown.Release();
            }
            if (self.index_buffer) |buffer| {
                _ = buffer.handle.IUnknown.Release();
            }
            if (self.vertex_buffer) |buffer| {
                _ = buffer.handle.IUnknown.Release();
            }
            _ = self.rasterizer_state.IUnknown.Release();
            _ = self.blend_state.IUnknown.Release();
            _ = self.depth_stencil_state.IUnknown.Release();
            _ = self.input_layout.IUnknown.Release();
            _ = self.pixel_shader.IUnknown.Release();
            if (self.geometry_shader) |shader| {
                _ = shader.IUnknown.Release();
            }
            _ = self.vertex_shader.IUnknown.Release();

            if (builtin.is_test) {
                std.testing.allocator.destroy(self.test_allocation);
            }
        }

        pub fn setVertices(self: *Self, context: *const dx11.Context, vertices: []const Vertex) !void {
            setBufferData(Vertex, context, &self.vertex_buffer, vertices, .vertex) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
            self.vertex_count = @intCast(vertices.len);
        }

        pub fn setIndices(self: *Self, context: *const dx11.Context, indices: []const Index) !void {
            if (Index == void) {
                @compileError("This function is not defined for indices of type void.");
            }
            setBufferData(Index, context, &self.index_buffer, indices, .index) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
            self.index_count = @intCast(indices.len);
        }

        pub fn setConstants(self: *Self, context: *const dx11.Context, constants: *const Constants) !void {
            if (Constants == void) {
                @compileError("This function is not defined for constants of type void.");
            }
            setBufferData(Constants, context, &self.constant_buffer, constants[0..1], .constant) catch |err| {
                misc.error_context.append("Failed to set vertex buffer data.", .{});
                return err;
            };
        }

        pub fn draw(self: *const Self, context: *const dx11.Context, buffer_context: *const dx11.BufferContext) !void {
            const device_context = context.device_context;
            _ = buffer_context;

            const vertex_buffer = self.vertex_buffer orelse {
                misc.error_context.new("Vertices never set.", .{});
                return error.MissingVertices;
            };
            if (Index != void and self.index_buffer == null) {
                misc.error_context.new("Indices never set.", .{});
                return error.MissingIndices;
            }
            if (Constants != void and self.constant_buffer == null) {
                misc.error_context.new("Constants never set.", .{});
                return error.MissingConstants;
            }

            device_context.IASetPrimitiveTopology(self.primitive_topology);
            device_context.VSSetShader(self.vertex_shader, null, 0);
            device_context.PSSetShader(self.pixel_shader, null, 0);
            device_context.GSSetShader(self.geometry_shader, null, 0);
            device_context.IASetInputLayout(self.input_layout);
            device_context.OMSetDepthStencilState(self.depth_stencil_state, 0xFF);
            const blend_factor = [4]f32{ 1.0, 1.0, 1.0, 1.0 };
            device_context.OMSetBlendState(self.blend_state, &blend_factor[0], 0xFFFFFFFF);
            device_context.RSSetState(self.rasterizer_state);
            if (self.constant_buffer) |buffer| {
                var array = [1](?*w32.ID3D11Buffer){buffer.handle};
                const buffers: [*](?*w32.ID3D11Buffer) = &array;
                device_context.VSSetConstantBuffers(0, 1, buffers);
                if (self.geometry_shader != null) {
                    device_context.GSSetConstantBuffers(0, 1, buffers);
                }
                device_context.PSSetConstantBuffers(0, 1, buffers);
            } else {
                device_context.VSSetConstantBuffers(0, 0, null);
                if (self.geometry_shader != null) {
                    device_context.GSSetConstantBuffers(0, 0, null);
                }
                device_context.PSSetConstantBuffers(0, 0, null);
            }
            var array = [1](?*w32.ID3D11Buffer){vertex_buffer.handle};
            const buffers: [*](?*w32.ID3D11Buffer) = &array;
            const sizes: [*]const u32 = &[1]u32{@sizeOf(Vertex)};
            const offsets: [*]const u32 = &[1]u32{0};
            device_context.IASetVertexBuffers(0, 1, buffers, sizes, offsets);

            const format: w32.DXGI_FORMAT = switch (Index) {
                void => {
                    device_context.Draw(self.vertex_count, 0);
                    return;
                },
                u16 => .R16_UINT,
                u32 => .R32_UINT,
                else => @compileError("Expecting Index to be void, u16 or u32 but got: " ++ @typeName(Index)),
            };
            device_context.IASetIndexBuffer(self.index_buffer.?.handle, format, 0);
            device_context.DrawIndexed(self.index_count, 0, 0);
        }

        fn setBufferData(
            comptime Element: type,
            context: *const dx11.Context,
            buffer_maybe: *?Buffer,
            data: []const Element,
            buffer_type: enum { vertex, index, constant },
        ) !void {
            const device = context.device;
            const device_context = context.device_context;

            const len = std.math.cast(u32, data.len) orelse {
                misc.error_context.new("Overflow while casting vertices length.", .{});
                return error.Overflow;
            };
            const bytes_needed = std.math.mul(u32, len, @sizeOf(Element)) catch |err| {
                misc.error_context.new("Overflow while calculating bytes needed.", .{});
                return err;
            };
            if (buffer_maybe.*) |*buffer| {
                if (bytes_needed > buffer.size) {
                    _ = buffer.handle.IUnknown.Release();
                    buffer_maybe.* = null;
                }
            }

            const buffer = buffer_maybe.* orelse block: {
                errdefer misc.error_context.append("Failed to (re)allocate the buffer.", .{});
                const size = switch (buffer_type) {
                    .vertex, .index => std.math.ceilPowerOfTwo(u32, @max(bytes_needed, 1024)) catch std.math.maxInt(u32),
                    .constant => b: {
                        if (@sizeOf(Constants) > std.math.maxInt(u32) - 15) {
                            misc.error_context.new("Overflow while calculating size.", .{});
                            return error.Overflow;
                        }
                        break :b std.mem.alignForward(u32, bytes_needed, 16);
                    },
                };

                const desc = w32.D3D11_BUFFER_DESC{
                    .ByteWidth = size,
                    .Usage = .DYNAMIC,
                    .BindFlags = switch (buffer_type) {
                        .vertex => .{ .VERTEX_BUFFER = 1 },
                        .index => .{ .INDEX_BUFFER = 1 },
                        .constant => .{ .CONSTANT_BUFFER = 1 },
                    },
                    .CPUAccessFlags = .{ .WRITE = 1 },
                    .MiscFlags = .{},
                    .StructureByteStride = 0,
                };
                var handle: *w32.ID3D11Buffer = undefined;
                const result = device.CreateBuffer(&desc, null, &handle);
                if (dx11.Error.from(result)) |err| {
                    misc.error_context.new("{f}", .{err});
                    misc.error_context.append("ID3D11Device.CreateBuffer returned a failure value.", .{});
                    return error.Dx11Error;
                }

                const buffer = Buffer{ .handle = handle, .size = size };
                buffer_maybe.* = buffer;
                break :block buffer;
            };

            var mapped: w32.D3D11_MAPPED_SUBRESOURCE = undefined;
            const result = device_context.Map(&buffer.handle.ID3D11Resource, 0, .WRITE_DISCARD, 0, &mapped);
            if (dx11.Error.from(result)) |err| {
                misc.error_context.new("{f}", .{err});
                misc.error_context.append("ID3D11DeviceContext.Map returned a failure value.", .{});
                return error.Dx11Error;
            }
            defer device_context.Unmap(&buffer.handle.ID3D11Resource, 0);

            if (mapped.pData == null) {
                misc.error_context.new("ID3D11DeviceContext.Map returned a null address to data.", .{});
                return error.Dx11Error;
            }
            const mapped_data: [*]u8 = @ptrCast(mapped.pData);

            if (buffer_type == .constant) {
                @memset(mapped_data[0..buffer.size], 0);
            }
            @memcpy(mapped_data, std.mem.sliceAsBytes(data));
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
    if (dx11.Error.from(result)) |err| {
        misc.error_context.clear();
        if (error_blob) |blob| {
            const base: [*c]u8 = @ptrCast(blob.GetBufferPointer());
            const compile_error = std.mem.sliceTo(base[0..blob.GetBufferSize()], 0);
            misc.error_context.append("{s}", .{compile_error});
        }
        misc.error_context.append("{f}", .{err});
        misc.error_context.append("D3DCompile returned a failure value.", .{});
        return error.Dx11Error;
    }
    return shader_blob orelse {
        misc.error_context.new("D3DCompile returned a null pointer to result blob.", .{});
        return error.Dx11Error;
    };
}

inline fn getInputLayoutDesc(comptime Vertex: type) []const w32.D3D11_INPUT_ELEMENT_DESC {
    comptime {
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
        var result: [info.field_names.len]w32.D3D11_INPUT_ELEMENT_DESC = undefined;
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
        const final = result[0..len].*;
        return &final;
    }
}

fn checkVertexLayout(comptime Vertex: type, reflection: *const w32.ID3D11ShaderReflection) !void {
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

    var shader_desc: w32.D3D11_SHADER_DESC = undefined;
    const shader_result = reflection.GetDesc(&shader_desc);
    if (dx11.Error.from(shader_result)) |err| {
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("ID3D11ShaderReflection.GetDesc returned a failure value.", .{});
        return error.Dx11Error;
    }

    for (0..shader_desc.InputParameters) |gpu_parameter_index| {
        var gpu_parameter: w32.D3D11_SIGNATURE_PARAMETER_DESC = undefined;
        const parameter_result = reflection.GetInputParameterDesc(@intCast(gpu_parameter_index), &gpu_parameter);
        if (dx11.Error.from(parameter_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D11ShaderReflection.GetInputParameterDesc returned a failure value.", .{});
            misc.error_context.append("Check failed for GPU input parameter at index: {}", .{gpu_parameter_index});
            return error.Dx11Error;
        }
        const gpu_name_start = gpu_parameter.SemanticName orelse {
            misc.error_context.new("Input parameter has no semantic name.", .{});
            misc.error_context.append("Check failed for GPU input parameter at index: {}", .{gpu_parameter_index});
            return error.Dx11Error;
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
                    return error.Dx11Error;
                }
                if (@popCount(gpu_parameter.Mask) != cpu_parameter.component_count) {
                    misc.error_context.new(
                        "GPU component count {} does not match the CPU component count: {}",
                        .{ @popCount(gpu_parameter.Mask), cpu_parameter.component_count },
                    );
                    return error.Dx11Error;
                }
                break;
            }
        } else {
            misc.error_context.new("Failed to find CPU struct field that matches GPU input parameter.", .{});
            return error.Dx11Error;
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
        return error.Dx11Error;
    }
}

fn checkConstantsLayout(comptime Constants: type, reflection: *const w32.ID3D11ShaderReflection) !void {
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
        return error.Dx11Error;
    };

    var number_of_cpu_fields: usize = 0;
    inline for (cpu_names, cpu_types) |cpu_name, cpu_type| {
        errdefer misc.error_context.append("Check failed for CPU field: {s}", .{cpu_name});
        if (cpu_name.len == 0 or cpu_name[0] == '_') {
            continue;
        }
        const gpu_variable = gpu_constants.GetVariableByName(cpu_name) orelse {
            misc.error_context.append("Failed to find a GPU variable with matching name.", .{});
            return error.Dx11Error;
        };
        var gpu_variable_desc: w32.D3D11_SHADER_VARIABLE_DESC = undefined;
        const desc_result = gpu_variable.GetDesc(&gpu_variable_desc);
        if (dx11.Error.from(desc_result)) |err| {
            misc.error_context.new("{f}", .{err});
            misc.error_context.append("ID3D11ShaderReflectionVariable.GetDesc returned a failure value.", .{});
            return error.Dx11Error;
        }
        if (gpu_variable_desc.StartOffset != @offsetOf(Constants, cpu_name)) {
            misc.error_context.new(
                "GPU offset {} does not match the CPU offset: {}",
                .{ gpu_variable_desc.StartOffset, @offsetOf(Constants, cpu_name) },
            );
            return error.Dx11Error;
        }
        if (gpu_variable_desc.Size != @sizeOf(cpu_type)) {
            misc.error_context.new(
                "GPU size {} does not match the CPU size: {}",
                .{ gpu_variable_desc.Size, @sizeOf(cpu_type) },
            );
            return error.Dx11Error;
        }
        number_of_cpu_fields += 1;
    }

    var gpu_constants_desc: w32.D3D11_SHADER_BUFFER_DESC = undefined;
    const desc_result = gpu_constants.GetDesc(&gpu_constants_desc);
    if (dx11.Error.from(desc_result)) |err| {
        if (cpu_names.len == 0) {
            return;
        }
        misc.error_context.new("{f}", .{err});
        misc.error_context.append("ID3D11ShaderReflectionConstantBuffer.GetDesc returned a failure value.", .{});
        return error.Dx11Error;
    }
    if (gpu_constants_desc.Variables != number_of_cpu_fields) {
        misc.error_context.new(
            "Found {} constant variables on the GPU side while the CPU side contains only {} constant fields.",
            .{ gpu_constants_desc.Variables, number_of_cpu_fields },
        );
        return error.Dx11Error;
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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

    const Vertex = extern struct { vec: math.Vec4 };
    try testing.expectError(
        error.Dx11Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = "syntax error" }),
    );
}

test "init should error when vertex field is missing on CPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex field is missing on GPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex input parameter has different component type on CPU compared to GPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when vertex input parameter has different component count on CPU compared to GPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, void).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field is missing on CPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field is missing on GPU side" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field has different offset on GPU then on CPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "init should error when constant field has different size on GPU then on CPU" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
        error.Dx11Error,
        Shader(Vertex, void, Constants).init(&context, &.{ .source_code = source_code }),
    );
}

test "draw should error when vertices are not set" {
    if (@import("config").skip_gpu) {
        return error.SkipZigTest;
    }
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
    const testing_context = try dx11.TestingContext.init();
    defer testing_context.deinit();
    const host_context = testing_context.getHostContext();
    var managed_context = try dx11.ManagedContext.init(testing.allocator, &host_context);
    defer managed_context.deinit();
    var context = dx11.Context.fromHostAndManaged(&testing_context.getHostContext(), &managed_context);

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
