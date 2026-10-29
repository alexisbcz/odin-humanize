# humanize

[![CI](https://github.com/alexisbcz/odin-humanize/actions/workflows/ci.yml/badge.svg)](https://github.com/alexisbcz/odin-humanize/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Odin](https://img.shields.io/badge/Odin-dev--2026--09-1e5a99.svg)](https://odin-lang.org)

Human-friendly formatting for Odin: byte sizes in SI and IEC units, durations, relative times such as "3 minutes ago", ordinals and grouped digits, plus parsers that turn "10MB" and "1h30m" back into values.

## Install

The repository root is the package, so you can vendor it in two ways.

As a Git submodule inside your project:

```sh
git submodule add https://github.com/alexisbcz/odin-humanize libs/humanize
```

```odin
import "libs/humanize"
```

As a copy in a shared collection that all your projects use:

```sh
git clone https://github.com/alexisbcz/odin-humanize ~/odin-shared/humanize
odin build . -collection:shared=$HOME/odin-shared
```

```odin
import "shared:humanize"
```

## Quick start

```odin
package main

import "core:fmt"
import "shared:humanize"

main :: proc() {
	size, err := humanize.bytes(82_854_982)
	if err != nil {
		fmt.eprintln("bytes failed:", err)
		return
	}
	defer delete(size)
	fmt.println(size) // 82.9 MB

	limit, perr := humanize.parse_bytes("10MB")
	fmt.println(limit, perr) // 10000000 None

	timeout, derr := humanize.parse_duration("1h30m")
	fmt.println(timeout, derr) // 1h30m0s None
}
```

Every formatter also has a `write_` form that appends to a `strings.Builder`, so a log line with several values needs one buffer:

```odin
sb := strings.builder_make()
defer strings.builder_destroy(&sb)

now := time.now()
humanize.write_bytes(&sb, 5 << 30, .IEC)
strings.write_string(&sb, " in ")
humanize.write_duration(&sb, 90 * time.Minute, style = .Long)
strings.write_string(&sb, ", finished ")
humanize.write_relative_time(&sb, time.time_add(now, -3 * time.Minute), now)
fmt.println(strings.to_string(sb)) // 5 GiB in 1 hour 30 minutes, finished 3 minutes ago
```

## API overview

| Declaration | Purpose | Allocates | Free with |
| --- | --- | --- | --- |
| `bytes(n, standard, decimals, allocator)` | Format a size: `82.9 MB`, `1.5 KiB` | Yes | `delete` |
| `parse_bytes(s)` | Read `10MB`, `1.5 GiB`, `1,024 kB` | No | Not needed |
| `duration(d, max_units, style, allocator)` | Format `1h30m` or `1 hour 30 minutes` | Yes | `delete` |
| `parse_duration(s)` | Read `1h30m`, `1.5h`, `2 days and 4 hours` | No | Not needed |
| `relative_time(t, now, allocator)` | Format `3 minutes ago` or `in 2 hours` | Yes | `delete` |
| `time_ago(t, allocator)` | `relative_time` against `time.now()` | Yes | `delete` |
| `ordinal(n, allocator)` | Format `1st`, `22nd`, `113th` | Yes | `delete` |
| `ordinal_suffix(n)` | Return `st`, `nd`, `rd` or `th` | No | Not needed |
| `comma(n, sep, allocator)` | Format `1,234,567` | Yes | `delete` |
| `comma_float(f, decimals, sep, point, allocator)` | Format `1,234.57` or `1.234,57` | Yes | `delete` |
| `write_bytes`, `write_duration`, `write_relative_time`, `write_ordinal`, `write_comma`, `write_comma_float` | Append to a `strings.Builder` | Only when the builder grows | `strings.builder_destroy` |
| `Byte_Standard` | `.SI` for powers of 1000, `.IEC` for powers of 1024 | No | Not needed |
| `Duration_Style` | `.Short` for `1h30m`, `.Long` for spelled-out units | No | Not needed |
| `Parse_Error` | `.Empty`, `.Invalid_Number`, `.Missing_Unit`, `.Unknown_Unit`, `.Overflow` | No | Not needed |

### Formatting rules

- **Bytes** below 1000, or 1024 for IEC, print as whole bytes: `512 B`. Larger sizes round half up to `decimals` places, default 1, and drop trailing zeros. Rounding that reaches the next unit moves to it, so 999,999 prints `1 MB`.
- **Durations** start at the largest unit that isn't zero and cover `max_units` consecutive units, default 2. They truncate the rest and leave out zero units: 1h0m45s prints `1h`, and `1h45s` with `max_units = 3`.
- **Relative times** truncate to the largest unit that fits. Under one second prints `now`, a month counts as 30 days and a year as 365 days.
- **Parsing** ignores case and surrounding whitespace. `kB` means 1000 and `KiB` means 1024. Durations accept `ns`, `us` or `µs`, `ms`, `s`, `m`, `h`, `d` and `w`, spelled-out names, fractions such as `1.5h`, and a sign.

## Examples

Each directory under `examples/` is a runnable program:

```sh
odin run examples/basic
```

## Design notes

- Every allocating procedure takes `allocator := context.allocator` and returns a string that the caller frees with `delete`.
- Formatters build into a stack buffer and allocate once for the result. Parsers never allocate.
- Byte rounding and parsing use exact integer arithmetic, so `1.5 GiB` is exactly 1,610,612,736 bytes and nothing wraps silently: values that don't fit return `.Overflow`.
- The library never panics on bad input and keeps no global mutable state, so it's safe to use from several threads at once.

## Testing

```sh
odin check . -vet -strict-style -disallow-do -no-entry-point
odin test tests -vet -strict-style -disallow-do
vale sync && vale *.md
```

Every test runs under a tracking allocator and fails if it leaks.

## Contributing

Read [CONTRIBUTING.md](CONTRIBUTING.md). Commits follow Conventional Commits, and every change that users can see gets a line in [CHANGELOG.md](CHANGELOG.md).

## License

MIT. See [LICENSE](LICENSE).
