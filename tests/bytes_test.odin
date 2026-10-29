package humanize_tests

import humanize ".."
import "core:mem"
import "core:strings"
import "core:testing"

// expect_bytes formats `n` with a tracking allocator and checks the text and that nothing leaks.
expect_bytes :: proc(
	t: ^testing.T,
	n: u64,
	want: string,
	standard := humanize.Byte_Standard.SI,
	decimals := 1,
	loc := #caller_location,
) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.bytes(n, standard, decimals, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

// expect_parse_bytes checks that parse_bytes(text) returns `want` with no error.
expect_parse_bytes :: proc(t: ^testing.T, text: string, want: u64, loc := #caller_location) {
	got, err := humanize.parse_bytes(text)
	testing.expectf(t, err == .None, "parse_bytes(%q) failed: %v", text, err, loc = loc)
	testing.expectf(t, got == want, "parse_bytes(%q): got %d, want %d", text, got, want, loc = loc)
}

// expect_parse_bytes_error checks that parse_bytes(text) fails with exactly `want`.
expect_parse_bytes_error :: proc(t: ^testing.T, text: string, want: humanize.Parse_Error, loc := #caller_location) {
	got, err := humanize.parse_bytes(text)
	testing.expectf(t, err == want, "parse_bytes(%q): got error %v, want %v", text, err, want, loc = loc)
	testing.expectf(t, got == 0, "parse_bytes(%q) returned %d alongside an error", text, got, loc = loc)
}

@(test)
test_bytes_below_one_kilobyte :: proc(t: ^testing.T) {
	expect_bytes(t, 0, "0 B")
	expect_bytes(t, 1, "1 B")
	expect_bytes(t, 999, "999 B")
	expect_bytes(t, 1023, "1023 B", .IEC)
}

@(test)
test_bytes_si_units :: proc(t: ^testing.T) {
	expect_bytes(t, 1000, "1 kB")
	expect_bytes(t, 1500, "1.5 kB")
	expect_bytes(t, 82_854_982, "82.9 MB")
	expect_bytes(t, 1_000_000_000, "1 GB")
	expect_bytes(t, 3_200_000_000_000, "3.2 TB")
	expect_bytes(t, 1_000_000_000_000_000, "1 PB")
}

@(test)
test_bytes_iec_units :: proc(t: ^testing.T) {
	expect_bytes(t, 1024, "1 KiB", .IEC)
	expect_bytes(t, 1536, "1.5 KiB", .IEC)
	expect_bytes(t, 1 << 20, "1 MiB", .IEC)
	expect_bytes(t, 1_572_864, "1.5 MiB", .IEC)
	expect_bytes(t, 5 << 30, "5 GiB", .IEC)
	expect_bytes(t, 1 << 40, "1 TiB", .IEC)
}

@(test)
test_bytes_rounds_half_up :: proc(t: ^testing.T) {
	expect_bytes(t, 1050, "1.1 kB")
	expect_bytes(t, 1049, "1 kB")
	expect_bytes(t, 1250, "1.3 kB")
	expect_bytes(t, 1_250_000, "1 MB", decimals = 0)
	expect_bytes(t, 1_500_000, "2 MB", decimals = 0)
}

@(test)
test_bytes_rolls_over_to_next_unit :: proc(t: ^testing.T) {
	expect_bytes(t, 999_949, "999.9 kB")
	expect_bytes(t, 999_950, "1 MB")
	expect_bytes(t, 999_999, "1 MB")
	expect_bytes(t, 1_048_575, "1 MiB", .IEC)
	expect_bytes(t, 999_500, "1 MB", decimals = 0)
}

@(test)
test_bytes_decimal_places :: proc(t: ^testing.T) {
	expect_bytes(t, 1_234_567, "1 MB", decimals = 0)
	expect_bytes(t, 1_234_567, "1.23 MB", decimals = 2)
	expect_bytes(t, 1_234_567, "1.235 MB", decimals = 3)
	expect_bytes(t, 1_005_000, "1.005 MB", decimals = 3)
	expect_bytes(t, 1_050_000, "1.05 MB", decimals = 3)
}

@(test)
test_bytes_clamps_decimals :: proc(t: ^testing.T) {
	expect_bytes(t, 1_234_567, "1 MB", decimals = -5)
	expect_bytes(t, 1_234_567_891, "1.234567891 GB", decimals = 99)
}

@(test)
test_bytes_largest_value :: proc(t: ^testing.T) {
	expect_bytes(t, max(u64), "18.4 EB")
	expect_bytes(t, max(u64), "16 EiB", .IEC)
	expect_bytes(t, max(u64), "18.446744074 EB", decimals = 9)
}

@(test)
test_write_bytes_appends_to_builder :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	sb := strings.builder_make(alloc)
	defer strings.builder_destroy(&sb)
	strings.write_string(&sb, "size=")
	n := humanize.write_bytes(&sb, 1536, .IEC)
	testing.expect_value(t, n, len("1.5 KiB"))
	testing.expect_value(t, strings.to_string(sb), "size=1.5 KiB")
}

