# Claude Usage Helper (Phase 1)

Serves your Claude 5-hour / 7-day usage as JSON on `http://127.0.0.1:8787/usage`
for the iCUE keyboard-LCD widget to poll. Binds to `127.0.0.1` only.

## Data source (tokenless)

The Claude **desktop app** already polls the authenticated usage endpoint and
caches the result to `%APPDATA%\Claude\plan-usage-history.json` (~every 5 min).
The helper reads **that file** — it never reads, stores, or logs any token.

`fh` = five-hour used %, `sd` = seven-day used %. We use the newest sample.

> The file format is undocumented and may change. **Everything that knows its
> shape is in the `Read-UsageSource` function in `usage-helper.ps1` — fix it
> there and nowhere else.**

## Served JSON contract

```json
{
  "five_hour": { "used_percentage": 58, "resets_at": null },
  "seven_day": { "used_percentage": 27, "resets_at": null },
  "status": "ok",            // "ok" | "stale" | "no_data"
  "stale": false,
  "as_of": "2026-08-06T16:15:58-05:00",   // timestamp of the sample
  "age_seconds": 234,
  "source": "desktop-cache",
  "org": "…",
  "served_at": "2026-08-06T16:19:52-05:00"
}
```

- `resets_at` is `null` — the local cache doesn't contain window reset times.
  The widget doesn't display them, so this is fine. (If ever needed, add them in
  `Read-UsageSource`.)
- On source failure (file missing / mid-write / corrupt), the helper serves the
  **last-known-good** sample with `stale: true` / `status: "stale"`. If it has
  never had a good sample it returns `status: "no_data"` with null percentages.
- The source is re-read at most once per 60s (`$CacheTtlSeconds`); a sample older
  than 11 min (`$StaleAfterSeconds`) is flagged stale.

## Files

- `usage-helper.ps1` — the service. Config knobs at the top (`$Port`,
  `$CacheTtlSeconds`, `$StaleAfterSeconds`).
- `run-helper-hidden.vbs` — launches it with **no window** (edit the path inside
  if you move this folder).
- `install-at-login.ps1` — creates a Startup shortcut to the VBS in place
  (`-Uninstall` to remove).

## Run

- **Test in a console:** `powershell -NoProfile -ExecutionPolicy Bypass -File .\usage-helper.ps1`
  then open `http://127.0.0.1:8787/usage`.
- **Run hidden now:** `wscript .\run-helper-hidden.vbs`
- **Run at login:** `powershell -NoProfile -ExecutionPolicy Bypass -File .\install-at-login.ps1`
