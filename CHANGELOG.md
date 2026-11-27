# Changelog

## 0.4.0-horse.1.0

- Added a required standalone timeout in seconds, with zero disabling execution expiry.
- Kept progress and output collection within the configured whole-process deadline.
- Added process-tree cleanup and native interruption handling on Unix and Windows.
- Preserved runtime cleanup under blocked output, closed stdout and early launcher exit.
- Isolated broken-stdout fixtures and added deterministic pipe-lifetime regressions.
- Added required native CI for Linux, macOS and Windows with source-managed protections.
- Added verified four-platform publication with recoverable, immutable release retries.
