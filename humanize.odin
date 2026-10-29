/*
Package humanize formats byte sizes, durations, relative times, ordinals and
large numbers for people, and parses sizes such as "10MB" and durations such
as "1h30m" back to values.

Every formatter comes in two forms:
- `bytes`, `duration`, `relative_time`, `ordinal`, `comma` and `comma_float`
  return a new string allocated with `allocator`. The caller frees it with
  `delete`.
- `write_bytes`, `write_duration`, `write_relative_time`, `write_ordinal`,
  `write_comma` and `write_comma_float` append to a `strings.Builder` and
  allocate only when the builder grows.

The parsers `parse_bytes` and `parse_duration` never allocate and report
problems with a `Parse_Error`.

The package keeps no global mutable state, so every procedure is safe to call
from several threads at once.

Example:
	import "core:fmt"
	import "shared:humanize"

	main :: proc() {
		size, err := humanize.bytes(82_854_982)
		if err != nil {
			return
		}
		defer delete(size)
		fmt.println(size) // 82.9 MB
	}
*/
package humanize

/*
Parse_Error lists the ways parse_bytes and parse_duration reject input.
The zero value, `.None`, means success.
*/
Parse_Error :: enum {
	None,
	// The input was empty or held only whitespace.
	Empty,
	// A number was missing or malformed, as in "MB", "1..5s" or "-3MB".
	Invalid_Number,
	// A number had no unit where one is required, as in "1h30".
	Missing_Unit,
	// The unit is not one this package knows, as in "10 parsecs".
	Unknown_Unit,
	// The value does not fit in the result type.
	Overflow,
}

// MAX_DECIMALS is the largest number of decimal places that the byte and float formatters print.
MAX_DECIMALS :: 9

// POW10 holds 10^0 through 10^MAX_DECIMALS.
@(private, rodata)
POW10 := [MAX_DECIMALS + 1]u64{1, 10, 100, 1_000, 10_000, 100_000, 1_000_000, 10_000_000, 100_000_000, 1_000_000_000}

// Decimal is a non-negative number read from text: whole + frac / scale.
@(private)
Decimal :: struct {
	whole: u64,
	frac:  u64,
	// scale is 10 to the power of the number of fraction digits kept.
	scale: u64,
}

// MAX_FRACTION_DIGITS caps the fraction digits that scan_decimal keeps; later digits are ignored.
@(private)
MAX_FRACTION_DIGITS :: 18

@(private)
is_digit :: #force_inline proc "contextless" (c: byte) -> bool {
	return '0' <= c && c <= '9'
}

/*
scan_decimal reads an unsigned decimal number, such as "12", "1.5" or ".25",
from the start of `s`. With `allow_grouping`, commas may group the whole part
in threes, so "1,024" reads as 1024.

Returns the number, the text after it, and `.Invalid_Number` when `s` does not
start with a number or groups its digits wrongly, as in "1,5" or "12,34,567",
or `.Overflow` when the whole part exceeds `max(u64)`.
*/
@(private)
scan_decimal :: proc(s: string, allow_grouping: bool) -> (d: Decimal, rest: string, err: Parse_Error) {
	d.scale = 1
	i := 0
	whole_digits := 0
	// group_digits counts the digits since the last grouping comma.
	group_digits := 0
	grouped := false
	scan: for i < len(s) {
		c := s[i]
		switch {
		case is_digit(c):
			digit := u64(c - '0')
			if d.whole > (max(u64) - digit) / 10 {
				return {}, "", .Overflow
			}
			d.whole = d.whole * 10 + digit
			whole_digits += 1
			group_digits += 1
		case c == ',' && allow_grouping && whole_digits > 0 && i + 1 < len(s) && is_digit(s[i + 1]):
			// A grouping comma follows a lead group of 1 to 3 digits or a full group of 3.
			if group_digits != 3 if grouped else group_digits > 3 {
				return {}, s, .Invalid_Number
			}
			grouped = true
			group_digits = 0
		case:
			break scan
		}
		i += 1
	}
	// The last group must be complete, so a decimal comma such as "1,5" is rejected.
	if grouped && group_digits != 3 {
		return {}, s, .Invalid_Number
	}

	frac_digits := 0
	if i < len(s) && s[i] == '.' {
		i += 1
		for i < len(s) && is_digit(s[i]) {
			if frac_digits < MAX_FRACTION_DIGITS {
				d.frac = d.frac * 10 + u64(s[i] - '0')
				d.scale *= 10
			}
			frac_digits += 1
			i += 1
		}
	}

	if whole_digits == 0 && frac_digits == 0 {
		return {}, s, .Invalid_Number
	}
	return d, s[i:], .None
}

// decimal_scale returns `d * mult`, truncated toward zero. It cannot overflow u128.
@(private)
decimal_scale :: proc "contextless" (d: Decimal, mult: u64) -> u128 {
	return u128(d.whole) * u128(mult) + u128(d.frac) * u128(mult) / u128(d.scale)
}

// starts_like_number reports whether `s` begins with a digit or a decimal point.
@(private)
starts_like_number :: proc "contextless" (s: string) -> bool {
	return len(s) > 0 && (is_digit(s[0]) || s[0] == '.' || s[0] == ',')
}
