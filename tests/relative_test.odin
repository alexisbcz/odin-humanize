package humanize_tests

import humanize ".."
import "core:mem"
import "core:strings"
import "core:testing"
import "core:time"

// REFERENCE is a fixed "now" so relative time tests never depend on the clock.
REFERENCE :: 1_700_000_000 * i64(time.Second)

// expect_relative checks the text for a moment `offset` away from REFERENCE, where negative is the past.
expect_relative :: proc(t: ^testing.T, offset: time.Duration, want: string, loc := #caller_location) {
	now := time.from_nanoseconds(REFERENCE)
	then := time.time_add(now, offset)

	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.relative_time(then, now, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

@(test)
test_relative_time_now :: proc(t: ^testing.T) {
	expect_relative(t, 0, "now")
	expect_relative(t, -999 * time.Millisecond, "now")
	expect_relative(t, 999 * time.Millisecond, "now")
}

@(test)
test_relative_time_seconds_minutes_hours :: proc(t: ^testing.T) {
	expect_relative(t, -time.Second, "1 second ago")
	expect_relative(t, -45 * time.Second, "45 seconds ago")
	expect_relative(t, -90 * time.Second, "1 minute ago")
	expect_relative(t, -3 * time.Minute, "3 minutes ago")
	expect_relative(t, -59 * time.Minute - 59 * time.Second, "59 minutes ago")
	expect_relative(t, -time.Hour, "1 hour ago")
	expect_relative(t, -23 * time.Hour, "23 hours ago")
}

@(test)
test_relative_time_days_weeks :: proc(t: ^testing.T) {
	expect_relative(t, -DAY, "1 day ago")
	expect_relative(t, -6 * DAY, "6 days ago")
	expect_relative(t, -7 * DAY, "1 week ago")
	expect_relative(t, -29 * DAY, "4 weeks ago")
}

@(test)
test_relative_time_months_years :: proc(t: ^testing.T) {
	expect_relative(t, -30 * DAY, "1 month ago")
	expect_relative(t, -364 * DAY, "12 months ago")
	expect_relative(t, -365 * DAY, "1 year ago")
	expect_relative(t, -800 * DAY, "2 years ago")
}

@(test)
test_relative_time_future :: proc(t: ^testing.T) {
	expect_relative(t, time.Second, "in 1 second")
	expect_relative(t, 3 * time.Minute, "in 3 minutes")
	expect_relative(t, time.Hour, "in 1 hour")
	expect_relative(t, 2 * DAY + time.Hour, "in 2 days")
	expect_relative(t, 400 * DAY, "in 1 year")
}

@(test)
test_relative_time_largest_gap :: proc(t: ^testing.T) {
	earliest := time.from_nanoseconds(min(i64))
	latest := time.from_nanoseconds(max(i64))

	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	past, perr := humanize.relative_time(earliest, latest, alloc)
	testing.expect_value(t, perr, mem.Allocator_Error.None)
	testing.expect_value(t, past, "584 years ago")
	delete(past, alloc)

	future, ferr := humanize.relative_time(latest, earliest, alloc)
	testing.expect_value(t, ferr, mem.Allocator_Error.None)
	testing.expect_value(t, future, "in 584 years")
	delete(future, alloc)
}

@(test)
test_time_ago_reads_the_clock :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	past, perr := humanize.time_ago(time.time_add(time.now(), -2 * time.Hour), alloc)
	testing.expect_value(t, perr, mem.Allocator_Error.None)
	testing.expect_value(t, past, "2 hours ago")
	delete(past, alloc)

	future, ferr := humanize.time_ago(time.time_add(time.now(), 3 * DAY + time.Hour), alloc)
	testing.expect_value(t, ferr, mem.Allocator_Error.None)
	testing.expect_value(t, future, "in 3 days")
	delete(future, alloc)
}

@(test)
test_write_relative_time_appends_to_builder :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	now := time.from_nanoseconds(REFERENCE)
	sb := strings.builder_make(alloc)
	defer strings.builder_destroy(&sb)
	strings.write_string(&sb, "edited ")
	n := humanize.write_relative_time(&sb, time.time_add(now, -5 * time.Minute), now)
	testing.expect_value(t, n, len("5 minutes ago"))
	testing.expect_value(t, strings.to_string(sb), "edited 5 minutes ago")
}

@(test)
test_relative_time_reports_allocator_error :: proc(t: ^testing.T) {
	now := time.from_nanoseconds(REFERENCE)
	s, err := humanize.relative_time(now, now, failing_allocator())
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, s, "")
}
