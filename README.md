# sweptbyte

## 1. What sweptbyte is

sweptbyte is a root-run cleanup CLI for Linux and macOS developer machines: it detects the host OS, runs platform-specific package/cache/log/container cleanup, scans for large files, broken symlinks, and `node_modules`, and reports disk usage before and after so developers, power users, and workstation admins can reclaim disposable space through one repeatable command.

## 2. How the files connect

`install.sh` - Installer entrypoint; detects installer OS, checks installer dependencies, downloads the executable plus `lib/` and `core/` files from GitHub, then hands execution to the installed `/usr/local/bin/sweptbyte` command when the user runs it later.

`bin/sweptbyte` - Installed CLI entrypoint; loads `/usr/local/lib/sweptbyte/common.sh`, parses flags, validates runtime requirements, coordinates OS-specific `lib/` modules and Python `core/` helpers, then prints the final disk report.

`lib/common.sh` - Shared shell layer; owns colors, glyphs, terminal helpers, `detect_os`, self-update, help UI, progress UI, and the command-level section runner that `linux.sh`, `macos.sh`, and `dev.sh` are supposed to call.

`lib/linux.sh` - Linux cleanup module; owns APT/Pacman/DNF/APK, journal, cache, temp, Snap, Flatpak, Docker, and old-kernel cleanup, and hands each command group to the shared `run_section` runner in `common.sh`.

`lib/macos.sh` - macOS cleanup module; owns Homebrew, user cache, system cache, temp, DNS, Xcode, and Docker cleanup, and hands each command group to the shared `run_section` runner in `common.sh`.

`lib/dev.sh` - Cross-platform developer cleanup module; owns pip, npm, Yarn, pnpm, Cargo, RubyGems, Gradle, and Maven cleanup. It reads developer cache targets from the scan JSON and hands cleanup groups to `common.sh`.

`core/report.py` - Python disk reporter; owns `--snapshot` JSON capture and `--compare` before/after rendering for `bin/sweptbyte`.

`core/scan.py` - Python filesystem scanner; owns large-file, broken-symlink, and `node_modules` discovery for `bin/sweptbyte` and `lib/dev.sh`.

`core/utils.py` - Shared Python helpers; owns size formatting, directory sizing, shell command execution helper, scan skip rules, and reusable scan helpers.

`sweptbyte.sh` - Legacy monolithic v1.1 script; duplicates older Linux/macOS cleanup logic but is not installed by `install.sh` and is not part of the current modular execution path.

`uninstall.sh` - Intended uninstall entrypoint; currently only prints a message and does not remove installed files.

`CHANGELOG.md` - Intended release history; currently empty and not used by install or runtime.

Dependency chain:

```text
install.sh
  -> /usr/local/bin/sweptbyte
    -> /usr/local/lib/sweptbyte/common.sh
      -> /usr/local/lib/sweptbyte/linux.sh or /usr/local/lib/sweptbyte/macos.sh
      -> /usr/local/lib/sweptbyte/dev.sh
        -> /usr/local/lib/sweptbyte/core/scan.py
          -> /usr/local/lib/sweptbyte/core/utils.py
      -> /usr/local/lib/sweptbyte/core/report.py
```

## 3. How it works - runtime flow

When a user runs `sudo sweptbyte`, the installed command starts in `bin/sweptbyte` and sets `LIB_DIR=/usr/local/lib/sweptbyte`, `CORE_DIR=/usr/local/lib/sweptbyte/core`, and `VERSION=2.0.0`.

Flag parsing happens before root and Python checks:

- `--dry-run` sets `DRY_RUN=true`; the shared section runner is intended to print cleanup labels and skip command execution.
- `--auto` sets `AUTO=true`; no code currently reads it, so it does not change behavior.
- `--section <name>` stores the requested section name and is intended to run only that section.
- `--update` calls `self_update` from `common.sh`, which runs the GitHub installer with `curl -fsSL .../install.sh | bash`, then exits.
- `--version` or `-v` prints `sweptbyte v2.0.0 - ByteCrest Corp`, then exits.
- `--help` or `-h` prints the inline help text in `bin/sweptbyte`, then exits.
- Unknown flags print `sweptbyte: unknown option: <flag>`, set `SHOW_HELP=true`, and then exit successfully after showing help.

