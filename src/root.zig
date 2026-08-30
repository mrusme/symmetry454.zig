const std = @import("std");
const symmetry454 = @This();

pub const gregorian_epoch: i64 = 1;
pub const sym_epoch: i64 = gregorian_epoch;

pub const days_in_common_year: i64 = 364;
pub const days_in_leap_year: i64 = 371;
pub const weeks_in_common_year: i64 = 52;
pub const weeks_in_leap_year: i64 = 53;

fn mod(x: i64, y: i64) i64 {
    return @mod(x, y);
}

fn divFloor(x: i64, y: i64) i64 {
    return @divFloor(x, y);
}

fn divCeil(x: i64, y: i64) i64 {
    return -@divFloor(-x, y);
}

pub const LeapCycle = struct {
    years: i64,
    leaps: i64,

    pub const northward_equinox: LeapCycle = .{ .years = 293, .leaps = 52 };
    pub const saros: LeapCycle = .{ .years = 1803, .leaps = 320 };
    pub const north_solstice: LeapCycle = .{ .years = 389, .leaps = 69 };

    pub fn shift(cycle: LeapCycle) i64 {
        return divFloor(cycle.years - 1, 2);
    }

    pub fn daysPerCycle(cycle: LeapCycle) i64 {
        return cycle.years * days_in_common_year + cycle.leaps * 7;
    }

    pub fn isLeapYear(cycle: LeapCycle, year: i64) bool {
        return mod(cycle.leaps * year + cycle.shift(), cycle.years) < cycle.leaps;
    }

    pub fn newYearDay(cycle: LeapCycle, year: i64) i64 {
        const elapsed = year - 1;
        const leaps = divFloor(cycle.leaps * elapsed + cycle.shift(), cycle.years);
        return sym_epoch + days_in_common_year * elapsed + 7 * leaps;
    }

    pub fn yearContaining(cycle: LeapCycle, fixed: i64) YearStart {
        var year = divCeil((fixed - sym_epoch) * cycle.years, cycle.daysPerCycle());
        var start = cycle.newYearDay(year);

        if (start < fixed) {
            if (fixed - start >= days_in_common_year) {
                const next = cycle.newYearDay(year + 1);
                if (fixed >= next) {
                    year += 1;
                    start = next;
                }
            }
        } else if (start > fixed) {
            year -= 1;
            start = cycle.newYearDay(year);
        }

        return .{ .year = year, .start = start };
    }
};

pub const YearStart = struct {
    year: i64,
    start: i64,
};

pub const default_cycle = LeapCycle.northward_equinox;

pub const LeapWeek = enum {
    december,
    irvember,
};

pub const irvember: u8 = 13;

pub fn isGregorianLeapYear(year: i64) bool {
    if (mod(year, 4) != 0) return false;
    if (mod(year, 100) != 0) return true;
    return mod(year, 400) == 0;
}

pub fn priorElapsedDays(year: i64) i64 {
    const prior = year - 1;
    return gregorian_epoch + prior * 365 +
        divFloor(prior, 4) -
        divFloor(prior, 100) +
        divFloor(prior, 400) - 1;
}

pub fn gregorianOrdinalDay(year: i64, month: u8, day: u8) i64 {
    const m: i64 = month;
    var ordinal = divFloor(367 * m - 362, 12) + @as(i64, day);

    if (month > 2) {
        ordinal -= if (isGregorianLeapYear(year)) 1 else 2;
    }

    return ordinal;
}

pub fn gregorianToFixed(year: i64, month: u8, day: u8) i64 {
    return priorElapsedDays(year) + gregorianOrdinalDay(year, month, day);
}

pub const Gregorian = struct {
    year: i64,
    month: u8,
    day: u8,

    pub fn fixed(self: Gregorian) i64 {
        return gregorianToFixed(self.year, self.month, self.day);
    }

    pub fn format(self: Gregorian, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.year < 0) try writer.writeByte('-');
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{
            @abs(self.year),
            self.month,
            self.day,
        });
    }
};

