package humanize_tests

import humanize ".."
import "core:mem"
import "core:strings"
import "core:testing"
import "core:time"

// expect_duration formats `d` with a tracking allocator and checks the text and that nothing leaks.
expect_duration :: proc(
	t: ^testing.T,
	d: time.Duration,
	want: string,
	max_units := 2,
	style := humanize.Duration_Style.Short,
	loc := #caller_location,
) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.duration(d, max_units, style, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

// expect_parse_duration checks that parse_duration(text) returns `want` with no error.
expect_parse_duration :: proc(t: ^testing.T, text: string, want: time.Duration, loc := #caller_location) {
	got, err := humanize.parse_duration(text)
	testing.expectf(t, err == .None, "parse_duration(%q) failed: %v", text, err, loc = loc)
	testing.expectf(t, got == want, "parse_duration(%q): got %d, want %d", text, i64(got), i64(want), loc = loc)
}

// expect_parse_duration_error checks that parse_duration(text) fails with exactly `want`.
expect_parse_duration_error :: proc(t: ^testing.T, text: string, want: humanize.Parse_Error, loc := #caller_location) {
	got, err := humanize.parse_duration(text)
	testing.expectf(t, err == want, "parse_duration(%q): got error %v, want %v", text, err, want, loc = loc)
	testing.expectf(t, got == 0, "parse_duration(%q) returned %d alongside an error", text, i64(got), loc = loc)
}

DAY :: 24 * time.Hour

@(test)
test_duration_zero :: proc(t: ^testing.T) {
	expect_duration(t, 0, "0s")
	expect_duration(t, 0, "0 seconds", style = .Long)
}

@(test)
test_duration_short_uses_two_units_by_default :: proc(t: ^testing.T) {
	expect_duration(t, 90 * time.Minute, "1h30m")
	expect_duration(t, time.Hour + 30 * time.Minute + 45 * time.Second, "1h30m")
	expect_duration(t, 45 * time.Second, "45s")
	expect_duration(t, 26 * time.Hour, "1d2h")
	expect_duration(t, 3 * DAY, "3d")
}

@(test)
test_duration_skips_zero_units :: proc(t: ^testing.T) {
	d := time.Hour + 45 * time.Second
	expect_duration(t, d, "1h")
	expect_duration(t, d, "1h45s", max_units = 3)
	expect_duration(t, d, "1 hour 45 seconds", max_units = 3, style = .Long)
}

@(test)
test_duration_every_unit :: proc(t: ^testing.T) {
	d := DAY + 2 * time.Hour + 3 * time.Minute + 4 * time.Second + 5 * time.Millisecond + 6 * time.Microsecond + 7
	expect_duration(t, d, "1d2h3m4s5ms6µs7ns", max_units = 0)
	expect_duration(t, d, "1d2h3m4s5ms6µs7ns", max_units = -1)
	expect_duration(t, d, "1d2h3m4s5ms6µs7ns", max_units = 99)
	expect_duration(t, d, "1d", max_units = 1)
}

@(test)
test_duration_below_one_second :: proc(t: ^testing.T) {
	expect_duration(t, 1500 * time.Millisecond, "1s500ms")
	expect_duration(t, 250 * time.Millisecond, "250ms")
	expect_duration(t, time.Microsecond, "1µs")
	expect_duration(t, 42, "42ns")
	expect_duration(t, 1, "1 nanosecond", style = .Long)
}

@(test)
test_duration_long_style :: proc(t: ^testing.T) {
	expect_duration(t, 90 * time.Minute, "1 hour 30 minutes", style = .Long)
	expect_duration(t, time.Second, "1 second", style = .Long)
	expect_duration(t, 2 * DAY, "2 days", style = .Long)
	expect_duration(t, time.Minute + time.Second, "1 minute 1 second", style = .Long)
	expect_duration(t, 2 * time.Millisecond + time.Microsecond, "2 milliseconds 1 microsecond", style = .Long)
}

@(test)
test_duration_negative :: proc(t: ^testing.T) {
	expect_duration(t, -90 * time.Second, "-1m30s")
	expect_duration(t, -90 * time.Second, "-1 minute 30 seconds", style = .Long)
	expect_duration(t, -1, "-1ns")
}

@(test)
test_duration_extremes :: proc(t: ^testing.T) {
	expect_duration(t, time.Duration(max(i64)), "106751d23h47m16s854ms775µs807ns", max_units = 0)
	expect_duration(t, time.Duration(min(i64)), "-106751d23h47m16s854ms775µs808ns", max_units = 0)
	expect_duration(t, time.Duration(min(i64)), "-106751d23h")
}

@(test)
test_write_duration_appends_to_builder :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	sb := strings.builder_make(alloc)
	defer strings.builder_destroy(&sb)
	strings.write_string(&sb, "took ")
	n := humanize.write_duration(&sb, 2 * time.Second + 300 * time.Millisecond)
	testing.expect_value(t, n, len("2s300ms"))
	testing.expect_value(t, strings.to_string(sb), "took 2s300ms")
}

@(test)
test_duration_reports_allocator_error :: proc(t: ^testing.T) {
	s, err := humanize.duration(time.Hour, allocator = failing_allocator())
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, s, "")
}

@(test)
test_parse_duration_go_style :: proc(t: ^testing.T) {
	expect_parse_duration(t, "1h30m", 90 * time.Minute)
	expect_parse_duration(t, "300ms", 300 * time.Millisecond)
	expect_parse_duration(t, "2h45m30s", 2 * time.Hour + 45 * time.Minute + 30 * time.Second)
	expect_parse_duration(t, "1us", time.Microsecond)
	expect_parse_duration(t, "1µs", time.Microsecond)
	expect_parse_duration(t, "1μs", time.Microsecond)
	expect_parse_duration(t, "7ns", 7)
	expect_parse_duration(t, "1d12h", DAY + 12 * time.Hour)
	expect_parse_duration(t, "2w", 14 * DAY)
}

