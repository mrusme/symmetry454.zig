const std = @import("std");
const sym454 = @import("symmetry454");
const Zone = @import("zone.zig").Zone;

pub const default_format =
    "{gregorian} -> {sym454} {weekday}, {month_name} {day}, {year}";

pub const default_sym_format = "{sym454} -> {gregorian} {weekday}";

pub const Options = struct {
    zone: Zone,
    format: []const u8 = "",
    long: bool = false,
    as_json: bool = false,
    from_sym: bool = false,
};

pub const Conversion = struct {
    gregorian: []const u8,
    unix: i64,
    fixed: i64,
    sym: sym454.Sym,

    pub fn field(self: Conversion, name: []const u8, writer: *std.Io.Writer) !bool {
        const sym = self.sym;

        if (std.mem.eql(u8, name, "gregorian")) {
            try writer.writeAll(self.gregorian);
        } else if (std.mem.eql(u8, name, "unix")) {
            try writer.print("{d}", .{self.unix});
        } else if (std.mem.eql(u8, name, "fixed")) {
            try writer.print("{d}", .{self.fixed});
        } else if (std.mem.eql(u8, name, "sym454")) {
            try writer.print("{f}", .{sym});
        } else if (std.mem.eql(u8, name, "year")) {
            try writer.print("{d}", .{sym.year});
        } else if (std.mem.eql(u8, name, "month")) {
            try writer.print("{d}", .{sym.month});
        } else if (std.mem.eql(u8, name, "month_name")) {
            try writer.writeAll(sym.monthName());
        } else if (std.mem.eql(u8, name, "day")) {
            try writer.print("{d}", .{sym.day});
        } else if (std.mem.eql(u8, name, "weekday")) {
            try writer.writeAll(sym.weekday().name());
        } else if (std.mem.eql(u8, name, "day_of_year")) {
            try writer.print("{d}", .{sym.dayOfYear()});
        } else if (std.mem.eql(u8, name, "week_of_year")) {
            try writer.print("{d}", .{sym.weekOfYear()});
        } else if (std.mem.eql(u8, name, "quarter")) {
            try writer.print("{d}", .{sym.quarter()});
        } else if (std.mem.eql(u8, name, "days_in_month")) {
            try writer.print("{d}", .{sym.daysInMonth()});
        } else if (std.mem.eql(u8, name, "days_in_year")) {
            try writer.print("{d}", .{sym.daysInYear()});
        } else if (std.mem.eql(u8, name, "weeks_in_year")) {
            try writer.print("{d}", .{sym.weeksInYear()});
        } else if (std.mem.eql(u8, name, "leap_year")) {
            try writer.print("{}", .{sym.isLeap()});
        } else {
            return false;
        }

        return true;
    }

    pub fn writeJson(self: Conversion, writer: *std.Io.Writer) !void {
        const sym = self.sym;

        try writer.print("{{\"gregorian\":\"{s}\"", .{self.gregorian});
        try writer.print(",\"unix\":{d}", .{self.unix});
        try writer.print(",\"fixed\":{d}", .{self.fixed});
        try writer.print(",\"sym454\":\"{f}\"", .{sym});
        try writer.print(",\"year\":{d}", .{sym.year});
        try writer.print(",\"month\":{d}", .{sym.month});
        try writer.print(",\"month_name\":\"{s}\"", .{sym.monthName()});
        try writer.print(",\"day\":{d}", .{sym.day});
        try writer.print(",\"weekday\":\"{s}\"", .{sym.weekday().name()});
        try writer.print(",\"day_of_year\":{d}", .{sym.dayOfYear()});
        try writer.print(",\"week_of_year\":{d}", .{sym.weekOfYear()});
        try writer.print(",\"quarter\":{d}", .{sym.quarter()});
        try writer.print(",\"days_in_month\":{d}", .{sym.daysInMonth()});
        try writer.print(",\"days_in_year\":{d}", .{sym.daysInYear()});
        try writer.print(",\"weeks_in_year\":{d}", .{sym.weeksInYear()});
        try writer.print(",\"leap_year\":{}", .{sym.isLeap()});
        try writer.writeAll("}\n");
    }

    pub fn writeLong(self: Conversion, writer: *std.Io.Writer) !void {
        const sym = self.sym;

        try writer.print("Gregorian     {s}\n", .{self.gregorian});
        try writer.print("Unix          {d}\n", .{self.unix});
        try writer.print("Fixed day     {d}\n", .{self.fixed});
        try writer.print("Symmetry454   {f}\n", .{sym});
        try writer.print("Long form     {s}, {s} {d}, {d}\n", .{
            sym.weekday().name(),
            sym.monthName(),
            sym.day,
            sym.year,
        });
        try writer.print("Day of year   {d} of {d}\n", .{ sym.dayOfYear(), sym.daysInYear() });
        try writer.print("Week of year  {d} of {d}\n", .{ sym.weekOfYear(), sym.weeksInYear() });
        try writer.print("Quarter       {d}\n", .{sym.quarter()});
        try writer.print("Days in month {d}\n", .{sym.daysInMonth()});
        try writer.print("Leap year     {s}\n", .{if (sym.isLeap()) "yes" else "no"});
    }
};