pub fn fixedToGregorian(fixed: i64) Gregorian {
    const d0 = fixed - gregorian_epoch;
    const n400 = divFloor(d0, 146097);
    const d1 = mod(d0, 146097);
    const n100 = divFloor(d1, 36524);
    const d2 = mod(d1, 36524);
    const n4 = divFloor(d2, 1461);
    const d3 = mod(d2, 1461);
    const n1 = divFloor(d3, 365);

    var year = 400 * n400 + 100 * n100 + 4 * n4 + n1;
    if (n100 != 4 and n1 != 4) year += 1;

    const prior_days = fixed - gregorianToFixed(year, 1, 1);

    const correction: i64 = if (fixed < gregorianToFixed(year, 3, 1))
        0
    else if (isGregorianLeapYear(year))
        1
    else
        2;

    const month = divFloor(12 * (prior_days + correction) + 373, 367);
    const day = fixed - gregorianToFixed(year, @intCast(month), 1) + 1;

    return .{
        .year = year,
        .month = @intCast(month),
        .day = @intCast(day),
    };
}

pub fn isLeapYear(year: i64) bool {
    return default_cycle.isLeapYear(year);
}

pub fn newYearDay(year: i64) i64 {
    return default_cycle.newYearDay(year);
}

pub fn daysInYear(year: i64) i64 {
    return if (isLeapYear(year)) days_in_leap_year else days_in_common_year;
}

pub fn weeksInYear(year: i64) i64 {
    return @divExact(daysInYear(year), 7);
}

pub fn daysBeforeMonth(month: u8) i64 {
    const m: i64 = month;
    return 28 * (m - 1) + 7 * divFloor(m, 3);
}

pub fn dayOfYear(month: u8, day: u8) i64 {
    return daysBeforeMonth(month) + @as(i64, day);
}

pub fn daysInMonthMode(mode: LeapWeek, year: i64, month: u8) i64 {
    if (month == irvember) {
        if (mode == .december) return 0;
        return if (isLeapYear(year)) 7 else 0;
    }

    const m: i64 = month;
    var days = 28 + 7 * divFloor(mod(m, 3), 2);

    if (mode == .december and month == 12 and isLeapYear(year)) days += 7;

    return days;
}

pub fn daysInMonth(year: i64, month: u8) i64 {
    return daysInMonthMode(.december, year, month);
}

pub fn symToFixed(year: i64, month: u8, day: u8) i64 {
    return newYearDay(year) + dayOfYear(month, day) - 1;
}

pub fn fixedToSymYear(fixed: i64) YearStart {
    return default_cycle.yearContaining(fixed);
}

pub fn fixedToSymMode(mode: LeapWeek, fixed: i64) Sym {
    const found = fixedToSymYear(fixed);
    const day_of_year = fixed - found.start + 1;
    const week_of_year = divCeil(day_of_year, 7);
    const quarter = divCeil(4 * week_of_year, 53);
    const day_of_quarter = day_of_year - 91 * (quarter - 1);
    const week_of_quarter = divCeil(day_of_quarter, 7);

    var month_of_quarter = divCeil(2 * week_of_quarter, 9);
    if (mode == .december and month_of_quarter > 3) month_of_quarter = 3;

    const month: u8 = @intCast(3 * quarter + month_of_quarter - 3);

    return .{
        .year = found.year,
        .month = month,
        .day = @intCast(day_of_year - daysBeforeMonth(month)),
    };
}

pub fn fixedToSym(fixed: i64) Sym {
    return fixedToSymMode(.december, fixed);
}

pub const weekday_adjust: i64 = mod(sym_epoch - 1, 7);

pub fn fixedToWeekdayNum(fixed: i64) u3 {
    return @intCast(mod(fixed - weekday_adjust, 7));
}

pub const Weekday = enum(u3) {
    sunday = 0,
    monday,
    tuesday,
    wednesday,
    thursday,
    friday,
    saturday,

    pub fn name(self: Weekday) []const u8 {
        return switch (self) {
            .sunday => "Sunday",
            .monday => "Monday",
            .tuesday => "Tuesday",
            .wednesday => "Wednesday",
            .thursday => "Thursday",
            .friday => "Friday",
            .saturday => "Saturday",
        };
    }

    pub fn format(self: Weekday, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        try writer.writeAll(self.name());
    }
};

pub fn fixedToWeekday(fixed: i64) Weekday {
    return @enumFromInt(fixedToWeekdayNum(fixed));
}

pub fn monthName(month: u8) []const u8 {
    return switch (month) {
        1 => "January",
        2 => "February",
        3 => "March",
        4 => "April",
        5 => "May",
        6 => "June",
        7 => "July",
        8 => "August",
        9 => "September",
        10 => "October",
        11 => "November",
        12 => "December",
        irvember => "Irvember",
        else => "",
    };
}

