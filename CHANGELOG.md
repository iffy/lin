# v0.7.0 - 2025-09-04

- **NEW:** Use `nim r` rather than `nim c -r` to avoid polluting things with built binaries

# v0.6.0 - 2025-08-13

- **NEW:** Fold output in Github Actions

# v0.5.3 - 2025-08-13

- **FIX:** stdout and stderr are flushed after each step to avoid step output mixing.

# v0.5.2 - 2023-02-17

- **FIX:** Enable --threads:on by default

# v0.5.1 - 2023-02-17

- **FIX:** Don't require threads on unless you capture output

# v0.5.0 - 2023-02-17

- **NEW:** Add `shout`, `sherr` and `shouterr` for getting command output
- **NEW:** Add Changelog

