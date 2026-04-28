# Synapse Commander

A sleek, keyboard-driven dual-pane file manager for macOS. Dark-theme friendly.
Inspired by classics like Norton Commander and Midnight Commander.

<img width="1353" height="987" alt="CleanShot 2026-04-24 at 15 30 48" src="https://github.com/user-attachments/assets/a5cd0065-5cc7-4fa1-9ce5-b1be26e5a5e6" />


## Download

Go to the [Releases](https://github.com/dep/my-commander/releases/latest), download the app, install it.

## Build & Run

Requires Xcode command-line tools and macOS 14+.

```sh
./run.sh
```

The script compiles a release binary, drops it into `Synapse Commander.app/Contents/MacOS/`,
and launches the app. You can also `swift run` directly for development.

## Keyboard Shortcuts

Press `?` inside the app at any time to see this same list as an in-app modal.

### Navigation
| Key | Action |
| --- | --- |
| `Tab` | Switch active pane |
| `↑` / `↓` | Move cursor |
| `PgUp` / `PgDn` | Move cursor by one page |
| `Home` / `⌘↑` | Jump to top |
| `End` / `⌘↓` | Jump to bottom |
| `Enter` | Open directory / open file with default app |
| `Backspace` | Go up one directory |
| `⌘←` | Open cursor directory in left pane |
| `⌘→` | Open cursor directory in right pane |
| `⌘G` | Go to folder by path (supports `~`, absolute, relative; Tab completes) |
| `Ctrl+R` | Reload both panes from disk |

### Selection
| Key | Action |
| --- | --- |
| `Space` | Toggle selection on the cursor row |
| `Shift+↑` / `Shift+↓` | Extend range selection |
| `Shift+PgUp` / `Shift+PgDn` | Extend selection by a page |
| `Shift+Home` / `Shift+End` | Extend selection to top / bottom |
| `⌘A` | Select all |

### File Operations
| Key | Action |
| --- | --- |
| `F2` | Rename cursor row |
| `F5` | Copy selection to the other pane |
| `F6` | Move selection to the other pane |
| `F7` | Create new folder (focused after creation) |
| `⌘O` | Open selection with default app |
| `⌘⌫` | Move selection to Trash (with confirmation) |

### Search & Sort
| Key | Action |
| --- | --- |
| _typing letters_ | Type-ahead: jumps cursor to the first matching entry |
| `Esc` | Cancel type-ahead buffer |
| `Ctrl+1` | Sort by name (press again to reverse) |
| `Ctrl+2` | Sort by size (press again to reverse) |
| `Ctrl+3` | Sort by date (press again to reverse) |

### Favorites
| Key | Action |
| --- | --- |
| `Ctrl+D` | Open the favorites modal |
| _letter/digit inside modal_ | Jump the active pane to that favorite |
| _Add button_ | Add the active pane's current directory |
| _Pencil icon_ | Rename label or shortcut key |
| _Trash icon_ | Remove favorite |

Favorites are persisted to
`~/Library/Application Support/SynapseCommander/favorites.json`.

### Help
| Key | Action |
| --- | --- |
| `?` | Show the keyboard shortcut modal |
| `Esc` | Close modals |

## Features

- **Two panes**, clear visual indication of the active pane.
- **Dark mode** enforced for a consistent look.
- **Type-ahead search** with a small overlay showing the current buffer.
- **Sortable columns** by name, size, or modified date (toggle direction).
- **Finder alias & symlink resolution** — entries that point to directories
  (like virtual Google Drive mounts) are navigated in-app instead of
  handing off to Finder.
- **Favorites** with single-key jump shortcuts.
- **Safe delete** via macOS Trash.
- **Range selection** with Shift-navigation, in addition to individual toggling.

## Project Layout

```
my-commander/
├── Package.swift
├── run.sh                         # build release + install + launch
├── Synapse Commander.app/              # app bundle (Info.plist tracked, binary gitignored)
│   └── Contents/
│       ├── Info.plist
│       └── MacOS/Synapse Commander     # compiled by run.sh
└── Sources/SynapseCommander/
    ├── App.swift                  # entry point + NSApplicationDelegate
    ├── ContentView.swift          # top-level layout + key dispatch
    ├── PaneModel.swift            # pane state, sort, selection, cursor
    ├── PaneView.swift             # single-pane rendering
    ├── FileOps.swift              # copy/move/rename/mkdir/trash
    ├── KeyCatcher.swift           # AppKit-backed key monitor (F-keys, Tab)
    ├── Favorites.swift            # favorites store (JSON persistence)
    ├── FavoritesView.swift        # favorites modal
    └── HelpView.swift             # keyboard-shortcut modal
```

## Notes

- The app is unsigned. On first launch macOS Gatekeeper may block it;
  right-click the `.app` in Finder and choose **Open**, or run
  `xattr -dr com.apple.quarantine "Synapse Commander.app"` and relaunch.
- Copy/move operations are synchronous on the main thread — fine for
  typical usage, but large transfers will block the UI.
