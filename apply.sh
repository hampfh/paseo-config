#!/usr/bin/env bash
# Apply the shared Paseo config from github.com/hampfh/paseo-config to this machine.
#
#   curl -fsSL https://raw.githubusercontent.com/hampfh/paseo-config/main/apply.sh | bash
#   curl -fsSL https://raw.githubusercontent.com/hampfh/paseo-config/main/apply.sh | bash -s -- --dry-run
#   curl -fsSL https://raw.githubusercontent.com/hampfh/paseo-config/main/apply.sh | PASEO_HUB_API_KEY=paseo_pk_... bash
#
# Safe to re-run: settings in the repo win, every other key in config.json is kept,
# and nothing is written when the result is unchanged.
#
# Options:
#   --dry-run     Show what would change, write nothing
#   --host NAME   Also apply hosts/NAME.json from the repo (default: $PASEO_CONFIG_HOST)
#   --restart     Restart the daemon if a changed setting needs it
#   --no-start    Do not start the daemon if it is stopped
#   --no-execute  When connecting to Hub, do not grant hub.execute
#
# Env: PASEO_HOME (default ~/.paseo), PASEO_CONFIG_REF (default main),
#      PASEO_HUB_API_KEY / PASEO_HUB_URL (connect this daemon to Hub when the key is set)

set -euo pipefail

main() {
  local repo_raw="https://raw.githubusercontent.com/hampfh/paseo-config/${PASEO_CONFIG_REF:-main}"
  local home="${PASEO_HOME:-$HOME/.paseo}"
  local host="${PASEO_CONFIG_HOST:-}" dry_run=0 restart=0 start=1 execute=1

  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) dry_run=1 ;;
      --host) host="$2"; shift ;;
      --restart) restart=1 ;;
      --no-start) start=0 ;;
      --no-execute) execute=0 ;;
      -h|--help) sed -n '2,21p' "${BASH_SOURCE[0]:-/dev/null}" 2>/dev/null || true; exit 0 ;;
      *) die "unknown option: $1" ;;
    esac
    shift
  done

  command -v node >/dev/null || die "node is required (Paseo runs on it). Install Node.js 20+ first."
  if ! command -v paseo >/dev/null; then
    [ "$dry_run" = 1 ] && die "paseo CLI not installed (dry run, not installing)"
    log "Installing the paseo CLI with npm"
    npm install -g @getpaseo/cli </dev/null || die "npm install failed; try: sudo npm install -g @getpaseo/cli"
  fi

  tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

  # Use files next to this script when run from a clone, otherwise download them.
  local src="" here=""
  if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  fi
  if [ -n "$here" ] && [ -f "$here/daemon/shared.json" ]; then
    src="$here"
    log "Using local repo at $src"
  else
    src="$tmp"; mkdir -p "$src/daemon" "$src/hosts"
    curl -fsSL "$repo_raw/daemon/shared.json" -o "$src/daemon/shared.json" || die "could not download daemon/shared.json"
    if [ -n "$host" ]; then
      curl -fsSL "$repo_raw/hosts/$host.json" -o "$src/hosts/$host.json" 2>/dev/null || rm -f "$src/hosts/$host.json"
    fi
  fi

  local layers=("$src/daemon/shared.json")
  if [ -n "$host" ]; then
    local f
    for f in "$src/hosts/$host.json" "$src/hosts/$host.local.json"; do
      [ -f "$f" ] && layers+=("$f") && log "Host layer: ${f#"$src"/}"
    done
  fi

  mkdir -p "$home"
  local config="$home/config.json"
  local merged="$tmp/config.json"

  local changes
  changes="$(node - "$config" "$merged" "${layers[@]}" <<'NODE'
