# Omatap

Keyboard-driven clicking for Omarchy: every spot on the screen gets a 2-letter hint, every window a number.

![Omatap](preview.png)

## Requirements

- `python-evdev`
- Write access to `/dev/uinput` (granted to the logged-in seat user by default; otherwise add an udev rule or join the `input` group)

## Install

```bash
cp -r . ~/.config/omarchy/plugins/gothe92.omatap
omarchy-shell shell rescanPlugins
omarchy plugin enable gothe92.omatap
```

Bind it in `~/.config/hypr/bindings.lua`:

```bash
omarchy-shell shell toggle gothe92.omatap '{}'
```

## Keys

| Key | Action |
|-----|--------|
| `A`–`Z` ×2 | Click grid cell |
| `Shift` + 2nd letter | Open 3×3 sub-grid |
| `1`–`9` | Click window |
| `Tab` | Toggle sub-grid mode |
| `QWE` `ASD` `ZXC` / arrows + `Enter` | Pick point in sub-grid |
| `;` `'` `,` `.` | Right / double / middle click / move only |
| `[` `]` | Scroll up / down |
| `Backspace` | Clear prefix |
| `Esc` | Back / close |

Punctuation keys are matched by position, so on Hungarian layout they are `É` `Á` `,` `.` and `Ő` `Ú`.

The click daemon exits after 10 minutes idle; errors are logged to `~/.local/state/omatap/daemon.log`.

## Screenshots

| | |
|---|---|
| ![Grid and window targets](screenshots/overview.png) Grid and window targets | ![First letter typed](screenshots/prefix.png) First letter typed |
| ![Precision sub-grid](screenshots/subgrid.png) Precision sub-grid | ![Right click mode](screenshots/mode-right.png) Right click mode |
| ![Double click mode](screenshots/mode-double.png) Double click mode | ![Middle click mode](screenshots/mode-middle.png) Middle click mode |
| ![Move only mode](screenshots/mode-move.png) Move only mode | ![Scroll mode](screenshots/mode-scroll-down.png) Scroll mode |