After flags, the command exports `DRY_RUN`, `AUTO`, `LIB_DIR`, and `CORE_DIR`, then checks `EUID`; if the user did not run as root, it tries to call `die "sweptbyte must be run as root. Use: sudo sweptbyte"`. It then checks for `python3`; if Python is missing, it tries to call `die "python3 is required but not found. Install it and re-run."`.

The next intended step is the banner print. `bin/sweptbyte` currently calls `print_banner`, but `common.sh` defines `show_splash`, not `print_banner`, so the current runtime stops here before cleanup until that naming bug is fixed.

After the banner, the intended flow is to take a disk snapshot with:

```bash
python3 "$CORE_DIR/report.py" --snapshot
```

The resulting JSON is stored in `DISK_BEFORE` and passed to the final compare step later.

`detect_os` from `common.sh` then identifies the platform. In the intended full run, Linux-like results should route to `linux.sh`, and `macos` should route to `macos.sh`. The current `bin/sweptbyte` full-run dispatcher sources the right file, but then calls `run_system`, `run_logs`, `run_docker`, and `run_kernels`; those functions do not exist. The modules currently expose `run_linux` and `run_macos`, so the OS cleanup path is broken until the dispatcher and module APIs are aligned.

For `sudo sweptbyte` without `--section`, the intended order is:

1. Parse flags.
2. Check root.
3. Check `python3`.
4. Print the banner.
5. Capture the before snapshot through `core/report.py --snapshot`.
6. Detect the OS through `detect_os`.
7. Route Linux-like systems to `lib/linux.sh` or macOS to `lib/macos.sh`.
8. Run OS cleanup sections.
9. Always source `lib/dev.sh` and run `run_dev` for cross-platform developer cleanup.
10. Always run `core/scan.py` for large-file, broken-symlink, and `node_modules` reporting.
11. Print the final before/after disk report with:

```bash
python3 "$CORE_DIR/report.py" --compare "$DISK_BEFORE"
```

## 4. How to install

```bash
curl -fsSL https://raw.githubusercontent.com/bytecrest43/sweptbyte/main/install.sh | bash
```

The installer downloads the command and support files from the `main` branch of `bytecrest43/sweptbyte`, stages them in a temporary directory, requests sudo, and installs them into system locations.

Installed paths:

- `/usr/local/bin/sweptbyte` - the command users run.
- `/usr/local/lib/sweptbyte/` - all shell library files and Python core files.
- `/usr/local/lib/sweptbyte/common.sh` - shared shell helpers.
- `/usr/local/lib/sweptbyte/linux.sh` - Linux cleanup module.
- `/usr/local/lib/sweptbyte/macos.sh` - macOS cleanup module.
- `/usr/local/lib/sweptbyte/dev.sh` - cross-platform developer cleanup module.
- `/usr/local/lib/sweptbyte/core/utils.py` - shared Python helpers.
- `/usr/local/lib/sweptbyte/core/report.py` - disk report helper.
- `/usr/local/lib/sweptbyte/core/scan.py` - filesystem scan helper.

## 5. How cross-platform detection works

`detect_os` in `common.sh` calls `uname -s` and maps the result to a small OS type string.

Returned values:

- `debian` - returned on Linux when `/etc/debian_version` exists.
- `arch` - returned on Linux when `/etc/arch-release` exists.
- `fedora` - returned on Linux when `/etc/fedora-release` exists.
- `alpine` - returned on Linux when `/etc/alpine-release` exists.
- `linux` - returned for other Linux systems.
- `macos` - returned when `uname -s` starts with `Darwin`.