const fs = require('fs');
const [configPath, outPath, ...layers] = process.argv.slice(2);
const read = (p) => JSON.parse(fs.readFileSync(p, 'utf8'));
const isObj = (v) => v && typeof v === 'object' && !Array.isArray(v);
const merge = (base, over) => {
  const out = { ...base };
  for (const [k, v] of Object.entries(over)) out[k] = isObj(v) && isObj(out[k]) ? merge(out[k], v) : v;
  return out;
};
const diff = (a, b, path = '') => Object.keys({ ...a, ...b }).flatMap((k) => {
  const p = path + k;
  if (isObj(a?.[k]) && isObj(b?.[k])) return diff(a[k], b[k], p + '.');
  return JSON.stringify(a?.[k]) === JSON.stringify(b?.[k]) ? [] : [p];
});
const live = fs.existsSync(configPath) ? read(configPath) : {};
let next = live;
for (const layer of layers) {
  const { $schema, ...settings } = read(layer);
  next = merge(next, settings);
}
fs.writeFileSync(outPath, JSON.stringify(next, null, 2) + '\n');
console.log(diff(live, next).join('\n'));
NODE
)"

  mkdir -p "$tmp/validate" && cp "$merged" "$tmp/validate/config.json"
  local invalid
  if ! invalid="$(paseo daemon config get --home "$tmp/validate" </dev/null 2>&1 >/dev/null)"; then
    die "merged config is invalid, nothing written:
$(printf '%s\n' "$invalid" | grep -v '^    at ')"
  fi

  if [ -z "$changes" ]; then
    log "config.json already matches the repo"
  else
    log "Settings that change:"; printf '  %s\n' $changes
    if [ "$dry_run" = 1 ]; then
      log "Dry run: nothing written"; exit 0
    fi
    local backup=""
    if [ -f "$config" ]; then
      backup="$config.bak.$(date +%Y%m%d%H%M%S)"
      cp -p "$config" "$backup"; log "Backup: $backup"
    fi
    install -m 600 "$merged" "$config"
    log "Wrote $config"
  fi
  [ "$dry_run" = 1 ] && exit 0

  if daemon_running "$home"; then
    if [ -n "$changes" ]; then
      local reload
      if ! reload="$(paseo reload --home "$home" --json </dev/null 2>&1)"; then
        if [ -n "${backup:-}" ]; then cp -p "$backup" "$config"; else rm -f "$config"; fi
        die "daemon rejected the new config, restored the previous file:
$reload"
      fi
      local needs_restart
      needs_restart="$(node -e 'const r=JSON.parse(process.argv[1]);console.log(r.restartRequiredPaths.join(" "))' "$reload")"
      if [ -n "$needs_restart" ]; then
        if [ "$restart" = 1 ]; then
          log "Restarting daemon for: $needs_restart"
          paseo daemon restart --home "$home" </dev/null
        else
          log "Reloaded. These need a restart to apply: $needs_restart (re-run with --restart)"
        fi
      else
        log "Reloaded daemon"
      fi
    fi
  elif [ "$start" = 1 ]; then
    log "Starting daemon"
    paseo daemon start --home "$home" </dev/null
  else
    log "Daemon is stopped (--no-start); settings apply on next start"
  fi

  if [ -n "${PASEO_HUB_API_KEY:-}" ]; then
    hub_connect "$home" "$execute"
  fi

  log "Done. Pair the Paseo app with: paseo daemon pair"
  log "Provider CLIs (claude, codex) must be installed and logged in on this machine separately."
}

daemon_running() {
  paseo daemon status --home "$1" --json </dev/null 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{process.exit(JSON.parse(s).localDaemon==="running"?0:1)}catch{process.exit(1)}})'
}

hub_connect() {
  local home="$1" execute="$2" state
  state="$(paseo hub status --home "$home" --json </dev/null 2>/dev/null |
    node -e 'let s="";process.stdin.on("data",d=>s+=d).on("end",()=>{try{const h=[].concat(JSON.parse(s))[0]||{};console.log((h.state||"")+" "+(h.permissions||""))}catch{}})' || true)"

  if [[ "$state" == connected* ]]; then
    log "Already connected to Hub"
    if [ "$execute" = 1 ] && [[ "$state" != *hub.execute* ]]; then
      paseo hub permissions grant hub.execute --home "$home" </dev/null
      log "Granted hub.execute"
    fi
    return
  fi

  log "Connecting daemon to Hub"
  local args=(hub connect --home "$home")
  [ "$execute" = 1 ] && args+=(--permission hub.execute)
  paseo "${args[@]}" </dev/null
}

log() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
die() { printf '\033[1;31merror:\033[0m %s\n' "$*" >&2; exit 1; }

main "$@"
