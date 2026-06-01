#!/usr/bin/env bash
# ════════════════════════════════════════════════════════════════════
#  install.sh — sweptbyte installer
#  ByteCrest Corp  ◆  v2.0.0
# ════════════════════════════════════════════════════════════════════

set -euo pipefail

# ── Config ────────────────────────────────────────────────────────────
GITHUB_USER="bytecrest43"
GITHUB_REPO="sweptbyte"
VERSION="2.0.0"
BASE_URL="https://raw.githubusercontent.com/${GITHUB_USER}/${GITHUB_REPO}/main"

INSTALL_BIN="/usr/local/bin/sweptbyte"
LIB_DIR="/usr/local/lib/sweptbyte"

# ── Colours & glyphs ─────────────────────────────────────────────────
I_RESET='\033[0m'
I_BOLD='\033[1m'
I_DIM='\033[2m'
I_WHITE='\033[97m'
I_SILVER='\033[37m'
I_GREY='\033[90m'
I_GOLD='\033[33m'
I_AMBER='\033[38;5;136m'
I_BRIGHT_GOLD='\033[38;5;220m'
I_GREEN='\033[38;5;178m'
I_RED='\033[91m'

I_HH='═'
I_BAR='─'
I_CHECK='✔'
I_CROSS='✖'
I_DIAMOND='◆'

COLS=$(tput cols 2>/dev/null || echo 72)
[[ $COLS -gt 72 ]] && COLS=72

install_repeat_char() {
  local char="$1" count="$2" out=""
  for ((i=0; i<count; i++)); do out+="$char"; done
  printf "%s" "$out"
}

install_center_text() {
  local text="$1" width="${2:-$COLS}"
  local clean
  clean=$(printf "%b" "$text" | sed 's/\x1b\[[0-9;]*m//g')
  local len=${#clean}
  local pad=$(( (width - len) / 2 ))
  [[ $pad -lt 0 ]] && pad=0
  printf "%*s%b%*s\n" $pad "" "$text" $pad ""
}

install_ok()   { echo -e "  ${I_GREEN}${I_CHECK}${I_RESET}  $1"; }
install_fail() { echo -e "  ${I_RED}${I_CROSS}${I_RESET}  $1"; }
install_info() { echo -e "  ${I_GREY}›${I_RESET}  $1"; }
install_warn() { echo -e "  ${I_BRIGHT_GOLD}!${I_RESET}  $1"; }

# ── Bash version check ────────────────────────────────────────────────
BASH_MAJOR="${BASH_VERSINFO[0]}"
if [[ "$BASH_MAJOR" -lt 4 ]]; then
  echo ""
  echo -e "  ${I_RED}${I_CROSS}  Bash 4 or higher is required (found: $BASH_VERSION)${I_RESET}"
  echo -e "  ${I_GREY}macOS ships Bash 3. Install a modern bash: brew install bash${I_RESET}"
  echo ""
  exit 1
fi

# ── OS detection ─────────────────────────────────────────────────────
install_detect_os() {
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
      echo -e "\n  ${I_RED}${I_CROSS}  Unsupported OS: $(uname -s)${I_RESET}\n" >&2
      exit 1 ;;
  esac
}

# ── Dependency check ──────────────────────────────────────────────────
check_dep() {
  local cmd="$1" os="$2"
  if ! command -v "$cmd" &>/dev/null; then
    install_fail "Required: ${I_BRIGHT_GOLD}${cmd}${I_RESET} not found."
    echo ""
    echo -e "  ${I_GREY}Install it with:${I_RESET}"
    case "$os" in
      debian) echo -e "  ${I_GOLD}sudo apt install $cmd -y${I_RESET}" ;;
      arch)   echo -e "  ${I_GOLD}sudo pacman -S $cmd${I_RESET}" ;;
      fedora|rhel) echo -e "  ${I_GOLD}sudo dnf install $cmd -y${I_RESET}" ;;
      macos)  echo -e "  ${I_GOLD}brew install $cmd${I_RESET}" ;;
      *)      echo -e "  ${I_GOLD}Please install $cmd via your package manager${I_RESET}" ;;
    esac
    echo ""
    exit 1
  fi
}

# ── File download ─────────────────────────────────────────────────────
download_file() {
  local url="$1" dest="$2"
  if ! curl -fsSL "$url" -o "$dest"; then
    install_fail "Download failed: ${I_GOLD}${url}${I_RESET}"
    exit 1
  fi
}

