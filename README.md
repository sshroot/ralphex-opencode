# Ralphex + OpenCode

Docker images based on the official Ralphex images with the OpenCode CLI installed.

## Images

```text
ghcr.io/sshroot/ralphex-opencode
ghcr.io/sshroot/ralphex-go-opencode
```

Both images are published for `linux/amd64` and `linux/arm64`.

## Docker wrapper

The repository includes `scripts/ralphex-dk.sh`, adapted for the Ralphex + OpenCode image.
It uses the OpenCode image by default and mounts OpenCode authentication/configuration when
those directories exist on the host.

```bash
./scripts/ralphex-dk.sh docs/plans/my-plan.md
```

OpenCode directories:

```text
~/.local/share/opencode -> /home/app/.local/share/opencode
~/.config/opencode     -> /home/app/.config/opencode
```

Both OpenCode directories are optional. Claude Code credentials are optional as well: if
`~/.claude` (or `CLAUDE_CONFIG_DIR`) does not exist, the wrapper does not mount it and does
not fail.

Use `--dry-run` to inspect the generated Docker command:

```bash
./scripts/ralphex-dk.sh --dry-run docs/plans/my-plan.md
```

The wrapper also supports the usual `-E`, `-v`, `--docker`, `--network`, `--image`, and
`--port` options.

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

Set the image explicitly when using the normal Ralphex CLI:

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