pub const Sym = struct {
    year: i64,
    month: u8,
    day: u8,

    pub fn fromFixed(fixed_date: i64) Sym {
        return fixedToSym(fixed_date);
    }

    pub fn fromUnix(seconds: i64) Sym {
        return fixedToSym(unixToFixed(seconds));
    }

    pub fn fromGregorian(date: Gregorian) Sym {
        return fixedToSym(date.fixed());
    }

    pub fn fixed(self: Sym) i64 {
        return symToFixed(self.year, self.month, self.day);
    }

    pub fn gregorian(self: Sym) Gregorian {
        return fixedToGregorian(self.fixed());
    }

    pub fn unix(self: Sym) i64 {
        return fixedToUnix(self.fixed());
    }

    pub fn startOfYear(self: Sym) i64 {
        return newYearDay(self.year);
    }

    pub fn isLeap(self: Sym) bool {
        return isLeapYear(self.year);
    }

    pub fn weekday(self: Sym) Weekday {
        return fixedToWeekday(self.fixed());
    }

    pub fn monthName(self: Sym) []const u8 {
        return symmetry454.monthName(self.month);
    }

    pub fn dayOfYear(self: Sym) i64 {
        return symmetry454.dayOfYear(self.month, self.day);
    }

    pub fn weekOfYear(self: Sym) i64 {
        return divCeil(self.dayOfYear(), 7);
    }

    pub fn quarter(self: Sym) i64 {
        return divCeil(4 * self.weekOfYear(), 53);
    }

    pub fn dayOfQuarter(self: Sym) i64 {
        return self.dayOfYear() - 91 * (self.quarter() - 1);
    }

    pub fn weekOfQuarter(self: Sym) i64 {
        return divCeil(self.dayOfQuarter(), 7);
    }

    pub fn monthOfQuarter(self: Sym) i64 {
        const value = divCeil(2 * self.weekOfQuarter(), 9);
        return if (value > 3) 3 else value;
    }

    pub fn weekOfMonth(self: Sym) i64 {
        return divCeil(self.day, 7);
    }

    pub fn daysInMonth(self: Sym) i64 {
        return symmetry454.daysInMonth(self.year, self.month);
    }

    pub fn weeksInMonth(self: Sym) i64 {
        return @divExact(self.daysInMonth(), 7);
    }

    pub fn daysInYear(self: Sym) i64 {
        return symmetry454.daysInYear(self.year);
    }

    pub fn weeksInYear(self: Sym) i64 {
        return symmetry454.weeksInYear(self.year);
    }

    pub fn validMode(self: Sym, mode: LeapWeek) bool {
        const last: u8 = if (mode == .december) 12 else irvember;
        if (self.month < 1 or self.month > last) return false;
        return self.day >= 1 and
            self.day <= daysInMonthMode(mode, self.year, self.month);
    }

    pub fn valid(self: Sym) bool {
        return self.validMode(.december);
    }

    pub fn format(self: Sym, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        if (self.year < 0) try writer.writeByte('-');
        try writer.print("{d:0>4}-{d:0>2}-{d:0>2}", .{
            @abs(self.year),
            self.month,
            self.day,
        });
    }
};

pub const unix_epoch_fixed: i64 = 719163;
pub const seconds_per_day: i64 = 86400;

pub fn unixToFixed(seconds: i64) i64 {
    return unix_epoch_fixed + divFloor(seconds, seconds_per_day);
}

pub fn fixedToUnix(fixed: i64) i64 {
    return (fixed - unix_epoch_fixed) * seconds_per_day;
}

const testing = std.testing;

const VerificationRow = struct {
    greg_year: i64,
    greg_month: u8,
    greg_day: u8,
    fixed: i64,
    weekday_num: u3,
    sym_year: i64,
    sym_month: u8,
    sym_day: u8,
};