@(test)
test_parse_duration_fractions :: proc(t: ^testing.T) {
	expect_parse_duration(t, "1.5h", 90 * time.Minute)
	expect_parse_duration(t, ".5s", 500 * time.Millisecond)
	expect_parse_duration(t, "1.s", time.Second)
	expect_parse_duration(t, "0.000000001s", 1)
	expect_parse_duration(t, "1.0000000009s", time.Second)
	expect_parse_duration(t, "0.25d", 6 * time.Hour)
}

@(test)
test_parse_duration_spelled_out_units :: proc(t: ^testing.T) {
	expect_parse_duration(t, "1 hour 30 minutes", 90 * time.Minute)
	expect_parse_duration(t, "2 days, 4 hours and 5 seconds", 2 * DAY + 4 * time.Hour + 5 * time.Second)
	expect_parse_duration(t, "1 week", 7 * DAY)
	expect_parse_duration(t, "3 Mins", 3 * time.Minute)
	expect_parse_duration(t, "10 SECS", 10 * time.Second)
	expect_parse_duration(t, "5 milliseconds AND 2 microseconds", 5 * time.Millisecond + 2 * time.Microsecond)
}

@(test)
test_parse_duration_signs :: proc(t: ^testing.T) {
	expect_parse_duration(t, "-1h", -time.Hour)
	expect_parse_duration(t, "+5m", 5 * time.Minute)
	expect_parse_duration(t, "-1h30m", -90 * time.Minute)
	expect_parse_duration(t, "-0", 0)
}

@(test)
test_parse_duration_zero :: proc(t: ^testing.T) {
	expect_parse_duration(t, "0", 0)
	expect_parse_duration(t, "  0 ", 0)
	expect_parse_duration(t, "0s", 0)
	expect_parse_duration(t, "0.0h", 0)
}

@(test)
test_parse_duration_rejects_empty_input :: proc(t: ^testing.T) {
	expect_parse_duration_error(t, "", .Empty)
	expect_parse_duration_error(t, "   ", .Empty)
}

@(test)
test_parse_duration_rejects_malformed_numbers :: proc(t: ^testing.T) {
	expect_parse_duration_error(t, "-", .Invalid_Number)
	expect_parse_duration_error(t, "h", .Invalid_Number)
	expect_parse_duration_error(t, "--1h", .Invalid_Number)
	expect_parse_duration_error(t, "1..5h", .Invalid_Number)
	expect_parse_duration_error(t, "1.5.h", .Invalid_Number)
	expect_parse_duration_error(t, ", 1h", .Invalid_Number)
	expect_parse_duration_error(t, "1h -5m", .Invalid_Number)
	expect_parse_duration_error(t, "and 5s", .Invalid_Number)
	expect_parse_duration_error(t, "0 5s", .Invalid_Number)
}

@(test)
test_parse_duration_rejects_missing_units :: proc(t: ^testing.T) {
	expect_parse_duration_error(t, "5", .Missing_Unit)
	expect_parse_duration_error(t, "1h30", .Missing_Unit)
	expect_parse_duration_error(t, "1.5", .Missing_Unit)
}

@(test)
test_parse_duration_rejects_unknown_units :: proc(t: ^testing.T) {
	expect_parse_duration_error(t, "10 parsecs", .Unknown_Unit)
	expect_parse_duration_error(t, "5y", .Unknown_Unit)
	expect_parse_duration_error(t, "1hh", .Unknown_Unit)
	expect_parse_duration_error(t, "5 and", .Unknown_Unit)
	expect_parse_duration_error(t, "3 fortnights", .Unknown_Unit)
}

@(test)
test_parse_duration_detects_overflow :: proc(t: ^testing.T) {
	expect_parse_duration(t, "9223372036854775807ns", time.Duration(max(i64)))
	expect_parse_duration(t, "-9223372036854775808ns", time.Duration(min(i64)))
	expect_parse_duration(t, "2562047h", 2_562_047 * time.Hour)
	expect_parse_duration_error(t, "9223372036854775808ns", .Overflow)
	expect_parse_duration_error(t, "2562048h", .Overflow)
	expect_parse_duration_error(t, "2562047h47m17s", .Overflow)
	expect_parse_duration_error(t, "99999999999999999999h", .Overflow)
}

@(test)
test_duration_round_trip :: proc(t: ^testing.T) {
	cases := [?]time.Duration {
		0,
		1,
		90 * time.Minute,
		-90 * time.Second,
		DAY + 2 * time.Hour + 3 * time.Minute + 4 * time.Second + 5 * time.Millisecond + 6 * time.Microsecond + 7,
		time.Duration(max(i64)),
		time.Duration(min(i64)),
	}

	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	for d in cases {
		for style in humanize.Duration_Style {
			text, ferr := humanize.duration(d, 0, style, alloc)
			testing.expect_value(t, ferr, mem.Allocator_Error.None)
			back, perr := humanize.parse_duration(text)
			testing.expectf(t, perr == .None && back == d, "%d -> %q -> %d (%v)", i64(d), text, i64(back), perr)
			delete(text, alloc)
		}
	}
}

@(test)
test_parse_duration_rejects_trailing_separator :: proc(t: ^testing.T) {
	// A trailing comma is as incomplete as a trailing "and".
	expect_parse_duration_error(t, "1h,", .Invalid_Number)
	expect_parse_duration_error(t, "1h30m, ", .Invalid_Number)
	expect_parse_duration_error(t, "1h and", .Invalid_Number)
	expect_parse_duration(t, "1h, 30m", time.Hour + 30 * time.Minute)
}
