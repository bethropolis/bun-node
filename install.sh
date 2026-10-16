#!/usr/bin/env bash
# bun-node — node/npm/npx/yarn compatibility shims backed by Bun.
# Install:   curl -fsSL https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh | bash
# Uninstall: bun-node-uninstall
# Update:    bun-node-update

set -Eeuo pipefail

readonly VERSION='2.0.0'
readonly MIN_BUN_MAJOR=1 MIN_BUN_MINOR=4 MIN_BUN_PATCH=2
readonly SPOOF_NODE_VERSION='v24.5.0'
readonly SPOOF_NPM_VERSION='12.2.0'
readonly SPOOF_YARN_VERSION='1.22.22'
readonly REPO='https://github.com/bethropolis/bun-node'
readonly RAW_INSTALL='https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh'

FORCE=0
QUIET=0
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=1 ;;
    --quiet|-q) QUIET=1 ;;
    --help|-h)
      cat <<'HELP'
bun-node installer

Usage: install.sh [--force] [--quiet]

  --force   Back up and replace conflicting files in Bun's bin directory.
  --quiet   Suppress progress messages (errors are still shown).
  --help    Show this help.

Existing non-bun-node files are never replaced without --force.
HELP
      exit 0
      ;;
    *) printf 'bun-node: unknown option: %s\n' "$arg" >&2; exit 2 ;;
  esac
done

