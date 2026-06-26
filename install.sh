#!/usr/bin/env bash
# bun-node — transparent node/npm/npx/yarn → bun shims
# Installs into bun's own bin dir — no PATH changes needed.
#
# Install:   curl -fsSL https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh | bash
# Uninstall: bun-node-uninstall
# Update:    bun-node-update

set -euo pipefail

# ── Config ───────────────────────────────────────────────────────────────────
SPOOF_NODE_VERSION="v22.14.0"
SPOOF_NPM_VERSION="10.9.2"
SPOOF_YARN_VERSION="1.22.22"

# ── Colours ──────────────────────────────────────────────────────────────────
if [ -t 1 ]; then
  BOLD='\033[1m'; DIM='\033[2m'; RED='\033[0;31m'
  GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; RED=''; GREEN=''; YELLOW=''; CYAN=''; RESET=''
fi

step()  { printf "${CYAN}  →${RESET}  %s\n" "$*"; }
ok()    { printf "${GREEN}  ✓${RESET}  %s\n" "$*"; }
warn()  { printf "${YELLOW}  !${RESET}  %s\n" "$*" >&2; }
fatal() { printf "${RED}  ✗${RESET}  %s\n" "$*" >&2; exit 1; }

# ── Preflight ────────────────────────────────────────────────────────────────
echo ""
printf "${BOLD}bun-node installer${RESET}${DIM}  node/npm/npx/yarn → bun${RESET}\n"
echo "──────────────────────────────────────────"
echo ""

command -v bun &>/dev/null \
  || fatal "bun is not installed. Get it at https://bun.sh"

BUN_BIN_PATH="$(command -v bun)"
BUN_VERSION="$(bun --version 2>/dev/null)"
ok "Found bun ${BUN_VERSION} at ${BUN_BIN_PATH}"

# Derive BIN_DIR from where bun actually lives — not a hardcoded default.
# This handles non-standard installs (Homebrew, Nix, custom prefix, etc.)
BIN_DIR="$(dirname "$BUN_BIN_PATH")"
ok "Install target: ${BIN_DIR}"

# Warn if the derived dir isn't in PATH (shouldn't happen, but be safe).
if ! echo "$PATH" | tr ':' '\n' | grep -qxF "$BIN_DIR"; then
  warn "$BIN_DIR is not in your PATH — shims will be written but may not be active."
fi

# Detect existing shims and offer to update rather than blindly overwrite.
EXISTING=()
for shim in node npm npx yarn; do
  [ -f "$BIN_DIR/$shim" ] && EXISTING+=("$shim")
done

if [ "${#EXISTING[@]}" -gt 0 ]; then
  printf "${YELLOW}  !${RESET}  Existing shims found: %s\n" "${EXISTING[*]}" >&2
  printf "     Re-running will update them in place. Continue? [Y/n] "
  read -r reply </dev/tty
  case "${reply:-Y}" in
    [Yy]*|"") : ;;
    *) echo "Aborted."; exit 0 ;;
  esac
fi

# ── Shared helpers written into each shim ────────────────────────────────────
# BIN_DIR is baked in at install time so shims can exclude themselves from PATH
# without hardcoding a path that might differ from where bun actually lives.
SHIM_BIN_DIR="$BIN_DIR"

# ── Write shim: node ─────────────────────────────────────────────────────────
step "Writing node shim"
cat > "$BIN_DIR/node" << SHIM
#!/usr/bin/env bash
# bun-node shim: node → bun
# https://github.com/bethropolis/bun-node

[ "\${BUN_NODE_DEBUG:-}" = "1" ] && echo "[bun-node] node \$*" >&2

# Absolute path to bun, baked in at install time.
_bun="${BUN_BIN_PATH}"
[ -x "\$_bun" ] || { echo "bun-node: bun not found at \$_bun" >&2; exit 127; }

# Read .node-version or .nvmrc from cwd upward for per-project version spoofing.
_spoof_version() {
  local dir="\$PWD"
  while [ "\$dir" != "/" ]; do
    if [ -f "\$dir/.node-version" ]; then
      cat "\$dir/.node-version"; return
    elif [ -f "\$dir/.nvmrc" ]; then
      cat "\$dir/.nvmrc"; return
    fi
    dir="\$(dirname "\$dir")"
  done
  echo "\${BUN_NODE_SPOOF_VERSION:-${SPOOF_NODE_VERSION}}"
}

