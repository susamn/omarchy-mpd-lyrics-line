# MPD Lyrics Overlay

An Omarchy overlay plugin that presents real-time butter-smooth synced `.lrc` and plain `.txt` lyrics in a centered modal popup matching Omarchy's design language.

## Requirements

| Dependency | Needed for | Notes |
|---|---|---|
| `mpd` | Music Player Daemon | Running background music playback service. |
| `python3` | Lyrics resolver | Queries MPD via raw TCP protocol and parses local `.lrc` / `.txt` files. |

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

- **Direct Same-Directory Lyrics Discovery**:
  - Automatically resolves `<track_name>.lrc` for real-time timestamp synchronization.
  - Falls back to `<track_name>.txt` for plain text lyrics if no `.lrc` is found.
  - Displays a clean empty state if neither file exists.
- **Butter-Smooth Synced Scrolling (5-Row Window)**:
  - **Row 0**: 1 preceding context line (dimmed).
  - **Row 1**: Current line being sung (bold, bright accent color, prominent font size, stationary position).
  - **Rows 2–4**: 3 upcoming context lines (gradually dimmed by distance).
  - Automatically glides lines upwards from bottom to top as song playback progresses.
  - **Top/Bottom Edge Gradients**: Subtle masks create a smooth entrance and exit for scrolling text.

- **Interactive Click-to-Seek**:
  - Click any line in synced lyrics mode to seek MPD playback directly to that timestamp.
- **Vim Navigation Support**:
  - `j` / `k` or `Down` / `Up`: Scroll line-by-line.
  - `Ctrl+d` / `d` & `Ctrl+u` / `u` or `PageDown` / `PageUp`: Half-page scroll.
  - `gg` / `g`: Jump to top.
  - `G`: Jump to bottom.
- **Easy Dismissal**:
  - Press `Esc`, `q`, or click anywhere outside the modal card to close.

## License

MIT — see [LICENSE](LICENSE).

