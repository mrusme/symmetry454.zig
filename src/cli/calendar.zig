const std = @import("std");
const sym454 = @import("symmetry454");

pub const inner_width = 22;
pub const box_width = inner_width + 2;
pub const max_week_rows = 5;

const weekday_header = " Mo Tu We Th Fr Sa Su ";
const gutter = " ";
const highlight_on = "\x1b[7m";
const highlight_off = "\x1b[0m";

pub const Style = struct {
    enabled: bool = false,
};

pub const Block = std.ArrayList([]const u8);

fn writeRepeated(writer: *std.Io.Writer, text: []const u8, count: usize) !void {
    var remaining = count;
    while (remaining > 0) : (remaining -= 1) try writer.writeAll(text);
}

fn displayWidth(text: []const u8) usize {
    var width: usize = 0;
    var index: usize = 0;

    while (index < text.len) {
        const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
        index += length;
        width += 1;
    }

    return width;
}

fn writeCentered(writer: *std.Io.Writer, text: []const u8, width: usize) !void {
    const measured = displayWidth(text);

    if (measured >= width) {
        var index: usize = 0;
        var emitted: usize = 0;
        while (index < text.len and emitted < width) : (emitted += 1) {
            const length = std.unicode.utf8ByteSequenceLength(text[index]) catch 1;
            try writer.writeAll(text[index .. index + length]);
            index += length;
        }
        return;
    }

    const left = (width - measured) / 2;
    try writer.splatByteAll(' ', left);
    try writer.writeAll(text);
    try writer.splatByteAll(' ', width - measured - left);
}

pub fn shiftMonth(year: i64, month: u8, offset: i64) struct { year: i64, month: u8 } {
    const index = year * 12 + @as(i64, month) - 1 + offset;

    return .{
        .year = @divFloor(index, 12),
        .month = @intCast(@mod(index, 12) + 1),
    };
}

fn monthTitle(
    writer: *std.Io.Writer,
    year: i64,
    month: u8,
    with_year: bool,
) !void {
    try writer.writeAll(sym454.monthName(month));
    if (with_year) try writer.print(" {d}", .{year});
}

pub fn renderMonth(
    arena: std.mem.Allocator,
    year: i64,
    month: u8,
    today: sym454.Sym,
    style: Style,
    with_year: bool,
    week_rows: usize,
) !Block {
    const days_in_month: usize = @intCast(sym454.daysInMonth(year, month));

    var block: Block = .empty;

    var line: std.Io.Writer.Allocating = .init(arena);
    const writer = &line.writer;

    try writer.writeAll("┌");
    try writeRepeated(writer, "─", inner_width);
    try writer.writeAll("┐");
    try block.append(arena, try line.toOwnedSlice());

    var title: std.Io.Writer.Allocating = .init(arena);
    try monthTitle(&title.writer, year, month, with_year);
    const title_text = try title.toOwnedSlice();

    try writer.writeAll("│");
    try writeCentered(writer, title_text, inner_width);
    try writer.writeAll("│");
    try block.append(arena, try line.toOwnedSlice());

    try writer.writeAll("├");
    try writeRepeated(writer, "─", inner_width);
    try writer.writeAll("┤");
    try block.append(arena, try line.toOwnedSlice());

    try writer.print("│{s}│", .{weekday_header});
    try block.append(arena, try line.toOwnedSlice());

    var day: usize = 1;
    while (day <= days_in_month) : (day += 7) {
        try writer.writeAll("│");

        var offset: usize = 0;
        while (offset < 7) : (offset += 1) {
            const number = day + offset;
            const marked = today.year == year and
                today.month == month and
                today.day == number;

            try writer.writeByte(' ');
            if (marked and style.enabled) try writer.writeAll(highlight_on);
            try writer.print("{d: >2}", .{number});
            if (marked and style.enabled) try writer.writeAll(highlight_off);
        }

        try writer.writeAll(" │");
        try block.append(arena, try line.toOwnedSlice());
    }

    var filled = days_in_month / 7;
    while (filled < week_rows) : (filled += 1) {
        try writer.writeAll("│");
        try writer.splatByteAll(' ', inner_width);
        try writer.writeAll("│");
        try block.append(arena, try line.toOwnedSlice());
    }

    try writer.writeAll("└");
    try writeRepeated(writer, "─", inner_width);
    try writer.writeAll("┘");
    try block.append(arena, try line.toOwnedSlice());

    return block;
}