case "\${1-}" in
  --version|-v)
    ver="\$(_spoof_version)"
    # Normalise: ensure it starts with v
    [[ "\$ver" == v* ]] || ver="v\$ver"
    echo "\$ver"
    ;;
  --print|-p)
    shift
    exec "\$_bun" -e "console.log(\$1)"
    ;;
  -e|--eval)
    shift
    exec "\$_bun" -e "\$@"
    ;;
  *)
    exec "\$_bun" "\$@"
    ;;
esac
SHIM

# ── Write shim: npm ──────────────────────────────────────────────────────────
step "Writing npm shim"
cat > "$BIN_DIR/npm" << SHIM
#!/usr/bin/env bash
# bun-node shim: npm → bun
# https://github.com/bethropolis/bun-node

[ "\${BUN_NODE_DEBUG:-}" = "1" ] && echo "[bun-node] npm \$*" >&2

_bun="${BUN_BIN_PATH}"
[ -x "\$_bun" ] || { echo "bun-node: bun not found at \$_bun" >&2; exit 127; }

# Find the real npm by excluding our shim dir from PATH.
_real_npm() {
  PATH="\$(echo "\$PATH" | tr ':' '\n' | grep -vxF "${SHIM_BIN_DIR}" | tr '\n' ':')" command -v npm 2>/dev/null
}

# Translate npm install flags → bun add flags.
# Handles: --save-dev/-D, --save-optional/-O, --save-exact/-E, --global/-g
_translate_install_flags() {
  local args=() pkg_args=()
  local is_global=0
  while [ "\$#" -gt 0 ]; do
    case "\$1" in
      --save-dev|-D)         pkg_args+=("-d") ;;
      --save-optional|-O)    pkg_args+=("--optional") ;;
      --save-exact|-E)       pkg_args+=("--exact") ;;
      --global|-g)           is_global=1 ;;
      --save|-S)             : ;; # default in bun, no-op
      --no-save)             pkg_args+=("--no-save") ;;
      *)                     args+=("\$1") ;;
    esac
    shift
  done
  if [ "\$is_global" = "1" ]; then
    echo "g \${pkg_args[*]-} \${args[*]-}"
  else
    echo " \${pkg_args[*]-} \${args[*]-}"
  fi
}