pub const ParseError = error{
    EmptyInput,
    UnrecognizedDate,
    UnrecognizedSymDate,
    MonthOutOfRange,
    InvalidSymDate,
    NumberTooLarge,
};

const Civil = struct {
    year: i64 = 0,
    month: u8 = 0,
    day: u8 = 0,
    hour: u8 = 0,
    minute: u8 = 0,
    second: u8 = 0,
    offset: ?i32 = null,
    abbrev: ?[]const u8 = null,
};

pub const Instant = struct {
    year: i64,
    month: u8,
    day: u8,
    unix: i64,
    offset: i32,
};

fn isDigits(text: []const u8) bool {
    if (text.len == 0) return false;
    for (text) |char| {
        if (char < '0' or char > '9') return false;
    }
    return true;
}

fn isEpochSeconds(text: []const u8) bool {
    if (text.len == 0) return false;
    if (text[0] == '+' or text[0] == '-') return isDigits(text[1..]);
    return isDigits(text);
}

fn parseUnsigned(comptime T: type, text: []const u8) ParseError!T {
    return std.fmt.parseInt(T, text, 10) catch error.NumberTooLarge;
}

fn monthFromName(text: []const u8) ?u8 {
    const names = [_][]const u8{
        "jan", "feb", "mar", "apr", "may", "jun",
        "jul", "aug", "sep", "oct", "nov", "dec",
    };

    if (text.len < 3) return null;

    var lower: [3]u8 = undefined;
    for (text[0..3], 0..) |char, index| lower[index] = std.ascii.toLower(char);

    for (names, 1..) |name, month| {
        if (std.mem.eql(u8, &lower, name)) return @intCast(month);
    }

    return null;
}

fn isWeekdayName(text: []const u8) bool {
    const names = [_][]const u8{ "mon", "tue", "wed", "thu", "fri", "sat", "sun" };

    if (text.len < 3) return false;

    var lower: [3]u8 = undefined;
    for (text[0..3], 0..) |char, index| lower[index] = std.ascii.toLower(char);

    for (names) |name| {
        if (std.mem.eql(u8, &lower, name)) return true;
    }

    return false;
}

fn parseOffset(text: []const u8) ?i32 {
    if (text.len == 0) return null;
    if (text.len == 1 and (text[0] == 'Z' or text[0] == 'z')) return 0;
    if (text[0] != '+' and text[0] != '-') return null;

    const sign: i32 = if (text[0] == '-') -1 else 1;
    const body = text[1..];

    var hours: []const u8 = undefined;
    var minutes: []const u8 = "0";

    if (std.mem.indexOfScalar(u8, body, ':')) |colon| {
        hours = body[0..colon];
        minutes = body[colon + 1 ..];
    } else switch (body.len) {
        2 => hours = body,
        4 => {
            hours = body[0..2];
            minutes = body[2..4];
        },
        else => return null,
    }

    if (!isDigits(hours) or !isDigits(minutes)) return null;

    const hour = std.fmt.parseInt(i32, hours, 10) catch return null;
    const minute = std.fmt.parseInt(i32, minutes, 10) catch return null;

    return sign * (hour * 3600 + minute * 60);
}

