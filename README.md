# bun-node

> `podman-docker`, but for bun. Transparent `node` / `npm` / `npx` / `yarn` → `bun` shims.

Your tools type `node`. Bun runs. Nobody notices.

```
node index.js            →  bun index.js
node --version           →  v22.14.0        (spoofed — version checks pass)
npm install              →  bun install
npm install lodash       →  bun add lodash
npm install -D typescript→  bun add -d typescript
npm install -g nodemon   →  bun add --global nodemon
npm ci                   →  bun install --frozen-lockfile
npm uninstall foo        →  bun remove foo
npm run build            →  bun run build
npm test                 →  bun test
npm ls                   →  bun pm ls
npm link                 →  bun link
npx cowsay hi            →  bun x cowsay hi
npx -y ts-node …         →  bun x ts-node …   (-y stripped, bun never needs it)
yarn                     →  bun install
yarn add lodash          →  bun add lodash
yarn dlx cowsay          →  bun x cowsay
yarn global add nodemon  →  bun add --global nodemon
```

## Install

```bash
curl -fsSL https://raw.githubusercontent.com/bethropolis/bun-node/main/install.sh | bash
```

That's it. No shell reload needed — shims land in the same directory as bun
(`~/.bun/bin` by default), which is already in your PATH.

**Requires:** [bun](https://bun.sh) already installed.

## Verify

```bash
bun-node status
```

```
bun-node  node/npm/npx/yarn → bun
──────────────────────────────────────────

  bun       /home/you/.bun/bin/bun  v1.2.15
  shim dir  /home/you/.bun/bin

  ✓  node   → bun  (spoof: v22.14.0)
  ✓  npm    → bun  (spoof: 10.9.2)
  ✓  npx    → bunx
  ✓  yarn   → bun  (spoof: 1.22.22)
```

## How it works

`install.sh` writes four shim scripts and two meta commands into bun's own bin
directory. Bun's installer already put that directory at the front of your
PATH, so the shims are immediately active with no further configuration.

```
~/.bun/bin/
  bun                  ← the real bun (untouched)
  bunx                 ← the real bunx (untouched)
  node                 ← shim → bun  (--version spoofing, .nvmrc aware)
  npm                  ← shim → bun  (subcommand translation + flag mapping)
  npx                  ← shim → bun x  (-y stripped)
  yarn                 ← shim → bun  (subcommand translation)
  bun-node             ← status / help
  bun-node-uninstall   ← removes the six files above, nothing else
  bun-node-update      ← re-runs the installer in place
```

Each shim has bun's absolute path baked in at install time — no PATH
manipulation at runtime, no risk of infinite recursion.

### npm subcommand translation

| You type                        | Bun receives                    |
|---------------------------------|---------------------------------|
| `npm install`                   | `bun install`                   |
| `npm install <pkg>`             | `bun add <pkg>`                 |
| `npm install -D <pkg>`          | `bun add -d <pkg>`              |
| `npm install -g <pkg>`          | `bun add --global <pkg>`        |
| `npm install --save-exact <pkg>`| `bun add --exact <pkg>`         |
| `npm ci`                        | `bun install --frozen-lockfile` |
| `npm uninstall <pkg>`           | `bun remove <pkg>`              |
| `npm run <script>`              | `bun run <script>`              |
| `npm test`                      | `bun test`                      |
| `npm ls` / `npm list`           | `bun pm ls`                     |
| `npm link`                      | `bun link`                      |
| `npm update`                    | `bun update`                    |
| `npm exec` / `npm x`            | `bun x`                         |
| `npm init`                      | `bun init`                      |
| `npm publish`                  | `bun publish`                  |
| `npm pack`                     | `bun pm pack`                  |
| `npm audit`                    | `bun audit`                    |
| `npm whoami`                   | `bun pm whoami`                |
| `npm deprecate` etc.           | → real npm (fallback)          |

Commands bun doesn't support (`npm deprecate`, `npm login`, `npm owner`, …) fall
back to the real `npm` if one exists on your system, or error helpfully if not.

### yarn subcommand translation

| You type                   | Bun receives             |
|----------------------------|--------------------------|
| `yarn` (bare)              | `bun install`            |
| `yarn add <pkg>`           | `bun add <pkg>`          |
| `yarn remove <pkg>`        | `bun remove <pkg>`       |
| `yarn run <script>`        | `bun run <script>`       |
| `yarn upgrade <pkg>`       | `bun update <pkg>`       |
| `yarn global add <pkg>`    | `bun add --global <pkg>` |
| `yarn dlx <pkg>`           | `bun x <pkg>`            |
| `yarn exec <cmd>`          | `bun x <cmd>`            |
| `yarn link`                | `bun link`               |
| `yarn publish` etc.        | → real yarn (fallback)   |

## Per-project Node version spoofing

`node --version` reads `.nvmrc` or `.node-version` walking up from the current
directory, so monorepos that pin a Node version per project get the right
output automatically.

```
project/
  .nvmrc          ← "18.20.0"
  packages/
    api/          ← inherits v18.20.0
```

Override globally at any time:

```bash
export BUN_NODE_SPOOF_VERSION=v20.18.0
export BUN_NODE_SPOOF_NPM_VERSION=10.5.0
export BUN_NODE_SPOOF_YARN_VERSION=1.22.19
```

## Debug mode

See exactly what every command translates to before bun receives it:

```bash
BUN_NODE_DEBUG=1 npm install lodash
# [bun-node] npm install lodash
# → bun add lodash
```

## Native addons

Packages that use `node-gyp` (native `.node` addons) cannot run under bun.
bun-node detects these and fails loudly rather than silently:

```
bun-node: native addons (.node files / node-gyp) are not supported by bun.
bun-node: You'll need Node.js for this package.
```

## Uninstall

```bash
bun-node-uninstall
```

Removes `node`, `npm`, `npx`, `yarn`, `bun-node`, `bun-node-uninstall`, and
`bun-node-update` from bun's bin directory. Bun itself is untouched. No
dotfiles were ever modified, so there's nothing else to clean up.

## Update

```bash
bun-node-update
```

Re-runs the installer in place. Existing shims are updated, bun is untouched.

## Caveats

- **Not a full Node.js runtime.** Bun is highly compatible but not 100%
  identical. Native addons (`.node` files), some obscure `vm` / `cluster`
  APIs, and a handful of edge-case behaviours differ.
- **Registry auth** (`npm login`, `npm adduser`) still falls back to real npm.
  Install it separately if you need those.
- **`node -p` / `--print`** is translated to `bun -e "console.log(...)"` —
  works for simple expressions; complex multi-statement `-p` may not.
- **Yarn Plug'n'Play (PnP)** is not supported by bun; classic node_modules
  mode works fine.

## Why do this?

- **Security** — no `preinstall` / `postinstall` scripts. Bun doesn't run them,
  so you're not executing arbitrary code from every dependency you pull.
- **Speed** — bun is supa fast. Installs, runs, resolves — all of it.
- **Preference** — I use and prefer bun a lot. This lets me stop worrying
  about whether a tool or CI script calls `node`, `npm`, `npx`, or `yarn`.

## License

MIT
