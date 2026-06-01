#!/usr/bin/env bash
# Requires: common.sh sourced, $REAL_HOME exported
# Requires: /tmp/sweptbyte-scan.json written by scan.py

_SCAN_JSON="/tmp/sweptbyte-scan.json"
_has_scan() { [[ -f "$_SCAN_JSON" ]]; }
_scan_lines() {
  python3 -c "import json; d=json.load(open('$_SCAN_JSON')); [print(x) for x in ($1)]" 2>/dev/null || true
}

_quote_path() {
  python3 -c "import shlex,sys; print(shlex.quote(sys.argv[1]))" "$1"
}

run_dev() {
  if ! _has_scan || ! command -v python3 &>/dev/null; then
    return 0
  fi

  local -a pairs=()
  local name path quoted
  while IFS=$'\t' read -r name path; do
    [[ -z "${path:-}" ]] && continue
    quoted=$(_quote_path "$path")
    pairs+=("[[ -d ${quoted} ]] && rm -rf ${quoted}/* 2>/dev/null || true" "Clearing $name")
  done < <(_scan_lines "f\"{t.get('name','tool')}\\t{t.get('path','')}\" for t in d['categories']['dev_cache'].get('tools', []) if t.get('exists') and t.get('size_bytes', 0) > 0")

  [[ ${#pairs[@]} -gt 0 ]] && run_section "Developer Caches" "${G_DIAMOND}" "${pairs[@]}"
}
