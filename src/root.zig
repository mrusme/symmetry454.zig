const std = @import("std");

pub const S454Date = struct {
    year: i32,
    month: u8, // 1 to 12
    day: u8, // 1 to 28 or 35

    const Self = @This();

    pub fn isLeapYear(year: i32) bool {
        const dividend = 52 * year + 146;
        const remainder = @mod(dividend, 293);
        return remainder < 52;
    }

    pub fn daysInMonth(month: u8, is_leap: bool) u8 {
        return switch (month) {
            1, 3, 4, 6, 7, 9, 10, 12 => 28,
            2, 5, 8, 11 => 35,
            13 => if (is_leap) 7 else 0,
            else => 0,
        };
    }

    pub fn daysInYear(year: i32) u16 {
        return if (isLeapYear(year)) 371 else 364;
    }

    pub fn dayOfYear(self: Self) u16 {
        var total: u16 = 0;
        for (1..self.month) |m| {
            total += daysInMonth(@intCast(m), isLeapYear(self.year));
        }
        return total + self.day;
    }

    pub fn daysSinceEpoch(self: Self) i32 {
        var total_days: i32 = 0;
        var y: i32 = 2001;

        if (self.year >= y) {
            while (y < self.year) : (y += 1) {
                total_days += @as(i32, daysInYear(y));
            }
        } else {
            while (y > self.year) : (y -= 1) {
                total_days -= @as(i32, daysInYear(y - 1));
            }
        }

        total_days += @as(i32, self.dayOfYear()) - 1;
        return total_days;
    }

    pub fn fromDaysSinceEpoch(days: i32) Self {
        var y: i32 = 2001;
        var rem_days = days;

        while (true) {
            const year_days = @as(i32, daysInYear(y));
            if (rem_days < 0) {
                if (-rem_days < year_days) break;
                y -= 1;
                rem_days += @as(i32, daysInYear(y));
            } else if (rem_days >= year_days) {
                rem_days -= year_days;
                y += 1;
            } else break;
        }

        const leap = isLeapYear(y);
        var m: u8 = 1;
        while (true) {
            const mdays = daysInMonth(m, leap);
            if (rem_days < mdays) break;
            rem_days -= mdays;
            m += 1;
        }

        return Self{
            .year = y,
            .month = m,
            .day = @as(u8, @intCast(rem_days + 1)),
        };
    }

    // TODO: https://github.com/ziglang/zig/issues/8396
    // pub fn toGregorian(self: Self) std.time.TODO {
    //     const epoch_date =
    //         std.time.TODO.init(2001, .January, 1) catch unreachable;
    //     const total_days =
    //         self.daysSinceEpoch();
    //     return epoch_date.addDays(total_days) catch unreachable;
    // }
    //
    // pub fn fromGregorian(date: std.time.TODO) Self {
    //     const epoch_date =
    //         std.time.TODO.init(2001, .January, 1) catch unreachable;
    //     const delta =
    //         date.diff(epoch_date).days;
    //     return Self.fromDaysSinceEpoch(delta);
    // }

    pub fn format(self: Self, writer: anytype) !void {
        if (self.month == 13) {
            if (self.year >= 1) {
                try std.fmt.format(
                    writer,
                    "{}-LeapWeek-{}",
                    .{ self.year, self.day },
                );
            } else {
                try std.fmt.format(
                    writer,
                    "{} BCE-LeapWeek-{}",
                    .{ -self.year + 1, self.day },
                );
            }
        } else if (self.year >= 1) {
            try std.fmt.format(
                writer,
                "{}-{:0>2}-{:0>2}",
                .{ self.year, self.month, self.day },
            );
        } else {
            try std.fmt.format(
                writer,
                "{} BCE-{:0>2}-{:0>2}",
                .{ -self.year + 1, self.month, self.day },
            );
        }
    }

    pub const Weekday = enum(u3) {
        Monday = 0,
        Tuesday,
        Wednesday,
        Thursday,
        Friday,
        Saturday,
        Sunday,

        pub fn name(self: Weekday) []const u8 {
            return switch (self) {
                .Monday => "Monday",
                .Tuesday => "Tuesday",
                .Wednesday => "Wednesday",
                .Thursday => "Thursday",
                .Friday => "Friday",
                .Saturday => "Saturday",
                .Sunday => "Sunday",
            };
        }
    };

    pub fn weekday(self: Self) Weekday {
        // 0 = Monday for the epoch (2001-01-01)
        const days = self.daysSinceEpoch();
        // Handle negative days, too
        const idx: u3 = @intCast(@mod((7 + @mod(days, 7)), 7));
        return @enumFromInt(idx);
    }
};

