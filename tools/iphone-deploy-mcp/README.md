# VocabularyWidget iPhone Deploy MCP

This local stdio MCP server automates the physical-iPhone workflow in `.agents/skills/iphone-device-build/SKILL.md`. It uses the Mac's Xcode, Keychain signing identity, and `devicectl`; credentials and device operations stay local.

## Setup

From this directory, run `npm install`, then reload the VS Code window. `.vscode/mcp.json` registers the server. Node.js 20 or newer is required.

## Tools

- `iphone_preflight` checks Xcode, signing team, target IDs, App Group, worktree changes, local deployment evidence, and paired devices.
- `iphone_build` creates a fresh signed Release build and verifies host/extension signatures and metadata. Automatic provisioning may contact Apple.
- `iphone_install` installs an MCP-created verified build in place on a connected physical iPhone; it does not uninstall or reset app data.
- `iphone_launch` launches only a build installed by this server on the same device. Failed launches do not consume the build counter.
- `iphone_deployment_status` reports the latest successful deployment and next version without changing anything.

Run the tools in order: preflight, build, install, launch. Pass the returned build ID and the selected physical device UDID to install and launch. A successful launch, not merely a successful build or install, advances the counter.

Builds and complete logs are kept under `/private/tmp/VocabularyWidgetBuilds`. The per-Mac deployment ledger is stored under `~/Library/Application Support/VocabularyWidget/iphone-deploy-mcp/deployments.json`. On first use, the server seeds its history from the latest successful deployment note in the skill and requires its recorded build, install, and launch logs to exist. If history or evidence is ambiguous, it stops instead of guessing.

The server exposes only fixed VocabularyWidget actions; it does not accept arbitrary shell commands, identifiers, teams, signing options, or filesystem paths.

## Tests

Run `npm test` from this directory.