if [[ -t 1 ]]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' RED=$'\033[0;31m'
  GREEN=$'\033[0;32m' YELLOW=$'\033[1;33m' CYAN=$'\033[0;36m' RESET=$'\033[0m'
else
  BOLD='' DIM='' RED='' GREEN='' YELLOW='' CYAN='' RESET=''
fi

say()  { (( QUIET )) || printf '%b  →%b  %s\n' "$CYAN" "$RESET" "$*"; }
ok()   { (( QUIET )) || printf '%b  ✓%b  %s\n' "$GREEN" "$RESET" "$*"; }
warn() { printf '%b  !%b  %s\n' "$YELLOW" "$RESET" "$*" >&2; }
die()  { printf '%b  ✗%b  %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }

command -v bun >/dev/null 2>&1 || die 'Bun is not installed. See https://bun.com.'
BUN_BIN_PATH="$(type -P bun || true)"
[[ -n "$BUN_BIN_PATH" && -x "$BUN_BIN_PATH" ]] || die 'Could not locate the Bun executable in PATH.'
[[ "$BUN_BIN_PATH" == /* ]] || BUN_BIN_PATH="$PWD/$BUN_BIN_PATH"
BUN_VERSION="$("$BUN_BIN_PATH" --version 2>/dev/null)" || die 'Could not run bun --version.'

if [[ "$BUN_VERSION" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+) ]]; then
  major=${BASH_REMATCH[1]} minor=${BASH_REMATCH[2]} patch=${BASH_REMATCH[3]}
  if (( major < MIN_BUN_MAJOR || (major == MIN_BUN_MAJOR && minor < MIN_BUN_MINOR) || (major == MIN_BUN_MAJOR && minor == MIN_BUN_MINOR && patch < MIN_BUN_PATCH) )); then
    die "Bun $MIN_BUN_MAJOR.$MIN_BUN_MINOR.$MIN_BUN_PATCH or newer is required; found $BUN_VERSION."
  fi
else
  die "Could not parse Bun version: $BUN_VERSION"
fi

BIN_DIR="$(dirname -- "$BUN_BIN_PATH")"
[[ -d "$BIN_DIR" && -w "$BIN_DIR" ]] || die "Bun's bin directory is not writable: $BIN_DIR"

if [[ ":${PATH}:" != *":${BIN_DIR}:"* ]]; then
  warn "$BIN_DIR is not in PATH; installed shims may not be active."
fi

if (( ! QUIET )); then
  printf '\n%b bun-node installer %b %s\n' "$BOLD" "$RESET" "$VERSION"
  printf '%bBun%b       %s (%s)\n' "$DIM" "$RESET" "$BUN_VERSION" "$BUN_BIN_PATH"
  printf '%bInstall to%b %s\n\n' "$DIM" "$RESET" "$BIN_DIR"
fi

# Managed executables include a marker so an unrelated file with the same name
# is not mistaken for a previous bun-node installation.
is_managed() {
  local name=$1 file="$BIN_DIR/$1"
  case "$name" in
    node|npm|npx|yarn)
      [[ -L "$file" && "$(readlink -- "$file" 2>/dev/null || true)" == 'bun-node-shim' ]]
      ;;
    *)
      [[ -f "$file" ]] && grep -qF 'bun-node-managed-file' "$file" 2>/dev/null
      ;;
  esac
}

DESTINATIONS=(bun-node-shim node npm npx yarn bun-node-prefix bun-node bun-node-uninstall bun-node-update)
CONFLICTS=()
for name in "${DESTINATIONS[@]}"; do
  file="$BIN_DIR/$name"
  if [[ -e "$file" || -L "$file" ]] && ! is_managed "$name"; then
    CONFLICTS+=("$name")
  fi
done

if ((${#CONFLICTS[@]})); then
  printf '%b  !%b  Conflicting files found: %s\n' "$YELLOW" "$RESET" "${CONFLICTS[*]}" >&2
  if (( ! FORCE )); then
    if [[ -r /dev/tty && -w /dev/tty ]]; then
      printf 'Back up these files and replace them? [y/N] ' >/dev/tty
      IFS= read -r answer </dev/tty || answer=''
      [[ "$answer" =~ ^[Yy]([Ee][Ss])?$ ]] || { echo 'Aborted.'; exit 0; }
    else
      die 'Non-interactive install has conflicts. Re-run with --force to back them up and replace them.'
    fi
  fi
fi

STAGE_DIR="$(mktemp -d "$BIN_DIR/.bun-node-stage.XXXXXX")" || die 'Could not create a staging directory.'
BACKUP_DIR=''
cleanup() { rm -rf -- "$STAGE_DIR"; }
trap cleanup EXIT

# One dispatcher handles all four command names. Its configured paths are
# shell-quoted by printf %q, so spaces and shell metacharacters are safe.
{
  printf '#!/usr/bin/env bash\n# bun-node-managed-file\n_BUN=%q\n_SHIM_BIN_DIR=%q\n_DEFAULT_NODE_VERSION=%q\n_DEFAULT_NPM_VERSION=%q\n_DEFAULT_YARN_VERSION=%q\n' \
    "$BUN_BIN_PATH" "$BIN_DIR" "$SPOOF_NODE_VERSION" "$SPOOF_NPM_VERSION" "$SPOOF_YARN_VERSION"
  cat <<'SHIM'
set -Eeuo pipefail

readonly _DEFAULT_NODE_VERSION _DEFAULT_NPM_VERSION _DEFAULT_YARN_VERSION
readonly _NPM_URL='https://docs.npmjs.com/downloading-and-installing-node-js-and-npm'
readonly _TOOL="${0##*/}"

_fail() { printf 'bun-node: %s\n' "$*" >&2; exit 1; }
_debug() {
  [[ "${BUN_NODE_DEBUG:-}" == 1 ]] || return 0
  printf '[bun-node] %s' "$_TOOL" >&2
  printf ' %q' "$@" >&2
  printf '\n' >&2
}
_need_bun() { [[ -x "$_BUN" ]] || _fail "Bun not found at $_BUN"; }

# Return the first matching executable outside bun-node's own bin directory.
_real_command() {
  local name=$1 dir candidate
  local -a dirs=()
  IFS=: read -r -a dirs <<< "${PATH-}"
  for dir in "${dirs[@]}"; do
    [[ -n "$dir" ]] || dir=.
    [[ "${dir%/}" == "${_SHIM_BIN_DIR%/}" ]] && continue
    candidate="$dir/$name"
    [[ -f "$candidate" && -x "$candidate" ]] || continue
    printf '%s\n' "$candidate"
    return 0
  done
  return 1
}

# Pull npm's --prefix/-C out of an argument list and leave all other argv
# elements intact. Arrays avoid word-splitting bugs for paths and arguments.
_BN_PREFIX=''
_BN_ARGS=()
_parse_prefix_args() {
  _BN_PREFIX=''
  _BN_ARGS=()
  while (($#)); do
    case "$1" in
      --prefix|-C)
        (($# >= 2)) || _fail "$1 requires a directory argument"
        _BN_PREFIX=$2
        # npm creates a fresh prefix directory on install; mirror that.
        mkdir -p -- "$_BN_PREFIX" || _fail "could not create prefix directory: $_BN_PREFIX"
        [[ -f "$_BN_PREFIX/package.json" ]] || printf '{}' > "$_BN_PREFIX/package.json"
        shift 2 ;;
      --prefix=*|-C=*)
        _BN_PREFIX=${1#*=}
        mkdir -p -- "$_BN_PREFIX" || _fail "could not create prefix directory: $_BN_PREFIX"
        [[ -f "$_BN_PREFIX/package.json" ]] || printf '{}' > "$_BN_PREFIX/package.json"
        shift ;;
      *) _BN_ARGS+=("$1"); shift ;;
    esac
  done
}
_run_bun() {
  local cwd=$1 command=$2; shift 2
  if [[ -n "$cwd" ]]; then exec "$_BUN" "$command" --cwd "$cwd" "$@"; fi
  exec "$_BUN" "$command" "$@"
}

_debug "$@"
_need_bun

case "$_TOOL" in
  node)
    _node_version() {
      local dir=$PWD file version
      while :; do
        for file in .node-version .nvmrc; do
          if [[ -f "$dir/$file" ]]; then
            IFS= read -r version < "$dir/$file" || :
            printf '%s\n' "$version"
            return
          fi
        done
        [[ "$dir" == / ]] && break
        dir=$(dirname -- "$dir")
      done
      printf '%s\n' "${BUN_NODE_SPOOF_VERSION:-$_DEFAULT_NODE_VERSION}"
    }
    case "${1-}" in
      --version|-v)
        version=$(_node_version)
        [[ "$version" == v* ]] || version="v$version"
        printf '%s\n' "$version" ;;
      --print|-p)
        shift
        exec "$_BUN" -e "console.log(${1-})" ;;
      -e|--eval)
        shift
        exec "$_BUN" -e "$@" ;;
      *) exec "$_BUN" "$@" ;;
    esac
    ;;

  npm)
    # npm permits --prefix before the command; normalize it to a command option.
    case "${1-}" in
      --prefix|-C)
        (($# >= 2)) || _fail "$1 requires a directory argument"
        _lead_prefix=$2; shift 2
        (($#)) || _fail 'expected an npm command after --prefix'
        set -- "$1" --prefix "$_lead_prefix" "${@:2}" ;;
      --prefix=*|-C=*)
        _lead_prefix=${1#*=}; shift
        (($#)) || _fail 'expected an npm command after --prefix'
        set -- "$1" --prefix "$_lead_prefix" "${@:2}" ;;
    esac
    case "${1-}" in
      --version|-v) printf '%s\n' "${BUN_NODE_SPOOF_NPM_VERSION:-$_DEFAULT_NPM_VERSION}" ;;
      install|i)
        shift; _parse_prefix_args "$@"
        # `npm install <pkg>` implies `bun add`; bare `npm install` implies install.
        _command=install
        for _arg in "${_BN_ARGS[@]}"; do
          if [[ "$_arg" != -* ]]; then _command=add; break; fi
        done
        _run_bun "$_BN_PREFIX" "$_command" "${_BN_ARGS[@]}" ;;
      ci)
        shift; _parse_prefix_args "$@"
        _BN_ARGS+=(--frozen-lockfile)
        _run_bun "$_BN_PREFIX" install "${_BN_ARGS[@]}" ;;
      uninstall|remove|rm|un|r)
        shift; _parse_prefix_args "$@"
        _run_bun "$_BN_PREFIX" remove "${_BN_ARGS[@]}" ;;
      ls|list|ll|la)
        shift; _parse_prefix_args "$@"
        _run_bun "$_BN_PREFIX" pm ls "${_BN_ARGS[@]}" ;;
      link|unlink|init|publish|update|up|upgrade|audit|whoami)
        _command=$1; shift
        case "$_command" in
          up|upgrade) _command=update ;;
          whoami) _parse_prefix_args "$@"; _run_bun "$_BN_PREFIX" pm whoami "${_BN_ARGS[@]}" ;;
          *) _parse_prefix_args "$@"; _run_bun "$_BN_PREFIX" "$_command" "${_BN_ARGS[@]}" ;;
        esac
        ;;
      pack) shift; _parse_prefix_args "$@"; _run_bun "$_BN_PREFIX" pm pack "${_BN_ARGS[@]}" ;;
      run|run-script|exec|x|start|test|t)
        _command=$1; shift; _parse_prefix_args "$@"
        case "$_command" in
          run-script) _command=run ;;
          exec|x) _command=x ;;
          start) _BN_ARGS=(start "${_BN_ARGS[@]}"); _command=run ;;
          # npm test runs the package's test script; it is not necessarily `bun test`.
          test|t) _BN_ARGS=(test "${_BN_ARGS[@]}"); _command=run ;;
        esac
        _run_bun "$_BN_PREFIX" "$_command" "${_BN_ARGS[@]}" ;;
      prefix)
        shift; _global=0; _cli_prefix=''
        while (($#)); do
          case "$1" in
            -g|--global) _global=1; shift ;;
            --prefix|-C)
              (($# >= 2)) || _fail "$1 requires a directory argument"
              _cli_prefix=$2; shift 2 ;;
            --prefix=*|-C=*) _cli_prefix=${1#*=}; shift ;;
            *) shift ;;
          esac
        done
        if ((_global)); then
          _global_bin=$("$_BUN" pm bin -g 2>/dev/null) || _fail 'could not resolve Bun global bin directory'
          dirname -- "$_global_bin"
        else
          exec "$_BUN" "${_BUN%/*}/bun-node-prefix" "$PWD" "$_cli_prefix"
        fi
        ;;
      node-gyp)
        printf 'bun-node: native addons (.node files / node-gyp) are not supported by Bun.\n' >&2
        printf 'bun-node: You will need Node.js for this package.\n' >&2
        exit 1 ;;
      deprecate|owner|team|org|hook|fund|token|profile|stars|adduser|login|logout|ping|access|dist-tag|shrinkwrap|doctor)
        _npm=$(_real_command npm || true)
        if [[ -n "$_npm" ]]; then
          printf "bun-node: '%s' is unsupported by Bun; delegating to %s\n" "$1" "$_npm" >&2
          exec "$_npm" "$@"
        fi
        _fail "'npm $1' is unsupported by Bun and no real npm was found. See $_NPM_URL" ;;
      *) exec "$_BUN" "$@" ;;
    esac
    ;;

  npx)
    case "${1-}" in
      --version|-v) printf '%s\n' "${BUN_NODE_SPOOF_NPM_VERSION:-$_DEFAULT_NPM_VERSION}" ;;
      node-gyp)
        printf 'bun-node: native addons (.node files / node-gyp) are not supported by Bun.\n' >&2
        printf 'bun-node: You will need Node.js for this package.\n' >&2
        exit 1 ;;
      *)
        while [[ "${1-}" == -y || "${1-}" == --yes ]]; do shift; done
        if [[ "${1-}" == --no-install ]]; then
          shift
          # Best-effort approximation: do not fetch if Bun can satisfy from cache.
          exec "$_BUN" x --prefer-offline "$@"
        fi
        exec "$_BUN" x "$@" ;;
    esac
    ;;

  yarn)
    case "${1-}" in
      --version|-v) printf '%s\n' "${BUN_NODE_SPOOF_YARN_VERSION:-$_DEFAULT_YARN_VERSION}" ;;
      '') exec "$_BUN" install ;;
      add) shift; exec "$_BUN" add "$@" ;;
      remove|rm) shift; exec "$_BUN" remove "$@" ;;
      install) shift; exec "$_BUN" install "$@" ;;
      run) shift; exec "$_BUN" run "$@" ;;
      start|build|test|dev|lint|format|clean|typecheck|check) exec "$_BUN" run "$@" ;;
      upgrade|up) shift; exec "$_BUN" update "$@" ;;
      global)
        [[ -n "${2-}" ]] || _fail 'expected a subcommand after yarn global'
        _global_sub=$2; shift 2
        case "$_global_sub" in
          add) exec "$_BUN" add --global "$@" ;;
          remove) exec "$_BUN" remove --global "$@" ;;
          *) exec "$_BUN" "$_global_sub" "$@" ;;
        esac ;;
      dlx|exec) shift; exec "$_BUN" x "$@" ;;
      init|link|unlink) _command=$1; shift; exec "$_BUN" "$_command" "$@" ;;
      info) shift; exec "$_BUN" pm "$@" ;;
      publish|pack|login|logout|owner|team|workspace|workspaces|policies|why|outdated|licenses|audit|import|create)
        _yarn=$(_real_command yarn || true)
        if [[ -n "$_yarn" ]]; then
          printf "bun-node: '%s' is unsupported by Bun; delegating to %s\n" "$1" "$_yarn" >&2
          exec "$_yarn" "$@"
        fi
        _fail "'yarn $1' is unsupported by Bun and no real yarn was found." ;;
      *) exec "$_BUN" run "$@" ;;
    esac
    ;;
  *) _fail "unknown dispatcher name: $_TOOL" ;;
