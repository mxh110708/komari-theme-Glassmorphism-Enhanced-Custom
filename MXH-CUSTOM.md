# MXH personal build

This private archive tracks the personal Komari theme derived from
`jianmomo/komari-theme-Glassmorphism-Enhanced`.

## Personal changes

- Load historical node metrics through Komari RPC2 with a REST compatibility fallback.
- Default node order: DMIT, VMISS, YUNYOO, BreadCloud.
- Keep unmatched nodes in their original Komari `weight` order.

The default order can be changed in the managed theme setting
`homeDefaultNodeOrder` with a comma-separated list of node-name keywords.

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
