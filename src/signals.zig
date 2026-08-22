const std = @import("std");
const Io = std.Io;

pub const Signal = union(enum) {
    startgg_response: struct {
        status: std.http.Status,
        body: []const u8,

        pub fn deinit(self: *const @This(), gpa: std.mem.Allocator) void {
            gpa.free(self.body);
        }
    },
};

pub const SignalEngine = struct {
    queue: Io.Queue(Signal),
    // Since startgg_response is the only signal at the moment, and it disables
    // the whole GUI while in-flight, we only need 1 Signal slot in the buffer
    // for now.
    queue_buffer: [1]Signal = undefined,

    pub fn init(gpa: std.mem.Allocator) !*SignalEngine {
        var result = try gpa.create(SignalEngine);
        result.queue = .init(&result.queue_buffer);
        return result;
    }

    pub fn deinit(self: *SignalEngine, gpa: std.mem.Allocator) void {
        gpa.destroy(self);
    }
};

pub const BackgroundJob = enum { startgg_request };