esac
SHIM
} > "$STAGE_DIR/bun-node-shim"
chmod 755 "$STAGE_DIR/bun-node-shim"

cat > "$STAGE_DIR/bun-node-prefix" <<'PREFIX'
#!/usr/bin/env bun
// bun-node-managed-file
import { Glob } from "bun";
import { existsSync, readFileSync } from "node:fs";
import path from "node:path";

const exists = existsSync;
const cwd = path.resolve(process.argv[2] || process.cwd());
const cliPrefix = process.argv[3] || "";
if (cliPrefix) {
  console.log(path.resolve(cwd, cliPrefix));
  process.exit(0);
}

function isWorkspaceMember(root, child, patterns) {
  if (!exists(path.join(child, "package.json"))) return false;
  const relative = path.relative(root, child).split(path.sep).join("/");
  if (!relative || relative === ".." || relative.startsWith("../")) return false;
  let matched = false;
  for (let pattern of patterns) {
    pattern = String(pattern);
    const excluded = pattern.startsWith("!");
    if (excluded) pattern = pattern.slice(1);
    pattern = pattern.replace(/^(?:\.\/)+/, "");
    pattern = pattern.endsWith("package.json")
      ? pattern
      : `${pattern.replace(/\/+$/, "")}/package.json`;
    try {
      if (new Glob(pattern).match(`${relative}/package.json`)) matched = !excluded;
    } catch {
      // Ignore invalid patterns, matching the helper's forgiving behavior.
    }
  }
  return matched;
}