pub fn joinBlocks(
    writer: *std.Io.Writer,
    arena: std.mem.Allocator,
    blocks: []const Block,
    per_row: usize,
) !void {
    const width = if (per_row < 1) 1 else per_row;

    var start: usize = 0;
    while (start < blocks.len) : (start += width) {
        const end = @min(start + width, blocks.len);

        var height: usize = 0;
        for (blocks[start..end]) |block| height = @max(height, block.items.len);

        var index: usize = 0;
        while (index < height) : (index += 1) {
            var line: std.Io.Writer.Allocating = .init(arena);
            defer line.deinit();

            for (blocks[start..end], 0..) |block, position| {
                if (position > 0) try line.writer.writeAll(gutter);
                if (index < block.items.len) {
                    try line.writer.writeAll(block.items[index]);
                } else {
                    try line.writer.splatByteAll(' ', box_width);
                }
            }

            try writer.writeAll(std.mem.trimEnd(u8, line.written(), " "));
            try writer.writeByte('\n');
        }

        if (end < blocks.len) try writer.writeByte('\n');
    }
}

fn writeGregorianSpan(
    writer: *std.Io.Writer,
    year: i64,
    first_month: u8,
    last_month: u8,
) !void {
    const first = sym454.Sym{ .year = year, .month = first_month, .day = 1 };
    const last = sym454.Sym{
        .year = year,
        .month = last_month,
        .day = @intCast(sym454.daysInMonth(year, last_month)),
    };

    try writer.print("{f} to {f} Gregorian\n", .{ first.gregorian(), last.gregorian() });
}

fn writeYearSummary(writer: *std.Io.Writer, year: i64) !void {
    if (sym454.isLeapYear(year)) {
        try writer.print("{d}, leap year of 371 days in 53 weeks", .{year});
    } else {
        try writer.print("{d}, common year of 364 days in 52 weeks", .{year});
    }
}

pub fn renderSingleMonth(
    writer: *std.Io.Writer,
    arena: std.mem.Allocator,
    year: i64,
    month: u8,
    today: sym454.Sym,
    style: Style,
    show_gregorian: bool,
) !void {
    const week_rows: usize = @intCast(@divExact(sym454.daysInMonth(year, month), 7));
    const block = try renderMonth(arena, year, month, today, style, true, week_rows);

    for (block.items) |line| {
        try writer.writeAll(line);
        try writer.writeByte('\n');
    }

    if (show_gregorian) try writeGregorianSpan(writer, year, month, month);
}

pub fn renderThreeMonths(
    writer: *std.Io.Writer,
    arena: std.mem.Allocator,
    year: i64,
    month: u8,
    today: sym454.Sym,
    style: Style,
    show_gregorian: bool,
) !void {
    var blocks: [3]Block = undefined;

    for (&blocks, 0..) |*block, index| {
        const shifted = shiftMonth(year, month, @as(i64, @intCast(index)) - 1);
        block.* = try renderMonth(
            arena,
            shifted.year,
            shifted.month,
            today,
            style,
            true,
            max_week_rows,
        );
    }

    try joinBlocks(writer, arena, &blocks, 3);

    if (show_gregorian) try writeGregorianSpan(writer, year, month, month);
}

pub fn renderYear(
    writer: *std.Io.Writer,
    arena: std.mem.Allocator,
    year: i64,
    today: sym454.Sym,
    style: Style,
    per_row: usize,
    show_gregorian: bool,
) !void {
    const width = if (per_row < 1) 1 else per_row;

    var blocks: [12]Block = undefined;
    for (&blocks, 1..) |*block, month| {
        block.* = try renderMonth(
            arena,
            year,
            @intCast(month),
            today,
            style,
            false,
            max_week_rows,
        );
    }

    var summary: std.Io.Writer.Allocating = .init(arena);
    defer summary.deinit();
    try writeYearSummary(&summary.writer, year);

    var heading: std.Io.Writer.Allocating = .init(arena);
    defer heading.deinit();
    try writeCentered(
        &heading.writer,
        summary.written(),
        width * box_width + width - 1,
    );

    try writer.writeAll(std.mem.trimEnd(u8, heading.written(), " "));
    try writer.writeAll("\n\n");

    try joinBlocks(writer, arena, &blocks, width);

    if (show_gregorian) {
        try writer.writeByte('\n');
        try writeGregorianSpan(writer, year, 1, 12);
    }
}

const testing = std.testing;

fn renderToString(arena: std.mem.Allocator, comptime render: anytype, args: anytype) ![]const u8 {
    var out: std.Io.Writer.Allocating = .init(arena);
    try @call(.auto, render, .{ &out.writer, arena } ++ args);
    return out.toOwnedSlice();
}

