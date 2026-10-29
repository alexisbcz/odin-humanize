# Changelog

This file records all notable changes to this project.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-10-29

### Added

- `bytes` and `write_bytes` format sizes in SI (`kB`, `MB`) or IEC (`KiB`, `MiB`) units with exact half-up rounding.
- `parse_bytes` reads sizes such as `10MB`, `1.5 GiB` and `1,024 kB`, and reports overflow.
- `duration` and `write_duration` format durations in short (`1h30m`) or long (`1 hour 30 minutes`) style.
- `parse_duration` reads Go style durations, spelled-out units, days, weeks, fractions and signs.
- `relative_time`, `write_relative_time` and `time_ago` describe moments as `3 minutes ago` or `in 2 hours`.
- `ordinal`, `write_ordinal` and `ordinal_suffix` format `1st`, `22nd` and `113th`.
- `comma`, `write_comma`, `comma_float` and `write_comma_float` group digits with a configurable separator and decimal point.
- `Parse_Error` reports empty input, malformed numbers, missing or unknown units and overflow.

[Unreleased]: https://github.com/alexisbcz/odin-humanize/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/alexisbcz/odin-humanize/releases/tag/v0.1.0