test "leap year logic" {
    const expect = std.testing.expect;

    try expect(!S454Date.isLeapYear(2006));
    try expect(!S454Date.isLeapYear(2005));
    try expect(S454Date.isLeapYear(2009));
    try expect(!S454Date.isLeapYear(2010));
    try expect(!S454Date.isLeapYear(2012));
    try expect(S454Date.isLeapYear(2015));
    try expect(!S454Date.isLeapYear(2016));
    try expect(!S454Date.isLeapYear(2017));
    try expect(!S454Date.isLeapYear(2018));
    try expect(!S454Date.isLeapYear(2019));
    try expect(!S454Date.isLeapYear(2020));
    try expect(S454Date.isLeapYear(2021));
    try expect(!S454Date.isLeapYear(2022));
    try expect(!S454Date.isLeapYear(2023));
    try expect(!S454Date.isLeapYear(2024));
    try expect(!S454Date.isLeapYear(2025));
    try expect(S454Date.isLeapYear(2026));
}

test "leap year has 371 days; leap week is after month 12" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;

    const year = 2105; // leap year
    try expect(S454Date.isLeapYear(year));
    try expectEqual(371, S454Date.daysInYear(year));

    // Last day of month 12 should be day 364
    const last_regular = S454Date{ .year = year, .month = 12, .day = 28 };
    try expectEqual(364, last_regular.dayOfYear());
    try expectEqual(S454Date.Weekday.Sunday, last_regular.weekday());

    // Leap week days (365–371) exist, but aren't in any month per the 4-5-4
    // model. Let's manually construct daysSinceEpoch + 364..370 and reverse
    // them.
    for (0..7) |i| {
        const day_num =
            last_regular.daysSinceEpoch() + @as(i32, @intCast(i)) + 1;
        const day =
            S454Date.fromDaysSinceEpoch(day_num);
        try expectEqual(year, day.year);
        try expect(day.month >= 12); // stays within year
        try expect(day.day <= 35); // never exceeds max month day
    }

    // First day of next year should reset to day 1, weekday Monday
    const new_year = S454Date{ .year = year + 1, .month = 1, .day = 1 };
    try expectEqual(1, new_year.dayOfYear());
    try expectEqual(S454Date.Weekday.Monday, new_year.weekday());
}

test "non-leap year has 364 days; next year starts after 364" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;

    const year = 2101; // non-leap
    try expect(!S454Date.isLeapYear(year));
    try expectEqual(364, S454Date.daysInYear(year));

    const last_day = S454Date{ .year = year, .month = 12, .day = 28 };
    try expectEqual(364, last_day.dayOfYear());
    try expectEqual(S454Date.Weekday.Sunday, last_day.weekday());

    const first_next = S454Date{ .year = year + 1, .month = 1, .day = 1 };
    try expectEqual(S454Date.Weekday.Monday, first_next.weekday());
}

test "leap week is month 13" {
    const expect = std.testing.expect;
    const expectEqual = std.testing.expectEqual;
    const expectEqualStrings = std.testing.expectEqualStrings;
    const year = 2105;

    try expect(S454Date.isLeapYear(year));

    // 365th day (day 1 of leap week)
    const last_day = S454Date{ .year = year, .month = 12, .day = 28 };
    const day = S454Date.fromDaysSinceEpoch(last_day.daysSinceEpoch() + 1);

    try expectEqual(13, day.month);
    try expectEqual(1, day.day);

    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try day.format(fbs.writer());
    try expectEqualStrings("2105-LeapWeek-1", fbs.getWritten());
}

test "weekday consistency from epoch" {
    const expectEqual = std.testing.expectEqual;

    // Epoch: 2001-01-01 is Monday
    const base = S454Date{ .year = 2001, .month = 1, .day = 1 };
    try expectEqual(S454Date.Weekday.Monday, base.weekday());

    // 2001-01-02 is Tuesday
    const day2 = S454Date{ .year = 2001, .month = 1, .day = 2 };
    try expectEqual(S454Date.Weekday.Tuesday, day2.weekday());

    // One week later: should be Monday again
    const week_later = S454Date{ .year = 2001, .month = 1, .day = 8 };
    try expectEqual(S454Date.Weekday.Monday, week_later.weekday());

    // Leap year offset check: go to leap year 2021 and check the same weekday
    const same_weekday = S454Date{ .year = 2021, .month = 1, .day = 1 };
    try expectEqual(S454Date.Weekday.Monday, same_weekday.weekday());

    // Day after leap week in 2022: should still be consistent
    // (leap week is added at the end)
    const after_leap_year = S454Date{ .year = 2022, .month = 1, .day = 1 };
    try expectEqual(S454Date.Weekday.Monday, after_leap_year.weekday());
}

test "negative year and BCE formatting" {
    const expect = std.testing.expect;
    const expectEqualStrings = std.testing.expectEqualStrings;

    const bce = S454Date{ .year = -99, .month = 1, .day = 1 };
    try expect(S454Date.isLeapYear(-99) == false);

    var buf: [32]u8 = undefined;
    var fbs = std.io.fixedBufferStream(&buf);
    try bce.format(fbs.writer());
    try expectEqualStrings("100 BCE-01-01", fbs.getWritten());
}

