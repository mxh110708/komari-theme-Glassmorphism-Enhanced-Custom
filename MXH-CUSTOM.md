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

The default order can be changed in the managed theme setting
`homeDefaultNodeOrder` with a comma-separated list of node-name keywords.

The optional `siteIconUrl` setting accepts an HTTPS image URL or a site-relative
path beginning with `/`. Leave it empty to use the bundled default icon.

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
