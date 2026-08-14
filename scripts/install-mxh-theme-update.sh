#!/bin/sh
set -eu

ZIP_PATH="${1:-}"
EXPECTED_SHA256="${2:-}"
THEME_SHORT="GlassmorphismEnhanced"
THEME_VERSION="${3:-}"
DEFAULT_NODE_ORDER="DMIT,VMISS,YUNYOO,BreadCloud"
DATA_DIR="/var/lib/komari/data"
THEME_ROOT="${DATA_DIR}/theme"
THEME_DIR="${THEME_ROOT}/${THEME_SHORT}"
DB_PATH="${DATA_DIR}/komari.db"
BACKUP_ROOT="/var/backups/komari"

if [ "$(id -u)" -ne 0 ]; then
  echo "ERROR=must_run_as_root" >&2
  exit 1
fi

if [ -z "$ZIP_PATH" ] || [ -z "$EXPECTED_SHA256" ] || [ -z "$THEME_VERSION" ]; then
  echo "ERROR=usage:<zip-path>:<sha256>:<version>" >&2
  exit 1
fi
if [ "${#EXPECTED_SHA256}" -ne 64 ]; then
  echo "ERROR=invalid_sha256" >&2
  exit 1
fi
case "$EXPECTED_SHA256" in
  *[!0-9A-Fa-f]*)
    echo "ERROR=invalid_sha256" >&2
    exit 1
    ;;
esac

for command in python3 sha256sum systemctl tar curl install mktemp find cp mv; do
  if ! command -v "$command" >/dev/null 2>&1; then
    echo "ERROR=missing_command:${command}" >&2
    exit 1
  fi
done

if [ ! -f "$ZIP_PATH" ]; then
  echo "ERROR=theme_archive_missing" >&2
  exit 1
fi
if [ ! -f "$DB_PATH" ]; then
  echo "ERROR=komari_database_missing" >&2
  exit 1
fi
if ! systemctl is-active --quiet komari.service; then
  echo "ERROR=komari_not_active" >&2
  exit 1
fi

printf '%s  %s\n' "$EXPECTED_SHA256" "$ZIP_PATH" | sha256sum --check --status

install -d -o root -g root -m 0700 "$BACKUP_ROOT"
stage_dir="$(mktemp -d /tmp/komari-theme-stage.XXXXXX)"
stamp="$(date -u +%Y%m%d-%H%M%S)"
backup_path="${BACKUP_ROOT}/komari-before-theme-${stamp}.tar.gz"
db_snapshot="${BACKUP_ROOT}/komari-before-theme-${stamp}.db"
old_theme_backup="${BACKUP_ROOT}/${THEME_SHORT}-before-${stamp}"
mutation_started=0
committed=0

cleanup() {
  exit_code=$?
  trap - EXIT INT TERM

  if [ "$committed" -ne 1 ] && [ "$mutation_started" -eq 1 ]; then
    systemctl stop komari.service >/dev/null 2>&1 || true
    if [ -e "$THEME_DIR" ]; then
      rm -rf -- "$THEME_DIR"
    fi
    if [ -d "$old_theme_backup" ]; then
      install -d -o komari -g komari -m 0755 "$THEME_ROOT"
      mv "$old_theme_backup" "$THEME_DIR"
    fi
    if [ -f "$db_snapshot" ]; then
      cp -a "$db_snapshot" "$DB_PATH"
      chown komari:komari "$DB_PATH"
    fi
    systemctl start komari.service >/dev/null 2>&1 || true
    echo "ROLLBACK=attempted" >&2
  fi

  if [ -n "$stage_dir" ] && [ -d "$stage_dir" ]; then
    rm -rf -- "$stage_dir"
  fi
  exit "$exit_code"
}
trap cleanup EXIT INT TERM

python3 - "$ZIP_PATH" "$stage_dir" "$THEME_SHORT" "$THEME_VERSION" <<'PY'
import json
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import sys
import zipfile

archive_path, stage_path, expected_short, expected_version = sys.argv[1:]
stage = Path(stage_path)

with zipfile.ZipFile(archive_path) as archive:
    entries = archive.infolist()
    if len(entries) > 10_000:
        raise SystemExit("Theme archive contains too many entries")

    names = [entry.filename for entry in entries]
    if len(names) != len(set(names)):
        raise SystemExit("Theme archive contains duplicate paths")

    total_size = 0
    for entry in entries:
        path = PurePosixPath(entry.filename)
        mode = (entry.external_attr >> 16) & 0o170000
        if path.is_absolute() or ".." in path.parts or "\\" in entry.filename:
            raise SystemExit("Theme archive contains an unsafe path")
        if mode == stat.S_IFLNK:
            raise SystemExit("Symbolic links are not allowed")
        if entry.file_size > 128 << 20:
            raise SystemExit("Theme archive contains an oversized file")
        total_size += entry.file_size
        if total_size > 512 << 20:
            raise SystemExit("Theme archive expands beyond the size limit")

    try:
        manifest = json.loads(archive.read("komari-theme.json"))
    except KeyError as error:
        raise SystemExit("komari-theme.json is missing") from error

    short = manifest.get("short", "")
    version = manifest.get("version", "")
    if short != expected_short or not re.fullmatch(r"[A-Za-z0-9_-]+", short):
        raise SystemExit("Unexpected or invalid theme short name")
    if version != expected_version:
        raise SystemExit("Unexpected theme version")
    if "dist/index.html" not in names:
        raise SystemExit("Theme entry page is missing")

    for entry in entries:
        relative = PurePosixPath(entry.filename)
        target = stage.joinpath(*relative.parts)
        if entry.is_dir():
            target.mkdir(parents=True, exist_ok=True)
            continue
        target.parent.mkdir(parents=True, exist_ok=True)
        with archive.open(entry) as source, target.open("wb") as destination:
            shutil.copyfileobj(source, destination)
        target.chmod(0o644)
