#!/usr/bin/env python3
"""Run ralphex in the Ralphex + OpenCode Docker image.

Claude Code credentials are optional. OpenCode authentication and configuration are
mounted from the host when present.

Usage:
  scripts/ralphex-dk.sh [wrapper-options] [ralphex-args]
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


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Run ralphex + OpenCode in Docker")
    parser.add_argument("-E", "--env", action="append", default=[], metavar="VAR[=value]",
                        help="extra environment variable (repeatable)")
    parser.add_argument("-v", "--volume", action="append", default=[], metavar="SRC:DST[:opts]",
                        help="extra volume mount (repeatable)")
    parser.add_argument("--image", default=os.environ.get("RALPHEX_IMAGE", DEFAULT_IMAGE),
                        help="Docker image")
    parser.add_argument("--port", default=os.environ.get("RALPHEX_PORT", DEFAULT_PORT),
                        help="web dashboard port")
    parser.add_argument("--network", default=os.environ.get("RALPHEX_DOCKER_NETWORK", ""),
                        help="Docker network mode")
    parser.add_argument("--docker", action="store_true",
                        help="mount the host Docker socket")
    parser.add_argument("--dry-run", action="store_true",
                        help="print the Docker command without executing it")
    return parser


def truthy(value: str) -> bool:
    return value.strip().lower() in {"1", "true", "yes"}


def add_mount(command: list[str], source: Path, target: str, readonly: bool = False) -> None:
    if not source.exists():
        return
    suffix = ":ro" if readonly else ""
    command.extend(["-v", f"{source}:{target}{suffix}"])


def build_command(args: argparse.Namespace, ralphex_args: list[str]) -> list[str]:
    home = Path.home()
    workspace = Path(os.environ.get("PWD", os.getcwd())).resolve()
    command = ["docker", "run"]

    if sys.stdin.isatty():
        command.append("-it")
    command.append("--rm")

    if args.network:
        command.extend(["--network", args.network])

    command.extend([
        "-e", f"APP_UID={os.getuid()}",
        "-e", "SKIP_HOME_CHOWN=1",
        "-e", "INIT_QUIET=1",
    ])

    # Claude Code credentials are optional. This also allows API-key/provider based
    # authentication without requiring ~/.claude to exist on the host.
    claude_config = Path(os.environ.get("CLAUDE_CONFIG_DIR", str(home / ".claude"))).expanduser()
    if claude_config.exists():
        command.extend(["-e", "CLAUDE_CONFIG_DIR=/home/app/.claude"])
        add_mount(command, claude_config, "/home/app/.claude")

    # OpenCode credentials and configuration are optional.
    opencode_data = Path(os.environ.get(
        "OPENCODE_DATA_DIR", str(home / ".local" / "share" / "opencode")
    )).expanduser()
    opencode_config = Path(os.environ.get(
        "OPENCODE_CONFIG_DIR", str(home / ".config" / "opencode")
    )).expanduser()
    add_mount(command, opencode_data, "/home/app/.local/share/opencode")
    add_mount(command, opencode_config, "/home/app/.config/opencode")

    # Ralphex configuration is persistent and created when missing.
    ralphex_config = home / ".config" / "ralphex"
    ralphex_config.mkdir(parents=True, exist_ok=True)
    add_mount(command, ralphex_config, "/home/app/.config/ralphex")

    # Codex credentials remain optional as in the upstream wrapper.
    add_mount(command, home / ".codex", "/home/app/.codex")

    # Project workspace.
    add_mount(command, workspace, "/workspace")

    for volume in args.volume:
        command.extend(["-v", volume])

    docker_socket_enabled = args.docker or truthy(os.environ.get("RALPHEX_DOCKER_SOCKET", ""))
    if docker_socket_enabled:
        socket = os.environ.get("DOCKER_HOST", "")
        if socket.startswith("unix://"):
            socket = socket[7:]
        socket = socket or DEFAULT_DOCKER_SOCKET
        socket_path = Path(socket)
        if not socket_path.exists():
            raise SystemExit(f"error: Docker socket not found: {socket}")
        command.extend(["-v", f"{socket}:{DEFAULT_DOCKER_SOCKET}"])
        if platform.system() == "Linux":
            command.extend(["-e", f"DOCKER_GID={socket_path.stat().st_gid}"])

    if "--serve" in ralphex_args or "-s" in ralphex_args:
        command.extend([
            "-p", f"127.0.0.1:{args.port}:8080",
            "-e", "RALPHEX_WEB_HOST=0.0.0.0",
        ])

    command.extend(["-w", "/workspace", args.image, "/srv/ralphex"])
    command.extend(ralphex_args)
    return command


def main() -> int:
    args, ralphex_args = build_parser().parse_known_args()
    command = build_command(args, ralphex_args)

    if args.dry_run:
        print(shlex.join(command))
        return 0

    process = subprocess.Popen(command)

    def terminate(signum: int, _frame: object) -> None:
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
        raise SystemExit(128 + signum)

    signal.signal(signal.SIGTERM, terminate)
    signal.signal(signal.SIGINT, terminate)
    return process.wait()


if __name__ == "__main__":
    sys.exit(main())
