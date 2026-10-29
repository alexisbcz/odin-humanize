package humanize

import "base:runtime"
import "core:math"
import "core:strconv"
import "core:strings"

/*
ordinal_suffix returns the English ordinal suffix for `n`: "st", "nd", "rd"
or "th". Numbers ending in 11, 12 or 13 take "th". The sign is ignored. The
result is a string literal, so there is nothing to free.
*/
ordinal_suffix :: proc "contextless" (n: i64) -> string {
	m := magnitude(n)
	switch m % 100 {
	case 11, 12, 13:
		return "th"
	}
	switch m % 10 {
	case 1:
		return "st"
	case 2:
		return "nd"
	case 3:
		return "rd"
	}
	return "th"
}

/*
write_ordinal appends `n` followed by its ordinal suffix to `b`, such as
"1st", "22nd", "113th" or "-3rd".

Returns:
- written: the number of bytes appended to `b`.
*/
write_ordinal :: proc(b: ^strings.Builder, n: i64) -> (written: int) {
	written += strings.write_i64(b, n)
	written += strings.write_string(b, ordinal_suffix(n))
	return
}

/*
ordinal formats `n` with its English ordinal suffix, such as "1st", "22nd" or
"113th".

Inputs:
- n: the number to format.
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.
*/
ordinal :: proc(n: i64, allocator := context.allocator, loc := #caller_location) -> (s: string, err: runtime.Allocator_Error) {
	buf: [32]byte
	sb := strings.builder_from_bytes(buf[:])
	write_ordinal(&sb, n)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

/*
write_comma appends `n` to `b` with its digits grouped in threes, such as
"1,234,567" or "-9,876". Pass another `sep`, such as '.', ' ' or '_', for
other conventions.

Returns:
- written: the number of bytes appended to `b`.
*/
write_comma :: proc(b: ^strings.Builder, n: i64, sep := ',') -> (written: int) {
	if n < 0 {
		written += strings.write_byte(b, '-')
	}
	digits: [20]byte
	written += write_grouped(b, strconv.write_uint(digits[:], magnitude(n), 10), sep)
	return
}

/*
comma formats `n` with its digits grouped in threes, such as "1,234,567".

Inputs:
- n: the number to format.
- sep: the group separator.
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.

Example:
	s, _ := humanize.comma(1_234_567)
	defer delete(s)
	// s == "1,234,567"
*/
comma :: proc(n: i64, sep := ',', allocator := context.allocator, loc := #caller_location) -> (s: string, err: runtime.Allocator_Error) {
	buf: [128]byte
	sb := strings.builder_from_bytes(buf[:])
	write_comma(&sb, n, sep)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

/*
write_comma_float appends `f` to `b` rounded to exactly `decimals` places,
with the whole part grouped in threes, such as "1,234,567.89".

`decimals` is clamped to 0 through MAX_DECIMALS. `sep` separates groups and
`point` separates the fraction, so `sep = '.', point = ','` gives the
"1.234,5" form. NaN prints "NaN" and infinities print "Inf" or "-Inf". A
value that rounds to zero prints without a minus sign.

Returns:
- written: the number of bytes appended to `b`.
*/
write_comma_float :: proc(b: ^strings.Builder, f: f64, decimals := 2, sep := ',', point := '.') -> (written: int) {
	switch {
	case math.is_nan(f):
		return strings.write_string(b, "NaN")
	case math.is_inf(f, 1):
		return strings.write_string(b, "Inf")
	case math.is_inf(f, -1):
		return strings.write_string(b, "-Inf")
	}

	places := clamp(decimals, 0, MAX_DECIMALS)
	buf: [512]byte
	text := strconv.write_float(buf[:], f, 'f', places, 64)

	negative := false
	if len(text) > 0 && (text[0] == '-' || text[0] == '+') {
		negative = text[0] == '-'
		text = text[1:]
	}
	whole, frac := text, ""
	if dot := strings.index_byte(text, '.'); dot >= 0 {
		whole, frac = text[:dot], text[dot + 1:]
	}

	if negative && strings.trim_left(whole, "0") == "" && strings.trim_left(frac, "0") == "" {
		negative = false
	}
	if negative {
		written += strings.write_byte(b, '-')
	}
	written += write_grouped(b, whole, sep)
	if len(frac) > 0 {
		n, _ := strings.write_rune(b, point)
		written += n
		written += strings.write_string(b, frac)
	}
	return
}

/*
comma_float formats `f` rounded to `decimals` places with its whole part
grouped in threes, such as "1,234,567.89". See write_comma_float for the
separators and special values.

Inputs:
- f: the number to format.
- decimals: the decimal places to print, clamped to 0 through MAX_DECIMALS.
- sep: the group separator.
- point: the decimal separator.
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.
*/
comma_float :: proc(
	f: f64,
	decimals := 2,
	sep := ',',
	point := '.',
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	s: string,
	err: runtime.Allocator_Error,
) {
	buf: [1024]byte
	sb := strings.builder_from_bytes(buf[:])
	write_comma_float(&sb, f, decimals, sep, point)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

// write_grouped appends the ASCII digits in `digits`, putting `sep` before every group of three from the right.
@(private = "file")
write_grouped :: proc(b: ^strings.Builder, digits: string, sep: rune) -> (written: int) {
	lead := len(digits) % 3
	if lead == 0 {
		lead = 3
	}
	written += strings.write_string(b, digits[:min(lead, len(digits))])
	for i := lead; i < len(digits); i += 3 {
		n, _ := strings.write_rune(b, sep)
		written += n
		written += strings.write_string(b, digits[i:i + 3])
	}
	return
}