fn parseClock(text: []const u8, civil: *Civil) bool {
    var body = text;

    if (std.mem.indexOfScalar(u8, body, '.')) |dot| body = body[0..dot];

    var parts = std.mem.splitScalar(u8, body, ':');

    const hours = parts.next() orelse return false;
    const minutes = parts.next() orelse return false;
    const seconds = parts.next() orelse "0";

    if (parts.next() != null) return false;
    if (!isDigits(hours) or !isDigits(minutes) or !isDigits(seconds)) return false;

    civil.hour = std.fmt.parseInt(u8, hours, 10) catch return false;
    civil.minute = std.fmt.parseInt(u8, minutes, 10) catch return false;
    civil.second = std.fmt.parseInt(u8, seconds, 10) catch return false;

    return civil.hour < 24 and civil.minute < 60 and civil.second < 61;
}

fn splitZoneSuffix(text: []const u8) struct { body: []const u8, zone: ?[]const u8 } {
    if (text.len > 1 and (text[text.len - 1] == 'Z' or text[text.len - 1] == 'z')) {
        return .{ .body = text[0 .. text.len - 1], .zone = text[text.len - 1 ..] };
    }

    var index: usize = 1;
    while (index < text.len) : (index += 1) {
        if (text[index] == '+' or text[index] == '-') {
            return .{ .body = text[0..index], .zone = text[index..] };
        }
    }

    return .{ .body = text, .zone = null };
}

fn parseYearMonthDay(text: []const u8, civil: *Civil) bool {
    const separator: u8 = if (std.mem.indexOfScalar(u8, text, '-') != null)
        '-'
    else if (std.mem.indexOfScalar(u8, text, '/') != null)
        '/'
    else
        return false;

    var parts = std.mem.splitScalar(u8, text, separator);

    const years = parts.next() orelse return false;
    const months = parts.next() orelse return false;
    const days = parts.next() orelse return false;

    if (parts.next() != null) return false;
    if (!isDigits(years) or !isDigits(months) or !isDigits(days)) return false;

    civil.year = std.fmt.parseInt(i64, years, 10) catch return false;
    civil.month = std.fmt.parseInt(u8, months, 10) catch return false;
    civil.day = std.fmt.parseInt(u8, days, 10) catch return false;

    return civil.month >= 1 and civil.month <= 12 and
        civil.day >= 1 and civil.day <= 31;
}

fn meridiemOf(text: []const u8) ?bool {
    var letters: [2]u8 = undefined;
    var count: usize = 0;

    for (text) |char| {
        if (char == '.') continue;
        if (count == letters.len) return null;
        letters[count] = std.ascii.toUpper(char);
        count += 1;
    }

    if (count != 2 or letters[1] != 'M') return null;

    return switch (letters[0]) {
        'A' => false,
        'P' => true,
        else => null,
    };
}

fn isZoneAbbrev(text: []const u8) bool {
    if (text.len < 2 or text.len > 6) return false;

    for (text) |char| {
        if (char < 'A' or char > 'Z') return false;
    }

    return true;
}