let project;
for (let dir = cwd; ; dir = path.dirname(dir)) {
  const pkgPath = path.join(dir, "package.json");
  const hasPackageJson = exists(pkgPath);
  if (!project && (hasPackageJson || exists(path.join(dir, "node_modules")))) project = dir;

  if (project && hasPackageJson && dir !== project) {
    try {
      const pkg = JSON.parse(readFileSync(pkgPath, "utf8"));
      const workspaces = Array.isArray(pkg.workspaces)
        ? pkg.workspaces
        : Array.isArray(pkg.workspaces?.packages) ? pkg.workspaces.packages : null;
      if (workspaces && isWorkspaceMember(dir, project, workspaces)) {
        project = dir;
        break;
      }
    } catch {
      // A malformed parent manifest should not prevent looking farther up.
    }
  }

  const parent = path.dirname(dir);
  if (parent === dir) break;
}
console.log(project || cwd);
PREFIX
chmod 755 "$STAGE_DIR/bun-node-prefix"

{
  printf '#!/usr/bin/env bash\n# bun-node-managed-file\n_BIN_DIR=%q\n' "$BIN_DIR"
  cat <<'STATUS'
set -Eeuo pipefail
BIN_DIR="$_BIN_DIR"
if [[ -t 1 ]]; then
  BOLD=$'\033[1m' DIM=$'\033[2m' GREEN=$'\033[0;32m' RED=$'\033[0;31m' RESET=$'\033[0m'
else BOLD='' DIM='' GREEN='' RED='' RESET=''; fi

shim_status() {
  local name=$1
  if [[ -L "$BIN_DIR/$name" && "$(readlink -- "$BIN_DIR/$name" 2>/dev/null || true)" == bun-node-shim ]]; then
    printf '%b✓%b' "$GREEN" "$RESET"
  else printf '%b✗%b' "$RED" "$RESET"; fi
}

case "${1:-status}" in
  status)
    printf '\n%b bun-node%b  node/npm/npx/yarn → bun\n' "$BOLD" "$RESET"
    printf '──────────────────────────────────────────\n\n'
    printf '  %bbun%b       %s  v%s\n' "$DIM" "$RESET" "$(type -P bun 2>/dev/null || echo 'not found')" "$(bun --version 2>/dev/null || echo '?')"
    printf '  %bshim dir%b  %s\n\n' "$DIM" "$RESET" "$BIN_DIR"
    for name in node npm npx yarn; do
      printf '  %s  %-5s' "$(shim_status "$name")" "$name"
      if [[ -L "$BIN_DIR/$name" && "$(readlink -- "$BIN_DIR/$name" 2>/dev/null || true)" == bun-node-shim ]]; then
        case "$name" in
          node) version=$("$BIN_DIR/node" --version 2>/dev/null || echo '?') ;;
          npm) version=$("$BIN_DIR/npm" --version 2>/dev/null || echo '?') ;;
          yarn) version=$("$BIN_DIR/yarn" --version 2>/dev/null || echo '?') ;;
          npx) version='bun x' ;;
        esac
        printf ' %b→ %s%b\n' "$DIM" "$version" "$RESET"
      else printf ' %bnot installed%b\n' "$RED" "$RESET"; fi
    done
    printf '\n  %bdebug%b     BUN_NODE_DEBUG=1 npm install\n\n' "$DIM" "$RESET" ;;
  help|-h|--help)
    printf '\nbun-node <command>\n\n  status   Show installed shims and versions (default)\n  help     Show this message\n\n' ;;
  *) printf "bun-node: unknown command '%s'. Run 'bun-node help'.\n" "$1" >&2; exit 1 ;;
