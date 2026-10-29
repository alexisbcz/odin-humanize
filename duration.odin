package humanize

import "base:runtime"
import "core:strings"
import "core:time"

// Duration_Style picks how write_duration spells units.
Duration_Style :: enum {
	// Short style uses unit symbols with no spaces, such as "1h30m". parse_duration reads it back.
	Short,
	// Long style spells units out, such as "1 hour 30 minutes". parse_duration reads it back too.
	Long,
}

@(private = "file")
Duration_Unit :: struct {
	size:     u64,
	symbol:   string,
	singular: string,
	plural:   string,
}

@(private = "file", rodata)
DURATION_UNITS := [?]Duration_Unit {
	{u64(24 * time.Hour), "d", "day", "days"},
	{u64(time.Hour), "h", "hour", "hours"},
	{u64(time.Minute), "m", "minute", "minutes"},
	{u64(time.Second), "s", "second", "seconds"},
	{u64(time.Millisecond), "ms", "millisecond", "milliseconds"},
	{u64(time.Microsecond), "µs", "microsecond", "microseconds"},
	{u64(time.Nanosecond), "ns", "nanosecond", "nanoseconds"},
}

/*
write_duration appends a duration such as "1h30m" or "1 hour 30 minutes" to `b`.

The units are days, hours, minutes, seconds, milliseconds, microseconds and
nanoseconds. Output starts at the largest unit that is not zero and covers at
most `max_units` consecutive units from there; zero units are left out and the
rest is truncated, not rounded. With the default of 2, 1h30m45s prints "1h30m"
and 1h0m45s prints "1h". A `max_units` of 0 or less prints every unit.

A negative duration starts with "-". Zero prints "0s" or "0 seconds".

Inputs:
- b: the builder to append to.
- d: the duration to format.
- max_units: the most consecutive units to consider; 0 or less means all.
- style: `.Short` for "1h30m", `.Long` for "1 hour 30 minutes".

Returns:
- written: the number of bytes appended to `b`.
*/
write_duration :: proc(b: ^strings.Builder, d: time.Duration, max_units := 2, style := Duration_Style.Short) -> (written: int) {
	mag := magnitude(i64(d))
	if d < 0 {
		written += strings.write_byte(b, '-')
	}
	if mag == 0 {
		written += strings.write_string(b, "0s" if style == .Short else "0 seconds")
		return
	}

	first := 0
	for mag < DURATION_UNITS[first].size {
		first += 1
	}
	last := len(DURATION_UNITS) - 1
	if max_units > 0 {
		last = min(first + max_units - 1, last)
	}

	rem := mag
	wrote_any := false
	for i in first ..= last {
		unit := DURATION_UNITS[i]
		count := rem / unit.size
		rem %= unit.size
		if count == 0 {
			continue
		}
		if style == .Long && wrote_any {
			written += strings.write_byte(b, ' ')
		}
		written += strings.write_u64(b, count)
		if style == .Short {
			written += strings.write_string(b, unit.symbol)
		} else {
			written += strings.write_byte(b, ' ')
			written += strings.write_string(b, unit.singular if count == 1 else unit.plural)
		}
		wrote_any = true
	}
	return
}