fn parseCivil(text: []const u8) ?Civil {
    var tokens: [8][]const u8 = undefined;
    var count: usize = 0;

    var it = std.mem.tokenizeAny(u8, text, " \t,");
    while (it.next()) |token| {
        if (count == tokens.len) return null;
        tokens[count] = token;
        count += 1;
    }

    if (count == 0) return null;

    var fields = tokens[0..count];
    if (isWeekdayName(fields[0]) and monthFromName(fields[0]) == null) {
        fields = fields[1..];
    }

    if (fields.len == 0) return null;

    var civil: Civil = .{};
    var have_clock = false;
    var have_year = false;
    var meridiem: ?bool = null;
    var rest: []const []const u8 = undefined;

    if (monthFromName(fields[0])) |month| {
        if (fields.len < 2 or !isDigits(fields[1])) return null;

        civil.month = month;
        civil.day = std.fmt.parseInt(u8, fields[1], 10) catch return null;
        rest = fields[2..];
    } else if (fields.len >= 2 and isDigits(fields[0]) and
        monthFromName(fields[1]) != null)
    {
        civil.day = std.fmt.parseInt(u8, fields[0], 10) catch return null;
        civil.month = monthFromName(fields[1]).?;
        rest = fields[2..];
    } else {
        var head = fields[0];
        rest = fields[1..];

        if (std.mem.indexOfScalar(u8, head, 'T')) |split| {
            const parted = splitZoneSuffix(head[split + 1 ..]);
            head = head[0..split];

            if (!parseClock(parted.body, &civil)) return null;
            if (parted.zone) |zone| {
                civil.offset = parseOffset(zone) orelse return null;
            }
            have_clock = true;
        }

        if (!parseYearMonthDay(head, &civil)) return null;
        have_year = true;
    }

    if (civil.day < 1 or civil.day > 31) return null;

    for (rest) |token| {
        if (meridiemOf(token)) |afternoon| {
            if (meridiem != null) return null;
            meridiem = afternoon;
            continue;
        }

        if (!have_clock and std.mem.indexOfScalar(u8, token, ':') != null) {
            const parted = splitZoneSuffix(token);
            if (!parseClock(parted.body, &civil)) return null;
            if (parted.zone) |zone| {
                civil.offset = parseOffset(zone) orelse return null;
            }
            have_clock = true;
            continue;
        }

        if (!have_year and isDigits(token)) {
            civil.year = std.fmt.parseInt(i64, token, 10) catch return null;
            have_year = true;
            continue;
        }

        if (parseOffset(token)) |offset| {
            civil.offset = offset;
            continue;
        }

        if (isZoneAbbrev(token)) {
            if (civil.abbrev != null) return null;
            civil.abbrev = token;
            continue;
        }

        return null;
    }

    if (!have_year) return null;

    if (meridiem) |afternoon| {
        if (!have_clock or civil.hour > 12) return null;
        if (afternoon) {
            if (civil.hour < 12) civil.hour += 12;
        } else if (civil.hour == 12) {
            civil.hour = 0;
        }
    }

    return civil;
}

fn civilSeconds(civil: Civil) i64 {
    const days = sym454.gregorianToFixed(civil.year, civil.month, civil.day) -
        sym454.unix_epoch_fixed;

    return days * sym454.seconds_per_day +
        @as(i64, civil.hour) * 3600 +
        @as(i64, civil.minute) * 60 +
        @as(i64, civil.second);
}

pub fn parseInstant(text: []const u8, zone: Zone) ParseError!Instant {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.EmptyInput;

    if (isEpochSeconds(trimmed)) {
        const seconds = std.fmt.parseInt(i64, trimmed, 10) catch
            return error.NumberTooLarge;
        const offset = zone.offsetAt(seconds);
        const greg = sym454.fixedToGregorian(
            sym454.unixToFixed(seconds + offset),
        );

        return .{
            .year = greg.year,
            .month = greg.month,
            .day = greg.day,
            .unix = seconds,
            .offset = offset,
        };
    }

    const civil = parseCivil(trimmed) orelse return error.UnrecognizedDate;

    const offset = civil.offset orelse blk: {
        if (civil.abbrev) |abbrev| {
            if (zone.offsetForAbbrev(abbrev)) |known| break :blk known;
        }

        const naive = civilSeconds(civil);
        const guess = zone.offsetAt(naive);
        break :blk zone.offsetAt(naive - guess);
    };

    return .{
        .year = civil.year,
        .month = civil.month,
        .day = civil.day,
        .unix = civilSeconds(civil) - offset,
        .offset = offset,
    };
}

pub const SymDetail = struct {
    year: i64 = 0,
    month: u8 = 0,
    days: i64 = 0,
};

pub fn parseSym(text: []const u8) ParseError!sym454.Sym {
    var detail: SymDetail = .{};
    return parseSymDetailed(text, &detail);
}

