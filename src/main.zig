const clap = @import("clap");
const std = @import("std");

const debug = std.debug;
const io = std.io;
const http = std.http;
const mem = std.mem;
const json = std.json;

const FxRate = struct {
    rate: f16,
    source: []const u8,
    target: []const u8,
    time: []const u8,

    pub fn format(self: FxRate, comptime fmt: []const u8, options: std.fmt.FormatOptions, writer: io.AnyWriter) !void {
        _ = fmt;
        _ = options;

        try writer.print("FxRate(rate: {d:.2}, source: \"{s}\", target: \"{s}\", time: \"{s}\")", .{ self.rate, self.source, self.target, self.time });
        try writer.writeAll("");
    }
};

pub fn main() !void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();

    const params = comptime clap.parseParamsComptime(
        \\-h, --help         Display this help and exit.
        \\-k, --apikey <str> (required) Wise API Key.
        \\-s, --source <str> (required) Source currency.
        \\-t, --target <str> (required) Target currency.
    );

    var diag = clap.Diagnostic{};
    var res = clap.parse(
        clap.Help,
        &params,
        clap.parsers.default,
        .{ .diagnostic = &diag, .allocator = arena.allocator() },
    ) catch |err| {
        diag.report(io.getStdErr().writer(), err) catch {};
        return err;
    };
    defer res.deinit();

    if (res.args.help != 0) {
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const wise_api_key: ?[]const u8 = res.args.apikey;
    const source_currency: ?[]const u8 = res.args.source;
    const target_currency: ?[]const u8 = res.args.target;
    debug.print("apikey={?s} source={?s} target={?s}\n", .{ wise_api_key, source_currency, target_currency });

    if (wise_api_key == null or source_currency == null or target_currency == null) {
        try io.getStdErr().writer().print("--apikey, --source, and --target are required.\n\n", .{});
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const fx_rate = try fxRate(arena.allocator(), wise_api_key.?, source_currency.?, target_currency.?);
    try waybarFmt(arena.allocator(), &fx_rate);
}

fn waybarFmt(alloc: mem.Allocator, fx_rate: *const FxRate) !void {
    const rate_with_currency: []const u8 = try std.fmt.allocPrint(alloc, "{d:.2} {s}/{s}", .{ fx_rate.rate, fx_rate.source, fx_rate.target });
    defer alloc.free(rate_with_currency);

    try io.getStdOut().writer().print("{{\"text\": \"{s}\", \"tooltip\": \"{s}\", \"alt\": \"\", \"class\": \"\"}}\n", .{ rate_with_currency, fx_rate.time });
}

// https://docs.wise.com/api-docs/api-reference/rate#get
fn fxRate(alloc: mem.Allocator, wise_api_key: []const u8, source: []const u8, target: []const u8) !FxRate {
    var client = http.Client{ .allocator = alloc };
    defer client.deinit();

    const url: []const u8 = try std.fmt.allocPrint(
        alloc,
        "https://api.transferwise.com/v1/rates?source={s}&target={s}",
        .{ source, target },
    );
    defer alloc.free(url);
    debug.print("url={s}\n", .{url});

    const bearer_token: []const u8 = try std.fmt.allocPrint(alloc, "Bearer {s}", .{wise_api_key});
    defer alloc.free(bearer_token);

    var response = std.ArrayList(u8).init(alloc);
    const fetch_result = try client.fetch(
        .{
            .method = .GET,
            .location = .{ .url = url },
            .headers = .{
                .authorization = .{
                    .override = bearer_token,
                },
            },
            .response_storage = .{
                .dynamic = &response,
            },
        },
    );
    debug.print("fetch_result={}\n", .{fetch_result});
    debug.print("fetch_result_response={s}\n", .{response.items});

    switch (fetch_result.status) {
        .ok => {
            const parsed_response = try json.parseFromSliceLeaky([]FxRate, alloc, response.items, .{});
            defer alloc.free(parsed_response);

            debug.print("parsed_response={s}\n", .{parsed_response});
            return parsed_response[0];
        },
        .bad_request => {
            try io.getStdErr().writer().print("Bad request. Check the --source and --target. http_response={s}", .{response.items});
            std.process.exit(1);
        },
        .unauthorized => {
            try io.getStdErr().writer().print("Unauthorized request. Check your Wise API Key.", .{});
            std.process.exit(1);
        },
        else => {
            try io.getStdErr().writer().print("Unknown result. Contact the developer!", .{});
            std.process.exit(1);
        },
    }
}
