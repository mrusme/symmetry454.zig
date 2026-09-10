const std = @import("std");
const sym454 = @import("symmetry454");
const calendar = @import("cli/calendar.zig");
const convert = @import("cli/convert.zig");
const Zone = @import("cli/zone.zig").Zone;

pub const usage_text =
    \\sym454 shows a Symmetry454 calendar and converts dates.
    \\
    \\Usage:
    \\  sym454 [flags] [[month] year]
    \\  sym454 -c [flags] < dates
    \\  sym454 --from-sym [flags] < dates
    \\
    \\With no arguments it prints the current Symmetry454 month and highlights today.
    \\A single argument is a year and prints all twelve months. Two arguments are a
    \\month and a year, in that order.
    \\
    \\Converter mode reads one date per line from stdin and accepts Unix epoch
    \\seconds from "date +%s", RFC 1123 with an offset from "date -R", RFC 3339 from
    \\"date -Is", the default output of "date", and plain YYYY-MM-DD. Epoch seconds
    \\are read in the local zone unless --utc is given.
    \\
    \\Calendar flags:
    \\  -y, --year        print all twelve months of the year
    \\  -3                print the previous, current and next month
    \\  --across n        months per row in the year view (default 3)
    \\  --gregorian       print the Gregorian span covered by the output
    \\  --color mode      highlight today: auto, always or never (default auto)
    \\
    \\Converter flags:
    \\  -c, --convert     read dates from stdin and print Symmetry454 dates
    \\  --from-sym        read Symmetry454 dates from stdin and print Gregorian dates
    \\  --utc             read epoch seconds as UTC rather than local time
    \\  --long            print a labeled block for each date
    \\  --json            print one JSON object per date
    \\  -f, --format s    placeholder template for each output line
    \\
    \\Format placeholders:
    \\  {gregorian} {unix} {fixed} {sym454} {year} {month} {month_name} {day}
    \\  {weekday} {day_of_year} {week_of_year} {quarter} {days_in_month}
    \\  {days_in_year} {weeks_in_year} {leap_year}
    \\
    \\Examples:
    \\  sym454
    \\  sym454 -y 2026
    \\  sym454 8 2026
    \\  date +%s | sym454 -c
    \\  date -R | sym454 -c --long
    \\  echo 2026-08-35 | sym454 --from-sym
    \\
;

pub const Color = enum { auto, always, never };

pub const Options = struct {
    convert: bool = false,
    from_sym: bool = false,
    year: bool = false,
    three: bool = false,
    utc: bool = false,
    long: bool = false,
    as_json: bool = false,
    show_gregorian: bool = false,
    help: bool = false,
    format: []const u8 = "",
    color: Color = .auto,
    per_row: usize = 3,
    target_year: i64 = 1,
    target_month: u8 = 1,
};

const bool_flags = [_][]const u8{
    "c",   "convert", "from-sym", "y",    "year", "3",
    "utc", "long",    "json",     "help", "h",    "gregorian",
};

const value_flags = [_][]const u8{ "f", "format", "color", "across" };

fn isBoolFlag(name: []const u8) bool {
    for (bool_flags) |flag| {
        if (std.mem.eql(u8, flag, name)) return true;
    }
    return false;
}

fn isValueFlag(name: []const u8) bool {
    for (value_flags) |flag| {
        if (std.mem.eql(u8, flag, name)) return true;
    }
    return false;
}

fn isNegativeNumber(token: []const u8) bool {
    if (token.len < 2 or token[0] != '-') return false;

    for (token[1..]) |char| {
        if (char < '0' or char > '9') return false;
    }

    return true;
}

