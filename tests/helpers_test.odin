// Package humanize_tests holds the unit tests for humanize. Run them with `odin test tests`.
package humanize_tests

import "base:runtime"
import "core:mem"
import "core:testing"

// tracker_begin starts a tracking allocator on top of the test's allocator and returns it.
tracker_begin :: proc(track: ^mem.Tracking_Allocator) -> mem.Allocator {
	mem.tracking_allocator_init(track, context.allocator)
	return mem.tracking_allocator(track)
}

// tracker_end fails the test when `track` still holds allocations or saw bad frees, then destroys it.
tracker_end :: proc(t: ^testing.T, track: ^mem.Tracking_Allocator, loc := #caller_location) {
	testing.expectf(t, len(track.allocation_map) == 0, "leaked %d allocation(s)", len(track.allocation_map), loc = loc)
	testing.expectf(t, len(track.bad_free_array) == 0, "%d bad free(s)", len(track.bad_free_array), loc = loc)
	mem.tracking_allocator_destroy(track)
}

/*
expect_owned checks one allocating formatter result: no error, the wanted
text, and exactly one live allocation that `delete` releases.
*/
expect_owned :: proc(
	t: ^testing.T,
	track: ^mem.Tracking_Allocator,
	got: string,
	err: runtime.Allocator_Error,
	want: string,
	loc := #caller_location,
) {
	testing.expect_value(t, err, runtime.Allocator_Error.None, loc = loc)
	testing.expectf(t, got == want, "got %q, want %q", got, want, loc = loc)
	testing.expectf(t, len(track.allocation_map) == 1, "want 1 live allocation, have %d", len(track.allocation_map), loc = loc)
	delete(got, mem.tracking_allocator(track))
}

// failing_allocator refuses every allocation with `.Out_Of_Memory`.
failing_allocator :: proc() -> mem.Allocator {
	fail :: proc(
		data: rawptr,
		mode: mem.Allocator_Mode,
		size, alignment: int,
		old_memory: rawptr,
		old_size: int,
		loc := #caller_location,
	) -> (
		[]byte,
		mem.Allocator_Error,
	) {
		#partial switch mode {
		case .Alloc, .Alloc_Non_Zeroed, .Resize, .Resize_Non_Zeroed:
			return nil, .Out_Of_Memory
		}
		return nil, nil
	}
	return {procedure = fail, data = nil}
}