const verification_table = [_]VerificationRow{
    .{ .greg_year = -121, .greg_month = 4, .greg_day = 26, .fixed = -44444, .weekday_num = 6, .sym_year = -121, .sym_month = 4, .sym_day = 27 },
    .{ .greg_year = -91, .greg_month = 9, .greg_day = 27, .fixed = -33333, .weekday_num = 1, .sym_year = -91, .sym_month = 9, .sym_day = 22 },
    .{ .greg_year = 122, .greg_month = 9, .greg_day = 7, .fixed = 44444, .weekday_num = 1, .sym_year = 122, .sym_month = 9, .sym_day = 8 },
    .{ .greg_year = 1776, .greg_month = 7, .greg_day = 4, .fixed = 648491, .weekday_num = 4, .sym_year = 1776, .sym_month = 7, .sym_day = 4 },
    .{ .greg_year = 1867, .greg_month = 7, .greg_day = 1, .fixed = 681724, .weekday_num = 1, .sym_year = 1867, .sym_month = 7, .sym_day = 1 },
    .{ .greg_year = 1947, .greg_month = 10, .greg_day = 24, .fixed = 711058, .weekday_num = 5, .sym_year = 1947, .sym_month = 10, .sym_day = 26 },
    .{ .greg_year = 1995, .greg_month = 8, .greg_day = 10, .fixed = 728515, .weekday_num = 4, .sym_year = 1995, .sym_month = 8, .sym_day = 11 },
    .{ .greg_year = 2000, .greg_month = 2, .greg_day = 29, .fixed = 730179, .weekday_num = 2, .sym_year = 2000, .sym_month = 2, .sym_day = 30 },
    .{ .greg_year = 2004, .greg_month = 5, .greg_day = 2, .fixed = 731703, .weekday_num = 0, .sym_year = 2004, .sym_month = 5, .sym_day = 7 },
    .{ .greg_year = 2004, .greg_month = 12, .greg_day = 31, .fixed = 731946, .weekday_num = 5, .sym_year = 2004, .sym_month = 12, .sym_day = 33 },
    .{ .greg_year = 2020, .greg_month = 2, .greg_day = 20, .fixed = 737475, .weekday_num = 4, .sym_year = 2020, .sym_month = 2, .sym_day = 25 },
    .{ .greg_year = 2222, .greg_month = 2, .greg_day = 2, .fixed = 811236, .weekday_num = 6, .sym_year = 2222, .sym_month = 2, .sym_day = 6 },
    .{ .greg_year = 3333, .greg_month = 3, .greg_day = 1, .fixed = 1217048, .weekday_num = 0, .sym_year = 3333, .sym_month = 2, .sym_day = 35 },
};

test "official verification table" {
    for (verification_table) |row| {
        try testing.expectEqual(
            row.fixed,
            gregorianToFixed(row.greg_year, row.greg_month, row.greg_day),
        );

        const greg = fixedToGregorian(row.fixed);
        try testing.expectEqual(row.greg_year, greg.year);
        try testing.expectEqual(row.greg_month, greg.month);
        try testing.expectEqual(row.greg_day, greg.day);

        try testing.expectEqual(
            row.fixed,
            symToFixed(row.sym_year, row.sym_month, row.sym_day),
        );

        const sym = fixedToSym(row.fixed);
        try testing.expectEqual(row.sym_year, sym.year);
        try testing.expectEqual(row.sym_month, sym.month);
        try testing.expectEqual(row.sym_day, sym.day);

        try testing.expectEqual(row.weekday_num, fixedToWeekdayNum(row.fixed));
    }
}

test "prior elapsed days" {
    try testing.expectEqual(733407, priorElapsedDays(2009));
}

test "gregorian leap years" {
    for ([_]i64{ 2000, 2004, 1996, -4, 400, -400 }) |year| {
        try testing.expect(isGregorianLeapYear(year));
    }

    for ([_]i64{ 1900, 2001, 2100, -1, -100, 300 }) |year| {
        try testing.expect(!isGregorianLeapYear(year));
    }
}

test "gregorian ordinal day" {
    try testing.expectEqual(196, gregorianOrdinalDay(2012, 7, 14));
    try testing.expectEqual(195, gregorianOrdinalDay(2011, 7, 14));
}

test "gregorian round trip" {
    var fixed: i64 = -400000;
    while (fixed <= 1300000) : (fixed += 1) {
        const greg = fixedToGregorian(fixed);
        try testing.expectEqual(fixed, greg.fixed());
    }
}

test "sym leap years" {
    try testing.expect(isLeapYear(2009));
    try testing.expect(!isLeapYear(2010));
    try testing.expect(isLeapYear(2015));
    try testing.expect(isLeapYear(2021));
    try testing.expect(isLeapYear(2026));

    const common = [_]i64{
        2005, 2006, 2010, 2012, 2016, 2017, 2018,
        2019, 2020, 2022, 2023, 2024, 2025,
    };

    for (common) |year| {
        try testing.expect(!isLeapYear(year));
    }
}

