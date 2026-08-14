# MXH personal build

This private archive tracks the personal Komari theme derived from
`jianmomo/komari-theme-Glassmorphism-Enhanced`.

## Personal changes

- Load historical node metrics through Komari RPC2 with a REST compatibility fallback.
- Normalize Komari 1.3.x RPC2 load records from UUID-grouped objects to chart-ready arrays.
- Default node order: DMIT, VMISS, YUNYOO, BreadCloud.
- Keep unmatched nodes in their original Komari `weight` order.
- Add a seven-day preset to the ping history chart when the server retention window allows it.
- Use the managed `siteIconUrl` setting for both the browser favicon and header icon, with the bundled favicon as fallback.
- Link the managed theme page to Komari's built-in local favicon uploader, while retaining an optional external URL override.
- Present managed settings with section summaries, concise help text, collapsible advanced references, and consistently formatted option labels.

The default order can be changed in the managed theme setting
`homeDefaultNodeOrder` with a comma-separated list of node-name keywords.

Use Komari's built-in local favicon uploader from the managed theme page for a
self-hosted icon. The optional `siteIconUrl` setting accepts an HTTPS image URL
or a site-relative path beginning with `/`; when set it overrides the locally
uploaded icon. Leave it empty to use `/favicon.ico`, with the bundled theme icon
as the final fallback.

## Build

```powershell
bun install --no-save
bun run lint
bun run build
```

The build produces `komari-theme-Glassmorphism-build-<commit>.zip` for import in
the Komari theme manager.

This repository must not contain Komari databases, backups, administrator
credentials, Cloudflare Tunnel tokens, VPS archives, or private keys.