pub fn parseSymDetailed(text: []const u8, detail: *SymDetail) ParseError!sym454.Sym {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");

    var body = trimmed;
    var negative = false;
    if (body.len > 0 and body[0] == '-') {
        negative = true;
        body = body[1..];
    }

    var parts = std.mem.splitScalar(u8, body, '-');
    const years = parts.next() orelse return error.UnrecognizedSymDate;
    const months = parts.next() orelse return error.UnrecognizedSymDate;
    const days = parts.next() orelse return error.UnrecognizedSymDate;

    if (parts.next() != null) return error.UnrecognizedSymDate;
    if (!isDigits(years) or !isDigits(months) or !isDigits(days)) {
        return error.UnrecognizedSymDate;
    }
    if (months.len > 2 or days.len > 2) return error.UnrecognizedSymDate;

    const year = try parseUnsigned(i64, years);
    const month = try parseUnsigned(u8, months);
    const day = try parseUnsigned(u8, days);

    detail.month = month;
    if (month < 1 or month > 12) return error.MonthOutOfRange;

    const sym = sym454.Sym{
        .year = if (negative) -year else year,
        .month = month,
        .day = day,
    };

    detail.year = sym.year;
    detail.days = sym.daysInMonth();

    if (!sym.valid()) return error.InvalidSymDate;

    return sym;
}

fn writeRfc3339(writer: *std.Io.Writer, instant: Instant, seconds: i64) !void {
    const local = seconds + instant.offset;
    const day_seconds: u64 = @intCast(@mod(local, sym454.seconds_per_day));

    try writer.print("{f}T{d:0>2}:{d:0>2}:{d:0>2}", .{
        sym454.Gregorian{
            .year = instant.year,
            .month = instant.month,
            .day = instant.day,
        },
        day_seconds / 3600,
        day_seconds % 3600 / 60,
        day_seconds % 60,
    });

    if (instant.offset == 0) {
        try writer.writeByte('Z');
        return;
    }

    const magnitude = @abs(instant.offset);
    try writer.print("{c}{d:0>2}:{d:0>2}", .{
        @as(u8, if (instant.offset < 0) '-' else '+'),
        @divFloor(magnitude, 3600),
        @divFloor(@mod(magnitude, 3600), 60),
    });
}

pub fn renderFormat(
    writer: *std.Io.Writer,
    template: []const u8,
    result: Conversion,
) !void {
    var index: usize = 0;

    while (index < template.len) {
        const char = template[index];

        if (char == '{') {
            if (index + 1 < template.len and template[index + 1] == '{') {
                try writer.writeByte('{');
                index += 2;
                continue;
            }

            const close = std.mem.indexOfScalarPos(u8, template, index, '}') orelse
                return error.UnterminatedPlaceholder;

            const name = template[index + 1 .. close];
            if (!try result.field(name, writer)) return error.UnknownPlaceholder;

            index = close + 1;
            continue;
        }

        if (char == '}') {
            if (index + 1 < template.len and template[index + 1] == '}') {
                try writer.writeByte('}');
                index += 2;
                continue;
            }
            return error.UnterminatedPlaceholder;
        }

        try writer.writeByte(char);
        index += 1;
    }
}

pub fn checkFormat(template: []const u8, errors: *std.Io.Writer) !bool {
    var discard = std.Io.Writer.Discarding.init(&.{});

    const probe = Conversion{
        .gregorian = "",
        .unix = 0,
        .fixed = 0,
        .sym = .{ .year = 1, .month = 1, .day = 1 },
    };

    renderFormat(&discard.writer, template, probe) catch |err| switch (err) {
        error.UnknownPlaceholder => {
            try errors.print("sym454: unknown placeholder in format {s}\n", .{template});
            return false;
        },
        error.UnterminatedPlaceholder => {
            try errors.print("sym454: unbalanced braces in format {s}\n", .{template});
            return false;
        },
        else => return err,
    };

    return true;
}