/*
duration formats a duration such as "1h30m" or "1 hour 30 minutes". See
write_duration for how `max_units` truncates the output.

Inputs:
- d: the duration to format.
- max_units: the most consecutive units to consider; 0 or less means all.
- style: `.Short` for "1h30m", `.Long` for "1 hour 30 minutes".
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.

Example:
	s, _ := humanize.duration(90 * time.Minute, style = .Long)
	defer delete(s)
	// s == "1 hour 30 minutes"
*/
duration :: proc(
	d: time.Duration,
	max_units := 2,
	style := Duration_Style.Short,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	s: string,
	err: runtime.Allocator_Error,
) {
	buf: [256]byte
	sb := strings.builder_from_bytes(buf[:])
	write_duration(&sb, d, max_units, style)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

/*
parse_duration reads a duration such as "1h30m", "1.5h", "-300ms",
"2 days 4 hours" or "1 hour, 30 minutes and 5 seconds".

The text is an optional sign followed by one or more number and unit pairs.
Numbers may have a fraction. Spaces, commas and the word "and" may separate
the pairs. Units are case-insensitive:

- ns, nsec, nanosecond(s)
- us, µs, μs, usec, microsecond(s)
- ms, msec, millisecond(s)
- s, sec, secs, second(s)
- m, min, mins, minute(s)
- h, hr, hrs, hour(s)
- d, day(s), meaning 24 hours
- w, wk, wks, week(s), meaning 7 days

A bare "0" is the only number allowed without a unit. A trailing comma or
"and", as in "1h," or "1h and", is `.Invalid_Number`.

Returns:
- d: the parsed duration.
- err: `.Empty`, `.Invalid_Number`, `.Missing_Unit`, `.Unknown_Unit`,
  `.Overflow` when the total does not fit in `time.Duration`, or `.None`.
*/
parse_duration :: proc(s: string) -> (d: time.Duration, err: Parse_Error) {
	text := strings.trim_space(s)
	if len(text) == 0 {
		return 0, .Empty
	}

	negative := false
	if text[0] == '-' || text[0] == '+' {
		negative = text[0] == '-'
		text = text[1:]
	}

	limit := u128(max(i64))
	if negative {
		limit += 1
	}

	total: u128
	pairs := 0
	for {
		before := text
		text = skip_separators(text, pairs > 0)
		if len(text) == 0 {
			// A comma with nothing after it, as in "1h,", is as incomplete as a trailing "and".
			if strings.contains_rune(before, ',') {
				return 0, .Invalid_Number
			}
			break
		}

		dec, rest, derr := scan_decimal(text, false)
		if derr != .None {
			return 0, derr
		}
		rest = strings.trim_left_space(rest)
		unit, after := split_unit(rest)
		if len(unit) == 0 {
			if starts_like_number(after) {
				return 0, .Invalid_Number
			}
			if pairs == 0 && len(after) == 0 && dec.whole == 0 && dec.frac == 0 {
				return 0, .None
			}
			return 0, .Missing_Unit
		}

		size, ok := duration_unit_size(unit)
		if !ok {
			return 0, .Unknown_Unit
		}
		total += decimal_scale(dec, size)
		if total > limit {
			return 0, .Overflow
		}
		pairs += 1
		text = after
	}

	if pairs == 0 {
		return 0, .Invalid_Number
	}
	if negative {
		return time.Duration(i64(-i128(total))), .None
	}
	return time.Duration(i64(total)), .None
}

// magnitude returns |x| without overflowing on min(i64).
@(private)
magnitude :: proc "contextless" (x: i64) -> u64 {
	if x >= 0 {
		return u64(x)
	}
	return u64(-(x + 1)) + 1
}

// skip_separators drops leading spaces and, between pairs, commas and the word "and".
@(private = "file")
skip_separators :: proc(s: string, between_pairs: bool) -> string {
	text := strings.trim_left_space(s)
	if !between_pairs {
		return text
	}
	for {
		switch {
		case strings.has_prefix(text, ","):
			text = strings.trim_left_space(text[1:])
		case len(text) > 3 && strings.equal_fold(text[:3], "and") && strings.is_space(rune(text[3])):
			text = strings.trim_left_space(text[3:])
		case:
			return text
		}
	}
}

// split_unit splits `s` after its leading run of letters, counting any non-ASCII byte as a letter so "µs" works.
@(private = "file")
split_unit :: proc(s: string) -> (unit, rest: string) {
	i := 0
	for i < len(s) {
		c := s[i]
		if !('a' <= c && c <= 'z' || 'A' <= c && c <= 'Z' || c >= 0x80) {
			break
		}
		i += 1
	}
	return s[:i], s[i:]
}

@(private = "file")
Unit_Name :: struct {
	name: string,
	size: u64,
}

@(private = "file", rodata)
DURATION_UNIT_NAMES := [?]Unit_Name {
	{"ns", u64(time.Nanosecond)},
	{"nsec", u64(time.Nanosecond)},
	{"nanosecond", u64(time.Nanosecond)},
	{"nanoseconds", u64(time.Nanosecond)},
	{"us", u64(time.Microsecond)},
	{"µs", u64(time.Microsecond)},
	{"μs", u64(time.Microsecond)},
	{"usec", u64(time.Microsecond)},
	{"microsecond", u64(time.Microsecond)},
	{"microseconds", u64(time.Microsecond)},
	{"ms", u64(time.Millisecond)},
	{"msec", u64(time.Millisecond)},
	{"millisecond", u64(time.Millisecond)},
	{"milliseconds", u64(time.Millisecond)},
	{"s", u64(time.Second)},
	{"sec", u64(time.Second)},
	{"secs", u64(time.Second)},
	{"second", u64(time.Second)},
	{"seconds", u64(time.Second)},
	{"m", u64(time.Minute)},
	{"min", u64(time.Minute)},
	{"mins", u64(time.Minute)},
	{"minute", u64(time.Minute)},
	{"minutes", u64(time.Minute)},
	{"h", u64(time.Hour)},
	{"hr", u64(time.Hour)},
	{"hrs", u64(time.Hour)},
	{"hour", u64(time.Hour)},
	{"hours", u64(time.Hour)},
	{"d", u64(24 * time.Hour)},
	{"day", u64(24 * time.Hour)},
	{"days", u64(24 * time.Hour)},
	{"w", u64(7 * 24 * time.Hour)},
	{"wk", u64(7 * 24 * time.Hour)},
	{"wks", u64(7 * 24 * time.Hour)},
	{"week", u64(7 * 24 * time.Hour)},
	{"weeks", u64(7 * 24 * time.Hour)},
}

@(private = "file")
duration_unit_size :: proc(unit: string) -> (size: u64, ok: bool) {
	for u in DURATION_UNIT_NAMES {
		if strings.equal_fold(unit, u.name) {
			return u.size, true
		}
	}
	return 0, false
}