test "single month box" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 8, sym454.Sym{ .year = 2026, .month = 8, .day = 35 }, Style{}, false },
    );

    try testing.expectEqualStrings(
        \\┌──────────────────────┐
        \\│     August 2026      │
        \\├──────────────────────┤
        \\│ Mo Tu We Th Fr Sa Su │
        \\│  1  2  3  4  5  6  7 │
        \\│  8  9 10 11 12 13 14 │
        \\│ 15 16 17 18 19 20 21 │
        \\│ 22 23 24 25 26 27 28 │
        \\│ 29 30 31 32 33 34 35 │
        \\└──────────────────────┘
        \\
    , text);
}

test "December carries the leap week" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const leap = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 12, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, false },
    );
    try testing.expect(std.mem.indexOf(u8, leap, "29 30 31 32 33 34 35") != null);

    const common = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2025, 12, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, false },
    );
    try testing.expect(std.mem.indexOf(u8, common, "29 30") == null);
    try testing.expect(std.mem.indexOf(u8, common, "22 23 24 25 26 27 28") != null);
}

test "today is highlighted only when color is on" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const today = sym454.Sym{ .year = 2026, .month = 8, .day = 35 };

    const plain = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 8, today, Style{ .enabled = false }, false },
    );
    try testing.expect(std.mem.indexOf(u8, plain, highlight_on) == null);

    const colored = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 8, today, Style{ .enabled = true }, false },
    );
    try testing.expect(std.mem.indexOf(u8, colored, highlight_on ++ "35" ++ highlight_off) != null);

    const other = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 7, today, Style{ .enabled = true }, false },
    );
    try testing.expect(std.mem.indexOf(u8, other, highlight_on) == null);
}

test "gregorian span" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text = try renderToString(
        arena.allocator(),
        renderSingleMonth,
        .{ 2026, 8, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, true },
    );

    try testing.expect(std.mem.endsWith(
        u8,
        text,
        "2026-07-27 to 2026-08-30 Gregorian\n",
    ));
}

test "three months side by side" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text = try renderToString(
        arena.allocator(),
        renderThreeMonths,
        .{ 2026, 8, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, false },
    );

    var lines = std.mem.splitScalar(u8, text, '\n');
    var count: usize = 0;
    while (lines.next()) |line| {
        if (line.len == 0) continue;
        count += 1;
        try testing.expectEqual(3 * box_width + 2, displayWidth(line));
    }

    try testing.expectEqual(10, count);
    try testing.expect(std.mem.indexOf(u8, text, "July 2026") != null);
    try testing.expect(std.mem.indexOf(u8, text, "September 2026") != null);
}

test "year view" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const leap = try renderToString(
        arena.allocator(),
        renderYear,
        .{ 2026, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, @as(usize, 3), false },
    );
    try testing.expect(std.mem.startsWith(
        u8,
        leap,
        "                 2026, leap year of 371 days in 53 weeks\n\n",
    ));

    const common = try renderToString(
        arena.allocator(),
        renderYear,
        .{ 2025, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, @as(usize, 3), false },
    );
    try testing.expect(std.mem.indexOf(
        u8,
        common,
        "2025, common year of 364 days in 52 weeks",
    ) != null);

    for ([_][]const u8{ "January", "June", "December" }) |name| {
        try testing.expect(std.mem.indexOf(u8, leap, name) != null);
    }
    try testing.expect(std.mem.indexOf(u8, leap, "January 2026") == null);
}

test "months per row" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();

    const text = try renderToString(
        arena.allocator(),
        renderYear,
        .{ 2026, sym454.Sym{ .year = 1, .month = 1, .day = 1 }, Style{}, @as(usize, 4), false },
    );

    var lines = std.mem.splitScalar(u8, text, '\n');
    _ = lines.next();
    _ = lines.next();

    const first = lines.next().?;
    try testing.expectEqual(4 * box_width + 3, displayWidth(first));
}

test "month shifting wraps across years" {
    try testing.expectEqual(2026, shiftMonth(2026, 8, 1).year);
    try testing.expectEqual(9, shiftMonth(2026, 8, 1).month);
    try testing.expectEqual(2027, shiftMonth(2026, 12, 1).year);
    try testing.expectEqual(1, shiftMonth(2026, 12, 1).month);
    try testing.expectEqual(2025, shiftMonth(2026, 1, -1).year);
    try testing.expectEqual(12, shiftMonth(2026, 1, -1).month);
    try testing.expectEqual(-1, shiftMonth(0, 1, -1).year);
    try testing.expectEqual(12, shiftMonth(0, 1, -1).month);
}