PY

systemctl stop komari.service
mutation_started=1
tar -C /var/lib/komari -czf "$backup_path" data
cp -a "$DB_PATH" "$db_snapshot"

if [ -e "$THEME_DIR" ]; then
  mv "$THEME_DIR" "$old_theme_backup"
fi

install -d -o komari -g komari -m 0755 "$THEME_ROOT"
mv "$stage_dir" "$THEME_DIR"
stage_dir=""
chown -R komari:komari "$THEME_DIR"
find "$THEME_DIR" -type d -exec chmod 0755 {} +
find "$THEME_DIR" -type f -exec chmod 0644 {} +

python3 - "$DB_PATH" "$THEME_SHORT" "$DEFAULT_NODE_ORDER" <<'PY'
import json
import sqlite3
import sys

database, theme, default_order = sys.argv[1:]
connection = sqlite3.connect(database)
try:
    connection.execute("BEGIN IMMEDIATE")
    row = connection.execute(
        "SELECT data FROM theme_configurations WHERE short = ?", (theme,)
    ).fetchone()
    if row and row[0]:
        settings = json.loads(row[0])
        if not isinstance(settings, dict):
            raise TypeError("Existing theme configuration is not an object")
    else:
        settings = {}
    settings["homeDefaultNodeOrder"] = default_order

    connection.execute(
        "INSERT INTO configs(key, value) VALUES(?, ?) "
        "ON CONFLICT(key) DO UPDATE SET value=excluded.value",
        ("theme", json.dumps(theme)),
    )
    connection.execute(
        "INSERT INTO theme_configurations(short, data) VALUES(?, ?) "
        "ON CONFLICT(short) DO UPDATE SET data=excluded.data",
        (theme, json.dumps(settings, ensure_ascii=False, separators=(",", ":"))),
    )
    connection.commit()
except Exception:
    connection.rollback()
    raise
finally:
    connection.close()
PY

systemctl start komari.service
sleep 3
systemctl is-active --quiet komari.service
curl --fail --silent --show-error http://127.0.0.1:25774/ping >/dev/null

python3 - "$THEME_DIR" "$DB_PATH" "$THEME_SHORT" "$THEME_VERSION" "$DEFAULT_NODE_ORDER" <<'PY'
import json
from pathlib import Path
import sqlite3
import sys
from urllib.error import HTTPError
from urllib.request import Request, urlopen

theme_dir = Path(sys.argv[1])
database, expected_short, expected_version, expected_order = sys.argv[2:]

manifest = json.loads((theme_dir / "komari-theme.json").read_text(encoding="utf-8"))
if manifest.get("short") != expected_short or manifest.get("version") != expected_version:
    raise SystemExit("Installed manifest does not match the release")

javascript = "\n".join(
    path.read_text(encoding="utf-8", errors="ignore")
    for path in (theme_dir / "dist").rglob("*.js")
)
if "undefined/records/load" in javascript:
    raise SystemExit("Legacy broken history URL is still present")
if "common:getRecords" not in javascript:
    raise SystemExit("RPC2 history implementation is missing")
configuration = manifest.get("configuration", {})
configuration_items = configuration.get("data", [])
order_item = next(
    (
        item
        for item in configuration_items
        if isinstance(item, dict) and item.get("key") == "homeDefaultNodeOrder"
    ),
    None,
)
if not order_item or order_item.get("default") != expected_order:
    raise SystemExit("Default node order is missing from the manifest")

connection = sqlite3.connect(database)
try:
    selected_row = connection.execute(
        "SELECT value FROM configs WHERE key = 'theme'"
    ).fetchone()
    config_row = connection.execute(
        "SELECT data FROM theme_configurations WHERE short = ?", (expected_short,)
    ).fetchone()
finally:
    connection.close()

if not selected_row or json.loads(selected_row[0]) != expected_short:
    raise SystemExit("Theme selection was not saved")
if not config_row:
    raise SystemExit("Theme configuration is missing")
settings = json.loads(config_row[0])
if settings.get("homeDefaultNodeOrder") != expected_order:
    raise SystemExit("Default node order was not saved")

request_id = 0

def rpc(method, params=None):
    global request_id
    request_id += 1
    payload = {"jsonrpc": "2.0", "method": method, "id": request_id}
    if params is not None:
        payload["params"] = params
    request = Request(
        "http://127.0.0.1:25774/api/rpc2",
        data=json.dumps(payload).encode("utf-8"),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urlopen(request, timeout=10) as response:
        document = json.load(response)
    if "error" in document:
        raise RuntimeError("RPC2 returned an error")
    return document.get("result")

history_api_status = "ok"
try:
    nodes = rpc("common:getNodes")
    if not isinstance(nodes, list) or not nodes:
        raise SystemExit("RPC2 node list is unavailable")
    node_id = nodes[0].get("uuid")
    if not node_id:
        raise SystemExit("RPC2 node identifier is unavailable")
    records = rpc(
        "common:getRecords",
        {"type": "load", "uuid": node_id, "hours": 4, "max_count": 600},
    )
    if not isinstance(records, dict) or not isinstance(records.get("records"), list):
        raise SystemExit("RPC2 historical load response is invalid")
except HTTPError as error:
    if error.code != 401:
        raise
    history_api_status = "protected"

print("INSTALLED_VERSION=" + expected_version)
print("DEFAULT_ORDER=ok")
print("HISTORY_API=" + history_api_status)
PY

committed=1
echo "INSTALL=ok"
echo "BACKUP_CREATED=yes"