pub fn parseArgs(
    argv: []const []const u8,
    today: sym454.Sym,
    errors: *std.Io.Writer,
) !union(enum) { options: Options, status: u8 } {
    var options = Options{
        .target_year = today.year,
        .target_month = today.month,
    };

    var positional: [3][]const u8 = undefined;
    var positional_count: usize = 0;
    var only_positional = false;
    var index: usize = 0;

    while (index < argv.len) : (index += 1) {
        const token = argv[index];

        if (only_positional or token.len == 0 or token[0] != '-' or
            std.mem.eql(u8, token, "-"))
        {
            if (positional_count == positional.len) {
                try errors.writeAll(usage_text);
                return .{ .status = 2 };
            }
            positional[positional_count] = token;
            positional_count += 1;
            continue;
        }

        if (std.mem.eql(u8, token, "--")) {
            only_positional = true;
            continue;
        }

        var name = token[1..];
        if (name.len > 0 and name[0] == '-') name = name[1..];

        var value: ?[]const u8 = null;
        if (std.mem.indexOfScalar(u8, name, '=')) |split| {
            value = name[split + 1 ..];
            name = name[0..split];
        }

        if (!isBoolFlag(name) and !isValueFlag(name)) {
            if (isNegativeNumber(token)) {
                if (positional_count == positional.len) {
                    try errors.writeAll(usage_text);
                    return .{ .status = 2 };
                }
                positional[positional_count] = token;
                positional_count += 1;
                continue;
            }

            try errors.print("sym454: unknown flag {s}\n", .{token});
            try errors.writeAll(usage_text);
            return .{ .status = 2 };
        }

        if (isValueFlag(name) and value == null) {
            index += 1;
            if (index == argv.len) {
                try errors.print("sym454: flag {s} needs a value\n", .{token});
                return .{ .status = 2 };
            }
            value = argv[index];
        }

        if (std.mem.eql(u8, name, "c") or std.mem.eql(u8, name, "convert")) {
            options.convert = true;
        } else if (std.mem.eql(u8, name, "from-sym")) {
            options.from_sym = true;
        } else if (std.mem.eql(u8, name, "y") or std.mem.eql(u8, name, "year")) {
            options.year = true;
        } else if (std.mem.eql(u8, name, "3")) {
            options.three = true;
        } else if (std.mem.eql(u8, name, "utc")) {
            options.utc = true;
        } else if (std.mem.eql(u8, name, "long")) {
            options.long = true;
        } else if (std.mem.eql(u8, name, "json")) {
            options.as_json = true;
        } else if (std.mem.eql(u8, name, "gregorian")) {
            options.show_gregorian = true;
        } else if (std.mem.eql(u8, name, "h") or std.mem.eql(u8, name, "help")) {
            options.help = true;
        } else if (std.mem.eql(u8, name, "f") or std.mem.eql(u8, name, "format")) {
            options.format = value.?;
        } else if (std.mem.eql(u8, name, "color")) {
            options.color = std.meta.stringToEnum(Color, value.?) orelse {
                try errors.print(
                    "sym454: invalid --color \"{s}\", want auto, always or never\n",
                    .{value.?},
                );
                return .{ .status = 2 };
            };
        } else if (std.mem.eql(u8, name, "across")) {
            options.per_row = std.fmt.parseInt(usize, value.?, 10) catch 0;
            if (options.per_row < 1 or options.per_row > 12) {
                try errors.print(
                    "sym454: invalid --across {s}, want 1 to 12\n",
                    .{value.?},
                );
                return .{ .status = 2 };
            }
        }
    }

    if (options.help) {
        return .{ .options = options };
    }

    switch (positional_count) {
        0 => {},
        1 => {
            options.target_year = std.fmt.parseInt(i64, positional[0], 10) catch {
                try errors.print("sym454: invalid year \"{s}\"\n", .{positional[0]});
                return .{ .status = 2 };
            };
            if (!options.three) options.year = true;
        },
        2 => {
            const month = std.fmt.parseInt(u8, positional[0], 10) catch 0;
            if (month < 1 or month > 12) {
                try errors.print(
                    "sym454: invalid month \"{s}\", want 1 to 12\n",
                    .{positional[0]},
                );
                return .{ .status = 2 };
            }
            options.target_month = month;

            options.target_year = std.fmt.parseInt(i64, positional[1], 10) catch {
                try errors.print("sym454: invalid year \"{s}\"\n", .{positional[1]});
                return .{ .status = 2 };
            };
        },
        else => {
            try errors.writeAll(usage_text);
            return .{ .status = 2 };
        },
    }

    return .{ .options = options };
}

