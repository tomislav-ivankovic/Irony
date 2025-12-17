const std = @import("std");
const w32 = @import("win32").everything;

pub const Error = struct {
    result: w32.HRESULT,

    const Self = @This();

    pub fn from(result: w32.HRESULT) ?Self {
        if (result >= 0) { // A non-negative number indicates success.
            return null;
        }
        return .{ .result = result };
    }

    pub fn format(self: Self, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        const u_result: u32 = @bitCast(self.result);
        if (ErrorEnum.from(self.result)) |err_enum| {
            const description = err_enum.getDescription();
            try writer.print("{s} (result code 0x{X} {s})", .{ description, u_result, @tagName(err_enum) });
        } else {
            try writer.print("result code 0x{X}", .{u_result});
        }
    }
};

// This is based on the Microsoft's documentation on Direct3D 11 Return Codes and DXGI_ERROR.
// https://learn.microsoft.com/en-us/windows/win32/com/structure-of-com-error-codes
// https://learn.microsoft.com/en-us/windows/win32/direct3d11/d3d11-graphics-reference-returnvalues
// https://learn.microsoft.com/en-us/windows/win32/direct3ddxgi/dxgi-error
pub const ErrorEnum = enum(w32.HRESULT) {
    S_OK = w32.S_OK,
    S_FALSE = w32.S_FALSE,
    D3D11_ERROR_FILE_NOT_FOUND = w32.D3D11_ERROR_FILE_NOT_FOUND,
    D3D11_ERROR_TOO_MANY_UNIQUE_STATE_OBJECTS = w32.D3D11_ERROR_TOO_MANY_UNIQUE_STATE_OBJECTS,
    D3D11_ERROR_TOO_MANY_UNIQUE_VIEW_OBJECTS = w32.D3D11_ERROR_TOO_MANY_UNIQUE_VIEW_OBJECTS,
    D3D11_ERROR_DEFERRED_CONTEXT_MAP_WITHOUT_INITIAL_DISCARD = w32.D3D11_ERROR_DEFERRED_CONTEXT_MAP_WITHOUT_INITIAL_DISCARD,
    E_FAIL = w32.E_FAIL,
    E_INVALIDARG = w32.E_INVALIDARG,
    E_OUTOFMEMORY = w32.E_OUTOFMEMORY,
    E_NOTIMPL = w32.E_NOTIMPL,
    DXGI_ERROR_ACCESS_DENIED = w32.DXGI_ERROR_ACCESS_DENIED,
    DXGI_ERROR_ACCESS_LOST = w32.DXGI_ERROR_ACCESS_LOST,
    DXGI_ERROR_ALREADY_EXISTS = w32.DXGI_ERROR_ALREADY_EXISTS,
    DXGI_ERROR_CANNOT_PROTECT_CONTENT = w32.DXGI_ERROR_CANNOT_PROTECT_CONTENT,
    DXGI_ERROR_DEVICE_HUNG = w32.DXGI_ERROR_DEVICE_HUNG,
    DXGI_ERROR_DEVICE_REMOVED = w32.DXGI_ERROR_DEVICE_REMOVED,
    DXGI_ERROR_DEVICE_RESET = w32.DXGI_ERROR_DEVICE_RESET,
    DXGI_ERROR_DRIVER_INTERNAL_ERROR = w32.DXGI_ERROR_DRIVER_INTERNAL_ERROR,
    DXGI_ERROR_FRAME_STATISTICS_DISJOINT = w32.DXGI_ERROR_FRAME_STATISTICS_DISJOINT,
    DXGI_ERROR_GRAPHICS_VIDPN_SOURCE_IN_USE = w32.DXGI_ERROR_GRAPHICS_VIDPN_SOURCE_IN_USE,
    DXGI_ERROR_INVALID_CALL = w32.DXGI_ERROR_INVALID_CALL,
    DXGI_ERROR_MORE_DATA = w32.DXGI_ERROR_MORE_DATA,
    DXGI_ERROR_NAME_ALREADY_EXISTS = w32.DXGI_ERROR_NAME_ALREADY_EXISTS,
    DXGI_ERROR_NONEXCLUSIVE = w32.DXGI_ERROR_NONEXCLUSIVE,
    DXGI_ERROR_NOT_CURRENTLY_AVAILABLE = w32.DXGI_ERROR_NOT_CURRENTLY_AVAILABLE,
    DXGI_ERROR_NOT_FOUND = w32.DXGI_ERROR_NOT_FOUND,
    DXGI_ERROR_REMOTE_CLIENT_DISCONNECTED = w32.DXGI_ERROR_REMOTE_CLIENT_DISCONNECTED,
    DXGI_ERROR_REMOTE_OUTOFMEMORY = w32.DXGI_ERROR_REMOTE_OUTOFMEMORY,
    DXGI_ERROR_RESTRICT_TO_OUTPUT_STALE = w32.DXGI_ERROR_RESTRICT_TO_OUTPUT_STALE,
    DXGI_ERROR_SDK_COMPONENT_MISSING = w32.DXGI_ERROR_SDK_COMPONENT_MISSING,
    DXGI_ERROR_SESSION_DISCONNECTED = w32.DXGI_ERROR_SESSION_DISCONNECTED,
    DXGI_ERROR_UNSUPPORTED = w32.DXGI_ERROR_UNSUPPORTED,
    DXGI_ERROR_WAIT_TIMEOUT = w32.DXGI_ERROR_WAIT_TIMEOUT,
    DXGI_ERROR_WAS_STILL_DRAWING = w32.DXGI_ERROR_WAS_STILL_DRAWING,

    const Self = @This();

    pub fn from(result: w32.HRESULT) ?Self {
        return std.meta.intToEnum(Self, result) catch null;
    }

    pub fn getDescription(self: Self) [:0]const u8 {
        return switch (self) {
            .S_OK => "No error occurred.",
            .S_FALSE => "Alternate success value, indicating a successful but nonstandard completion (the precise meaning depends on context).",
            .D3D11_ERROR_FILE_NOT_FOUND => "The file was not found.",
            .D3D11_ERROR_TOO_MANY_UNIQUE_STATE_OBJECTS => "There are too many unique instances of a particular type of state object.",
            .D3D11_ERROR_TOO_MANY_UNIQUE_VIEW_OBJECTS => "There are too many unique instances of a particular type of view object.",
            .D3D11_ERROR_DEFERRED_CONTEXT_MAP_WITHOUT_INITIAL_DISCARD => "The first call to ID3D11DeviceContext::Map after either ID3D11Device::CreateDeferredContext or ID3D11DeviceContext::FinishCommandList per Resource was not D3D11_MAP_WRITE_DISCARD.",
            .E_FAIL => "Attempted to create a device with the debug layer enabled and the layer is not installed.",
            .E_INVALIDARG => "An invalid parameter was passed to the returning function.",
            .E_OUTOFMEMORY => "Direct3D could not allocate sufficient memory to complete the call.",
            .E_NOTIMPL => "The method call isn't implemented with the passed parameter combination.",
            .DXGI_ERROR_ACCESS_DENIED => "You tried to use a resource to which you did not have the required access privileges. This error is most typically caused when you write to a shared resource with read-only access.",
            .DXGI_ERROR_ACCESS_LOST => "The desktop duplication interface is invalid. The desktop duplication interface typically becomes invalid when a different type of image is displayed on the desktop.",
            .DXGI_ERROR_ALREADY_EXISTS => "The desired element already exists. This is returned by DXGIDeclareAdapterRemovalSupport if it is not the first time that the function is called.",
            .DXGI_ERROR_CANNOT_PROTECT_CONTENT => "DXGI can't provide content protection on the swap chain. This error is typically caused by an older driver, or when you use a swap chain that is incompatible with content protection.",
            .DXGI_ERROR_DEVICE_HUNG => "The application's device failed due to badly formed commands sent by the application. This is an design-time issue that should be investigated and fixed.",
            .DXGI_ERROR_DEVICE_REMOVED => "The video card has been physically removed from the system, or a driver upgrade for the video card has occurred. The application should destroy and recreate the device. For help debugging the problem, call ID3D10Device::GetDeviceRemovedReason.",
            .DXGI_ERROR_DEVICE_RESET => "The device failed due to a badly formed command. This is a run-time issue; The application should destroy and recreate the device.",
            .DXGI_ERROR_DRIVER_INTERNAL_ERROR => "The driver encountered a problem and was put into the device removed state.",
            .DXGI_ERROR_FRAME_STATISTICS_DISJOINT => "An event (for example, a power cycle) interrupted the gathering of presentation statistics.",
            .DXGI_ERROR_GRAPHICS_VIDPN_SOURCE_IN_USE => "The application attempted to acquire exclusive ownership of an output, but failed because some other application (or device within the application) already acquired ownership.",
            .DXGI_ERROR_INVALID_CALL => "The application provided invalid parameter data; this must be debugged and fixed before the application is released.",
            .DXGI_ERROR_MORE_DATA => "The buffer supplied by the application is not big enough to hold the requested data.",
            .DXGI_ERROR_NAME_ALREADY_EXISTS => "The supplied name of a resource in a call to IDXGIResource1::CreateSharedHandle is already associated with some other resource.",
            .DXGI_ERROR_NONEXCLUSIVE => "A global counter resource is in use, and the Direct3D device can't currently use the counter resource.",
            .DXGI_ERROR_NOT_CURRENTLY_AVAILABLE => "The resource or request is not currently available, but it might become available later.",
            .DXGI_ERROR_NOT_FOUND => "When calling IDXGIObject::GetPrivateData, the GUID passed in is not recognized as one previously passed to IDXGIObject::SetPrivateData or IDXGIObject::SetPrivateDataInterface. When calling IDXGIFactory::EnumAdapters or IDXGIAdapter::EnumOutputs, the enumerated ordinal is out of range.",
            .DXGI_ERROR_REMOTE_CLIENT_DISCONNECTED => "Reserved",
            .DXGI_ERROR_REMOTE_OUTOFMEMORY => "Reserved",
            .DXGI_ERROR_RESTRICT_TO_OUTPUT_STALE => "The DXGI output (monitor) to which the swap chain content was restricted is now disconnected or changed.",
            .DXGI_ERROR_SDK_COMPONENT_MISSING => "The operation depends on an SDK component that is missing or mismatched.",
            .DXGI_ERROR_SESSION_DISCONNECTED => "The Remote Desktop Services session is currently disconnected.",
            .DXGI_ERROR_UNSUPPORTED => "The requested functionality is not supported by the device or the driver.",
            .DXGI_ERROR_WAIT_TIMEOUT => "The time-out interval elapsed before the next desktop frame was available.",
            .DXGI_ERROR_WAS_STILL_DRAWING => "The GPU was busy at the moment when a call was made to perform an operation, and did not execute or schedule the operation.",
        };
    }
};

const testing = std.testing;

test "from should return null when result code represents success" {
    try testing.expectEqual(null, Error.from(w32.S_OK));
    try testing.expectEqual(null, Error.from(w32.S_FALSE));
}

test "from should return correct value when result code represents failure" {
    try testing.expectEqual(
        Error{ .result = w32.D3D11_ERROR_FILE_NOT_FOUND },
        Error.from(w32.D3D11_ERROR_FILE_NOT_FOUND),
    );
}

test "should format correctly when error has message" {
    const err = Error{ .result = w32.DXGI_ERROR_DRIVER_INTERNAL_ERROR };
    const message = try std.fmt.allocPrint(testing.allocator, "{f}", .{err});
    defer testing.allocator.free(message);
    try testing.expectEqualStrings(
        "The driver encountered a problem and was put into the device removed state. (result code 0x887A0020 DXGI_ERROR_DRIVER_INTERNAL_ERROR)",
        message,
    );
}

test "should format correctly when error has no message" {
    const err = Error{ .result = w32.STG_E_MEDIUMFULL };
    const message = try std.fmt.allocPrint(testing.allocator, "{f}", .{err});
    defer testing.allocator.free(message);
    try testing.expectEqualStrings("result code 0x80030070", message);
}
