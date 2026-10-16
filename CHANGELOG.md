# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).


## [2.0.0] - 2026-10-16

### Added
- `bun-node --force`-style installer support and managed-file markers for safe conflict detection and backups.
- Shared `bun-node-shim` dispatcher instead of four copied shim scripts.
- `bun-node-prefix` helper for npm-compatible `prefix` resolution.
- Bun `1.4.2` or newer is now required.
- Staged, atomic installation of shims and helper files.

### Changed
- npm subcommands now route through one shared dispatcher.
- `npm prefix` resolves local project roots, global prefixes, explicit `--prefix`/`-C`,
  and workspace roots like npm does.
- `npm install` installs packages and bootstraps missing `--prefix` directories.
- `npm run`, `npm exec`, and `npm x` support `--prefix`/`-C` via Bun's `--cwd`.
- `npm --prefix` before the subcommand is normalized to an option.
- `bun-node status` and install output are streamlined.
- Spoofed versions updated to `v24.5.0` / `12.2.0`.

### Fixed
- Avoid "Script not found" when `bun add` is invoked with `--cwd`.
- `bun-node-uninstall` removes the shared dispatcher and all managed files.

### Removed
- Standalone generated `node`, `npm`, `npx`, and `yarn` shim copies.

## [1.0.0] - 2026-05-15

### Added
- Initial release: transparent `node`/`npm`/`npx`/`yarn` → `bun` shims
- `node --version` spoofing (`.nvmrc` / `.node-version` aware)
- `npm` subcommand translation with flag mapping (`install`, `publish`, `pack`, `audit`, `whoami`, etc.)
- `npx` → `bun x` translation
- `yarn` subcommand translation
- `bun-node status` / `bun-node help` meta commands
- `bun-node-update` and `bun-node-uninstall` helpers
- `BUN_NODE_DEBUG=1` debug mode
- Graceful fallback to real npm/yarn for unsupported commands

[2.0.0]: https://github.com/bethropolis/bun-node/compare/v1.0.0...v2.0.0
[1.0.0]: https://github.com/bethropolis/bun-node/releases/tag/v1.0.0