case "\${1-}" in
  # ── Version / meta ──────────────────────────────────────────────────────
  --version|-v)
    echo "\${BUN_NODE_SPOOF_NPM_VERSION:-${SPOOF_NPM_VERSION}}"
    ;;

  # ── Install ─────────────────────────────────────────────────────────────
  install|i)
    shift
    if [ "\$#" -eq 0 ]; then
      exec "\$_bun" install
    else
      translated="\$(_translate_install_flags "\$@")"
      is_global="\${translated%% *}"
      rest="\${translated#* }"
      if [ "\$is_global" = "g" ]; then
        # shellcheck disable=SC2086
        exec "\$_bun" add --global \$rest
      else
        # shellcheck disable=SC2086
        exec "\$_bun" add \$rest
      fi
    fi
    ;;

  # ── ci (frozen install — critical for CI pipelines) ─────────────────────
  ci)
    exec "\$_bun" install --frozen-lockfile
    ;;

  # ── Remove ──────────────────────────────────────────────────────────────
  uninstall|remove|rm|un|r)
    shift; exec "\$_bun" remove "\$@"
    ;;

  # ── List ────────────────────────────────────────────────────────────────
  ls|list|ll|la)
    shift; exec "\$_bun" pm ls "\$@"
    ;;

  # ── Link ────────────────────────────────────────────────────────────────
  link)
    shift; exec "\$_bun" link "\$@"
    ;;
  unlink)
    shift; exec "\$_bun" unlink "\$@"
    ;;

  # ── Scripts ─────────────────────────────────────────────────────────────
  run|run-script)
    shift; exec "\$_bun" run "\$@"
    ;;
  start)
    exec "\$_bun" run start
    ;;
  test|t)
    shift; exec "\$_bun" test "\$@"
    ;;

  # ── Update ──────────────────────────────────────────────────────────────
  update|up|upgrade)
    shift; exec "\$_bun" update "\$@"
    ;;

  # ── Exec / dlx ──────────────────────────────────────────────────────────
  exec|x)
    shift; exec "\$_bun" x "\$@"
    ;;

  # ── Init ────────────────────────────────────────────────────────────────
  init)
    shift; exec "\$_bun" init "\$@"
    ;;

  # ── node-gyp: native addons can't run under bun — fail clearly ──────────
  # (npm install of a gyp package triggers this internally)
  node-gyp)
    echo "bun-node: native addons (.node files / node-gyp) are not supported by bun." >&2
    echo "bun-node: You'll need Node.js for this package." >&2
    exit 1
    ;;

  # ── Publish / Pack ──────────────────────────────────────────────────────
  publish)
    shift; exec "\$_bun" publish "\$@"
    ;;
  pack)
    shift; exec "\$_bun" pm pack "\$@"
    ;;

  # ── Audit ───────────────────────────────────────────────────────────────
  audit)
    exec "\$_bun" audit
    ;;

  # ── Whoami ──────────────────────────────────────────────────────────────
  whoami)
    exec "\$_bun" pm whoami
    ;;

  # ── Commands bun doesn't support — fall back to real npm ────────────────
  deprecate|owner|team|org|hook|fund|token|profile|stars|adduser|login|logout|ping|access|dist-tag|shrinkwrap|doctor)
    _npm="\$(_real_npm)"
    if [ -n "\$_npm" ]; then
      echo "bun-node: '\$1' is unsupported by bun — delegating to real npm at \$_npm" >&2
      exec "\$_npm" "\$@"
    else
      echo "bun-node: 'npm \$1' is not supported by bun and no real npm was found." >&2
      echo "bun-node: Install npm (https://docs.npmjs.com/downloading-and-installing-node-js-and-npm) to use this command." >&2
      exit 1
    fi
    ;;

  # ── Prefix ──────────────────────────────────────────────────────
  prefix)
    shift
    if [ "\${1-}" = "-g" ] || [ "\${1-}" = "--global" ]; then
      dirname "\$(bun pm bin -g 2>/dev/null)"
    else
      dir="\$PWD"
      while [ "\$dir" != "/" ]; do
        if [ -f "\$dir/package.json" ] || [ -d "\$dir/node_modules" ]; then
          echo "\$dir"
          break
        fi
        dir="\$(dirname "\$dir")"
      done
      [ "\$dir" = "/" ] && echo "\$PWD"
    fi
    ;;

  # ── Passthrough ─────────────────────────────────────────────────────────
  *)
    exec "\$_bun" "\$@"
    ;;
esac
SHIM

# ── Write shim: npx ──────────────────────────────────────────────────────────
step "Writing npx shim"
cat > "$BIN_DIR/npx" << SHIM
#!/usr/bin/env bash
# bun-node shim: npx → bun x
# https://github.com/bethropolis/bun-node

[ "\${BUN_NODE_DEBUG:-}" = "1" ] && echo "[bun-node] npx \$*" >&2

_bun="${BUN_BIN_PATH}"
[ -x "\$_bun" ] || { echo "bun-node: bun not found at \$_bun" >&2; exit 127; }

case "\${1-}" in
  --version|-v)
    echo "\${BUN_NODE_SPOOF_NPM_VERSION:-${SPOOF_NPM_VERSION}}"
    ;;
  # bunx never needs -y / --yes — strip silently.
  -y|--yes)
    shift; exec "\$_bun" x "\$@"
    ;;
  # --no-install: honour intent with --prefer-offline.
  --no-install)
    shift; exec "\$_bun" x --prefer-offline "\$@"
    ;;
  # node-gyp: fail clearly rather than letting bun give a confusing error.
  node-gyp)
    echo "bun-node: native addons (.node files / node-gyp) are not supported by bun." >&2
    echo "bun-node: You'll need Node.js for this package." >&2
    exit 1
    ;;
  *)
    exec "\$_bun" x "\$@"
    ;;
esac
SHIM

# ── Write shim: yarn ─────────────────────────────────────────────────────────
step "Writing yarn shim"
cat > "$BIN_DIR/yarn" << SHIM
#!/usr/bin/env bash
# bun-node shim: yarn → bun
# https://github.com/bethropolis/bun-node

