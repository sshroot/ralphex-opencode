# Ralphex + OpenCode

Docker images based on the official Ralphex images with the OpenCode CLI installed.

## Images

```text
ghcr.io/sshroot/ralphex-opencode
ghcr.io/sshroot/ralphex-go-opencode
```

Both images are published for `linux/amd64` and `linux/arm64`.

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

Renovate monitors both dependencies and creates pull requests when new releases are available.

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

Pull requests build both images and run smoke tests for Ralphex and OpenCode. Merges to `main` build and publish multi-platform images to GHCR.

Renovate updates the pinned Ralphex and OpenCode versions; publishing happens only after the update PR is merged.

## OpenCode

This project is not affiliated with or endorsed by the OpenCode team. OpenCode is installed from the `opencode-ai` npm package.
