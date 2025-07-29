const std = @import("std");
const misc = @import("root.zig");

pub fn Task(comptime Result: type) type {
    return union(enum) {
        in_progress: InProgress,
        completed: Result,

        const Self = @This();
        const State = struct {
            result: Result,
            is_ready: std.atomic.Value(bool),
        };
        const InProgress = struct {
            allocator: std.mem.Allocator,
            state: *State,
            thread: std.Thread,
        };

        pub fn spawn(allocator: std.mem.Allocator, comptime function: anytype, args: anytype) !Self {
            const state = allocator.create(State) catch |err| {
                misc.error_context.new("Failed to allocate the state memory.", .{});
                return err;
            };
            errdefer allocator.destroy(state);
            state.* = .{
                .result = undefined,
                .is_ready = .init(false),
            };
            const thread = std.Thread.spawn(.{}, struct {
                fn call(thread_state: *State, arguments: anytype) void {
                    const result = @call(.auto, function, arguments);
                    thread_state.result = result;
                    thread_state.is_ready.store(true, .seq_cst);
                }
            }.call, .{ state, args }) catch |err| {
                misc.error_context.new("Failed to spawn the task thread.", .{});
                return err;
            };
            errdefer thread.join();
            return .{ .in_progress = .{
                .allocator = allocator,
                .state = state,
                .thread = thread,
            } };
        }

        pub fn join(self: *Self) *Result {
            switch (self.*) {
                .in_progress => |*task| {
                    task.thread.join();
                    const result = task.state.result;
                    task.allocator.destroy(task.state);
                    self.* = .{ .completed = result };
                    return &self.completed;
                },
                .completed => |*result| return result,
            }
        }

        pub fn createCompleted(result: Result) Self {
            return .{ .completed = result };
        }

        pub fn peek(self: *Self) ?*Result {
            switch (self.*) {
                .in_progress => |*task| {
                    const is_ready = task.state.is_ready.load(.seq_cst);
                    if (is_ready) {
                        return self.join();
                    } else {
                        return null;
                    }
                },
                .completed => |*result| return result,
            }
        }
    };
}

const testing = std.testing;

test "join should should block and return the result when the task is done" {
    var task = try Task(usize).spawn(testing.allocator, struct {
        fn call() usize {
            var counter: usize = 0;
            for (0..10) |_| {
                counter += 1;
                std.Thread.yield() catch {};
            }
            return counter;
        }
    }.call, .{});
    try testing.expectEqual(10, task.join().*);
}

test "peek should not block and return null while task is getting executed and return a value as soon as the task is done" {
    var counter = std.atomic.Value(usize).init(0);

    var task = try Task(usize).spawn(testing.allocator, struct {
        fn call(atomic: *std.atomic.Value(usize)) usize {
            var value = atomic.load(.seq_cst);
            while (value < 10) {
                std.Thread.yield() catch {};
                value = atomic.load(.seq_cst);
            }
            return value;
        }
    }.call, .{&counter});
    defer _ = task.join();

    for (0..10) |_| {
        try testing.expectEqual(null, task.peek());
        _ = counter.fetchAdd(1, .seq_cst);
        try std.Thread.yield();
    }
    std.Thread.sleep(std.time.ns_per_ms);

    try testing.expect(task.peek() != null);
    try testing.expectEqual(10, task.peek().?.*);
}

test "createCompleted should create a task that make peek and join to instantly return the value" {
    var task = Task(usize).createCompleted(123);
    try testing.expect(task.peek() != null);
    try testing.expectEqual(123, task.peek().?.*);
    try testing.expectEqual(123, task.join().*);
}
