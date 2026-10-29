// Example basic shows every humanize formatter and parser. Run it with `odin run examples/basic`.
package main

import humanize "../.."
import "core:fmt"
import "core:os"
import "core:strings"
import "core:time"

main :: proc() {
	// Allocating formatters return a string that the caller frees.
	size, err := humanize.bytes(82_854_982)
	if err != nil {
		fmt.eprintln("bytes failed:", err)
		os.exit(1)
	}
	defer delete(size)
	fmt.println("download:", size)

	// The write_ forms append to one builder, so a whole line costs one buffer.
	sb := strings.builder_make()
	defer strings.builder_destroy(&sb)

	now := time.now()
	strings.write_string(&sb, "backup: ")
	humanize.write_bytes(&sb, 5 << 30, .IEC)
	strings.write_string(&sb, " in ")
	humanize.write_duration(&sb, 90 * time.Minute, style = .Long)
	strings.write_string(&sb, ", finished ")
	humanize.write_relative_time(&sb, time.time_add(now, -3 * time.Minute), now)
	fmt.println(strings.to_string(sb))

	strings.builder_reset(&sb)
	humanize.write_ordinal(&sb, 22)
	strings.write_string(&sb, " of ")
	humanize.write_comma(&sb, 1_234_567)
	strings.write_string(&sb, " runners, total distance ")
	humanize.write_comma_float(&sb, 1234.5678, 2)
	strings.write_string(&sb, " km")
	fmt.println(strings.to_string(sb))

	// Parsers never allocate and report problems as a Parse_Error.
	limit, perr := humanize.parse_bytes("10MB")
	fmt.println("parse_bytes(\"10MB\") =", limit, perr)

	timeout, derr := humanize.parse_duration("1h30m")
	fmt.println("parse_duration(\"1h30m\") =", timeout, derr)

	_, bad := humanize.parse_duration("1h30")
	fmt.println("parse_duration(\"1h30\") fails with", bad)
}