test "sym leap years before the epoch" {
    for ([_]i64{ -2, -8, -14, -19, -25, -30, -36 }) |year| {
        try testing.expect(isLeapYear(year));
    }

    for ([_]i64{ -1, -3, -4, -5, -6, -7, -9, -13, -15 }) |year| {
        try testing.expect(!isLeapYear(year));
    }
}

test "every 293 year cycle holds 52 leap years" {
    for ([_]i64{ 1, 294, -292, -1000, -5000 }) |start| {
        var count: i64 = 0;
        var year = start;
        while (year < start + 293) : (year += 1) {
            if (isLeapYear(year)) count += 1;
        }
        try testing.expectEqual(52, count);
    }
}

test "published leap cycles" {
    try testing.expect(LeapCycle.northward_equinox.isLeapYear(2009));
    try testing.expect(!LeapCycle.north_solstice.isLeapYear(2009));
    try testing.expect(LeapCycle.north_solstice.isLeapYear(2010));
    try testing.expectEqual(146, LeapCycle.northward_equinox.shift());
    try testing.expectEqual(901, LeapCycle.saros.shift());
    try testing.expectEqual(194, LeapCycle.north_solstice.shift());
    try testing.expectEqual(107016, LeapCycle.northward_equinox.daysPerCycle());
}

test "new year day" {
    try testing.expectEqual(733405, newYearDay(2009));
    try testing.expectEqual(733776, newYearDay(2010));
}

test "new year day always falls on a Monday" {
    var year: i64 = -3000;
    while (year <= 4000) : (year += 1) {
        try testing.expectEqual(Weekday.monday, fixedToWeekday(newYearDay(year)));
    }
}

test "year lengths" {
    var year: i64 = -3000;
    while (year <= 4000) : (year += 1) {
        const want: i64 = if (isLeapYear(year)) 371 else 364;
        try testing.expectEqual(want, newYearDay(year + 1) - newYearDay(year));
        try testing.expectEqual(want, daysInYear(year));
        try testing.expectEqual(@divExact(want, 7), weeksInYear(year));
    }
}

test "days before month" {
    const want = [_]i64{ 0, 28, 63, 91, 119, 154, 182, 210, 245, 273, 301, 336 };
    for (want, 1..) |days, month| {
        try testing.expectEqual(days, daysBeforeMonth(@intCast(month)));
    }
    try testing.expectEqual(364, daysBeforeMonth(irvember));
}

test "day of year" {
    try testing.expectEqual(171, dayOfYear(6, 17));
}

test "days in month" {
    const want = [_]i64{ 28, 35, 28, 28, 35, 28, 28, 35, 28, 28, 35, 28 };
    for (want, 1..) |days, month| {
        try testing.expectEqual(days, daysInMonth(2010, @intCast(month)));
    }

    try testing.expectEqual(35, daysInMonth(2009, 12));
    try testing.expectEqual(28, daysInMonth(2010, 12));
}

test "sym to fixed" {
    try testing.expectEqual(-44444, symToFixed(-121, 4, 27));
    try testing.expectEqual(648491, symToFixed(1776, 7, 4));
    try testing.expectEqual(733500, symToFixed(2009, 4, 5));
    try testing.expectEqual(1217048, symToFixed(3333, 2, 35));
}

test "fixed to sym year" {
    try testing.expectEqual(2009, fixedToSymYear(733774).year);
    try testing.expectEqual(2009, fixedToSymYear(733406).year);

    const found = fixedToSymYear(733649);
    try testing.expectEqual(2009, found.year);
    try testing.expectEqual(733405, found.start);
}

test "fixed to sym year brackets every fixed day" {
    var fixed: i64 = -400000;
    while (fixed <= 1300000) : (fixed += 1) {
        const found = fixedToSymYear(fixed);
        try testing.expectEqual(newYearDay(found.year), found.start);
        try testing.expect(fixed >= found.start);
        try testing.expect(fixed < newYearDay(found.year + 1));
    }
}

