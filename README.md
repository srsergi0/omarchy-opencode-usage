# OpenCode Usage — Unofficial Bar Widget for Omarchy

> Unofficial Omarchy bar widget for `opencode-go` usage: **rolling 5h / weekly 7d / monthly 30d** with model breakdown. No `oc_sk_...` service key needed — uses your workspace + `auth` cookie (same as `https://opencode.ai`).

![Omarchy](https://img.shields.io/badge/Omarchy-shell%20plugin-blue)
![Quickshell](https://img.shields.io/badge/Quickshell-QML-lightgrey)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Features

- **Bar widget** on the right side — shows `Rolling%` only (e.g. `3.5%`), vector `opencode` logo when disconnected (light/dark theme aware, `Color.accent`)
- **Hybrid refresh**: `15s` fast `_server` (`rollingUsage/weeklyUsage/monthlyUsage` aggregated — accurate `3.x%` vs HTML `1.x%`) + `300s` HTML fallback (stable). Incremental backoff (`min(3600, interval*2^fails)`) avoids infinite loops
- **Auto-discovered `serverId`**: first load runs `discover_server_id.py` (`curl` + `accept:text/html` + `referer`) to find `64hex` `_server?id=...` and persists via `bar.shell.updateEntryInline` to `~/.config/omarchy/shell.json` — **no hardcoded defaults in code** (`manifest.json:defaults` all `""`)
- **Progress bars** use `Color.accent` (theme, not `red/yellow/green` hardcoded)
- **Panel** (`BarWidget click` → `Panel.qml` `KeyboardPanel`): header with vector icon + gear, `Rolling (5h) / Weekly (7d) / Monthly (30d)` cards. Default view only `%` + `reset in 3h 55m` (`fmtReset` → `"<1m" / "1m" / "1h" / "3d 20h"` — no `14420s`). **More details** toggle shows tokens `usage/limit` + **model breakdown per period** (`muse-spark-1.2-contributor`, `deepseek-v4-flash` with `cost/quotaCost/multiplier/contributionPercent`)
- **Credentials** gear inline in same panel + `Settings.qml` overlay (`PanelWindow` `WlrLayershell.Overlay`): `workspaceId` (`wrk_...`) + `auth` cookie (`Fe26.2**...`), persisted to `shell.json`; `connectionStatus: connected/disconnected`
- **Details breakdown**: `/_server?id=...&args={"t":{"t":9,"i":0,"l":2,"a":[{"t":1,"s":"wrk_..."},{"t":1,"s":"rolling|weekly|monthly"}],"o":0},"f":31}` with `referer: .../go`, `x-server-id`, `server-fn:1/2` → `parse_details.py` (`usage/limit/pct + rows[]`)
- **Security**: `manifest.json` `defaults` empty, `BarWidget.qml:setting("...", "")` — no `wrk`/`Fe26`/`64hex`/`st_` in repo; `fetch-unofficial.sh` requires `WRK`/`AUTH`/`SERVER_ID` env; `shell.json` is local `600` data, never committed

## Screenshots

- Bar: `3.5%` when connected, vector logo `18x20` `opacity 0.45` when disconnected
- Panel: `Label left — pct + reset same row` (`Weekly (7d) 10.4% 3d 20h` style), `More details` expands `Models` (`Muse Spark 1.2 Contributor 275M 9.2%`)

## Installation (Omarchy)

Plugin is a **git repo with `manifest.json` at root** — Omarchy clones to `~/.config/omarchy/plugins/<id>/`.

```bash
# from GitHub (interactive — shows diff, lands disabled for review)
omarchy plugin add https://github.com/srsergi0/omarchy-opencode-usage.git

# non-interactive + enable + right side
omarchy plugin add https://github.com/srsergi0/omarchy-opencode-usage.git --enable --yes
omarchy plugin list
omarchy plugin enable io.github.srsergi0.omarchy-opencode-usage

# move bar section if needed (default center, we use right)
omarchy bar move --section right io.github.srsergi0.omarchy-opencode-usage

# update
omarchy plugin update io.github.srsergi0.omarchy-opencode-usage --yes
omarchy plugin remove io.github.srsergi0.omarchy-opencode-usage --yes

# manual (without git)
# 1. cp -r . ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage/
# 2. omarchy-shell shell rescanPlugins
# 3. omarchy plugin enable io.github.srsergi0.omarchy-opencode-usage
```

Requires `omarchy-shell` (single `quickshell -p` instance) — see `shell/README.md` for `barWidget`, `overlay`, `IpcHandler`, `shell.json` inline settings.

## Configuration

1. Click bar widget → gear `` → **Credentials** (or `omarchy-shell shell summon io.github.srsergi0.omarchy-opencode-usage '{"tab":"connection"}'`)
2. Paste:
   - `Workspace ID`: `wrk_...` from `https://opencode.ai/workspace/<id>/usage`
   - `Auth cookie`: `auth` value from `DevTools → Application → Cookies → auth` (`Fe26.2**...` ~561 chars, `expires 1y`)
3. `Save` → `connectionStatus: connected`, `serverId` auto-discovered on first `15s` tick and saved to `~/.config/omarchy/shell.json` (`bar.layout.right: [{id:"io.github.srsergi0.omarchy-opencode-usage", workspaceId, authKey, serverId, detailsServerId}]`). `detailsServerId` for model breakdown auto-discovered from `/go` (`ba154...`-style, 64hex) — leave empty, no manual input needed (form removed for security).

Validate:

```bash
omarchy plugin validate ./omarchy-plugins/opencode-usage-unofficial
# or installed
omarchy plugin validate ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage
```

## How it works

- **Fast path** (`BarWidget.qml:refreshFast`): `curl --silent "https://opencode.ai/_server?id=$SID&args=...l=1..." -H 'accept: */*' -b "auth=$AUTH" -H "referer: https://opencode.ai/workspace/$WRK/usage" -H "x-server-id: $SID" -H "x-server-instance: server-fn:9" | python3 parse.py` → `{"rolling":{usage,limit,pct,resetSec}, "weekly":..., "monthly":...}` (limits `1.2B/3B/6B`)
- **HTML fallback** (`refreshHtml`): `curl "https://opencode.ai/workspace/$WRK/usage" -b "auth=$AUTH" -H 'accept: text/html' | python3 parse_html.py` → parses `$R[25]=[{id:"usg_...", cost, inputTokens, timeCreated: new Date(...)}]` 25 records, sums `cost` in `5h/7d/30d` windows
- **Details** (`fetchDetails`): `curl "..._server?id=$DETAILS_SID&args=...l=2,a:[wrk,period]..." -H "referer: .../go" -H "x-server-instance: server-fn:1/2" | python3 parse_details.py <period>` → `{"usage":..., "rows":[{"model","name","cost","quotaCost","multiplier","contributionPercent"}]}` — `weekly`/`monthly` include `deepseek-v4-flash` `x2` multiplier
- **Discovery**: `discover_server_id.py` / `discover_details_server_id.py` (`curl` HTML `accept:text/html` + `referer`, grep `src="*.js"` + `[a-f0-9]{64}`, test `rollingUsage`/`rows` + `model`) — no `known = "c738..."` fallback
- **UI**: `BarWidget.qml` `displayLabel` `pct`, `tooltipText2` `pct + reset`, `fixedWidth: contentRow.implicitWidth` avoids `5h` overlap, `isDark` `Color.background` luminance `<0.5` picks `opencode-logo-dark/light.svg` `assets/` (240x300 `path fill`)

## Security

- No `wrk_`, `Fe26`, `64hex`, `st_` in repo — `manifest.json` `defaults` `""`, `BarWidget.qml` `setting(..., "")`, `discover_*.py` no `known`. Test scripts `fetch-unofficial*.sh` use `WRK="${WRK:?Set WRK}"` etc.
- `shell.json` is `~/.config` local (`chmod 600` recommended) — never committed. `console.log` only `connected/disconnected` and `t.slice(0,300)` (no auth).
- HTML fallback is read-only, no `sudo`/`install hooks` — `omarchy plugin add` only clones + validates.

## Development

```bash
# edit QML/Python under project, copy to installed for hot-reload
cp project/omarchy-plugins/opencode-usage-unofficial/{BarWidget,Panel,Settings}.qml discover_*.py parse*.py ~/.config/omarchy/plugins/io.github.srsergi0.omarchy-opencode-usage/
omarchy-shell shell rescanPlugins; omarchy restart shell

# test parsers
AUTH=$(python3 -c "import json; print(json.load(open('/home/srsergio/.config/omarchy/shell.json'))['bar']['layout']['right'][0]['authKey'])") # or env
WRK=wrk_... SID=... curl ... | python3 parse.py
curl "https://opencode.ai/workspace/$WRK/usage" -b "auth=$AUTH" | python3 parse_html.py
```

## Publishing to GitHub for Omarchy

1. Create repo `github.com/srsergi0/omarchy-opencode-usage` with **root** containing:
   ```
   manifest.json
   BarWidget.qml
   Panel.qml
   Settings.qml
   parse.py
   parse_html.py
   parse_details.py
   discover_server_id.py
   discover_details_server_id.py
   assets/opencode-logo-light.svg
   assets/opencode-logo-dark.svg
   README.md
   LICENSE
   ```
2. `git init; git add .; git commit -m "feat: initial unofficial opencode usage" ; git branch -M main; git remote add origin https://github.com/srsergi0/omarchy-opencode-usage.git; git push -u origin main`
3. Tag `v0.1.0`: `git tag v0.1.0; git push --tags`
4. Users install via `omarchy plugin add https://github.com/srsergi0/omarchy-opencode-usage.git --enable --yes` — no `opencode.json` needed, Omarchy reads `manifest.json` schemaVersion 1.

See `shell/README.md#installing-a-third-party-plugin` for `add/update/remove` interactive vs `--yes` non-interactive, and `omarchy plugin validate`.

## License

MIT — unofficial, not affiliated with `opencode.ai` or `Omarchy`.