esac
STATUS
} > "$STAGE_DIR/bun-node"
chmod 755 "$STAGE_DIR/bun-node"

{
  printf '#!/usr/bin/env bash\n# bun-node-managed-file\n_BIN_DIR=%q\n' "$BIN_DIR"
  cat <<'UNINSTALL'
set -Eeuo pipefail
BIN_DIR="$_BIN_DIR"
for name in node npm npx yarn; do
  if [[ -L "$BIN_DIR/$name" && "$(readlink -- "$BIN_DIR/$name" 2>/dev/null || true)" == bun-node-shim ]]; then
    rm -- "$BIN_DIR/$name"
  fi
done
for name in bun-node-shim bun-node-prefix bun-node bun-node-uninstall bun-node-update; do
  file="$BIN_DIR/$name"
  if [[ -f "$file" ]] && grep -qF 'bun-node-managed-file' "$file" 2>/dev/null; then rm -- "$file"; fi
done
printf 'Removed bun-node. Bun itself and unrelated files were left untouched.\n'
UNINSTALL
} > "$STAGE_DIR/bun-node-uninstall"
chmod 755 "$STAGE_DIR/bun-node-uninstall"

cat > "$STAGE_DIR/bun-node-update" <<'UPDATE'
#!/usr/bin/env bash
# bun-node-managed-file
set -Eeuo pipefail
url='https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh'
tmp=$(mktemp "${TMPDIR:-/tmp}/bun-node-update.XXXXXX")
trap 'rm -f -- "$tmp"' EXIT
command -v curl >/dev/null 2>&1 || { echo 'bun-node-update: curl is required.' >&2; exit 1; }
printf 'Updating bun-node...\n'
curl -fsSL "$url" -o "$tmp"
bash "$tmp" "$@"
UPDATE
chmod 755 "$STAGE_DIR/bun-node-update"