# ══════════════════════════════════════════════════════════════════════
#   SPLASH
# ══════════════════════════════════════════════════════════════════════
clear
echo ""
echo -e "${I_BRIGHT_GOLD}$(install_repeat_char "$I_HH" "$COLS")${I_RESET}"
echo ""
install_center_text "${I_BOLD}${I_WHITE} ███████╗██╗    ██╗███████╗██████╗ ████████╗██████╗ ██╗   ██╗████████╗███████╗${I_RESET}"
install_center_text "${I_BOLD}${I_WHITE} ██╔════╝██║    ██║██╔════╝██╔══██╗╚══██╔══╝██╔══██╗╚██╗ ██╔╝╚══██╔══╝██╔════╝${I_RESET}"
install_center_text "${I_BOLD}${I_GOLD} ███████╗██║ █╗ ██║█████╗  ██████╔╝   ██║   ██████╔╝ ╚████╔╝    ██║   █████╗${I_RESET}"
install_center_text "${I_BOLD}${I_GOLD} ╚════██║██║███╗██║██╔══╝  ██╔═══╝    ██║   ██╔══██╗  ╚██╔╝     ██║   ██╔══╝${I_RESET}"
install_center_text "${I_BOLD}${I_AMBER} ███████║╚███╔███╔╝███████╗██║        ██║   ██████╔╝   ██║      ██║   ███████╗${I_RESET}"
install_center_text "${I_BOLD}${I_AMBER} ╚══════╝ ╚══╝╚══╝ ╚══════╝╚═╝        ╚═╝   ╚═════╝    ╚═╝      ╚═╝   ╚══════╝${I_RESET}"
echo ""
install_center_text "${I_GREY}${I_DIM}I  N  S  T  A  L  L  E  R${I_RESET}"
echo ""
echo -e "${I_BRIGHT_GOLD}$(install_repeat_char "$I_HH" "$COLS")${I_RESET}"
echo ""
install_center_text "${I_GREY}${I_DIM}A ByteCrest Corp Product  ${I_DIAMOND}  v${VERSION}${I_RESET}"
echo ""
echo -e "${I_GREY}$(install_repeat_char "$I_BAR" "$COLS")${I_RESET}"

# ── OS + platform row ─────────────────────────────────────────────────
echo ""
OS=$(install_detect_os)
case "$OS" in
  debian) OS_LABEL="Ubuntu / Debian" ;;
  arch)   OS_LABEL="Arch Linux"      ;;
  fedora) OS_LABEL="Fedora"          ;;
  rhel)   OS_LABEL="RHEL / CentOS"   ;;
  alpine) OS_LABEL="Alpine Linux"    ;;
  macos)  OS_LABEL="macOS"           ;;
  *)      OS_LABEL="Linux"           ;;
esac

printf "  ${I_GREY}Platform${I_RESET}  ${I_GOLD}%-20s${I_RESET}  ${I_GREY}Target${I_RESET}  ${I_GOLD}%s${I_RESET}\n" \
  "$OS_LABEL" "$INSTALL_BIN"
echo ""
echo -e "${I_GREY}$(install_repeat_char "$I_BAR" "$COLS")${I_RESET}"

# ── Dependency checks ─────────────────────────────────────────────────
echo ""
echo -e "  ${I_BOLD}${I_BRIGHT_GOLD}${I_DIAMOND} CHECKING DEPENDENCIES${I_RESET}"
echo ""

check_dep "curl" "$OS"
install_ok "${I_SILVER}curl${I_RESET}       found"

check_dep "bash" "$OS"
install_ok "${I_SILVER}bash${I_RESET}       found"

check_dep "python3" "$OS"
install_ok "${I_SILVER}python3${I_RESET}    found"

echo ""
echo -e "${I_GREY}$(install_repeat_char "$I_BAR" "$COLS")${I_RESET}"

# ── Sudo authentication ───────────────────────────────────────────────
echo ""
echo -e "  ${I_BOLD}${I_BRIGHT_GOLD}${I_DIAMOND} AUTHENTICATION REQUIRED${I_RESET}"
echo -e "  ${I_GREY}Installing to ${INSTALL_BIN} requires elevated privileges.${I_RESET}"
echo ""