fn reportParseError(
    errors: *std.Io.Writer,
    err: ParseError,
    line: []const u8,
    detail: SymDetail,
) !void {
    switch (err) {
        error.EmptyInput => try errors.writeAll("sym454: empty input\n"),
        error.UnrecognizedDate => try errors.print(
            "sym454: unrecognized date format \"{s}\"\n",
            .{line},
        ),
        error.UnrecognizedSymDate => try errors.print(
            "sym454: unrecognized Symmetry454 date \"{s}\", want YYYY-MM-DD\n",
            .{line},
        ),
        error.MonthOutOfRange => try errors.print(
            "sym454: invalid Symmetry454 date \"{s}\", month {d} is not in 1 to 12\n",
            .{ line, detail.month },
        ),
        error.InvalidSymDate => try errors.print(
            "sym454: invalid Symmetry454 date \"{s}\", {s} {d} has {d} days\n",
            .{ line, sym454.monthName(detail.month), detail.year, detail.days },
        ),
        error.NumberTooLarge => try errors.print(
            "sym454: number out of range in \"{s}\"\n",
            .{line},
        ),
    }
}

pub fn run(
    reader: *std.Io.Reader,
    writer: *std.Io.Writer,
    errors: *std.Io.Writer,
    options: Options,
) !u8 {
    const template = if (options.format.len > 0)
        options.format
    else if (options.from_sym)
        default_sym_format
    else
        default_format;

    if (!try checkFormat(template, errors)) return 2;

    var status: u8 = 0;
    var blocks: usize = 0;
    var buffer: [64]u8 = undefined;

    while (try reader.takeDelimiter('\n')) |raw| {
        const line = std.mem.trim(u8, raw, " \t\r");
        if (line.len == 0) continue;

        var result: Conversion = undefined;

        if (options.from_sym) {
            var detail: SymDetail = .{};
            const sym = parseSymDetailed(line, &detail) catch |err| {
                try writer.flush();
                try reportParseError(errors, err, line, detail);
                try errors.flush();
                status = 1;
                continue;
            };

            const fixed = sym.fixed();
            const greg = sym454.fixedToGregorian(fixed);
            var text = std.Io.Writer.fixed(&buffer);
            try text.print("{f}", .{greg});

            result = .{
                .gregorian = text.buffered(),
                .unix = sym454.fixedToUnix(fixed) - options.zone.offsetAt(
                    sym454.fixedToUnix(fixed),
                ),
                .fixed = fixed,
                .sym = sym,
            };
        } else {
            const instant = parseInstant(line, options.zone) catch |err| {
                try writer.flush();
                try reportParseError(errors, err, line, .{});
                try errors.flush();
                status = 1;
                continue;
            };

            const fixed = sym454.gregorianToFixed(
                instant.year,
                instant.month,
                instant.day,
            );

            var text = std.Io.Writer.fixed(&buffer);
            try writeRfc3339(&text, instant, instant.unix);

            result = .{
                .gregorian = text.buffered(),
                .unix = instant.unix,
                .fixed = fixed,
                .sym = sym454.fixedToSym(fixed),
            };
        }

        if (options.as_json) {
            try result.writeJson(writer);
        } else if (options.long) {
            if (blocks > 0) try writer.writeByte('\n');
            try result.writeLong(writer);
            blocks += 1;
        } else {
            try renderFormat(writer, template, result);
            try writer.writeByte('\n');
        }
    }

    return status;
}

const testing = std.testing;

fn expectParsed(text: []const u8, year: i64, month: u8, day: u8) !void {
    const instant = try parseInstant(text, Zone.utc());
    try testing.expectEqual(year, instant.year);
    try testing.expectEqual(month, instant.month);
    try testing.expectEqual(day, instant.day);
}

test "parses epoch seconds" {
    try expectParsed("0", 1970, 1, 1);
    try expectParsed("1788110945", 2026, 8, 30);
    try expectParsed("-1", 1969, 12, 31);
    try expectParsed("  1788110945  ", 2026, 8, 30);
}

test "parses RFC 1123 with an offset from date -R" {
    try expectParsed("Sun, 30 Aug 2026 12:29:05 -0500", 2026, 8, 30);
    try expectParsed("Mon, 02 Jan 2006 15:04:05 +0100", 2006, 1, 2);
}

