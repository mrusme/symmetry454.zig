const std = @import("std");
const sym454 = @import("symmetry454");

pub const Rule = union(enum) {
    month_week_day: struct { month: u8, week: u8, weekday: u8, seconds: i32 },
    julian: struct { day: u16, seconds: i32 },
    ordinal: struct { day: u16, seconds: i32 },
};

pub const Posix = struct {
    std_offset: i32,
    dst_offset: ?i32 = null,
    start: ?Rule = null,
    end: ?Rule = null,
};

pub const Zone = struct {
    data: ?std.tz.Tz = null,
    posix: ?Posix = null,

    pub fn utc() Zone {
        return .{};
    }

    pub fn local(gpa: std.mem.Allocator, io: std.Io, tz_name: ?[]const u8) Zone {
        if (tz_name) |raw| {
            const name = if (raw.len > 0 and raw[0] == ':') raw[1..] else raw;

            if (name.len == 0 or
                std.mem.eql(u8, name, "UTC") or
                std.mem.eql(u8, name, "UTC0") or
                std.mem.eql(u8, name, "GMT"))
            {
                return .{};
            }

            if (std.mem.startsWith(u8, name, "/")) {
                if (load(gpa, io, name)) |zone| return zone else |_| {}
            } else if (isPathSafe(name)) {
                var buf: [std.fs.max_path_bytes]u8 = undefined;
                const path = std.fmt.bufPrint(
                    &buf,
                    "/usr/share/zoneinfo/{s}",
                    .{name},
                ) catch return .{};
                if (load(gpa, io, path)) |zone| return zone else |_| {}
            }

            if (parsePosix(name)) |posix| return .{ .posix = posix };
        }

        if (load(gpa, io, "/etc/localtime")) |zone| return zone else |_| {}

        return .{};
    }

    pub fn deinit(self: *Zone) void {
        if (self.data) |*data| data.deinit();
        self.data = null;
    }

    pub fn offsetForAbbrev(self: Zone, abbrev: []const u8) ?i32 {
        if (isUniversal(abbrev)) return 0;

        const data = self.data orelse return null;

        for (data.timetypes) |timetype| {
            if (std.mem.eql(u8, timetype.name(), abbrev)) return timetype.offset;
        }

        return null;
    }

    pub fn offsetAt(self: Zone, seconds: i64) i32 {
        const data = self.data orelse {
            const posix = self.posix orelse return 0;
            return posixOffsetAt(posix, seconds);
        };

        var offset: i32 = 0;
        for (data.timetypes) |timetype| {
            if (!timetype.isDst()) {
                offset = timetype.offset;
                break;
            }
        } else if (data.timetypes.len > 0) {
            offset = data.timetypes[0].offset;
        }

        for (data.transitions) |transition| {
            if (transition.ts > seconds) break;
            offset = transition.timetype.offset;
        }

        if (data.transitions.len > 0 and
            seconds >= data.transitions[data.transitions.len - 1].ts)
        {
            if (self.posix) |posix| return posixOffsetAt(posix, seconds);
        }

        return offset;
    }
};

pub fn isUniversal(abbrev: []const u8) bool {
    for ([_][]const u8{ "UTC", "UCT", "GMT", "UT", "Z", "ZULU" }) |name| {
        if (std.ascii.eqlIgnoreCase(name, abbrev)) return true;
    }

    return false;
}

fn isPathSafe(name: []const u8) bool {
    if (std.mem.indexOf(u8, name, "..") != null) return false;

    for (name) |char| {
        switch (char) {
            'A'...'Z', 'a'...'z', '0'...'9', '/', '_', '-', '+' => {},
            else => return false,
        }
    }

    return true;
}

