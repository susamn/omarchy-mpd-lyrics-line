# MPD Lyrics Overlay

An Omarchy overlay plugin that presents real-time synced 4-line `.lrc` lyrics in a modal dialog matching Omarchy's package install / Polkit modal popup style.

## Requirements

| Dependency | Needed for | Notes |
|---|---|---|
| `mpd` | Music Player Daemon | Running background music playback service. |
| `mpc` | Metadata & state queries | Standard lightweight client for MPD. |
| `mpdtui` | Synced LRC window generator | Generates real-time 4-line lyrics windows via `mpdtui -lyrics-line`. |
| `jq` | JSON serialization | Formats lyrics output into JSON for Quickshell. |

## Install

```bash
omarchy plugin add https://github.com/susamn/omarchy-plugin-mpd-lyrics.git --enable
```

<details>
<summary>Manual install</summary>

```bash
git clone https://github.com/susamn/omarchy-plugin-mpd-lyrics.git \
  ~/.config/omarchy/plugins/susamn.mpd-lyrics
omarchy-shell shell rescanPlugins
omarchy plugin enable susamn.mpd-lyrics
```
</details>

## Usage & Keybindings

Summon or dismiss the lyrics modal from the command line or IPC:

```bash
omarchy-shell susamn.mpd-lyrics toggle
omarchy-shell susamn.mpd-lyrics open
omarchy-shell susamn.mpd-lyrics close
```

### Hyprland Keybinding Example

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER SHIFT", "L", "MPD Synced Lyrics", "omarchy-shell susamn.mpd-lyrics toggle")
```

## Features

- **Centered Modal Popup**: Uses Omarchy's `PanelWindow` overlay with a translucent scrim backdrop (`WlrLayer.Overlay`).
- **4-Line Synced Window**:
  - **Line 0**: 1 line of preceding context (dimmed)
  - **Line 1**: Current line being sung (bold, highlighted in accent color)
  - **Line 2**: 1 line of upcoming context (dimmed)
  - **Line 3**: 2 lines of upcoming context (dimmed)
- **Fast Dynamic Polling**: Automatically refreshes every 500ms while visible and stops immediately when dismissed.
- **Easy Dismissal**: Press `Esc` or click anywhere outside the modal card to close.

## License

MIT — see [LICENSE](LICENSE).
