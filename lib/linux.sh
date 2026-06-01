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
  local cmds_name="$1" labels_name="$2" path="$3" label="$4"
  local -n cmds_ref="$cmds_name"
  local -n labels_ref="$labels_name"
  local quoted

  [[ -z "$path" ]] && return 0
  quoted=$(_quote_path "$path")
  cmds_ref+=("[[ -d ${quoted} ]] && rm -rf ${quoted}/* 2>/dev/null || true")
  labels_ref+=("$label")
}

_run_array_section() {
  local title="$1" icon="$2" cmds_name="$3" labels_name="$4"
  local -n cmds_ref="$cmds_name"
  local -n labels_ref="$labels_name"
  local -a pairs=()
  local i

  for ((i=0; i<${#cmds_ref[@]}; i++)); do
    pairs+=("${cmds_ref[$i]}" "${labels_ref[$i]}")
  done

  [[ ${#pairs[@]} -gt 0 ]] && run_section "$title" "$icon" "${pairs[@]}"
}

_fallback_linux() {
  case "$OS" in
    debian)
      run_section "Package Manager Cache" "${G_DIAMOND}" \
        "apt clean 2>/dev/null || true" \
        "Clearing APT archives" \
        "apt autoclean 2>/dev/null || true" \
        "Removing obsolete APT archives" \
        "apt autoremove --purge -y 2>/dev/null || true" \
        "Removing unused dependencies"
      ;;
    arch)
      run_section "Package Manager Cache" "${G_DIAMOND}" \
        "pacman -Sc --noconfirm 2>/dev/null || true" \
        "Clearing pacman package cache" \
        "pacman -Rns \$(pacman -Qdtq) --noconfirm 2>/dev/null || true" \
        "Removing orphaned packages"
      ;;
    fedora|rhel)
      run_section "Package Manager Cache" "${G_DIAMOND}" \
        "dnf clean all 2>/dev/null || true" \
        "Clearing DNF cache" \
        "dnf autoremove -y 2>/dev/null || true" \
        "Removing unused dependencies"
      ;;
    alpine)
      run_section "Package Manager Cache" "${G_DIAMOND}" \
        "apk cache clean 2>/dev/null || true" \
        "Clearing APK cache"
      ;;
  esac

  run_section "System Cache" "${G_DIAMOND}" \
    "[[ -d /var/cache/fontconfig ]] && rm -rf /var/cache/fontconfig/* 2>/dev/null || true" \
    "Clearing fontconfig cache" \
    "[[ -d \"$REAL_HOME/.cache/thumbnails\" ]] && rm -rf \"$REAL_HOME/.cache/thumbnails\"/* 2>/dev/null || true" \
    "Clearing thumbnail cache"

  if command -v journalctl &>/dev/null; then
    run_section "Journal Logs" "${G_DIAMOND}" \
      "journalctl --vacuum-time=3d 2>/dev/null || true" \
      "Vacuuming logs older than 3 days" \
      "journalctl --vacuum-size=50M 2>/dev/null || true" \
      "Capping journal size to 50 MB"
  fi

  run_section "Temporary Files" "${G_DIAMOND}" \
    "find /tmp -mindepth 1 -type f -atime +10 -delete 2>/dev/null || true" \
    "Removing stale /tmp files" \
    "find /var/tmp -mindepth 1 -type f -atime +10 -delete 2>/dev/null || true" \
    "Removing stale /var/tmp files"

  if command -v docker &>/dev/null && docker info &>/dev/null; then
    run_section "Docker" "${G_CIRCLE}" \
      "docker system prune -a --volumes -f 2>/dev/null || true" \
      "Pruning Docker system data"
  fi
}

_run_path_category() {
  local title="$1" category="$2"
  local size
  size=$(_scan_val "d['categories']['$category'].get('size_bytes', 0)")
  [[ "$size" -le 0 ]] && return 0

  local -a cmds=()
  local -a labels=()
  local path
  while IFS= read -r path; do
    _append_clean_dir cmds labels "$path" "Clearing $path"
  done < <(_scan_lines "p.get('path','') for p in d['categories']['$category'].get('paths', []) if p.get('exists')")

  _run_array_section "$title" "${G_DIAMOND}" cmds labels
}

run_linux() {
  if ! _has_scan || ! command -v python3 &>/dev/null; then
    warn "Scan report missing; falling back to safe defaults."
    _fallback_linux
    return
  fi

  if [[ "$(_scan_val "1 if 'categories' in d else 0")" -ne 1 ]]; then
    warn "Scan report unreadable; falling back to safe defaults."
    _fallback_linux
    return
  fi

  run_section "RAM and Kernel Cache" "${G_DIAMOND}" \
    "sync && echo 3 > /proc/sys/vm/drop_caches 2>/dev/null || true" \
    "Dropping filesystem cache"

  if [[ "$(_scan_val "1 if d['categories']['swap'].get('used_bytes', 0) > 0 and not d.get('skip_swap_clear', False) else 0")" -eq 1 ]]; then
    run_section "Swap Clear" "${G_DIAMOND}" \
      "swapoff -a && swapon -a" \
      "Cycling swap"
    python3 -c "import json; p='$_SCAN_JSON'; d=json.load(open(p)); d['restart_required']=True; json.dump(d, open(p, 'w'), indent=2)" 2>/dev/null || true
  fi

  if [[ "$(_scan_val "d['categories']['package_cache']['size_bytes']")" -gt 0 ]]; then
    case "$OS" in
      debian)
        run_section "Package Manager Cache" "${G_DIAMOND}" \
          "apt clean 2>/dev/null || true" \
          "Clearing APT archives" \
          "apt autoclean 2>/dev/null || true" \
          "Removing obsolete APT archives" \
          "apt autoremove --purge -y 2>/dev/null || true" \
          "Removing unused dependencies"
        ;;
      arch)
        run_section "Package Manager Cache" "${G_DIAMOND}" \
          "pacman -Sc --noconfirm 2>/dev/null || true" \
          "Clearing pacman package cache" \
          "pacman -Rns \$(pacman -Qdtq) --noconfirm 2>/dev/null || true" \
          "Removing orphaned packages"
        ;;
      fedora|rhel)
        run_section "Package Manager Cache" "${G_DIAMOND}" \
          "dnf clean all 2>/dev/null || true" \
          "Clearing DNF cache" \
          "dnf autoremove -y 2>/dev/null || true" \
          "Removing unused dependencies"
        ;;
      alpine)
        run_section "Package Manager Cache" "${G_DIAMOND}" \
          "apk cache clean 2>/dev/null || true" \
          "Clearing APK cache"
        ;;
    esac
  fi

  local -a app_cmds=()
  local -a app_labels=()
  local name path
  while IFS=$'\t' read -r name path; do
    _append_clean_dir app_cmds app_labels "$path" "Clearing $name"
  done < <(_scan_lines "f\"{a.get('name','App')}\\t{a.get('path','')}\" for a in d['categories']['app_cache'].get('apps', []) if a.get('exists') and a.get('size_bytes', 0) > 0")
  _run_array_section "App Cache Cleanup" "${G_DIAMOND}" app_cmds app_labels

  _run_path_category "System Cache" "system_cache"
  _run_path_category "Logs" "logs"
  _run_path_category "Temporary Files" "temp_files"
  _run_path_category "Trash" "trash"

  local -a dev_cmds=()
  local -a dev_labels=()
  while IFS=$'\t' read -r name path; do
    _append_clean_dir dev_cmds dev_labels "$path" "Clearing $name"
  done < <(_scan_lines "f\"{t.get('name','tool')}\\t{t.get('path','')}\" for t in d['categories']['dev_cache'].get('tools', []) if t.get('exists') and t.get('size_bytes', 0) > 0")
  _run_array_section "Developer Caches" "${G_DIAMOND}" dev_cmds dev_labels

  if [[ "$(_scan_val "1 if d['categories']['docker'].get('available', False) and d['categories']['docker'].get('reclaimable_bytes', 0) > 0 else 0")" -eq 1 ]]; then
    run_section "Docker" "${G_CIRCLE}" \
      "docker system prune -a --volumes -f 2>/dev/null || true" \
      "Pruning Docker system data"
  fi

  if [[ "$(_scan_val "1 if d['categories']['snap'].get('available', False) and d['categories']['snap'].get('size_bytes', 0) > 0 else 0")" -eq 1 ]]; then
    run_section "Snap" "${G_CIRCLE}" \
      "[[ -d /var/lib/snapd/cache ]] && rm -rf /var/lib/snapd/cache/* 2>/dev/null || true" \
      "Clearing Snap cache"
  fi

  if [[ "$(_scan_val "1 if d['categories']['flatpak'].get('available', False) and d['categories']['flatpak'].get('reclaimable_bytes', 0) > 0 else 0")" -eq 1 ]]; then
    run_section "Flatpak" "${G_CIRCLE}" \
      "sudo -u \"$SUDO_USER\" flatpak uninstall --unused -y 2>/dev/null || true" \
      "Removing unused Flatpak runtimes"
  fi

  if [[ "$OS" == "debian" ]]; then
    local kernels
    kernels=$(_scan_lines "d['categories']['kernels'].get('removable', [])" | tr '\n' ' ')
    if [[ -n "${kernels// /}" ]]; then
      run_section "Old Kernels" "${G_CIRCLE}" \
        "apt purge -y $kernels 2>/dev/null || true" \
        "Removing old kernel images" \
        "update-grub 2>/dev/null || true" \
        "Updating boot menu"
      python3 -c "import json; p='$_SCAN_JSON'; d=json.load(open(p)); d['restart_required']=True; json.dump(d, open(p, 'w'), indent=2)" 2>/dev/null || true
    fi
  fi
}
