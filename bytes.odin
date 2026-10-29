package humanize

import "base:runtime"
import "core:strings"

// Byte_Standard picks the unit family that bytes and write_bytes use.
Byte_Standard :: enum {
	// SI units are powers of 1000: kB, MB, GB, TB, PB and EB.
	SI,
	// IEC units are powers of 1024: KiB, MiB, GiB, TiB, PiB and EiB.
	IEC,
}

@(private = "file", rodata)
SI_UNITS := [?]string{"B", "kB", "MB", "GB", "TB", "PB", "EB"}

@(private = "file", rodata)
IEC_UNITS := [?]string{"B", "KiB", "MiB", "GiB", "TiB", "PiB", "EiB"}

/*
write_bytes appends a size such as "1.5 kB" or "3 MiB" to `b`.

Sizes below one kilobyte print as a whole number of bytes, such as "512 B".
Larger sizes use the biggest unit that keeps the number at or above 1, round
half up to `decimals` places and drop trailing zeros, so 1000 prints "1 kB"
and 1500 prints "1.5 kB". When rounding reaches the next unit, the next unit
wins: 999,999 prints "1 MB", not "1000 kB".

Inputs:
- b: the builder to append to.
- n: the size in bytes.
- standard: `.SI` for powers of 1000, `.IEC` for powers of 1024.
- decimals: the most decimal places to print, clamped to 0 through MAX_DECIMALS.

Returns:
- written: the number of bytes appended to `b`.
*/
write_bytes :: proc(b: ^strings.Builder, n: u64, standard := Byte_Standard.SI, decimals := 1) -> (written: int) {
	base: u64 = 1000 if standard == .SI else 1024
	units := SI_UNITS[:] if standard == .SI else IEC_UNITS[:]

	if n < base {
		written += strings.write_u64(b, n)
		written += strings.write_string(b, " B")
		return
	}

	places := clamp(decimals, 0, MAX_DECIMALS)
	pow10 := POW10[places]

	exp := 1
	div := base
	for exp < len(units) - 1 && n / div >= base {
		div *= base
		exp += 1
	}

	scaled := round_div(n, pow10, div)
	if scaled >= u128(base) * u128(pow10) && exp < len(units) - 1 {
		div *= base
		exp += 1
		scaled = round_div(n, pow10, div)
	}

	written += write_fixed(b, scaled, pow10, places)
	written += strings.write_byte(b, ' ')
	written += strings.write_string(b, units[exp])
	return
}

/*
bytes formats a size such as "1.5 kB" or "3 MiB". See write_bytes for the
rounding rules.

Inputs:
- n: the size in bytes.
- standard: `.SI` for powers of 1000, `.IEC` for powers of 1024.
- decimals: the most decimal places to print, clamped to 0 through MAX_DECIMALS.
- allocator: allocates the result.

Returns:
- s: a new string owned by the caller; free it with `delete(s, allocator)`.
- err: an allocator error, or `nil`.

Example:
	s, _ := humanize.bytes(1_572_864, .IEC)
	defer delete(s)
	// s == "1.5 MiB"
*/
bytes :: proc(
	n: u64,
	standard := Byte_Standard.SI,
	decimals := 1,
	allocator := context.allocator,
	loc := #caller_location,
) -> (
	s: string,
	err: runtime.Allocator_Error,
) {
	buf: [64]byte
	sb := strings.builder_from_bytes(buf[:])
	write_bytes(&sb, n, standard, decimals)
	return strings.clone(strings.to_string(sb), allocator, loc)
}

