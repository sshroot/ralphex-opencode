#!/usr/bin/env python3
"""Run ralphex in the Ralphex + OpenCode Docker image.

Claude credentials are optional. OpenCode credentials are mounted when present.
Use --opencode to route ralphex's Claude-compatible executor through the bundled
OpenCode adapter.
"""

import argparse
import os
import platform
import shlex
import signal
import subprocess
import sys
from pathlib import Path

DEFAULT_IMAGE = "ghcr.io/sshroot/ralphex-go-opencode:latest"
DEFAULT_PORT = "8080"
DEFAULT_DOCKER_SOCKET = "/var/run/docker.sock"
OPENCODE_COMMAND = "/opt/ralphex/opencode-as-claude.sh"


def parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="Run ralphex in Docker")
    p.add_argument("-E", "--env", action="append", default=[], metavar="VAR[=value]")
    p.add_argument("-v", "--volume", action="append", default=[], metavar="SRC:DST[:opts]")
    p.add_argument("--image", default=os.environ.get("RALPHEX_IMAGE", DEFAULT_IMAGE))
    p.add_argument("--port", default=os.environ.get("RALPHEX_PORT", DEFAULT_PORT))
    p.add_argument("--network", default=os.environ.get("RALPHEX_DOCKER_NETWORK", ""))
    p.add_argument("--docker", action="store_true", help="mount host Docker socket")
    p.add_argument("--opencode", action="store_true", help="use bundled OpenCode adapter as Claude command")
    p.add_argument("--dry-run", action="store_true")
    return p


def truthy(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes"}


def add_mount(cmd: list[str], source: Path, target: str, readonly: bool = False) -> None:
    if not source.exists():
        return
    suffix = ":ro" if readonly else ""
    cmd.extend(["-v", f"{source}:{target}{suffix}"])


def build_command(args: argparse.Namespace, ralphex_args: list[str]) -> list[str]:
    home = Path.home()
    workspace = Path(os.environ.get("PWD", os.getcwd())).resolve()
    cmd = ["docker", "run"]

    if sys.stdin.isatty():
        cmd.append("-it")
    cmd.append("--rm")

    if args.network:
        cmd.extend(["--network", args.network])

    cmd.extend([
        "-e", f"APP_UID={os.getuid()}",
        "-e", "SKIP_HOME_CHOWN=1",
        "-e", "INIT_QUIET=1",
        "-e", "CLAUDE_CONFIG_DIR=/home/app/.claude",
    ])

    tz = os.environ.get("TZ", "")
    if tz:
        cmd.extend(["-e", f"TIME_ZONE={tz}", "-e", f"TZ={tz}"])

    for entry in args.env:
        cmd.extend(["-e", entry])

    # Claude credentials are optional.
    claude_home = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(home / ".claude"))).expanduser()
    add_mount(cmd, claude_home, "/home/app/.claude")

    # OpenCode authentication/configuration is optional.
    add_mount(cmd, home / ".local" / "share" / "opencode", "/home/app/.local/share/opencode")
    add_mount(cmd, home / ".config" / "opencode", "/home/app/.config/opencode")

    # Ralphex configuration is always available in the container.
    ralphex_config = home / ".config" / "ralphex"
    ralphex_config.mkdir(parents=True, exist_ok=True)
    add_mount(cmd, ralphex_config, "/home/app/.config/ralphex")

    add_mount(cmd, home / ".codex", "/home/app/.codex")
    add_mount(cmd, workspace, "/workspace")

    for volume in args.volume:
        cmd.extend(["-v", volume])

    if args.docker or truthy(os.environ.get("RALPHEX_DOCKER_SOCKET", "")):
        socket = os.environ.get("DOCKER_HOST", "")
        if socket.startswith("unix://"):
            socket = socket[7:]
        socket = socket or DEFAULT_DOCKER_SOCKET
        if not Path(socket).exists():
            raise SystemExit(f"error: Docker socket not found: {socket}")
        cmd.extend(["-v", f"{socket}:{DEFAULT_DOCKER_SOCKET}"])
        if platform.system() == "Linux":
            cmd.extend(["-e", f"DOCKER_GID={Path(socket).stat().st_gid}"])

    if "--serve" in ralphex_args or "-s" in ralphex_args:
        cmd.extend(["-p", f"127.0.0.1:{args.port}:8080", "-e", "RALPHEX_WEB_HOST=0.0.0.0"])

    final_args = list(ralphex_args)
    if args.opencode:
        final_args.insert(0, f"--claude-command={OPENCODE_COMMAND}")

    cmd.extend(["-w", "/workspace", args.image, "/srv/ralphex"])
    cmd.extend(final_args)
    return cmd


def main() -> int:
    args, ralphex_args = parser().parse_known_args()
    cmd = build_command(args, ralphex_args)
    if args.dry_run:
        print(shlex.join(cmd))
        return 0

    proc = subprocess.Popen(cmd)

    def terminate(signum: int, _frame: object) -> None:
        if proc.poll() is None:
            proc.terminate()
            try:
                proc.wait(timeout=5)
            except subprocess.TimeoutExpired:
                proc.kill()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    return proc.wait()


if __name__ == "__main__":
    sys.exit(main())
