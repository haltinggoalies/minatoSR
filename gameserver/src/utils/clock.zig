const std = @import("std");
const ProfileStore = @import("../manager/profile_store.zig");

// The time the server reports to the client. The client checks the MoC/PF/AS schedules in its own design data
// against it, so once the schedules of the client version in use have closed, those modes show "Locked".
// /faketime fixes that from the game: each login restarts the reported clock at noon UTC+8 of the chosen day.
// A window (start, end) does the same at build time: once the real clock is past `end`, each login restarts the
// reported clock at `start` and lets it run from there; before it, the real time is used.
// 4.5.54 needed 2026-09-20 00:00 UTC .. 2026-09-24 20:00 UTC (its MoC 1035/1036, PF 2026/2027 and AS 3020/3021
// closed at 2026-09-25 04:00 UTC+8). 4.6.51 came out on 2026-09-29 and runs on the real time (as CapySR does);
// its closing dates are not known here. If MoC/PF/AS show "Locked" later, use /faketime or set a window.
const Window = struct { start_ms: i64, end_ms: i64 };
const window: ?Window = null;

var offset_ms: i64 = 0;

pub fn resetAtLogin() void {
    const now = std.time.milliTimestamp();
    if (dateStartMs(ProfileStore.get().fake_date)) |start| {
        offset_ms = now - start;
        return;
    }
    offset_ms = 0;
    const w = window orelse return;
    if (now >= w.end_ms) offset_ms = now - w.start_ms;
}

// Unix milliseconds as the client should see them.
pub fn nowMs() u64 {
    return @intCast(@max(0, std.time.milliTimestamp() - offset_ms));
}
// Unix seconds, for protocol fields in seconds.
pub fn nowSec() u64 {
    return nowMs() / std.time.ms_per_s;
}

// "20260920" or "2026-09-20" as 20260920, if it is a real day in 2023..2099.
pub fn parseDate(text: []const u8) ?u32 {
    var digits: [8]u8 = undefined;
    switch (text.len) {
        8 => @memcpy(&digits, text),
        10 => {
            if (text[4] != '-' or text[7] != '-') return null;
            @memcpy(digits[0..4], text[0..4]);
            @memcpy(digits[4..6], text[5..7]);
            @memcpy(digits[6..8], text[8..10]);
        },
        else => return null,
    }
    const date = std.fmt.parseInt(u32, &digits, 10) catch return null;
    return if (dateStartMs(date) != null) date else null;
}

// Noon UTC+8 of yyyymmdd in Unix milliseconds. The schedules open at 04:00 UTC+8, so midnight would still be
// before the first day of one.
pub fn dateStartMs(date: u32) ?i64 {
    const year = date / 10000;
    const month = date / 100 % 100;
    const day = date % 100;
    if (year < 2023 or year > 2099 or month < 1 or month > 12 or day < 1) return null;
    if (day > daysInMonth(year, month)) return null;
    var days: i64 = 0;
    var y: u32 = 1970;
    while (y < year) : (y += 1) days += std.time.epoch.getDaysInYear(@intCast(y));
    var m: u32 = 1;
    while (m < month) : (m += 1) days += daysInMonth(year, m);
    days += day - 1;
    return (days * std.time.s_per_day + 4 * std.time.s_per_hour) * std.time.ms_per_s;
}

fn daysInMonth(year: u32, month: u32) u32 {
    const leap: std.time.epoch.YearLeapKind = if (std.time.epoch.isLeapYear(@intCast(year))) .leap else .not_leap;
    return std.time.epoch.getDaysInMonth(leap, @enumFromInt(month));
}

test "dates parse in both forms and only when they exist" {
    try std.testing.expectEqual(@as(?u32, 20260920), parseDate("20260920"));
    try std.testing.expectEqual(@as(?u32, 20260920), parseDate("2026-09-20"));
    try std.testing.expectEqual(@as(?u32, 20240229), parseDate("2024-02-29"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026-02-29"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026-13-01"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("1999-01-01"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("2026/09/20"));
    try std.testing.expectEqual(@as(?u32, null), parseDate("today"));
}

test "a date starts at noon UTC+8" {
    try std.testing.expectEqual(@as(?i64, 1789876800000), dateStartMs(20260920));
    try std.testing.expectEqual(@as(?i64, 1709179200000), dateStartMs(20240229));
    try std.testing.expectEqual(@as(?i64, null), dateStartMs(0));
}