/*
parse_bytes reads a size such as "10MB", "1.5 GiB", "1,024 kB" or "512" and
returns it in bytes.

Units are case-insensitive. "k", "kB" and "kilobytes" mean 1000; "Ki", "KiB"
and "kibibytes" mean 1024, and likewise for M, G, T, P and E. A bare number,
"B", "byte" or "bytes" means bytes. Whitespace may surround the number and the
unit. Commas may group the whole part in threes, as in "1,024,000"; any other
comma, such as the decimal comma in "1,5 MB", is `.Invalid_Number` rather than
a silent 15 MB. Fractions of a byte are dropped, so "1.5 B" is 1.

Returns:
- n: the size in bytes.
- err: `.Empty`, `.Invalid_Number` (including any sign or misplaced comma),
  `.Unknown_Unit`, `.Overflow` when the size exceeds `max(u64)`, or `.None`.
*/
parse_bytes :: proc(s: string) -> (n: u64, err: Parse_Error) {
	text := strings.trim_space(s)
	if len(text) == 0 {
		return 0, .Empty
	}

	d, rest, derr := scan_decimal(text, true)
	if derr != .None {
		return 0, derr
	}

	unit := strings.trim_left_space(rest)
	if starts_like_number(unit) {
		return 0, .Invalid_Number
	}
	mult, ok := byte_unit_size(unit)
	if !ok {
		return 0, .Unknown_Unit
	}

	v := decimal_scale(d, mult)
	if v > u128(max(u64)) {
		return 0, .Overflow
	}
	return u64(v), .None
}

@(private = "file")
Byte_Unit :: struct {
	name: string,
	size: u64,
}

@(private = "file", rodata)
BYTE_UNITS := [?]Byte_Unit {
	{"", 1},
	{"b", 1},
	{"byte", 1},
	{"bytes", 1},
	{"k", 1e3},
	{"kb", 1e3},
	{"kilobyte", 1e3},
	{"kilobytes", 1e3},
	{"ki", 1 << 10},
	{"kib", 1 << 10},
	{"kibibyte", 1 << 10},
	{"kibibytes", 1 << 10},
	{"m", 1e6},
	{"mb", 1e6},
	{"megabyte", 1e6},
	{"megabytes", 1e6},
	{"mi", 1 << 20},
	{"mib", 1 << 20},
	{"mebibyte", 1 << 20},
	{"mebibytes", 1 << 20},
	{"g", 1e9},
	{"gb", 1e9},
	{"gigabyte", 1e9},
	{"gigabytes", 1e9},
	{"gi", 1 << 30},
	{"gib", 1 << 30},
	{"gibibyte", 1 << 30},
	{"gibibytes", 1 << 30},
	{"t", 1e12},
	{"tb", 1e12},
	{"terabyte", 1e12},
	{"terabytes", 1e12},
	{"ti", 1 << 40},
	{"tib", 1 << 40},
	{"tebibyte", 1 << 40},
	{"tebibytes", 1 << 40},
	{"p", 1e15},
	{"pb", 1e15},
	{"petabyte", 1e15},
	{"petabytes", 1e15},
	{"pi", 1 << 50},
	{"pib", 1 << 50},
	{"pebibyte", 1 << 50},
	{"pebibytes", 1 << 50},
	{"e", 1e18},
	{"eb", 1e18},
	{"exabyte", 1e18},
	{"exabytes", 1e18},
	{"ei", 1 << 60},
	{"eib", 1 << 60},
	{"exbibyte", 1 << 60},
	{"exbibytes", 1 << 60},
}

@(private = "file")
byte_unit_size :: proc(unit: string) -> (size: u64, ok: bool) {
	for u in BYTE_UNITS {
		if strings.equal_fold(unit, u.name) {
			return u.size, true
		}
	}
	return 0, false
}

// round_div returns n * pow10 / div rounded half up, computed exactly.
@(private = "file")
round_div :: proc "contextless" (n, pow10, div: u64) -> u128 {
	return (u128(n) * u128(pow10) * 2 + u128(div)) / (u128(div) * 2)
}

/*
write_fixed appends `scaled / pow10` with up to `places` decimals, dropping
trailing zeros and the decimal point when the fraction is zero.
*/
@(private = "file")
write_fixed :: proc(b: ^strings.Builder, scaled: u128, pow10: u64, places: int) -> (written: int) {
	whole := u64(scaled / u128(pow10))
	frac := u64(scaled % u128(pow10))
	written += strings.write_u64(b, whole)
	if frac == 0 {
		return
	}
	digits := places
	for frac % 10 == 0 {
		frac /= 10
		digits -= 1
	}
	written += strings.write_byte(b, '.')
	for p := POW10[digits - 1]; p > 1 && frac < p; p /= 10 {
		written += strings.write_byte(b, '0')
	}
	written += strings.write_u64(b, frac)
	return
}
