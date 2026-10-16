<div align="center">

# bun-node

### Your tools ask for Node. Bun answers.

**Transparent `node` · `npm` · `npx` · `yarn` compatibility shims powered by [Bun](https://bun.com).**

[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)
[![Requires Bun 1.4+](https://img.shields.io/badge/Bun-1.4%2B-f9f1e1?logo=bun&logoColor=black)](https://bun.com)

*Keep using the commands your tools expect—without installing Node.js just to satisfy every tool that calls it.*

</div>

---

## What is bun-node?

Some JavaScript tools assume `node`, `npm`, `npx`, or `yarn` will be available. But when you prefer Bun, having to install a second JavaScript runtime just to satisfy those commands is annoying.

**bun-node bridges that gap.** It installs lightweight command shims next to your Bun executable. When a tool invokes `node`, `npm`, `npx`, or `yarn`, the shim routes the command to Bun and translates common package-manager commands where needed.

```text
node app.js             ──▶ bun app.js
npm install             ──▶ bun install
npm install zod          ──▶ bun add zod
npm run build            ──▶ bun run build
npm ci                   ──▶ bun install --frozen-lockfile
npx cowsay "Hello!"      ──▶ bun x cowsay "Hello!"
yarn add zod             ──▶ bun add zod
yarn                     ──▶ bun install
```

It's inspired by the familiar idea of a compatibility shim: let existing tools call the command they expect, then delegate the work to the tool you actually want to use.

> **Important:** bun-node is a compatibility layer, not Node.js itself. Bun supports a lot of the Node.js ecosystem, but it is not a drop-in replacement for every runtime API or package.

## Features

- **Transparent commands** — provides `node`, `npm`, `npx`, and `yarn` shims.
- **Bun-native execution** — JavaScript execution, package management, and one-off package commands are delegated to Bun.
- **No shell configuration edits** — the installer uses the directory containing your Bun executable and warns if that directory isn't on `PATH`.
- **Project-aware Node version reporting** — `node --version` checks `.node-version` and `.nvmrc` files while walking up from the current directory.
- **Workspace-aware `npm prefix`** — the helper considers package manifests, `node_modules`, and common npm workspace declarations.
- **Argument-safe forwarding** — Bash arrays are used for argument handling so paths and arguments containing spaces are kept as separate arguments.
- **Fallback for unsupported commands** — selected `npm` and `yarn` commands can be delegated to a separately installed real CLI when available.
- **Debug logging** — inspect which shim was invoked and which arguments it received.
- **Safer installation** — unrelated files are not silently overwritten; conflicts can be backed up before replacement.
- **Easy maintenance** — status, update, and uninstall commands are included.

## Requirements

- **Bun 1.4 or newer**
- Bash
- A writable directory containing the Bun executable
- `curl` is needed by the `bun-node-update` command; it is not needed when installing from a local checkout

The installer targets Unix-like environments. Windows support is not currently documented or guaranteed.

## Install

### Option A: Clone and inspect first

This is the recommended approach if you'd like to read the installer before running it.

```bash
git clone https://github.com/bethropolis/bun-node.git
cd bun-node
less install.sh
bash install.sh
```

### Option B: Download the installer, inspect it, then run it

```bash
curl -fsSL \
  https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh \
  -o /tmp/bun-node-install.sh

less /tmp/bun-node-install.sh
bash /tmp/bun-node-install.sh
```

### Option C: One-line install

```bash
curl -fsSL https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh | bash
```

The one-line method is convenient, but it executes the downloaded installer immediately. Review the script first if you want to audit what will run.

### Installer options

```text
--help       Show installer help
--force      Back up and replace conflicting files
--quiet      Suppress progress messages; errors and warnings remain visible
```

For example, a non-interactive install that backs up conflicting files:

```bash
bash install.sh --force
```

By default, the installer detects conflicts and asks before replacing existing files. With `--force`, conflicting files are moved into a timestamped backup directory inside Bun's bin directory. Keep that backup until you've confirmed everything works.

## Verify the installation

Run:

```bash
bun-node status
```

Then check the shims:

```bash
node --version
npm --version
npx --version
yarn --version
```

The reported Node, npm, and Yarn versions are **compatibility versions**, not versions of separate Node.js/npm/Yarn installations. Defaults can be overridden with environment variables; see [Version reporting](#version-reporting).

If a command still resolves to another installation, inspect command resolution:

```bash
command -v bun
command -v node
command -v npm
command -v npx
command -v yarn
printf '%s\n' "$PATH"
```

bun-node installs shims beside the Bun executable it discovers. If that directory isn't on `PATH`, the installer prints a warning; it does not edit your shell configuration.

## Command reference

### `node`

| Command | Behavior |
| --- | --- |
| `node app.js` | Runs the script with Bun. |
| `node --version` / `node -v` | Reports the configured compatibility version, using `.node-version` or `.nvmrc` when found. |
| `node -e '...'` | Evaluates JavaScript with Bun. |
| `node -p 'expression'` | Prints the expression result through Bun's evaluation mode. Best for simple expressions. |

Version lookup checks `.node-version` first, then `.nvmrc`, in each directory from the current working directory upwards. If neither file is found, bun-node uses its configured default.

### `npm`

Common commands are mapped to Bun equivalents:

| Command | Delegated behavior |
| --- | --- |
| `npm install` | `bun install` |
| `npm install <package>` | `bun add <package>` |
| `npm install -D <package>` | `bun add -D <package>` |
| `npm install -g <package>` | `bun add -g <package>` |
| `npm ci` | `bun install --frozen-lockfile` |
| `npm uninstall <package>` | `bun remove <package>` |
| `npm run build` | `bun run build` |
| `npm start` | `bun run start` |
| `npm test` | `bun run test` |
| `npm ls` / `npm list` | `bun pm ls` |
| `npm link` / `npm unlink` | `bun link` / `bun unlink` |
| `npm update` | `bun update` |
| `npm exec <command>` | `bun x <command>` |
| `npm init` | `bun init` |
| `npm publish` | `bun publish` |
| `npm pack` | `bun pm pack` |
| `npm audit` | `bun audit` |
| `npm prefix` | Resolves the project prefix, including supported workspace layouts. |

`--prefix` and `-C` are supported by the commands that process project-local arguments. For example:

```bash
npm install --prefix ./apps/web
npm run --prefix ./apps/web build
npm prefix
npm prefix --prefix ./apps/web
```

For commands that bun-node explicitly does not implement—such as `npm login`, `npm owner`, and `npm deprecate`—the shim looks for a real `npm` executable outside bun-node's own bin directory and delegates to it. If one cannot be found, the command exits with an explanatory error.

### `npx`

| Command | Behavior |
| --- | --- |
| `npx cowsay hello` | `bun x cowsay hello` |
| `npx -y <package>` | Removes the unnecessary `-y` flag and runs `bun x`. |
| `npx --no-install <package>` | Uses `bun x --prefer-offline` as a best-effort approximation. |
| `npx --version` | Reports the configured npm compatibility version. |

**Note:** `--no-install` is not a strict no-network guarantee. Use Bun's explicit offline options when you require network access to be disabled.

### `yarn`

| Command | Behavior |
| --- | --- |
| `yarn` | `bun install` |
| `yarn add <package>` | `bun add <package>` |
| `yarn remove <package>` | `bun remove <package>` |
| `yarn run build` | `bun run build` |
| `yarn build` | Runs the named script through `bun run`. |
| `yarn upgrade` | `bun update` |
| `yarn global add <package>` | `bun add --global <package>` |
| `yarn dlx <package>` | `bun x <package>` |
| `yarn link` / `yarn unlink` | Delegates to Bun's link commands. |

Commands such as `yarn login`, `yarn publish`, and workspace-management commands are not implemented by this shim. For selected unsupported commands, bun-node tries to delegate to a real Yarn executable outside its own bin directory.

The mapping is intentionally pragmatic, not a promise that every npm or Yarn option behaves identically under Bun. When in doubt, consult the [Bun package-manager documentation](https://bun.com/docs/pm/cli/install) and the [Bun command reference](https://bun.com/docs).

## Version reporting

The default compatibility versions are configurable per process or shell session:

```bash
# Defaults supplied by the installer
export BUN_NODE_SPOOF_VERSION='v24.5.0'
export BUN_NODE_SPOOF_NPM_VERSION='12.2.0'
export BUN_NODE_SPOOF_YARN_VERSION='1.22.22'
```

- `BUN_NODE_SPOOF_VERSION` controls `node --version`, unless the project has a `.node-version` or `.nvmrc` file.
- `BUN_NODE_SPOOF_NPM_VERSION` controls `npm --version` and `npx --version`.
- `BUN_NODE_SPOOF_YARN_VERSION` controls `yarn --version`.

These values only affect the reported version strings. **They do not install or emulate those versions of Node.js, npm, or Yarn.** If a tool depends on a particular runtime feature, a spoofed version string cannot provide it.

## Debugging

Set `BUN_NODE_DEBUG=1` to log the invoked shim and its arguments:

```bash
BUN_NODE_DEBUG=1 npm install zod
BUN_NODE_DEBUG=1 npx cowsay hello
```

The debug output is written to standard error. It is useful for confirming which shim is being invoked and inspecting argument forwarding.

## Update and uninstall

Update bun-node:

```bash
bun-node-update
```

Remove bun-node:

```bash
bun-node-uninstall
```

The uninstaller removes the managed command links and bun-node helper files. It does not remove Bun itself, change shell configuration files, or intentionally remove unrelated files.

## Limitations and compatibility notes

bun-node is deliberately small. It redirects common commands; it does not turn Bun into a fully identical Node.js/npm/Yarn environment.

- **Native Node addons:** packages that require `node-gyp` or native `.node` addons may need a real Node.js installation and are not supported by this shim's Bun execution path.
- **Runtime differences:** Node.js APIs and edge cases are not all implemented identically by Bun. Some tools may still require Node.js.
- **Package-manager differences:** npm, Yarn, and Bun do not have identical command-line behavior, lockfiles, lifecycle behavior, or configuration. Verify important CI and production workflows before switching.
- **Yarn Plug'n'Play:** do not assume PnP projects work; this setup is intended for projects using a `node_modules`-based installation.
- **Fallback commands:** selected unsupported npm/Yarn commands work only when a real npm/Yarn executable is installed and can be found outside bun-node's shim directory.
- **Version spoofing:** version checks may pass even though the underlying runtime is Bun. Do not use spoofed versions as proof of runtime compatibility.

If a dependency fundamentally requires Node.js, install Node.js for that project and invoke it explicitly rather than relying on a compatibility shim.

## Troubleshooting

### `bun-node: Bun not found`

Check that Bun is installed and on `PATH`:

```bash
command -v bun
bun --version
```

The installer requires Bun 1.4.2 or newer.

### The shims are installed, but another `node` or `npm` runs

Check command resolution and `PATH` order:

```bash
command -v node
command -v npm
printf '%s\n' "$PATH"
```

Open a new shell if your terminal or shell caches command locations. Make sure Bun's bin directory appears before competing Node.js installations when you want bun-node to take precedence.

### The installer reports conflicting files

The installer will not silently overwrite unrelated files. Review the conflict names and back them up yourself, or rerun with `--force` to have the installer move conflicting files into a backup directory before replacement.

### A command works in Bun but not through npm or Yarn

Try the equivalent `bun` command directly. If that works, enable debug output and inspect the arguments. If the command depends on npm/Yarn-specific behavior that is not mapped, use Bun's native command or a real npm/Yarn installation for that workflow.

## Why bun-node?

Because sometimes the cleanest toolchain is the one that gets out of your way. bun-node lets Bun handle the common JavaScript runtime and package-manager entry points while keeping familiar command names available for scripts and developer tools.

It's a bridge, not a compatibility miracle—and that distinction is intentional.

## Contributing

Issues and pull requests are welcome. Please include the command you ran, the behavior you expected, the behavior you saw, your operating system, and the output of `bun --version` when reporting a compatibility issue.

## License

[MIT](LICENSE)