test "fixed to sym stays inside the calendar" {
    var fixed: i64 = -400000;
    while (fixed <= 1300000) : (fixed += 1) {
        const sym = fixedToSym(fixed);
        try testing.expect(sym.valid());
        try testing.expectEqual(fixed, sym.fixed());
    }
}

test "sym to fixed round trip" {
    var year: i64 = -1200;
    while (year <= 3600) : (year += 1) {
        var month: u8 = 1;
        while (month <= 12) : (month += 1) {
            var day: u8 = 1;
            while (day <= daysInMonth(year, month)) : (day += 1) {
                const sym = Sym{ .year = year, .month = month, .day = day };
                try testing.expectEqual(sym, fixedToSym(sym.fixed()));
            }
        }
    }
}

test "leap week belongs to December" {
    const year: i64 = 2026;
    try testing.expect(isLeapYear(year));
    try testing.expectEqual(35, daysInMonth(year, 12));
    try testing.expectEqual(28, daysInMonth(2025, 12));

    const last = Sym{ .year = year, .month = 12, .day = 28 };
    try testing.expectEqual(364, last.dayOfYear());
    try testing.expectEqual(Weekday.sunday, last.weekday());

    var offset: i64 = 1;
    while (offset <= 7) : (offset += 1) {
        const sym = fixedToSym(last.fixed() + offset);
        try testing.expectEqual(year, sym.year);
        try testing.expectEqual(12, sym.month);
        try testing.expectEqual(@as(u8, @intCast(28 + offset)), sym.day);
        try testing.expectEqual(53, sym.weekOfYear());
        try testing.expectEqual(4, sym.quarter());
    }

    const next = fixedToSym(last.fixed() + 8);
    try testing.expectEqual(year + 1, next.year);
    try testing.expectEqual(1, next.month);
    try testing.expectEqual(1, next.day);
    try testing.expectEqual(Weekday.monday, next.weekday());
}

test "leap week as a stand-alone Irvember" {
    const year: i64 = 2026;
    try testing.expectEqual(7, daysInMonthMode(.irvember, year, irvember));
    try testing.expectEqual(0, daysInMonthMode(.irvember, 2025, irvember));
    try testing.expectEqual(28, daysInMonthMode(.irvember, year, 12));

    const last = Sym{ .year = year, .month = 12, .day = 28 };
    var offset: i64 = 1;
    while (offset <= 7) : (offset += 1) {
        const sym = fixedToSymMode(.irvember, last.fixed() + offset);
        try testing.expectEqual(year, sym.year);
        try testing.expectEqual(irvember, sym.month);
        try testing.expectEqual(@as(u8, @intCast(offset)), sym.day);
        try testing.expectEqual(last.fixed() + offset, sym.fixed());
        try testing.expect(sym.validMode(.irvember));
        try testing.expect(!sym.valid());
    }

    try testing.expectEqual(
        Sym{ .year = 2004, .month = irvember, .day = 5 },
        fixedToSymMode(.irvember, 731946),
    );
}

test "weekday numbering follows the specification" {
    try testing.expectEqual(0, weekday_adjust);
    try testing.expectEqual(5, fixedToWeekdayNum(1461));
    try testing.expectEqual(Weekday.monday, fixedToWeekday(sym_epoch));

    var fixed: i64 = -400000;
    while (fixed <= 1300000) : (fixed += 1) {
        const num = fixedToWeekdayNum(fixed);
        try testing.expectEqual(num, @intFromEnum(fixedToWeekday(fixed)));
    }
}

test "every month starts on a Monday" {
    var year: i64 = 1800;
    while (year <= 2200) : (year += 1) {
        var month: u8 = 1;
        while (month <= 12) : (month += 1) {
            const sym = Sym{ .year = year, .month = month, .day = 1 };
            try testing.expectEqual(Weekday.monday, sym.weekday());
        }
    }
}

test "derived calendar fields" {
    const sym = Sym{ .year = 2026, .month = 8, .day = 35 };

    try testing.expectEqual(245, sym.dayOfYear());
    try testing.expectEqual(35, sym.weekOfYear());
    try testing.expectEqual(3, sym.quarter());
    try testing.expectEqual(63, sym.dayOfQuarter());
    try testing.expectEqual(9, sym.weekOfQuarter());
    try testing.expectEqual(2, sym.monthOfQuarter());
    try testing.expectEqual(5, sym.weekOfMonth());
    try testing.expectEqual(35, sym.daysInMonth());
    try testing.expectEqual(5, sym.weeksInMonth());
    try testing.expectEqual(371, sym.daysInYear());
    try testing.expectEqual(53, sym.weeksInYear());
    try testing.expectEqual(newYearDay(2026), sym.startOfYear());
    try testing.expect(sym.isLeap());
    try testing.expectEqual(Weekday.sunday, sym.weekday());
    try testing.expectEqualStrings("August", sym.monthName());
}