pub fn colorEnabled(color: Color, is_tty: bool, no_color: bool) bool {
    return switch (color) {
        .always => true,
        .never => false,
        .auto => !no_color and is_tty,
    };
}

pub fn main(init: std.process.Init) !u8 {
    const io = init.io;
    const arena = init.arena.allocator();

    var argv: std.ArrayList([]const u8) = .empty;
    var args = init.minimal.args.iterate();
    _ = args.next();
    while (args.next()) |arg| try argv.append(arena, arg);

    var error_buffer: [4096]u8 = undefined;
    var error_writer = std.Io.File.stderr().writer(io, &error_buffer);
    const errors = &error_writer.interface;
    defer errors.flush() catch {};

    var out_buffer: [64 * 1024]u8 = undefined;
    var out_writer = std.Io.File.stdout().writer(io, &out_buffer);
    const out = &out_writer.interface;

    const epoch = sym454.Sym{ .year = 1, .month = 1, .day = 1 };

    const probe = switch (try parseArgs(argv.items, epoch, errors)) {
        .status => |status| return status,
        .options => |value| value,
    };

    if (probe.help) {
        try out.writeAll(usage_text);
        try out.flush();
        return 0;
    }

    var zone: Zone = if (probe.utc)
        .utc()
    else
        .local(init.gpa, io, init.environ_map.get("TZ"));
    defer zone.deinit();

    const now = std.Io.Timestamp.now(io, .real).nanoseconds;
    const unix_seconds: i64 = @intCast(@divFloor(now, std.time.ns_per_s));

    const today = sym454.Sym.fromFixed(
        sym454.unixToFixed(unix_seconds + zone.offsetAt(unix_seconds)),
    );

    const options = switch (try parseArgs(argv.items, today, errors)) {
        .status => |status| return status,
        .options => |value| value,
    };

    if (options.convert or options.from_sym) {
        var in_buffer: [64 * 1024]u8 = undefined;
        var in_reader = std.Io.File.stdin().readerStreaming(io, &in_buffer);

        const status = try convert.run(&in_reader.interface, out, errors, .{
            .zone = zone,
            .format = options.format,
            .long = options.long,
            .as_json = options.as_json,
            .from_sym = options.from_sym,
        });

        try out.flush();
        return status;
    }

    const style = calendar.Style{
        .enabled = colorEnabled(
            options.color,
            std.Io.File.stdout().isTty(io) catch false,
            init.environ_map.get("NO_COLOR") != null,
        ),
    };

    if (options.year) {
        try calendar.renderYear(
            out,
            arena,
            options.target_year,
            today,
            style,
            options.per_row,
            options.show_gregorian,
        );
    } else if (options.three) {
        try calendar.renderThreeMonths(
            out,
            arena,
            options.target_year,
            options.target_month,
            today,
            style,
            options.show_gregorian,
        );
    } else {
        try calendar.renderSingleMonth(
            out,
            arena,
            options.target_year,
            options.target_month,
            today,
            style,
            options.show_gregorian,
        );
    }

    try out.flush();
    return 0;
}

const testing = std.testing;

fn parseFor(argv: []const []const u8) !Options {
    var discard = std.Io.Writer.Discarding.init(&.{});
    const today = sym454.Sym{ .year = 2026, .month = 8, .day = 35 };

    return switch (try parseArgs(argv, today, &discard.writer)) {
        .options => |options| options,
        .status => error.Rejected,
    };
}

fn statusFor(argv: []const []const u8) !u8 {
    var discard = std.Io.Writer.Discarding.init(&.{});
    const today = sym454.Sym{ .year = 2026, .month = 8, .day = 35 };

    return switch (try parseArgs(argv, today, &discard.writer)) {
        .options => 0,
        .status => |status| status,
    };
}