test "parses RFC 3339 from date -Is" {
    try expectParsed("2026-08-30T12:29:05-05:00", 2026, 8, 30);
    try expectParsed("2026-08-30T17:29:05Z", 2026, 8, 30);
    try expectParsed("2026-08-30T17:29:05.123456Z", 2026, 8, 30);
}

test "parses the default output of date" {
    try expectParsed("Sun Aug 30 12:29:05 CDT 2026", 2026, 8, 30);
    try expectParsed("Sun Aug 30 12:29:05 2026", 2026, 8, 30);
    try expectParsed("Sun Aug 30 12:29:05 -0500 2026", 2026, 8, 30);
}

test "parses plain dates" {
    try expectParsed("2026-08-30", 2026, 8, 30);
    try expectParsed("2026/08/30", 2026, 8, 30);
    try expectParsed("2026-08-30 12:29:05", 2026, 8, 30);
    try expectParsed("2026-08-30 12:29", 2026, 8, 30);
    try expectParsed("2026-08-30 12:29:05 -0500", 2026, 8, 30);
    try expectParsed("30 Aug 2026 12:29:05 -0500", 2026, 8, 30);
    try expectParsed("2 Jan 2006 15:04:05 -0700", 2006, 1, 2);
}

test "parses the date output of English locales" {
    const inputs = [_][]const u8{
        "Sun Aug  9 13:05:03 UTC 2026",
        "Sun Aug  9 01:05:03 PM UTC 2026",
        "Sun Aug 09 01:05:03 PM UTC 2026",
        "Sun  9 Aug 13:05:03 UTC 2026",
        "Sun  9 Aug 01:05:03 PM UTC 2026",
        "Sun 09 Aug 2026 13:05:03 UTC",
        "Sun 09 Aug 2026 01:05:03 PM UTC",
        "09 Aug 2026 13:05:03 UTC",
        "2026-08-09 13:05:03",
        "2026-08-09 01:05:03 PM",
    };

    for (inputs) |input| {
        const instant = try parseInstant(input, Zone.utc());
        try testing.expectEqual(2026, instant.year);
        try testing.expectEqual(8, instant.month);
        try testing.expectEqual(9, instant.day);
        try testing.expectEqual(1786280703, instant.unix);
    }
}

test "converts a 12 hour clock" {
    const cases = [_]struct { input: []const u8, hour: i64 }{
        .{ .input = "Sun Aug  9 00:05:03 AM UTC 2026", .hour = 0 },
        .{ .input = "Sun Aug  9 00:05:03 PM UTC 2026", .hour = 12 },
        .{ .input = "Sun Aug  9 12:05:03 AM UTC 2026", .hour = 0 },
        .{ .input = "Sun Aug  9 01:05:03 AM UTC 2026", .hour = 1 },
        .{ .input = "Sun Aug  9 11:05:03 AM UTC 2026", .hour = 11 },
        .{ .input = "Sun Aug  9 12:05:03 PM UTC 2026", .hour = 12 },
        .{ .input = "Sun Aug  9 01:05:03 PM UTC 2026", .hour = 13 },
        .{ .input = "Sun Aug  9 11:05:03 PM UTC 2026", .hour = 23 },
    };

    const midnight = try parseInstant("2026-08-09T00:00:00Z", Zone.utc());

    for (cases) |case| {
        const instant = try parseInstant(case.input, Zone.utc());
        const elapsed = instant.unix - midnight.unix;
        try testing.expectEqual(case.hour, @divFloor(elapsed, 3600));
    }
}

test "rejects an impossible 12 hour clock" {
    const inputs = [_][]const u8{
        "Sun Aug  9 13:05:03 PM UTC 2026",
        "Sun Aug  9 25:05:03 UTC 2026",
        "Sun Aug  9 12:05:03 XM UTC 2026",
        "Sun Aug  9 12:05:03 AM PM UTC 2026",
    };

    for (inputs) |input| {
        try testing.expectError(
            error.UnrecognizedDate,
            parseInstant(input, Zone.utc()),
        );
    }
}

