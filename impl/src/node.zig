const std = @import("std");

pub const Color = enum { Red, Black };

pub fn NodeResult(comptime T: type) type {
    return struct {
        index: usize,
        data: T,
    };
}

pub fn Node(comptime T: type) type {
    return struct {
        const Self = @This();

        data: T,

        size: usize,
        count: usize,

        parent: ?*Self,
        left: ?*Self,
        right: ?*Self,

        color: Color,
    };
}
