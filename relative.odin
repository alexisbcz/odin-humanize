package humanize

import "base:runtime"
import "core:strings"
import "core:time"

@(private = "file")
Relative_Unit :: struct {
	// below is the first gap, in nanoseconds, that this unit no longer covers.
	below:    u128,
	size:     u128,
	singular: string,
	plural:   string,
}

@(private = "file", rodata)
RELATIVE_UNITS := [?]Relative_Unit {
	{u128(time.Minute), u128(time.Second), "second", "seconds"},
	{u128(time.Hour), u128(time.Minute), "minute", "minutes"},
	{u128(24 * time.Hour), u128(time.Hour), "hour", "hours"},
	{u128(7 * 24 * time.Hour), u128(24 * time.Hour), "day", "days"},
	{u128(30 * 24 * time.Hour), u128(7 * 24 * time.Hour), "week", "weeks"},
	{u128(365 * 24 * time.Hour), u128(30 * 24 * time.Hour), "month", "months"},
	{max(u128), u128(365 * 24 * time.Hour), "year", "years"},
}

/*
write_relative_time appends how far `t` is from `now` to `b`, such as
"3 minutes ago" or "in 2 hours".

A gap under one second prints "now". Otherwise the output uses the largest
unit that fits and truncates: 90 seconds is "1 minute ago". The units are
seconds, minutes, hours, days, weeks (from 7 days), months (from 30 days,
counted as 30 days each) and years (from 365 days, counted as 365 days each).

Inputs:
- b: the builder to append to.
- t: the moment to describe.
- now: the reference moment, usually `time.now()`.

Returns:
- written: the number of bytes appended to `b`.
*/
write_relative_time :: proc(b: ^strings.Builder, t, now: time.Time) -> (written: int) {
	delta := i128(time.to_unix_nanoseconds(now)) - i128(time.to_unix_nanoseconds(t))
	past := delta > 0
	gap := u128(delta) if past else u128(-delta)

	if gap < u128(time.Second) {
		written += strings.write_string(b, "now")
		return
	}

	unit := RELATIVE_UNITS[len(RELATIVE_UNITS) - 1]
	for u in RELATIVE_UNITS {
		if gap < u.below {
			unit = u
			break
		}
	}
	count := u64(gap / unit.size)

	if !past {
		written += strings.write_string(b, "in ")
	}
	written += strings.write_u64(b, count)
	written += strings.write_byte(b, ' ')
	written += strings.write_string(b, unit.singular if count == 1 else unit.plural)
	if past {
		written += strings.write_string(b, " ago")
	}
	return
}

/*
relative_time describes how far `t` is from `now`, such as "3 minutes ago" or
"in 2 hours". See write_relative_time for the units and rounding.

Inputs:
- t: the moment to describe.
- now: the reference moment, usually `time.now()`.
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.

Example:
	now := time.now()
	s, _ := humanize.relative_time(time.time_add(now, -3 * time.Minute), now)
	defer delete(s)
	// s == "3 minutes ago"
*/
relative_time :: proc(
	t, now: time.Time,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	s: string,
	err: runtime.Allocator_Error,
) {
	buf: [64]byte
	sb := strings.builder_from_bytes(buf[:])
	write_relative_time(&sb, t, now)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

/*
time_ago describes how far `t` is from the current time, such as
"5 seconds ago" or "in 3 days". It reads the clock with `time.now()`; use
relative_time when you need a fixed reference, for example in tests.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.
*/
time_ago :: proc(t: time.Time, allocator := context.allocator, loc := #caller_location) -> (s: string, err: runtime.Allocator_Error) {
	return relative_time(t, time.now(), allocator, loc)
}