fn load(gpa: std.mem.Allocator, io: std.Io, path: []const u8) !Zone {
    const bytes = try std.Io.Dir.cwd().readFileAlloc(io, path, gpa, .limited(1 << 22));
    defer gpa.free(bytes);

    var reader = std.Io.Reader.fixed(bytes);
    const data = try std.tz.Tz.parse(gpa, &reader);

    return .{
        .data = data,
        .posix = if (data.footer) |footer| parsePosix(footer) else null,
    };
}

const Cursor = struct {
    text: []const u8,
    index: usize = 0,

    fn atEnd(self: Cursor) bool {
        return self.index >= self.text.len;
    }

    fn peek(self: Cursor) ?u8 {
        if (self.atEnd()) return null;
        return self.text[self.index];
    }

    fn eat(self: *Cursor, char: u8) bool {
        if (self.peek() == char) {
            self.index += 1;
            return true;
        }
        return false;
    }

    fn number(self: *Cursor) ?i32 {
        const start = self.index;
        while (self.peek()) |char| {
            if (char < '0' or char > '9') break;
            self.index += 1;
        }

        if (self.index == start) return null;
        return std.fmt.parseInt(i32, self.text[start..self.index], 10) catch null;
    }

    fn name(self: *Cursor) bool {
        if (self.eat('<')) {
            while (self.peek()) |char| {
                self.index += 1;
                if (char == '>') return true;
            }
            return false;
        }

        const start = self.index;
        while (self.peek()) |char| {
            switch (char) {
                'A'...'Z', 'a'...'z' => self.index += 1,
                else => break,
            }
        }

        return self.index - start >= 3;
    }

    fn offset(self: *Cursor) ?i32 {
        var sign: i32 = 1;
        if (self.eat('-')) sign = -1 else _ = self.eat('+');

        const hours = self.number() orelse return null;
        var total = hours * 3600;

        if (self.eat(':')) {
            const minutes = self.number() orelse return null;
            total += minutes * 60;

            if (self.eat(':')) {
                const seconds = self.number() orelse return null;
                total += seconds;
            }
        }

        return -sign * total;
    }

    fn rule(self: *Cursor) ?Rule {
        var when: i32 = 2 * 3600;

        if (self.eat('M')) {
            const month = self.number() orelse return null;
            if (!self.eat('.')) return null;
            const week = self.number() orelse return null;
            if (!self.eat('.')) return null;
            const weekday = self.number() orelse return null;

            if (month < 1 or month > 12) return null;
            if (week < 1 or week > 5) return null;
            if (weekday < 0 or weekday > 6) return null;

            if (self.eat('/')) when = self.ruleTime() orelse return null;

            return .{ .month_week_day = .{
                .month = @intCast(month),
                .week = @intCast(week),
                .weekday = @intCast(weekday),
                .seconds = when,
            } };
        }

        if (self.eat('J')) {
            const day = self.number() orelse return null;
            if (day < 1 or day > 365) return null;
            if (self.eat('/')) when = self.ruleTime() orelse return null;
            return .{ .julian = .{ .day = @intCast(day), .seconds = when } };
        }

        const day = self.number() orelse return null;
        if (day < 0 or day > 365) return null;
        if (self.eat('/')) when = self.ruleTime() orelse return null;

        return .{ .ordinal = .{ .day = @intCast(day), .seconds = when } };
    }

    fn ruleTime(self: *Cursor) ?i32 {
        var sign: i32 = 1;
        if (self.eat('-')) sign = -1 else _ = self.eat('+');

        const hours = self.number() orelse return null;
        var total = hours * 3600;

        if (self.eat(':')) {
            const minutes = self.number() orelse return null;
            total += minutes * 60;

            if (self.eat(':')) {
                const seconds = self.number() orelse return null;
                total += seconds;
            }
        }

        return sign * total;
    }
};