Unsupported `uname -s` values print `Unsupported OS: <name>` and exit.

`bin/sweptbyte` routes OS types like this:

- `debian`, `ubuntu`, `arch`, `fedora`, `rhel`, `alpine`, and `linux` route to `lib/linux.sh`.
- `macos` routes to `lib/macos.sh`.
- Any other value warns that the OS could not be detected and skips system sections.

The full list of OS types handled by the current router is `debian`, `ubuntu`, `arch`, `fedora`, `rhel`, `alpine`, `linux`, and `macos`. The full list actually returned by `detect_os` is `debian`, `arch`, `fedora`, `alpine`, `linux`, and `macos`; `ubuntu` and `rhel` are routed in `bin/sweptbyte` but never returned by `detect_os`.

## 6. Bugs and gaps to fix

`install.sh`:

- Missing shebang. Direct execution relies on the caller choosing Bash; fix by adding `#!/usr/bin/env bash`.
- Python is treated as optional during install, but `bin/sweptbyte` requires Python at runtime. Fix by making `python3` a hard installer dependency or making runtime Python features truly optional.
- The installer checks for `curl` and `bash`, but not `sudo`, `mktemp`, `sed`, `grep`, `head`, `tput`, or `clear`. Fix by checking required commands or degrading safely for cosmetic commands.
- It uses `declare -A`, which requires Bash 4+, but only macOS gets a Bash major-version check. Fix by validating Bash 4+ on every platform.
- Downloads executable code from the `main` branch without checksum, signature, tag pinning, or release version validation. Fix by installing from a versioned release and verifying integrity.
- The associative-array download manifest installs files in nondeterministic order. This is not currently fatal, but logs are unstable; fix by using an ordered list.
- It does not remove stale files from older installs. Fix by deleting or reconciling files under `/usr/local/lib/sweptbyte` that are no longer in the manifest.
- It installs `/usr/local/bin/sweptbyte` even though that file has no shebang. Fix the installed file, not just the installer.
- It does not install `uninstall.sh`, `README.md`, `CHANGELOG.md`, or license metadata. Fix if packaged installs should include docs and uninstall support.

`bin/sweptbyte`:

- Missing shebang. `/usr/local/bin/sweptbyte` may be interpreted by the user's shell or `/bin/sh`, which is unsafe for Bash-specific syntax. Fix by adding `#!/usr/bin/env bash`.
- Calls `die`, but `common.sh` does not define `die`. Root, Python, and unknown-section failures can become `die: command not found`. Fix by adding `die` to `common.sh` or replacing calls with existing `fail` plus `exit 1`.
- Calls `print_banner`, but `common.sh` defines `show_splash`. The current runtime stops before cleanup. Fix by calling `show_splash` or renaming the function consistently.
- Defines a dispatcher named `run_section`, overwriting the shared `run_section` from `common.sh`. After this, `linux.sh`, `macos.sh`, and `dev.sh` can no longer call the command runner they were written for. Fix by renaming the dispatcher, for example to `dispatch_section`.
- Full Linux runs call `run_system`, `run_logs`, `run_docker`, and `run_kernels`, but `linux.sh` only defines `run_linux`. Fix by either calling `run_linux` or splitting `linux.sh` into those functions.
- Full macOS runs call `run_system`, `run_logs`, and `run_docker`, but `macos.sh` only defines `run_macos`. Fix by either calling `run_macos` or splitting `macos.sh` into those functions.
- Targeted `--section system`, `--section logs`, `--section docker`, and `--section kernels` call `run_system`, `run_logs`, `run_docker`, or `run_kernels`; none exist. Fix the section API and help text together.
- The help text lists `system`, `logs`, `docker`, `dev`, and `scan`, while `common.sh` and the modules use section IDs such as `apt`, `journal`, `cache`, `tmp`, `brew`, `user-cache`, and `dev-npm`. Fix by publishing one canonical section list.
- `--auto` is parsed and exported but never used. Fix by adding interactive prompts that `--auto` bypasses, or remove the flag.
- `SECTION` is not exported. It is visible to sourced shell functions, but not subprocesses. Fix only if Python helpers need section awareness; otherwise document that it is shell-local.
- `HAS_PYTHON` is never set or exported, so `lib/dev.sh` skips `devclean.py --detect` and the extra node_modules report even though runtime already requires Python. Fix by setting `HAS_PYTHON=true` after the Python check.
- `OS_TYPE` is set, but `linux.sh` expects `OS`. If `run_linux` were called under `set -u`, references to `$OS` would fail. Fix by exporting `OS="$OS_TYPE"` or updating modules to use `OS_TYPE`.
- `core/report.py` is used without an `_require` check. Fix by validating `"$CORE_DIR/report.py"` before snapshot and compare.
- It calls `core/scan.py --large-files --broken-symlinks --node-modules`, but `scan.py` uses `if/elif`, so only `--large-files` runs. Fix `scan.py` to process all requested flags or call it once per scan type.
- Unknown options show help and exit with status `0`. Fix by exiting nonzero after an invalid option.
- `--dry-run` still requires root. A preview mode should not need full root unless scans intentionally inspect system-only paths; fix by moving the root check after dry-run planning or documenting why root is required.
- If an OS cleanup function fails under `set -e`, `lib/dev.sh`, `core/scan.py`, and the final disk report may never run. Fix by handling section failures consistently and preserving the final report path.

