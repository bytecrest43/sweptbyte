#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  lib/common.sh — shared foundation
#  ByteCrest Corp  ◆  sweptbyte v2.0.0
#  Sourced by bin/sweptbyte before anything else runs.
# ════════════════════════════════════════════════════════════════════

# ── Terminal width (cap at 72) ────────────────────────────────────────
COLS=$(tput cols 2>/dev/null || echo 72)
[[ $COLS -gt 72 ]] && COLS=72

# ── Colour palette — ByteCrest Corp (black & gold) ───────────────────
C_RESET='\033[0m'
C_BOLD='\033[1m'
C_DIM='\033[2m'
C_WHITE='\033[97m'
C_SILVER='\033[37m'
C_GREY='\033[90m'
C_GOLD='\033[33m'
C_AMBER='\033[38;5;136m'
C_GREEN='\033[38;5;178m'
C_BRIGHT_GOLD='\033[38;5;220m'
C_RED='\033[91m'

# ── Unicode glyphs ────────────────────────────────────────────────────
G_BLOCK='█'
G_LIGHT='░'
G_CHECK='✔'
G_CROSS='✖'
G_BAR_H='─'
G_HH='═'
G_DIAMOND='◆'
G_CIRCLE='○'
G_FILLED='●'

# ── Terminal helpers ──────────────────────────────────────────────────
repeat_char() {
  local char="$1" count="$2" out=""
  for ((i=0; i<count; i++)); do out+="$char"; done
  printf "%s" "$out"
}