test "no arguments show the current month" {
    const options = try parseFor(&.{});

    try testing.expectEqual(2026, options.target_year);
    try testing.expectEqual(8, options.target_month);
    try testing.expect(!options.year);
    try testing.expect(!options.three);
}

test "a single argument is a year" {
    const options = try parseFor(&.{"2030"});

    try testing.expectEqual(2030, options.target_year);
    try testing.expect(options.year);
}

test "two arguments are a month and a year" {
    const options = try parseFor(&.{ "8", "2030" });

    try testing.expectEqual(2030, options.target_year);
    try testing.expectEqual(8, options.target_month);
    try testing.expect(!options.year);
}

test "negative years are arguments, not flags" {
    const options = try parseFor(&.{"-121"});

    try testing.expectEqual(-121, options.target_year);
    try testing.expect(options.year);

    const both = try parseFor(&.{ "4", "-121" });
    try testing.expectEqual(-121, both.target_year);
    try testing.expectEqual(4, both.target_month);
}

test "-3 stays a flag" {
    const options = try parseFor(&.{"-3"});

    try testing.expect(options.three);
    try testing.expectEqual(2026, options.target_year);
    try testing.expectEqual(8, options.target_month);

    const with_year = try parseFor(&.{ "-3", "2030" });
    try testing.expect(with_year.three);
    try testing.expect(!with_year.year);
    try testing.expectEqual(2030, with_year.target_year);
}

test "long and short flags" {
    try testing.expect((try parseFor(&.{"-y"})).year);
    try testing.expect((try parseFor(&.{"--year"})).year);
    try testing.expect((try parseFor(&.{"-c"})).convert);
    try testing.expect((try parseFor(&.{"--convert"})).convert);
    try testing.expect((try parseFor(&.{"--from-sym"})).from_sym);
    try testing.expect((try parseFor(&.{"--utc"})).utc);
    try testing.expect((try parseFor(&.{"--long"})).long);
    try testing.expect((try parseFor(&.{"--json"})).as_json);
    try testing.expect((try parseFor(&.{"--gregorian"})).show_gregorian);
}

test "flag values in both forms" {
    try testing.expectEqual(Color.never, (try parseFor(&.{ "--color", "never" })).color);
    try testing.expectEqual(Color.always, (try parseFor(&.{"--color=always"})).color);
    try testing.expectEqual(4, (try parseFor(&.{ "--across", "4" })).per_row);
    try testing.expectEqual(2, (try parseFor(&.{"--across=2"})).per_row);
    try testing.expectEqualStrings("{sym454}", (try parseFor(&.{ "-f", "{sym454}" })).format);
    try testing.expectEqualStrings("{year}", (try parseFor(&.{"--format={year}"})).format);
}

test "flags mixed with arguments" {
    const options = try parseFor(&.{ "-y", "2030", "--color", "never" });

    try testing.expect(options.year);
    try testing.expectEqual(2030, options.target_year);
    try testing.expectEqual(Color.never, options.color);
}

test "rejected arguments exit with status 2" {
    try testing.expectEqual(2, try statusFor(&.{ "--color", "purple" }));
    try testing.expectEqual(2, try statusFor(&.{ "--across", "0" }));
    try testing.expectEqual(2, try statusFor(&.{ "--across", "13" }));
    try testing.expectEqual(2, try statusFor(&.{ "13", "2026" }));
    try testing.expectEqual(2, try statusFor(&.{ "0", "2026" }));
    try testing.expectEqual(2, try statusFor(&.{"nonsense"}));
    try testing.expectEqual(2, try statusFor(&.{"--nope"}));
    try testing.expectEqual(2, try statusFor(&.{ "1", "2", "3", "4" }));
    try testing.expectEqual(2, try statusFor(&.{"--color"}));
}

test "color decisions" {
    try testing.expect(colorEnabled(.always, false, true));
    try testing.expect(!colorEnabled(.never, true, false));
    try testing.expect(colorEnabled(.auto, true, false));
    try testing.expect(!colorEnabled(.auto, false, false));
    try testing.expect(!colorEnabled(.auto, true, true));
}