[ "\${BUN_NODE_DEBUG:-}" = "1" ] && echo "[bun-node] yarn \$*" >&2

_bun="${BUN_BIN_PATH}"
[ -x "\$_bun" ] || { echo "bun-node: bun not found at \$_bun" >&2; exit 127; }

_real_yarn() {
  PATH="\$(echo "\$PATH" | tr ':' '\n' | grep -vxF "${SHIM_BIN_DIR}" | tr '\n' ':')" command -v yarn 2>/dev/null
}

case "\${1-}" in
  --version|-v)
    echo "\${BUN_NODE_SPOOF_YARN_VERSION:-${SPOOF_YARN_VERSION}}"
    ;;
  # bare "yarn" with no args = install
  "")
    exec "\$_bun" install
    ;;
  add)
    shift; exec "\$_bun" add "\$@"
    ;;
  remove|rm)
    shift; exec "\$_bun" remove "\$@"
    ;;
  install)
    shift; exec "\$_bun" install "\$@"
    ;;
  run)
    shift; exec "\$_bun" run "\$@"
    ;;
  # bare "yarn <script>" — yarn allows calling scripts without "run"
  # Try bun run; if the script doesn't exist bun will error naturally.
  start|build|test|dev|lint|format|clean|typecheck|check)
    exec "\$_bun" run "\$@"
    ;;
  upgrade|up)
    shift; exec "\$_bun" update "\$@"
    ;;
  global)
    # "yarn global add <pkg>" → "bun add --global <pkg>"
    sub="\${2-}"
    shift 2 || shift
    case "\$sub" in
      add)    exec "\$_bun" add --global "\$@" ;;
      remove) exec "\$_bun" remove --global "\$@" ;;
      *)      exec "\$_bun" "\$sub" "\$@" ;;
    esac
    ;;
  dlx)
    shift; exec "\$_bun" x "\$@"
    ;;
  exec)
    shift; exec "\$_bun" x "\$@"
    ;;
  init)
    shift; exec "\$_bun" init "\$@"
    ;;
  link)
    shift; exec "\$_bun" link "\$@"
    ;;
  unlink)
    shift; exec "\$_bun" unlink "\$@"
    ;;
  info)
    shift; exec "\$_bun" pm "\$@"
    ;;
  # Commands with no bun equivalent — fall back to real yarn if present.
  publish|pack|login|logout|owner|team|workspace|workspaces|policies|why|outdated|licenses|audit|import|create)
    _yarn="\$(_real_yarn)"
    if [ -n "\$_yarn" ]; then
      echo "bun-node: '\$1' unsupported by bun — delegating to real yarn at \$_yarn" >&2
      exec "\$_yarn" "\$@"
    else
      echo "bun-node: 'yarn \$1' is not supported by bun and no real yarn was found." >&2
      exit 1
    fi
    ;;
  # Unknown: pass straight through and let bun decide.
  *)
    exec "\$_bun" run "\$@"
    ;;
esac
SHIM

chmod +x "$BIN_DIR/node" "$BIN_DIR/npm" "$BIN_DIR/npx" "$BIN_DIR/yarn"
ok "Shims written and made executable"

# ── Write: bun-node status ───────────────────────────────────────────────────
step "Writing bun-node status"
cat > "$BIN_DIR/bun-node" << SHIM
#!/usr/bin/env bash
# bun-node — meta command for status, update, and help
# https://github.com/bethropolis/bun-node

BIN_DIR="${SHIM_BIN_DIR}"

if [ -t 1 ]; then
  BOLD='\033[1m'; DIM='\033[2m'; GREEN='\033[0;32m'
  YELLOW='\033[1;33m'; CYAN='\033[0;36m'; RED='\033[0;31m'; RESET='\033[0m'
else
  BOLD=''; DIM=''; GREEN=''; YELLOW=''; CYAN=''; RED=''; RESET=''
fi

_shim_ok() {
  [ -f "\$BIN_DIR/\$1" ] && echo "${GREEN}✓${RESET}" || echo "${RED}✗${RESET}"
}