test "quarters cover the whole year" {
    var year: i64 = 1990;
    while (year <= 2060) : (year += 1) {
        var day: i64 = 1;
        while (day <= daysInYear(year)) : (day += 1) {
            const sym = fixedToSym(newYearDay(year) + day - 1);
            const quarter = sym.quarter();
            try testing.expect(quarter >= 1 and quarter <= 4);
            try testing.expectEqual(quarter, divCeil(sym.month, 3));
            try testing.expect(sym.dayOfQuarter() >= 1);
            const rebuilt = 3 * quarter + sym.monthOfQuarter() - 3;
            try testing.expectEqual(sym.month, @as(u8, @intCast(rebuilt)));
        }
    }
}

test "validity" {
    try testing.expect((Sym{ .year = 2026, .month = 12, .day = 35 }).valid());
    try testing.expect(!(Sym{ .year = 2025, .month = 12, .day = 35 }).valid());
    try testing.expect(!(Sym{ .year = 2026, .month = 1, .day = 29 }).valid());
    try testing.expect((Sym{ .year = 2026, .month = 2, .day = 35 }).valid());
    try testing.expect(!(Sym{ .year = 2026, .month = 0, .day = 1 }).valid());
    try testing.expect(!(Sym{ .year = 2026, .month = 13, .day = 1 }).valid());
    try testing.expect(!(Sym{ .year = 2026, .month = 1, .day = 0 }).valid());
}

test "unix seconds" {
    try testing.expectEqual(719163, unixToFixed(0));
    try testing.expectEqual(719163, unixToFixed(86399));
    try testing.expectEqual(719162, unixToFixed(-1));
    try testing.expectEqual(0, fixedToUnix(719163));

    const sym = Sym.fromUnix(0);
    try testing.expectEqual(1970, sym.year);
    try testing.expectEqual(1, sym.month);
    try testing.expectEqual(4, sym.day);

    const greg = fixedToGregorian(unixToFixed(0));
    try testing.expectEqual(1970, greg.year);
    try testing.expectEqual(1, greg.month);
    try testing.expectEqual(1, greg.day);
}

test "conversion helpers" {
    const sym = Sym.fromGregorian(.{ .year = 2004, .month = 12, .day = 31 });
    try testing.expectEqual(Sym{ .year = 2004, .month = 12, .day = 33 }, sym);

    const greg = sym.gregorian();
    try testing.expectEqual(2004, greg.year);
    try testing.expectEqual(12, greg.month);
    try testing.expectEqual(31, greg.day);

    try testing.expectEqual(sym, Sym.fromFixed(731946));
}

test "formatting" {
    var buf: [64]u8 = undefined;

    try testing.expectEqualStrings(
        "2026-08-35",
        try std.fmt.bufPrint(&buf, "{f}", .{Sym{ .year = 2026, .month = 8, .day = 35 }}),
    );

    try testing.expectEqualStrings(
        "-0099-01-01",
        try std.fmt.bufPrint(&buf, "{f}", .{Sym{ .year = -99, .month = 1, .day = 1 }}),
    );

    try testing.expectEqualStrings(
        "0122-09-08",
        try std.fmt.bufPrint(&buf, "{f}", .{Sym{ .year = 122, .month = 9, .day = 8 }}),
    );

    try testing.expectEqualStrings(
        "2004-12-31",
        try std.fmt.bufPrint(&buf, "{f}", .{Gregorian{ .year = 2004, .month = 12, .day = 31 }}),
    );

    try testing.expectEqualStrings(
        "Sunday",
        try std.fmt.bufPrint(&buf, "{f}", .{Weekday.sunday}),
    );
}

test "month names" {
    try testing.expectEqualStrings("January", monthName(1));
    try testing.expectEqualStrings("December", monthName(12));
    try testing.expectEqualStrings("Irvember", monthName(irvember));
    try testing.expectEqualStrings("", monthName(0));
    try testing.expectEqualStrings("", monthName(14));
}