`lib/common.sh`:

- Defines `show_splash`, but `bin/sweptbyte` calls `print_banner`. Fix the name mismatch.
- Does not define `die`, but `bin/sweptbyte` calls it. Fix by adding a fatal error helper.
- Defines `show_help`, but `bin/sweptbyte` uses its own inline help. Fix by using one help implementation.
- Its section IDs differ from `bin/sweptbyte` help and dispatcher names. Fix by centralizing section definitions.
- `run_section` uses `eval` on command strings. Fix by using arrays/functions for commands, or tightly constrain any interpolated values.
- `run_section` captures command output to a temp file and deletes it even on failure, leaving no diagnostic detail. Fix by printing or preserving failed command output.
- `progress_bar` divides by `total`; if called with no commands it can divide by zero. Fix by guarding empty sections.
- `center_text` measures raw string length after stripping ANSI but not terminal display width, so Unicode glyphs and wide characters can misalign. Fix with a display-width-aware helper or keep banner text ASCII.
- `self_update` pipes remote code from `main` directly to Bash. Fix by using the same verified release mechanism as install.

`lib/linux.sh`:

- Exposes only `run_linux`, but `bin/sweptbyte` expects `run_system`, `run_logs`, `run_docker`, and `run_kernels`. Fix the module API.
- Requires `OS` to be exported, but `bin/sweptbyte` only sets `OS_TYPE`. Fix the variable contract.
- If `bin/sweptbyte` keeps its own `run_section` dispatcher, every cleanup call in this file will recurse into the wrong function signature. Fix the dispatcher name collision.
- `detect_os` never returns `ubuntu` or `rhel`, and this module only checks `debian`, `arch`, `fedora`, and `alpine`. Fix distro detection or remove unreachable router values.
- Fedora/RHEL support is incomplete: RHEL-like systems without `/etc/fedora-release` become `linux`, so DNF cleanup is skipped. Fix detection for `/etc/redhat-release` or `/etc/os-release`.
- Running the whole tool with `sudo` makes `~` resolve to root's home, so `rm -rf ~/.cache/*` cleans `/root/.cache`, not the invoking user's cache. Fix by using `SUDO_USER`/`getent` to find the original user's home for user-scoped cleanup.
- The broad `rm -rf ~/.cache/*` can remove active application caches indiscriminately. Fix by narrowing targets or prompting before broad cache deletion.
- Old-kernel removal keeps only the running kernel and `linux-image-generic`, which can remove useful fallback kernels. Fix by keeping the running kernel plus at least the latest fallback kernel and matching headers.
- Arch uses separate `pacman -Sy` and `pacman -Su`; this can create partial-upgrade risk. Fix with `pacman -Syu --noconfirm`.
- Flatpak cleanup runs as root when the tool is run with `sudo`, so it may miss the invoking user's user-level Flatpak installs. Fix by running user-level Flatpak cleanup as the original user.
- Docker cleanup prunes unused containers, images, volumes, and builder cache without confirmation outside dry-run. Fix by gating destructive container cleanup behind `--auto`, a prompt, or clearer section targeting.
- Package-manager cleanup also upgrades packages. Fix by separating "upgrade" from "cleanup" or documenting and gating upgrade behavior.

