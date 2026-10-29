package humanize_tests

import humanize ".."
import "core:math"
import "core:mem"
import "core:strings"
import "core:testing"

// expect_ordinal formats `n` with a tracking allocator and checks the text and that nothing leaks.
expect_ordinal :: proc(t: ^testing.T, n: i64, want: string, loc := #caller_location) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.ordinal(n, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

// expect_comma formats `n` with a tracking allocator and checks the text and that nothing leaks.
expect_comma :: proc(t: ^testing.T, n: i64, want: string, sep := ',', loc := #caller_location) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.comma(n, sep, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

// expect_comma_float formats `f` with a tracking allocator and checks the text and that nothing leaks.
expect_comma_float :: proc(
	t: ^testing.T,
	f: f64,
	want: string,
	decimals := 2,
	sep := ',',
	point := '.',
	loc := #caller_location,
) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	got, err := humanize.comma_float(f, decimals, sep, point, alloc)
	expect_owned(t, &track, got, err, want, loc)
	tracker_end(t, &track, loc)
}

@(test)
test_ordinal_regular_suffixes :: proc(t: ^testing.T) {
	expect_ordinal(t, 0, "0th")
	expect_ordinal(t, 1, "1st")
	expect_ordinal(t, 2, "2nd")
	expect_ordinal(t, 3, "3rd")
	expect_ordinal(t, 4, "4th")
	expect_ordinal(t, 10, "10th")
	expect_ordinal(t, 21, "21st")
	expect_ordinal(t, 22, "22nd")
	expect_ordinal(t, 23, "23rd")
	expect_ordinal(t, 101, "101st")
	expect_ordinal(t, 1000, "1000th")
}

@(test)
test_ordinal_teens_take_th :: proc(t: ^testing.T) {
	expect_ordinal(t, 11, "11th")
	expect_ordinal(t, 12, "12th")
	expect_ordinal(t, 13, "13th")
	expect_ordinal(t, 111, "111th")
	expect_ordinal(t, 112, "112th")
	expect_ordinal(t, 1013, "1013th")
}

@(test)
test_ordinal_negative_and_extremes :: proc(t: ^testing.T) {
	expect_ordinal(t, -1, "-1st")
	expect_ordinal(t, -11, "-11th")
	expect_ordinal(t, -22, "-22nd")
	expect_ordinal(t, max(i64), "9223372036854775807th")
	expect_ordinal(t, min(i64), "-9223372036854775808th")
}

@(test)
test_ordinal_suffix_needs_no_allocator :: proc(t: ^testing.T) {
	testing.expect_value(t, humanize.ordinal_suffix(1), "st")
	testing.expect_value(t, humanize.ordinal_suffix(2), "nd")
	testing.expect_value(t, humanize.ordinal_suffix(3), "rd")
	testing.expect_value(t, humanize.ordinal_suffix(13), "th")
	testing.expect_value(t, humanize.ordinal_suffix(-102), "nd")
	testing.expect_value(t, humanize.ordinal_suffix(min(i64)), "th")
}

@(test)
test_comma_groups_digits :: proc(t: ^testing.T) {
	expect_comma(t, 0, "0")
	expect_comma(t, 7, "7")
	expect_comma(t, 999, "999")
	expect_comma(t, 1000, "1,000")
	expect_comma(t, 100_000, "100,000")
	expect_comma(t, 1_234_567, "1,234,567")
}

@(test)
test_comma_negative_and_extremes :: proc(t: ^testing.T) {
	expect_comma(t, -999, "-999")
	expect_comma(t, -1234, "-1,234")
	expect_comma(t, max(i64), "9,223,372,036,854,775,807")
	expect_comma(t, min(i64), "-9,223,372,036,854,775,808")
}

@(test)
test_comma_custom_separator :: proc(t: ^testing.T) {
	expect_comma(t, 1_234_567, "1.234.567", '.')
	expect_comma(t, 1_234_567, "1_234_567", '_')
	expect_comma(t, 1_234_567, "1 234 567", ' ')
	expect_comma(t, 1_234_567, "1 234 567", ' ')
}

@(test)
test_comma_float_rounds_to_decimals :: proc(t: ^testing.T) {
	expect_comma_float(t, 1_234_567.891, "1,234,567.89")
	expect_comma_float(t, 1234.5678, "1,235", decimals = 0)
	expect_comma_float(t, 1234.5678, "1,234.568", decimals = 3)
	expect_comma_float(t, 0.5, "0.50")
	expect_comma_float(t, 999.999, "1,000.00")
	expect_comma_float(t, 1, "1.000000000", decimals = 99)
	expect_comma_float(t, 12.34, "12", decimals = -1)
}

@(test)
test_comma_float_signs :: proc(t: ^testing.T) {
	expect_comma_float(t, -1234.5, "-1,234.50")
	expect_comma_float(t, -0.001, "0.00")
	expect_comma_float(t, -0.0, "0.00")
	expect_comma_float(t, -0.006, "-0.01")
}

@(test)
test_comma_float_special_values :: proc(t: ^testing.T) {
	expect_comma_float(t, math.nan_f64(), "NaN")
	expect_comma_float(t, math.inf_f64(1), "Inf")
	expect_comma_float(t, math.inf_f64(-1), "-Inf")
}

@(test)
test_comma_float_european_style :: proc(t: ^testing.T) {
	expect_comma_float(t, 1_234_567.891, "1.234.567,89", sep = '.', point = ',')
	expect_comma_float(t, 1234.5, "1 234,5", decimals = 1, sep = ' ', point = ',')
}

@(test)
test_comma_float_huge_values :: proc(t: ^testing.T) {
	expect_comma_float(t, 1e21, "1,000,000,000,000,000,000,000", decimals = 0)

	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)
	s, err := humanize.comma_float(math.F64_MAX, decimals = humanize.MAX_DECIMALS, sep = ' ', allocator = alloc)
	defer delete(s, alloc)
	testing.expect_value(t, err, mem.Allocator_Error.None)
	testing.expect(t, strings.has_prefix(s, "179 769 313"), "F64_MAX keeps its leading digits")
	testing.expect(t, strings.has_suffix(s, ".000000000"), "F64_MAX keeps every decimal place")
	testing.expect_value(t, strings.count(s, " "), 102)
}

@(test)
test_number_formatters_report_allocator_error :: proc(t: ^testing.T) {
	o, oerr := humanize.ordinal(1, failing_allocator())
	testing.expect_value(t, oerr, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, o, "")

	c, cerr := humanize.comma(1000, allocator = failing_allocator())
	testing.expect_value(t, cerr, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, c, "")

	f, ferr := humanize.comma_float(1000, allocator = failing_allocator())
	testing.expect_value(t, ferr, mem.Allocator_Error.Out_Of_Memory)
	testing.expect_value(t, f, "")
}

@(test)
test_write_procedures_share_one_builder :: proc(t: ^testing.T) {
	track: mem.Tracking_Allocator
	alloc := tracker_begin(&track)
	defer tracker_end(t, &track)

	sb := strings.builder_make(alloc)
	defer strings.builder_destroy(&sb)
	humanize.write_ordinal(&sb, 3)
	strings.write_string(&sb, " place, ")
	humanize.write_comma(&sb, 12_500)
	strings.write_string(&sb, " points, ")
	humanize.write_comma_float(&sb, 98.765, 1)
	strings.write_string(&sb, "%, ")
	humanize.write_bytes(&sb, 2_000_000)
	testing.expect_value(t, strings.to_string(sb), "3rd place, 12,500 points, 98.8%, 2 MB")
}