@(test)
test_bytes_reports_allocator_error :: proc(t: ^testing.T) {
	s, err := humanize.bytes(1500, allocator = failing_allocator())
	testing.expect_value(t, err, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, s, "")
}

@(test)
test_parse_bytes_plain_numbers :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "0", 0)
	expect_parse_bytes(t, "512", 512)
	expect_parse_bytes(t, "512B", 512)
	expect_parse_bytes(t, "512 bytes", 512)
	expect_parse_bytes(t, "1 byte", 1)
}

@(test)
test_parse_bytes_si_units :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "10MB", 10_000_000)
	expect_parse_bytes(t, "1kB", 1000)
	expect_parse_bytes(t, "1 k", 1000)
	expect_parse_bytes(t, "2 GB", 2_000_000_000)
	expect_parse_bytes(t, "1 TB", 1_000_000_000_000)
	expect_parse_bytes(t, "1PB", 1_000_000_000_000_000)
	expect_parse_bytes(t, "1EB", 1_000_000_000_000_000_000)
}

@(test)
test_parse_bytes_iec_units :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "1KiB", 1024)
	expect_parse_bytes(t, "1.5 GiB", 1_610_612_736)
	expect_parse_bytes(t, "2 Mi", 2 << 20)
	expect_parse_bytes(t, "3 TiB", 3 << 40)
	expect_parse_bytes(t, "1 PiB", 1 << 50)
	expect_parse_bytes(t, "1 EiB", 1 << 60)
}

@(test)
test_parse_bytes_ignores_case :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "10mb", 10_000_000)
	expect_parse_bytes(t, "10Mb", 10_000_000)
	expect_parse_bytes(t, "1kib", 1024)
	expect_parse_bytes(t, "1KIB", 1024)
	expect_parse_bytes(t, "4 BYTES", 4)
}

@(test)
test_parse_bytes_fractions :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "1.5kB", 1500)
	expect_parse_bytes(t, ".5 KiB", 512)
	expect_parse_bytes(t, "1. kB", 1000)
	expect_parse_bytes(t, "0.001 kB", 1)
	expect_parse_bytes(t, "1.5 B", 1)
	expect_parse_bytes(t, "0.0000000000000000000001 EB", 0)
}

@(test)
test_parse_bytes_whitespace_and_grouping :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "  10 MB  ", 10_000_000)
	expect_parse_bytes(t, "\t64\tKiB\n", 64 << 10)
	expect_parse_bytes(t, "1,024 kB", 1_024_000)
	expect_parse_bytes(t, "1,000,000", 1_000_000)
}

@(test)
test_parse_bytes_spelled_out_units :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "3 megabytes", 3_000_000)
	expect_parse_bytes(t, "1 kibibyte", 1024)
	expect_parse_bytes(t, "2 Gigabytes", 2_000_000_000)
	expect_parse_bytes(t, "1 exbibyte", 1 << 60)
}