# Back up conflicts only after the replacement files are staged successfully.
if ((${#CONFLICTS[@]})); then
  BACKUP_DIR="$BIN_DIR/.bun-node-backup-$(date +%Y%m%d-%H%M%S)-$$"
  mkdir -m 700 -- "$BACKUP_DIR" || die "Could not create backup directory: $BACKUP_DIR"
  for name in "${CONFLICTS[@]}"; do
    if [[ -e "$BIN_DIR/$name" || -L "$BIN_DIR/$name" ]]; then
      mv -- "$BIN_DIR/$name" "$BACKUP_DIR/$name" || die "Could not back up $BIN_DIR/$name"
    fi
  done
  warn "Previous files backed up to $BACKUP_DIR"
fi

# Replace the shared dispatcher atomically, then relink the command names.
for name in bun-node-shim bun-node-prefix bun-node bun-node-uninstall bun-node-update; do
  mv -f -- "$STAGE_DIR/$name" "$BIN_DIR/$name" || die "Could not install $name"
done
for name in node npm npx yarn; do
  ln -sfn -- bun-node-shim "$STAGE_DIR/$name"
  mv -f -- "$STAGE_DIR/$name" "$BIN_DIR/$name" || die "Could not install shim: $name"
done

ok 'Shared dispatcher, command shims, and helper utilities installed.'
if (( ! QUIET )); then
  printf '\n%b bun-node installed!%b\n' "$GREEN$BOLD" "$RESET"
  printf '  shims     node  npm  npx  yarn\n  location  %s\n  status    bun-node status\n  debug     BUN_NODE_DEBUG=1 npm install\n  update    bun-node-update\n  uninstall bun-node-uninstall\n' "$BIN_DIR"
  [[ -z "$BACKUP_DIR" ]] || printf '  backups   %s\n' "$BACKUP_DIR"
  printf '\n'
fi