if ! sudo -v; then
  echo ""
  install_fail "Authentication failed. Aborting."
  echo ""
  exit 1
fi
install_ok "Access granted — proceeding."
echo ""
echo -e "${I_GREY}$(install_repeat_char "$I_BAR" "$COLS")${I_RESET}"

# Sudo keepalive
while true; do sudo -n true; sleep 50; kill -0 "$$" || exit; done 2>/dev/null &
SUDO_PID=$!
trap 'rm -rf "$TMP_DIR" 2>/dev/null; kill "$SUDO_PID" 2>/dev/null' EXIT

# ── Download ──────────────────────────────────────────────────────────
echo ""
echo -e "  ${I_BOLD}${I_BRIGHT_GOLD}${I_DIAMOND} DOWNLOADING${I_RESET}"
echo ""

TMP_DIR=$(mktemp -d /tmp/sweptbyte-install.XXXXXX)

# Ordered manifest: "remote_path" "local filename"
FILES=(
  "bin/sweptbyte"   "sweptbyte"
  "lib/common.sh"   "common.sh"
  "lib/linux.sh"    "linux.sh"
  "lib/macos.sh"    "macos.sh"
  "lib/dev.sh"      "dev.sh"
  "core/scan.py"    "scan.py"
  "core/report.py"  "report.py"
  "core/utils.py"   "utils.py"
)

TOTAL=$(( ${#FILES[@]} / 2 ))
COUNT=0

for (( i=0; i<${#FILES[@]}; i+=2 )); do
  remote="${FILES[$i]}"
  local_name="${FILES[$i+1]}"
  COUNT=$(( COUNT + 1 ))
  install_info "(${COUNT}/${TOTAL})  Downloading ${I_GOLD}${remote}${I_RESET}..."
  download_file "${BASE_URL}/${remote}" "${TMP_DIR}/${local_name}"
done

install_ok "All files downloaded."
echo ""
echo -e "${I_GREY}$(install_repeat_char "$I_BAR" "$COLS")${I_RESET}"

# ── Install ───────────────────────────────────────────────────────────
echo ""
echo -e "  ${I_BOLD}${I_BRIGHT_GOLD}${I_DIAMOND} INSTALLING${I_RESET}"
echo ""

install_info "Creating ${I_GOLD}${LIB_DIR}${I_RESET}..."
sudo mkdir -p "$LIB_DIR"
sudo mkdir -p "$LIB_DIR/core"

install_info "Installing binary to ${I_GOLD}${INSTALL_BIN}${I_RESET}..."
sudo cp "${TMP_DIR}/sweptbyte" "$INSTALL_BIN"
sudo chmod +x "$INSTALL_BIN"

for f in common.sh linux.sh macos.sh dev.sh; do
  install_info "Installing ${I_GOLD}lib/${f}${I_RESET}..."
  sudo cp "${TMP_DIR}/${f}" "${LIB_DIR}/${f}"
done

for f in scan.py report.py utils.py; do
  install_info "Installing ${I_GOLD}core/${f}${I_RESET}..."
  sudo cp "${TMP_DIR}/${f}" "${LIB_DIR}/core/${f}"
done

install_ok "All files installed."
echo ""

# ── Verify on PATH ────────────────────────────────────────────────────
if command -v sweptbyte &>/dev/null; then
  install_ok "${I_GOLD}sweptbyte${I_RESET} is on your PATH and ready."
else
  install_warn "Installed but not found on PATH."
  install_info "Add to your shell profile: ${I_GOLD}export PATH=\"\$PATH:/usr/local/bin\"${I_RESET}"
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo -e "${I_BRIGHT_GOLD}$(install_repeat_char "$I_HH" "$COLS")${I_RESET}"
echo ""
install_center_text "${I_BOLD}${I_GREEN}${I_CHECK}  INSTALLATION COMPLETE${I_RESET}"
echo ""
install_center_text "${I_GREY}${I_DIM}Run SweptByte from anywhere:${I_RESET}"
echo ""
install_center_text "${I_BOLD}${I_GOLD}sudo sweptbyte${I_RESET}"
echo ""
install_center_text "${I_GREY}${I_DIM}A ByteCrest Corp Product  ${I_DIAMOND}  v${VERSION}${I_RESET}"
echo ""
echo -e "${I_BRIGHT_GOLD}$(install_repeat_char "$I_HH" "$COLS")${I_RESET}"
echo ""
