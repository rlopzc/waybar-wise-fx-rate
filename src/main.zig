const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help         Display this help and exit.
        \\-s, --source <str> (required) Source currency.
        \\-t, --target <str> (required) Target currency.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(clap.Help, &params, clap.parsers.default, .{
        .diagnostic = &diag,
        .allocator = gpa.allocator(),
    }) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const sourceCurrency = res.args.source;
    const targetCurrency = res.args.source;
    if (sourceCurrency == null or targetCurrency == null) {
        try io.getStdErr().writer().print("--source and --target are required\n\n", .{});
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }
}