pub fn parsePosix(text: []const u8) ?Posix {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return null;

    var cursor = Cursor{ .text = trimmed };

    if (!cursor.name()) return null;
    const std_offset = cursor.offset() orelse return null;

    var posix = Posix{ .std_offset = std_offset };

    if (cursor.atEnd()) return posix;
    if (!cursor.name()) return posix;

    posix.dst_offset = cursor.offset() orelse std_offset + 3600;

    if (!cursor.eat(',')) return posix;
    posix.start = cursor.rule() orelse return posix;

    if (!cursor.eat(',')) {
        posix.start = null;
        return posix;
    }

    posix.end = cursor.rule() orelse {
        posix.start = null;
        return posix;
    };

    return posix;
}

fn ruleFixedDay(rule: Rule, year: i64) i64 {
    switch (rule) {
        .month_week_day => |spec| {
            const first = sym454.gregorianToFixed(year, spec.month, 1);
            const first_weekday: i64 = sym454.fixedToWeekdayNum(first);
            const wanted: i64 = spec.weekday;
            const shift = @mod(wanted - first_weekday, 7);

            var day = first + shift + 7 * (@as(i64, spec.week) - 1);

            const next_month = sym454.gregorianToFixed(
                if (spec.month == 12) year + 1 else year,
                if (spec.month == 12) 1 else spec.month + 1,
                1,
            );
            while (day >= next_month) day -= 7;

            return day;
        },
        .julian => |spec| {
            var day = sym454.gregorianToFixed(year, 1, 1) + @as(i64, spec.day) - 1;
            if (spec.day >= 60 and sym454.isGregorianLeapYear(year)) day += 1;
            return day;
        },
        .ordinal => |spec| {
            return sym454.gregorianToFixed(year, 1, 1) + @as(i64, spec.day);
        },
    }
}

fn ruleInstant(rule: Rule, year: i64, offset: i32) i64 {
    const seconds = switch (rule) {
        .month_week_day => |spec| spec.seconds,
        .julian => |spec| spec.seconds,
        .ordinal => |spec| spec.seconds,
    };

    const days = ruleFixedDay(rule, year) - sym454.unix_epoch_fixed;

    return days * sym454.seconds_per_day + seconds - offset;
}

pub fn posixOffsetAt(posix: Posix, seconds: i64) i32 {
    const dst_offset = posix.dst_offset orelse return posix.std_offset;
    const start_rule = posix.start orelse return posix.std_offset;
    const end_rule = posix.end orelse return posix.std_offset;

    const year = sym454.fixedToGregorian(
        sym454.unixToFixed(seconds + posix.std_offset),
    ).year;

    const start = ruleInstant(start_rule, year, posix.std_offset);
    const end = ruleInstant(end_rule, year, dst_offset);

    if (start <= end) {
        if (seconds >= start and seconds < end) return dst_offset;
        return posix.std_offset;
    }

    if (seconds >= start or seconds < end) return dst_offset;
    return posix.std_offset;
}

const testing = std.testing;

test "utc zone has no offset" {
    var zone = Zone.utc();
    defer zone.deinit();

    try testing.expectEqual(0, zone.offsetAt(0));
    try testing.expectEqual(0, zone.offsetAt(1788110945));
}

test "rejects traversal in zone names" {
    try testing.expect(isPathSafe("America/New_York"));
    try testing.expect(isPathSafe("Etc/GMT+5"));
    try testing.expect(!isPathSafe("../../etc/shadow"));
    try testing.expect(!isPathSafe("Europe/Berlin\x00"));
}

test "parses a northern hemisphere rule" {
    const posix = parsePosix("CST6CDT,M3.2.0,M11.1.0").?;

    try testing.expectEqual(-6 * 3600, posix.std_offset);
    try testing.expectEqual(-5 * 3600, posix.dst_offset.?);
    try testing.expectEqual(3, posix.start.?.month_week_day.month);
    try testing.expectEqual(2, posix.start.?.month_week_day.week);
    try testing.expectEqual(0, posix.start.?.month_week_day.weekday);
    try testing.expectEqual(2 * 3600, posix.start.?.month_week_day.seconds);
    try testing.expectEqual(11, posix.end.?.month_week_day.month);
    try testing.expectEqual(1, posix.end.?.month_week_day.week);
}