case "\${1-status}" in
  status)
    echo ""
    printf "\${BOLD}bun-node\${RESET}\${DIM}  node/npm/npx/yarn → bun\${RESET}\n"
    echo "──────────────────────────────────────────"
    echo ""
    printf "  \${DIM}bun\${RESET}       \$(command -v bun 2>/dev/null || echo 'not found')  v\$(bun --version 2>/dev/null || echo '?')\n"
    printf "  \${DIM}shim dir\${RESET}  \$BIN_DIR\n"
    echo ""
    printf "  \$(_shim_ok node)  node   "
    [ -f "\$BIN_DIR/node" ] \
      && printf "\${DIM}→ bun\${RESET}  (spoof: \$(BUN_NODE_SPOOF_VERSION='' node --version 2>/dev/null || echo '?'))\n" \
      || printf "\${RED}not installed\${RESET}\n"
    printf "  \$(_shim_ok npm)  npm    "
    [ -f "\$BIN_DIR/npm" ] \
      && printf "\${DIM}→ bun\${RESET}  (spoof: \$(BUN_NODE_SPOOF_NPM_VERSION='' npm --version 2>/dev/null || echo '?'))\n" \
      || printf "\${RED}not installed\${RESET}\n"
    printf "  \$(_shim_ok npx)  npx    "
    [ -f "\$BIN_DIR/npx" ] \
      && printf "\${DIM}→ bunx\${RESET}\n" \
      || printf "\${RED}not installed\${RESET}\n"
    printf "  \$(_shim_ok yarn)  yarn   "
    [ -f "\$BIN_DIR/yarn" ] \
      && printf "\${DIM}→ bun\${RESET}  (spoof: \$(BUN_NODE_SPOOF_YARN_VERSION='' yarn --version 2>/dev/null || echo '?'))\n" \
      || printf "\${RED}not installed\${RESET}\n"
    echo ""
    printf "  \${DIM}debug\${RESET}     export BUN_NODE_DEBUG=1  (logs every translation)\n"
    echo ""
    ;;
  help|-h|--help)
    echo ""
    printf "  \${BOLD}bun-node\${RESET} <command>\n\n"
    printf "  status   show installed shims and versions (default)\n"
    printf "  help     this message\n"
    echo ""
    ;;
  *)
    echo "bun-node: unknown command '\$1'. Run 'bun-node status' or 'bun-node help'." >&2
    exit 1
    ;;
esac
SHIM
chmod +x "$BIN_DIR/bun-node"
ok "bun-node status command written"

# ── Write: bun-node-uninstall ─────────────────────────────────────────────────
step "Writing uninstaller"
cat > "$BIN_DIR/bun-node-uninstall" << UNINSTALL
#!/usr/bin/env bash
set -euo pipefail
BIN_DIR="${SHIM_BIN_DIR}"
echo "Removing bun-node shims from \$BIN_DIR ..."
rm -f "\$BIN_DIR/node" "\$BIN_DIR/npm" "\$BIN_DIR/npx" "\$BIN_DIR/yarn" \
      "\$BIN_DIR/bun-node" "\$BIN_DIR/bun-node-uninstall"
echo "Done. bun itself is untouched."
UNINSTALL
chmod +x "$BIN_DIR/bun-node-uninstall"

# ── Write: bun-node-update ────────────────────────────────────────────────────
step "Writing updater"
cat > "$BIN_DIR/bun-node-update" << 'UPDATE'
#!/usr/bin/env bash
set -euo pipefail
echo "Updating bun-node..."
curl -fsSL https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh | bash
UPDATE
chmod +x "$BIN_DIR/bun-node-update"
ok "Updater written"

# ── Done ─────────────────────────────────────────────────────────────────────
echo ""
echo "──────────────────────────────────────────"
printf "${GREEN}${BOLD}  bun-node installed!${RESET}\n"
echo "──────────────────────────────────────────"
echo ""
printf "  ${DIM}shims${RESET}     node  npm  npx  yarn\n"
printf "  ${DIM}location${RESET}  $BIN_DIR\n"
printf "  ${DIM}PATH${RESET}      no changes — bun already owns this dir\n"
echo ""
printf "  Verify:\n"
printf "    ${BOLD}bun-node status${RESET}\n"
echo ""
printf "  Debug mode:\n"
printf "    ${BOLD}BUN_NODE_DEBUG=1 npm install${RESET}\n"
echo ""
printf "  To update:    ${BOLD}bun-node-update${RESET}\n"
printf "  To uninstall: ${BOLD}bun-node-uninstall${RESET}\n"
echo ""