center_text() {
  local text="$1" width="${2:-$COLS}"
  local clean
  clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local len=${#clean}
  local pad=$(( (width - len) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%*s%b%*s\n" $pad "" "$text" $pad ""
}

# ── Messaging helpers ─────────────────────────────────────────────────
ok()   { echo -e "  ${C_GREEN}${G_CHECK}${C_RESET}  $1"; }
fail() { echo -e "  ${C_RED}${G_CROSS}${C_RESET}  $1"; }
info() { echo -e "  ${C_GREY}›${C_RESET}  $1"; }
warn() { echo -e "  ${C_BRIGHT_GOLD}!${C_RESET}  $1"; }
die()  { echo -e "\n  ${C_RED}${G_CROSS}  $1${C_RESET}\n" >&2; exit 1; }

# ── Sudo real-user home ───────────────────────────────────────────────
# When run as `sudo sweptbyte`, SUDO_USER is the invoking user.
# REAL_HOME is their home directory — never root's home.
if [[ -n "${SUDO_USER:-}" ]]; then
  REAL_HOME=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
  [[ -z "$REAL_HOME" ]] && REAL_HOME="/home/$SUDO_USER"
else
  CURRENT_USER=$(id -un 2>/dev/null || whoami)
  REAL_HOME=$(getent passwd "$CURRENT_USER" 2>/dev/null | cut -d: -f6)
  [[ -z "$REAL_HOME" ]] && REAL_HOME="$(pwd)"
fi
export REAL_HOME

# ── Progress bar engine ───────────────────────────────────────────────
progress_bar() {
  local current="$1" total="$2" width="${3:-42}"
  local pct=$(( current * 100 / total ))
  local filled=$(( current * width / total ))
  local empty=$(( width - filled ))
  local color

  if   [[ $pct -lt 40 ]]; then color="$C_GOLD"
  elif [[ $pct -lt 75 ]]; then color="$C_BRIGHT_GOLD"
  else                          color="$C_GREEN"
  fi

  local bar_f bar_e
  bar_f=$(repeat_char "$G_BLOCK" "$filled")
  bar_e=$(repeat_char "$G_LIGHT" "$empty")

  printf "  ${C_GREY}[${C_RESET}${color}%s${C_RESET}${C_GREY}%s${C_RESET}${C_GREY}]${C_RESET} ${C_BOLD}%3d%%${C_RESET}" \
    "$bar_f" "$bar_e" "$pct"
}

# ── Section runner ────────────────────────────────────────────────────
# Usage: run_section "Title" "icon" \
#          "cmd1" "Label 1" \
#          "cmd2" "Label 2"
run_section() {
  local title="$1"
  local icon="$2"
  shift 2

  local -a cmds=()
  local -a labels=()
  while [[ $# -ge 2 ]]; do
    cmds+=("$1")
    labels+=("$2")
    shift 2
  done

  local total=${#cmds[@]}
  [[ $total -eq 0 ]] && return 0

  local section_failed=0

  echo ""
  echo -e "  ${C_BOLD}${C_WHITE}${icon}  ${title}${C_RESET}"
  echo -e "  ${C_GREY}$(repeat_char "$G_BAR_H" $(( COLS - 4 )))${C_RESET}"
  echo ""

  for ((i=0; i<total; i++)); do
    local cmd="${cmds[$i]}"
    local label="${labels[$i]}"
    local step=$(( i + 1 ))

    printf "  ${C_GREY}%2d/%d${C_RESET}  ${C_SILVER}%-40s${C_RESET}\n" "$step" "$total" "$label"

    local tmp_out
    tmp_out=$(mktemp)

    bash -c "$cmd" >"$tmp_out" 2>&1 &
    local cmd_pid=$!

    local tick=0
    while kill -0 "$cmd_pid" 2>/dev/null; do
      local fake_pct=$(( tick > 90 ? 90 : tick ))
      printf "\r"
      progress_bar "$fake_pct" 100 42
      sleep 0.07
      (( tick = tick < 90 ? tick + 3 : 90 ))
    done

    wait "$cmd_pid"
    local exit_code=$?

    printf "\r"
    if [[ $exit_code -eq 0 ]]; then
      progress_bar 100 100 42
      echo -e "  ${C_GREEN}${G_CHECK}${C_RESET}"
    else
      printf "  ${C_RED}$(repeat_char "$G_BLOCK" 42)${C_RESET}  ${C_RED}${G_CROSS}${C_RESET}\n"
      echo -e "  ${C_RED}${C_DIM}  Step failed (exit $exit_code) — continuing…${C_RESET}"
      if [[ -s "$tmp_out" ]]; then
        echo -e "  ${C_DIM}$(head -3 "$tmp_out")${C_RESET}"
      fi
      section_failed=1
    fi

    rm -f "$tmp_out"
    echo ""
  done

  if [[ $section_failed -eq 0 ]]; then
    echo -e "  ${C_GREEN}${G_FILLED}  Section complete.${C_RESET}"
  else
    echo -e "  ${C_BRIGHT_GOLD}!  Section finished with warnings.${C_RESET}"
  fi

  echo ""
  echo -e "${C_GREY}$(repeat_char "$G_BAR_H" "$COLS")${C_RESET}"
}

# ── OS detection ─────────────────────────────────────────────────────
detect_os() {
  case "$(uname -s)" in
    Linux*)
      if   [[ -f /etc/debian_version ]]; then echo "debian"
      elif [[ -f /etc/arch-release   ]]; then echo "arch"
      elif [[ -f /etc/fedora-release ]]; then echo "fedora"
      elif [[ -f /etc/redhat-release ]]; then echo "rhel"
      elif [[ -f /etc/alpine-release ]]; then echo "alpine"
      else                                    echo "linux"
      fi ;;
    Darwin*) echo "macos" ;;
    *)
      die "Unsupported OS: $(uname -s)" ;;
  esac
}

# ── Splash / banner ──────────────────────────────────────────────────
show_splash() {
  local version="${VERSION:-2.0.0}"

  clear
  echo ""
  echo -e "${C_BRIGHT_GOLD}$(repeat_char "$G_HH" "$COLS")${C_RESET}"
  echo ""
  center_text "${C_BOLD}${C_WHITE} ███████╗██╗    ██╗███████╗██████╗ ████████╗██████╗ ██╗   ██╗████████╗███████╗${C_RESET}"
  center_text "${C_BOLD}${C_WHITE} ██╔════╝██║    ██║██╔════╝██╔══██╗╚══██╔══╝██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝${C_RESET}"
  center_text "${C_BOLD}${C_GOLD} ███████╗██║ █╗ ██║█████╗  ██████╔╝   ██║   ██████╔╝ ╚████╔╝    ██║   █████╗${C_RESET}"
  center_text "${C_BOLD}${C_GOLD} ╚════██║██║███╗██║██╔══╝  ██╔═══╝    ██║   ██╔══██╗  ╚██╔╝     ██║   ██╔══╝${C_RESET}"
  center_text "${C_BOLD}${C_AMBER} ███████║╚███╔███╔╝███████╗██║        ██║   ██████╔╝   ██║      ██║   ███████╗${C_RESET}"
  center_text "${C_BOLD}${C_AMBER} ╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝        ╚═╝   ╚═════╝    ╚═╝      ╚═╝   ╚══════╝${C_RESET}"
  echo ""
  center_text "${C_GREY}${C_DIM}S  Y  S  T  E  M     M  A  I  N  T  E  N  A  N  C  E${C_RESET}"
  echo ""
  echo -e "${C_BRIGHT_GOLD}$(repeat_char "$G_HH" "$COLS")${C_RESET}"
  echo ""
  center_text "${C_SILVER}${C_DIM}A ByteCrest Corp Product  ${G_DIAMOND}  v${version}${C_RESET}"
  echo ""
  echo -e "${C_GREY}$(repeat_char "$G_BAR_H" "$COLS")${C_RESET}"
  echo ""
}

# ── Self-update ──────────────────────────────────────────────────────
self_update() {
  local installer_url="https://raw.githubusercontent.com/bytecrest43/sweptbyte/main/install.sh"
  if ! command -v curl &>/dev/null; then
    die "curl is required for self-update."
  fi
  curl -fsSL "$installer_url" | bash
}