test "parses offsets with minutes and quoted names" {
    const india = parsePosix("<+0530>-5:30").?;
    try testing.expectEqual(5 * 3600 + 30 * 60, india.std_offset);
    try testing.expectEqual(null, india.dst_offset);

    const nepal = parsePosix("<+0545>-5:45").?;
    try testing.expectEqual(5 * 3600 + 45 * 60, nepal.std_offset);

    const utc_zone = parsePosix("UTC0").?;
    try testing.expectEqual(0, utc_zone.std_offset);
}

test "parses a southern hemisphere rule" {
    const posix = parsePosix("AEST-10AEDT,M10.1.0,M4.1.0/3").?;

    try testing.expectEqual(10 * 3600, posix.std_offset);
    try testing.expectEqual(11 * 3600, posix.dst_offset.?);
    try testing.expectEqual(3 * 3600, posix.end.?.month_week_day.seconds);
}

test "applies a northern hemisphere rule" {
    const posix = parsePosix("CST6CDT,M3.2.0,M11.1.0").?;

    try testing.expectEqual(-6 * 3600, posixOffsetAt(posix, 1770000000));
    try testing.expectEqual(-5 * 3600, posixOffsetAt(posix, 1788110945));
    try testing.expectEqual(-6 * 3600, posixOffsetAt(posix, 16726478400));
    try testing.expectEqual(-5 * 3600, posixOffsetAt(posix, 16744449600));
    try testing.expectEqual(-5 * 3600, posixOffsetAt(posix, 18725083200));
    try testing.expectEqual(-6 * 3600, posixOffsetAt(posix, 16756200000));
}

test "applies a southern hemisphere rule across the new year" {
    const posix = parsePosix("AEST-10AEDT,M10.1.0,M4.1.0/3").?;

    try testing.expectEqual(11 * 3600, posixOffsetAt(posix, 1767225600));
    try testing.expectEqual(10 * 3600, posixOffsetAt(posix, 1751328000));
}

test "julian rules skip the leap day" {
    const skipping = Rule{ .julian = .{ .day = 60, .seconds = 0 } };
    const counting = Rule{ .ordinal = .{ .day = 59, .seconds = 0 } };

    try testing.expectEqual(
        sym454.gregorianToFixed(2024, 3, 1),
        ruleFixedDay(skipping, 2024),
    );
    try testing.expectEqual(
        sym454.gregorianToFixed(2023, 3, 1),
        ruleFixedDay(skipping, 2023),
    );
    try testing.expectEqual(
        sym454.gregorianToFixed(2024, 2, 29),
        ruleFixedDay(counting, 2024),
    );
}

test "week five means the last such weekday" {
    const last_sunday = Rule{
        .month_week_day = .{ .month = 3, .week = 5, .weekday = 0, .seconds = 0 },
    };

    try testing.expectEqual(
        sym454.gregorianToFixed(2026, 3, 29),
        ruleFixedDay(last_sunday, 2026),
    );
    try testing.expectEqual(
        sym454.gregorianToFixed(2025, 3, 30),
        ruleFixedDay(last_sunday, 2025),
    );
}

test "resolves universal zone names" {
    var zone = Zone.utc();
    defer zone.deinit();

    try testing.expectEqual(0, zone.offsetForAbbrev("UTC").?);
    try testing.expectEqual(0, zone.offsetForAbbrev("GMT").?);
    try testing.expectEqual(0, zone.offsetForAbbrev("Z").?);
    try testing.expectEqual(null, zone.offsetForAbbrev("CDT"));
    try testing.expect(!isUniversal("CDT"));
}

test "rejects malformed rules" {
    try testing.expectEqual(null, parsePosix(""));
    try testing.expectEqual(null, parsePosix("XY5"));
    try testing.expectEqual(null, parsePosix("CST"));
    try testing.expectEqual(null, parsePosix("12345"));
}