test "resolves universal zone abbreviations" {
    const utc = try parseInstant("Sun Aug  9 13:05:03 UTC 2026", Zone.utc());
    try testing.expectEqual(0, utc.offset);

    const gmt = try parseInstant("Sun Aug  9 13:05:03 GMT 2026", Zone.utc());
    try testing.expectEqual(0, gmt.offset);
    try testing.expectEqual(utc.unix, gmt.unix);

    const explicit = try parseInstant("Sun  9 Aug 13:05:03 -0700 2026", Zone.utc());
    try testing.expectEqual(-7 * 3600, explicit.offset);
    try testing.expectEqual(utc.unix + 7 * 3600, explicit.unix);
}

test "rejects unparsable input" {
    try testing.expectError(error.UnrecognizedDate, parseInstant("garbage", Zone.utc()));
    try testing.expectError(error.UnrecognizedDate, parseInstant("Aug 30 12:00:00 CDT", Zone.utc()));
    try testing.expectError(error.UnrecognizedDate, parseInstant("Sun Aug 30", Zone.utc()));
    try testing.expectError(error.UnrecognizedDate, parseInstant("Aug 30 12:00:00 hello 2026", Zone.utc()));
    try testing.expectError(error.UnrecognizedDate, parseInstant("2026-13", Zone.utc()));
    try testing.expectError(error.UnrecognizedDate, parseInstant("2026-99-99", Zone.utc()));
    try testing.expectError(error.EmptyInput, parseInstant("   ", Zone.utc()));
}

test "offsets shift the reported day" {
    const before = try parseInstant("2026-08-30T23:00:00-05:00", Zone.utc());
    try testing.expectEqual(30, before.day);
    try testing.expectEqual(1788148800, before.unix);

    const after = try parseInstant("2026-08-31T04:00:00Z", Zone.utc());
    try testing.expectEqual(31, after.day);
    try testing.expectEqual(1788148800, after.unix);
}

test "parses Symmetry454 dates" {
    try testing.expectEqual(
        sym454.Sym{ .year = 2026, .month = 8, .day = 35 },
        try parseSym("2026-08-35"),
    );
    try testing.expectEqual(
        sym454.Sym{ .year = 2026, .month = 12, .day = 35 },
        try parseSym("2026-12-35"),
    );
    try testing.expectEqual(
        sym454.Sym{ .year = -99, .month = 1, .day = 1 },
        try parseSym("-0099-01-01"),
    );
}

test "rejects invalid Symmetry454 dates" {
    try testing.expectError(error.InvalidSymDate, parseSym("2025-12-35"));
    try testing.expectError(error.InvalidSymDate, parseSym("2026-01-29"));
    try testing.expectError(error.MonthOutOfRange, parseSym("2026-13-01"));
    try testing.expectError(error.UnrecognizedSymDate, parseSym("2026-08"));
    try testing.expectError(error.UnrecognizedSymDate, parseSym("garbage"));
}

test "renders format placeholders" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    const result = Conversion{
        .gregorian = "2026-08-30",
        .unix = 1788110945,
        .fixed = 739858,
        .sym = .{ .year = 2026, .month = 8, .day = 35 },
    };

    try renderFormat(&writer, default_format, result);
    try testing.expectEqualStrings(
        "2026-08-30 -> 2026-08-35 Sunday, August 35, 2026",
        writer.buffered(),
    );

    writer = std.Io.Writer.fixed(&buffer);
    try renderFormat(&writer, "{{{quarter}}}", result);
    try testing.expectEqualStrings("{3}", writer.buffered());
}

test "rejects unknown placeholders" {
    var buffer: [256]u8 = undefined;
    var writer = std.Io.Writer.fixed(&buffer);

    const result = Conversion{
        .gregorian = "",
        .unix = 0,
        .fixed = 0,
        .sym = .{ .year = 1, .month = 1, .day = 1 },
    };

    try testing.expectError(
        error.UnknownPlaceholder,
        renderFormat(&writer, "{nope}", result),
    );
    try testing.expectError(
        error.UnterminatedPlaceholder,
        renderFormat(&writer, "{sym454", result),
    );
}
