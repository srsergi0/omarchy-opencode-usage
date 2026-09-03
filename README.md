# OpenCode Usage for Omarchy

Unofficial bar widget for [Omarchy](https://omarchy.org) that shows your `opencode-go` usage directly in the bar: **Rolling 5h / Weekly 7d / Monthly 30d** with model breakdown. No service key required.

![Omarchy](https://img.shields.io/badge/Omarchy-plugin-blue)
![License](https://img.shields.io/badge/license-MIT-green)

## Preview

![preview](preview.png)

Bar shows `4.0%` (rolling). Panel shows `Label left — % + reset` and `More details` expands to model breakdown.

## Installation

```bash
omarchy plugin add https://github.com/srsergi0/omarchy-opencode-usage.git --enable --yes
# or interactive (shows diff)
omarchy plugin add https://github.com/srsergi0/omarchy-opencode-usage.git
```

Manual:

```bash
cp -r . ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage/
omarchy-shell shell rescanPlugins
omarchy plugin enable io.github.srsergi0.omarchy-opencode-usage
omarchy bar move --section right io.github.srsergi0.omarchy-opencode-usage
```

Update / remove:

```bash
omarchy plugin update io.github.srsergi0.omarchy-opencode-usage --yes
omarchy plugin remove io.github.srsergi0.omarchy-opencode-usage --yes
```

Requires `omarchy-shell` (Quickshell).

## Configuration

1. Click the bar widget → gear icon
2. Enter:
   - **Workspace ID** — `wrk_...` from `https://opencode.ai/workspace/<id>/usage`
   - **Auth cookie** — `auth` from `DevTools → Application → Cookies → auth` on `opencode.ai` (`Fe26.2**...`, ~561 chars, expires ~1 year)
3. Save

That's it. `serverId` is auto-discovered on first load and saved to `~/.config/omarchy/shell.json`. Status shows as `connected` when valid.

Validate:

```bash
omarchy plugin validate ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage
```

## Usage

- **Bar:** shows rolling usage `%` only. Vector logo when disconnected.
- **Click bar:** opens panel with `Rolling (5h)`, `Weekly (7d)`, `Monthly (30d)` — each shows `%` on the left and `reset in` time on the right (`3h 55m`, `3d 20h`).
- **More details:** shows tokens `usage / limit` and per-model breakdown (`Muse Spark 1.2 Contributor`, `DeepSeek V4 Flash` with quota multiplier).
- **Right-click bar:** opens `https://opencode.ai/workspace/<id>/usage`
- **Middle-click bar:** refresh

## Troubleshooting

- **disconnected / 0%:** check `Workspace ID` and `auth` cookie (expires ~1 year, re-copy from DevTools)
- **No details:** details are auto-discovered from `/go`; if they stay empty after `More details`, re-save credentials and wait 15s
- **Bar not visible:** `omarchy plugin list` → ensure `enabled`, then `omarchy bar move --section right io.github.srsergi0.omarchy-opencode-usage`

## Development

```bash
# hot-reload after edits
cp BarWidget.qml Panel.qml Settings.qml parse*.py discover*.py ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage/
omarchy-shell shell rescanPlugins; omarchy restart shell
```

## License

MIT — unofficial, not affiliated with `opencode.ai` or `Omarchy`.
