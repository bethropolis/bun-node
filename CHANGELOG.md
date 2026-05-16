# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

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

[Unreleased]: https://github.com/bethropolis/bun-node/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/bethropolis/bun-node/releases/tag/v1.0.0
