const clap = @import("clap");
const std = @import("std");

const log = std.log;
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
    log.debug("apikey={?s} source={?s} target={?s}\n", .{ wise_api_key, source_currency, target_currency });

    if (wise_api_key == null or source_currency == null or target_currency == null) {
        try io.getStdErr().writer().print("--apikey, --source, and --target are required.\n\n", .{});
        return clap.help(io.getStdErr().writer(), clap.Help, &params, .{});
    }

    const fx_rate = try fxRate(arena.allocator(), wise_api_key.?, source_currency.?, target_currency.?);
    try waybarFmt(arena.allocator(), io.getStdOut().writer(), &fx_rate);
}

fn waybarFmt(alloc: mem.Allocator, writer: anytype, fx_rate: *const FxRate) !void {
    const rate_with_currency: []const u8 = try std.fmt.allocPrint(alloc, "{d:.2} {s}/{s}", .{
        fx_rate.rate,
        fx_rate.source,
        fx_rate.target,
    });
    defer alloc.free(rate_with_currency);

    try writer.print("{{\"text\": \"{s}\", \"tooltip\": \"{s}\", \"alt\": \"default\", \"class\": \"default\"}}\n", .{
        rate_with_currency,
        fx_rate.time,
    });
}

fn parseRate(alloc: mem.Allocator, body: []const u8) !FxRate {
    const parsed = try json.parseFromSliceLeaky([]FxRate, alloc, body, .{});
    return parsed[0];
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
    log.debug("url={s}\n", .{url});

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
    log.debug("fetch_result={}\n", .{fetch_result});
    log.debug("fetch_result_response={s}\n", .{response.items});

    switch (fetch_result.status) {
        .ok => {
            return parseRate(alloc, response.items);
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

test "parseRate: parses valid API response" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const body =
        \\[{"rate":18.12,"source":"USD","target":"MXN","time":"2024-01-01T00:00:00+0000"}]
    ;
    const fx_rate = try parseRate(arena.allocator(), body);

    try std.testing.expectApproxEqAbs(@as(f16, 18.12), fx_rate.rate, 0.1);
    try std.testing.expectEqualStrings("USD", fx_rate.source);
    try std.testing.expectEqualStrings("MXN", fx_rate.target);
    try std.testing.expectEqualStrings("2024-01-01T00:00:00+0000", fx_rate.time);
}

test "parseRate: returns first rate when multiple rates returned" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    const body =
        \\[{"rate":18.12,"source":"USD","target":"MXN","time":"2024-01-01T00:00:00+0000"},{"rate":1.08,"source":"USD","target":"EUR","time":"2024-01-01T00:00:00+0000"}]
    ;
    const fx_rate = try parseRate(arena.allocator(), body);

    try std.testing.expectEqualStrings("USD", fx_rate.source);
    try std.testing.expectEqualStrings("MXN", fx_rate.target);
}

test "waybarFmt: formats output as waybar JSON" {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    var arena = std.heap.ArenaAllocator.init(gpa.allocator());
    defer arena.deinit();

    var buf = std.ArrayList(u8).init(gpa.allocator());
    defer buf.deinit();

    const fx_rate = FxRate{
        .rate = 18.12,
        .source = "USD",
        .target = "MXN",
        .time = "2024-01-01T00:00:00+0000",
    };

    try waybarFmt(arena.allocator(), buf.writer(), &fx_rate);

    try std.testing.expectEqualStrings(
        "{\"text\": \"18.12 USD/MXN\", \"tooltip\": \"2024-01-01T00:00:00+0000\", \"alt\": \"default\", \"class\": \"default\"}\n",
        buf.items,
    );
}