@(test)
test_parse_bytes_rejects_empty_input :: proc(t: ^testing.T) {
	expect_parse_bytes_error(t, "", .Empty)
	expect_parse_bytes_error(t, "   ", .Empty)
	expect_parse_bytes_error(t, "\t\n", .Empty)
}

@(test)
test_parse_bytes_rejects_malformed_numbers :: proc(t: ^testing.T) {
	expect_parse_bytes_error(t, "MB", .Invalid_Number)
	expect_parse_bytes_error(t, "-5MB", .Invalid_Number)
	expect_parse_bytes_error(t, "+5MB", .Invalid_Number)
	expect_parse_bytes_error(t, ".", .Invalid_Number)
	expect_parse_bytes_error(t, ".MB", .Invalid_Number)
	expect_parse_bytes_error(t, "1..5MB", .Invalid_Number)
	expect_parse_bytes_error(t, "1.2.3 MB", .Invalid_Number)
	expect_parse_bytes_error(t, ",5 MB", .Invalid_Number)
	expect_parse_bytes_error(t, "1 2 MB", .Invalid_Number)
}

@(test)
test_parse_bytes_rejects_unknown_units :: proc(t: ^testing.T) {
	expect_parse_bytes_error(t, "10 parsecs", .Unknown_Unit)
	expect_parse_bytes_error(t, "10 MBs", .Unknown_Unit)
	expect_parse_bytes_error(t, "10 M B", .Unknown_Unit)
	expect_parse_bytes_error(t, "5 kB!", .Unknown_Unit)
	expect_parse_bytes_error(t, "5 ZB", .Unknown_Unit)
}

@(test)
test_parse_bytes_detects_overflow :: proc(t: ^testing.T) {
	expect_parse_bytes(t, "18446744073709551615", max(u64))
	expect_parse_bytes(t, "15.999 EiB", 18_445_591_152_204_944_769)
	expect_parse_bytes_error(t, "18446744073709551616", .Overflow)
	expect_parse_bytes_error(t, "19 EB", .Overflow)
	expect_parse_bytes_error(t, "16 EiB", .Overflow)
	expect_parse_bytes_error(t, "99999999999999999999999 B", .Overflow)
}

@(test)
test_bytes_round_trip :: proc(t: ^testing.T) {
	Case :: struct {
		n:        u64,
		standard: humanize.Byte_Standard,
	}
	cases := [?]Case{{0, .SI}, {999, .SI}, {1000, .SI}, {2_500_000, .SI}, {1536, .IEC}, {5 << 30, .IEC}, {1 << 60, .IEC}}

	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	for c in cases {
		text, ferr := humanize.bytes(c.n, c.standard, humanize.MAX_DECIMALS, alloc)
		testing.expect_value(t, ferr, mem.Allocator_Error.None)
		back, perr := humanize.parse_bytes(text)
		testing.expectf(t, perr == .None && back == c.n, "%d -> %q -> %d (%v)", c.n, text, back, perr)
		delete(text, alloc)
	}
}

@(test)
test_parse_bytes_rejects_misplaced_grouping :: proc(t: ^testing.T) {
	// A decimal comma, as in "1,5 MB", must not silently read as 15 MB.
	expect_parse_bytes_error(t, "1,5 MB", .Invalid_Number)
	expect_parse_bytes_error(t, "1,5", .Invalid_Number)
	expect_parse_bytes_error(t, "1,0000 B", .Invalid_Number)
	expect_parse_bytes_error(t, "12,34,567", .Invalid_Number)
	expect_parse_bytes_error(t, "1234,567", .Invalid_Number)
	expect_parse_bytes_error(t, "1,024,5 kB", .Invalid_Number)
	expect_parse_bytes_error(t, "1,02.5 kB", .Invalid_Number)
	expect_parse_bytes(t, "999,999,999", 999_999_999)
	expect_parse_bytes(t, "12,345 B", 12_345)
	expect_parse_bytes(t, "1,024.5 kB", 1_024_500)
}
