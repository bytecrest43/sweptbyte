#!/usr/bin/env bash
# Requires: common.sh sourced, $OS exported, $REAL_HOME exported
# Requires: /tmp/sweptbyte-scan.json written by scan.py

_SCAN_JSON="/tmp/sweptbyte-scan.json"
_has_scan() { [[ -f "$_SCAN_JSON" ]]; }
_scan_val() { python3 -c "import json,sys; d=json.load(open('$_SCAN_JSON')); print($1)" 2>/dev/null || echo "0"; }

_scan_lines() {
  python3 -c "import json; d=json.load(open('$_SCAN_JSON')); [print(x) for x in ($1)]" 2>/dev/null || true
}

_quote_path() {
  python3 -c "import shlex,sys; print(shlex.quote(sys.argv[1]))" "$1"
}

_append_clean_dir() {
  local pairs_name="$1" path="$2" label="$3"
  local -n pairs_ref="$pairs_name"
  local quoted

  [[ -z "$path" ]] && return 0
  quoted=$(_quote_path "$path")
  pairs_ref+=("[[ -d ${quoted} ]] && rm -rf ${quoted}/* 2>/dev/null || true" "$label")
}

_brew_bin() {
  local candidate
  for candidate in "/opt/homebrew/bin/brew" "/usr/local/bin/brew"; do
    if [[ -x "$candidate" ]]; then
      printf "%s" "$candidate"
      return 0
    fi
  done
  return 1
}

_run_pairs_section() {
  local title="$1" icon="$2" pairs_name="$3"
  local -n pairs_ref="$pairs_name"
  [[ ${#pairs_ref[@]} -gt 0 ]] && run_section "$title" "$icon" "${pairs_ref[@]}"
}

_fallback_macos() {
  local brew
  brew=$(_brew_bin 2>/dev/null || true)

  if [[ -n "$brew" ]]; then
    run_section "Homebrew" "${G_CIRCLE}" \
      "sudo -u \"$SUDO_USER\" \"$brew\" cleanup -s 2>/dev/null || true" \
      "Cleaning Homebrew cache" \
      "sudo -u \"$SUDO_USER\" \"$brew\" autoremove 2>/dev/null || true" \
      "Removing unused Homebrew dependencies"
  fi

  run_section "System Cache" "${G_DIAMOND}" \
    "[[ -d \"$REAL_HOME/Library/Caches\" ]] && rm -rf \"$REAL_HOME/Library/Caches\"/* 2>/dev/null || true" \
    "Clearing user Library caches" \
    "[[ -d /Library/Caches ]] && rm -rf /Library/Caches/* 2>/dev/null || true" \
    "Clearing system Library caches"

  run_section "Logs" "${G_DIAMOND}" \
    "[[ -d \"$REAL_HOME/Library/Logs\" ]] && rm -rf \"$REAL_HOME/Library/Logs\"/* 2>/dev/null || true" \
    "Clearing user logs" \
    "[[ -d /Library/Logs ]] && rm -rf /Library/Logs/* 2>/dev/null || true" \
    "Clearing system logs"

  run_section "Temporary Files" "${G_DIAMOND}" \
    "[[ -d /tmp ]] && rm -rf /tmp/* 2>/dev/null || true" \
    "Clearing /tmp" \
    "[[ -d /private/tmp ]] && rm -rf /private/tmp/* 2>/dev/null || true" \
    "Clearing /private/tmp"
}

_run_path_category() {
  local title="$1" category="$2"
  local size
  size=$(_scan_val "d['categories']['$category'].get('size_bytes', 0)")
  [[ "$size" -le 0 ]] && return 0

  local -a pairs=()
  local path
  while IFS= read -r path; do
    _append_clean_dir pairs "$path" "Clearing $path"
  done < <(_scan_lines "p.get('path','') for p in d['categories']['$category'].get('paths', []) if p.get('exists')")

  _run_pairs_section "$title" "${G_DIAMOND}" pairs
}

run_macos() {
  if ! _has_scan || ! command -v python3 >/dev/null 2>&1; then
    warn "Scan report missing; falling back to safe defaults."
    _fallback_macos
    return
  fi

  if [[ "$(_scan_val "1 if 'categories' in d else 0")" -ne 1 ]]; then
    warn "Scan report unreadable; falling back to safe defaults."
    _fallback_macos
    return
  fi

  run_section "Memory Cache" "${G_DIAMOND}" \
    "purge 2>/dev/null || true" \
    "Purging inactive memory"

  local brew
  brew=$(_brew_bin 2>/dev/null || true)
  if [[ "$(_scan_val "d['categories']['package_cache']['size_bytes']")" -gt 0 && -n "$brew" ]]; then
    run_section "Homebrew" "${G_CIRCLE}" \
      "sudo -u \"$SUDO_USER\" \"$brew\" cleanup -s 2>/dev/null || true" \
      "Cleaning Homebrew cache" \
      "sudo -u \"$SUDO_USER\" \"$brew\" autoremove 2>/dev/null || true" \
      "Removing unused Homebrew dependencies"
  fi

  local -a app_pairs=()
  local name path
  while IFS=$'\t' read -r name path; do
    _append_clean_dir app_pairs "$path" "Clearing $name"
  done < <(_scan_lines "f\"{a.get('name','App')}\\t{a.get('path','')}\" for a in d['categories']['app_cache'].get('apps', []) if a.get('exists') and a.get('size_bytes', 0) > 0")
  _run_pairs_section "App Cache Cleanup" "${G_DIAMOND}" app_pairs

  _run_path_category "System Cache" "system_cache"
  _run_path_category "Logs" "logs"
  _run_path_category "Temporary Files" "temp_files"
  _run_path_category "Trash" "trash"

  local -a dev_pairs=()
  while IFS=$'\t' read -r name path; do
    _append_clean_dir dev_pairs "$path" "Clearing $name"
  done < <(_scan_lines "f\"{t.get('name','tool')}\\t{t.get('path','')}\" for t in d['categories']['dev_cache'].get('tools', []) if t.get('exists') and t.get('size_bytes', 0) > 0")
  _run_pairs_section "Developer Caches" "${G_DIAMOND}" dev_pairs

  if [[ "$(_scan_val "1 if d['categories']['docker'].get('available', False) and d['categories']['docker'].get('reclaimable_bytes', 0) > 0 else 0")" -eq 1 ]]; then
    run_section "Docker" "${G_CIRCLE}" \
      "docker system prune -a --volumes -f 2>/dev/null || true" \
      "Pruning Docker system data"
  fi

  run_section "DNS Cache" "${G_DIAMOND}" \
    "dscacheutil -flushcache 2>/dev/null || true" \
    "Flushing DNS cache" \
    "killall -HUP mDNSResponder 2>/dev/null || true" \
    "Restarting mDNSResponder"

  run_section "Font Cache" "${G_DIAMOND}" \
    "atsutil databases -remove 2>/dev/null || true" \
    "Removing font cache databases"

  if command -v tmutil >/dev/null 2>&1; then
    run_section "Time Machine Snapshots" "${G_CIRCLE}" \
      "tmutil listlocalsnapshots / 2>/dev/null || true" \
      "Listing local snapshots" \
      "tmutil thinlocalsnapshots / 999999999999 1 2>/dev/null || true" \
      "Thinning local snapshots"
  fi
}