`lib/macos.sh`:

- Exposes only `run_macos`, but `bin/sweptbyte` expects `run_system`, `run_logs`, and `run_docker`. Fix the module API.
- If `bin/sweptbyte` keeps its own `run_section` dispatcher, every cleanup call in this file will call the wrong function. Fix the dispatcher name collision.
- The tool requires `sudo`, so `~` resolves to root's home; user cache, log, CrashReporter, and Xcode cleanup target root instead of the invoking user. Fix by resolving the original user's home.
- Homebrew is run as root, which Homebrew rejects. Fix by running Homebrew commands as the original user.
- Homebrew detection with `command -v brew` under sudo may miss `/opt/homebrew/bin/brew` or `/usr/local/bin/brew` from the user's shell. Fix by resolving common Homebrew paths or the original user's login environment.
- `sudo rm -rf /private/var/folders/*/*/C/*` is broad system cache deletion. Fix by narrowing scope and documenting risk.
- Docker cleanup assumes the Docker CLI can talk to a running Docker daemon. Fix by checking daemon availability before pruning.
- macOS has no `kernels` section, but `bin/sweptbyte --section kernels` routes `macos` to `run_kernels`, which does not exist. Fix section routing by OS.

`lib/dev.sh`:

- Depends on `HAS_PYTHON=true`, but `bin/sweptbyte` never sets it. Fix runtime exports.
- Uses `~` under `sudo`, so it cleans root's pip/npm/Yarn/pnpm/Cargo/Gem/Gradle/Maven caches instead of the invoking user's caches. Fix by targeting the original user's home and running user package-manager commands as that user.
- Calls `run_section`, which is overwritten by `bin/sweptbyte`. Fix the function name collision.
- `devclean.py` detects Go module and Composer caches, but `dev.sh` does not clean them. Fix by adding `dev-go` and `dev-composer` cleanup sections or removing them from detection.
- The pip cleanup tests `pip3` or `pip`, then starts with `pip3`; if only `pip` exists this relies on a failing command before fallback. Fix by selecting the executable first.
- Cargo cleanup removes registry sources as well as cache. Fix by confirming this is intended or limiting cleanup to download cache.
- Gradle cleanup removes downloaded modules, which can force large re-downloads and break offline builds. Fix by making it a targeted or prompted section.
- The node_modules scan is duplicated with the final `core/scan.py` call once `HAS_PYTHON` is fixed. Fix by choosing one place to report it.

`core/utils.py`:

- `human_size` returns `num_bytes` for PB values instead of the scaled `size` value. Fix the final line to `return f"{size:.1f} PB"`.
- `HOME = Path.home()` resolves to root when `sweptbyte` is run with `sudo`. Fix by deriving the invoking user's home from `SUDO_USER` when present.
- `run_command` is unused. Fix by removing it or using it.
- `run_command` uses `shell=True`. Fix by accepting argument arrays if it remains.
- `should_skip` only has a small hard-coded skip list. Fix by adding other expensive or virtual mount roots as needed, such as `/media`, `/mnt`, `/Volumes`, and container/runtime paths.

`core/report.py`:

- Only reports disk usage for `/`. Fix by reporting all relevant mounted filesystems or documenting that the summary is root-filesystem-only.
- `--compare` validates JSON syntax but not required keys. Fix by validating `total`, `used`, and `free` before comparing.
- The report width is hardcoded to 72 columns. Fix by detecting terminal width or matching `common.sh`.
- It duplicates `human_size` instead of using `utils.py`. Fix by sharing formatting or intentionally keeping it standalone.
- It can report disk usage increased after package upgrades, but the rest of the UI still frames the run as cleanup. Fix by making upgrade behavior explicit in the summary.

`core/scan.py`:

- Multiple flags are not cumulative because the CLI uses `if/elif`. `--large-files --broken-symlinks --node-modules` only runs the large-file scan. Fix by processing each present flag independently.
- Large-file scanning starts at `/`, can be slow, and can cross mounted filesystems. Fix by adding mount pruning, configurable roots, or time/progress limits.
- Large-file scanning skips all hidden directories, so it misses large files under paths like `~/.cache`, `.gradle`, `.npm`, and other developer caches. Fix by skipping only known unsafe paths, not every dot directory.
- Broken-symlink scanning only checks `filenames`, not symlinked directories listed in `dirnames`. Fix by checking both.
- `HOME` comes from `Path.home()` in `utils.py`, so scans run against root's home under `sudo`. Fix original-user home handling.
- It has no CLI options for minimum large-file size, result count, or scan root. Fix by adding argparse options.
- It reports cleanup suggestions but performs no cleanup for scan findings. That is acceptable for safety, but the help text should call it "reporting", not cleanup.

`core/devclean.py`:

- Uses `HOME` from `utils.py`, so cache detection targets root under `sudo`. Fix original-user home handling.
- Detects Go module and Composer caches that `dev.sh` never cleans. Fix by aligning detector and cleaner coverage.
- Yarn detection only checks `.yarn/cache`; Yarn classic commonly uses `~/.cache/yarn`. Fix by adding classic Yarn paths.
- pnpm detection only checks `.pnpm-store`; modern pnpm commonly stores data under `~/.local/share/pnpm/store`. Fix by adding modern pnpm paths.
- It has no JSON or machine-readable output. Fix if the shell layer needs structured decisions instead of display-only reporting.

`sweptbyte.sh`:

- It is a stale monolithic v1.1 implementation while the installer installs the modular v2 files. Fix by deleting it, renaming it as legacy documentation, or updating it to delegate to `bin/sweptbyte`.
- Missing shebang. Fix by adding `#!/usr/bin/env bash` if it remains executable.
- It duplicates OS detection, UI, section runner, Linux cleanup, and macOS cleanup. Fix by keeping one implementation.
- It has no `--dry-run`, `--auto`, `--section`, `--update`, `--version`, or `--help` handling. Fix by removing it or bringing it to v2 parity.
- It has no Python disk snapshot, final compare report, developer cache detector, large-file scan, broken-symlink scan, or `node_modules` scan. Fix by removing it or wiring it to `core/`.
- It reports version `1.1.0`, conflicting with v2.0.0 in the installer, `bin/sweptbyte`, and `common.sh`. Fix version ownership.

`uninstall.sh`:

- It does not uninstall anything; it only prints `Uninstalling sweptbyte...`. Fix by removing `/usr/local/bin/sweptbyte` and `/usr/local/lib/sweptbyte`.
- It does not request sudo even though installed paths require elevated permissions. Fix by using `sudo` or requiring root.
- It is not installed by `install.sh`. Fix by installing it or documenting manual uninstall commands.
- It has no verification, dry-run, or success/failure output. Fix by checking paths before and after removal.

`CHANGELOG.md`:

- Empty. Fix by documenting v1.1 legacy state, v2.0 modular install/runtime changes, and known breaking issues.

`README.md`:

- The previous README described v1.1 behavior, claimed there was no dry-run mode, omitted the modular `bin/`, `lib/`, and `core/` architecture, and did not document current runtime breakages. This file replaces it with the current audit.
