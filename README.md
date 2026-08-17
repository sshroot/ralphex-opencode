# Ralphex + OpenCode

Docker images based on the official Ralphex images with the OpenCode CLI installed.

## Images

```text
ghcr.io/sshroot/ralphex-opencode
ghcr.io/sshroot/ralphex-go-opencode
```

Both images are published for `linux/amd64` and `linux/arm64`.

## OpenCode Docker wrapper

The repository includes an OpenCode-aware Docker wrapper:

```bash
./scripts/ralphex-dk.sh --opencode docs/plans/my-plan.md
```

The wrapper uses the bundled Claude-compatible OpenCode adapter and passes Ralphex's
`--claude-command` override automatically. OpenCode authentication is optional: when
present, the following host directories are mounted into the container:

```text
~/.local/share/opencode -> /home/app/.local/share/opencode
~/.config/opencode     -> /home/app/.config/opencode
```

Claude credentials are also optional. If `~/.claude` (or `CLAUDE_CONFIG_DIR`) does not
exist, the wrapper simply starts without mounting it. This makes the OpenCode image usable
without a Claude Code login.

For a dry run:

```bash
./scripts/ralphex-dk.sh --opencode --dry-run docs/plans/my-plan.md
```

The adapter is also available in the image as:

```text
/opt/ralphex/opencode-as-claude.sh
```

## Tags

For every Ralphex release the workflow publishes:

```text
latest
<RALPHEX_VERSION>
ralphex-<RALPHEX_VERSION>-opencode-<OPENCODE_VERSION>
```

The last tag identifies the exact Ralphex/OpenCode combination.

## Versions

Pinned versions are stored in `versions.env`:

```dotenv
RALPHEX_VERSION=1.6.1
OPENCODE_VERSION=1.18.16
```

Dependabot updates GitHub Actions. A dedicated GitHub Actions workflow checks the
Ralphex and OpenCode GitHub Releases and opens a PR when either pinned version changes.

## Using with Ralphex

Set the image explicitly:

```bash
export RALPHEX_IMAGE=ghcr.io/sshroot/ralphex-go-opencode:latest
ralphex docs/plans/my-plan.md
```

For a reproducible environment:

```bash
export RALPHEX_IMAGE=ghcr.io/sshroot/ralphex-go-opencode:ralphex-1.6.1-opencode-1.18.16
```

## CI

Pull requests build both images and run smoke tests for Ralphex and OpenCode. Merges to
`main` build and publish multi-platform images to GHCR.

## OpenCode

OpenCode is installed from its GitHub Release musl archive rather than npm. The image
selects the `x64` or `arm64` musl artifact according to the target architecture.

This project is not affiliated with or endorsed by the OpenCode team.
