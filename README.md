# Calendar Mesh Sync

A robust, Swift-based command-line tool for macOS that synchronizes events across multiple user-selected calendars. It implements a "mesh" synchronization strategy, ensuring that events are replicated across all selected calendars while preserving the "True Source" of each event.

## Features

*   **Mesh Synchronization**: Replicates events across all selected calendars.
*   **Source Protection**: Identifies the original "Source" of an event and protects it from being overwritten by changes to copies.
*   **One-Way Sync Logic**: Updates flow from Source -> Copies. Deletions of the Source propagate to Copies. Deletions of a Copy result in the Copy being resurrected (to maintain the mesh).
*   **Metadata Injection**: Adds a "Sync Metadata" section to the notes of copied events, indicating the Source Calendar and Participants.
*   **De-duplication**: Uses fuzzy matching (Title + Start Time) to link existing events and prevent duplicates.
*   **Headless Mode**: Supports a `config.json` file for automated, zero-touch execution (e.g., via `cron` or `launchd`).
*   **Self-Healing**: Automatically repairs broken links or missing copies.
*   **Pruning**: Automatically prunes internal state and logs older than 1 month to keep file sizes manageable.

## Prerequisites

*   macOS (Requires `EventKit` framework)
*   Swift 5.5+ installed

## Installation

1.  Clone the repository:
    ```bash
    git clone <repository-url>
    cd CalendarSync
    ```

2.  Build the project:
    ```bash
    swift build -c release
    ```

## Usage

### Interactive Mode (First Run)

Run the tool directly:

```bash
swift run
```

On the first run, the tool will:
1.  Request access to your Calendars.
2.  List available calendars.
3.  Ask you to select which calendars to synchronize (enter IDs separated by commas).
4.  Ask if you want to save this selection to `config.json` for future headless runs.

### Headless Mode (Automation)

If a `config.json` file exists in the working directory (created during the interactive run), the tool will run automatically without user intervention.

To run it as a scheduled job, you can use the built binary:

```bash
.build/release/CalendarSync
```

### Configuration

The tool uses a configuration file located at `~/.calendarsync/config.json`.

```json
{
  "selectedCalendarIds": [
    "calendar-id-1",
    "calendar-id-2"
  ]
}
```

### Logs & State

All data is stored in `~/.calendarsync/`:

*   **`calendar_state.json`**: Stores the mapping between events across calendars. **Do not edit this manually.**
*   **`sync_log.json`**: Structured JSON logs of all operations. Rotated automatically (logs > 1 month old are pruned).
*   **`backups/`**: Automatic backups of the state file are kept here.

## License

GPLv3 - for details see [LICENSE](LICENSE)
