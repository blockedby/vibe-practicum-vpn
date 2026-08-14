#!/usr/bin/env python3
"""Small, local-only curses UI skeleton for the issue #40 VPN flow.

This module deliberately stops at an integration boundary.  It does not know
how to operate Docker, NetworkManager, sudo, OpenVPN, or a live VPN.  Lifecycle
buttons either record an action in :class:`MockLifecycleRunner` or invoke one
caller-supplied executable with one of the fixed argv suffixes below:

* ``start``
* ``stop``
* ``retest select``
* ``toggle mode``
* ``diagnostics``

The executable is never invoked through a shell, and its output is discarded so
that a lifecycle implementation cannot accidentally put a subscription or
endpoint in this UI's output. By default the UI uses the adjacent tracked
``vpnkit-local.sh`` adapter and the canonical gitignored local subscription
path; an explicit subscription path must still be that BASE's ``vibe-vpn/sub_url``.
``--status-json`` and ``--test`` are deliberately non-interactive and expose only
redacted state.
"""
from __future__ import annotations

import argparse
import curses
import json
import math
import os
import selectors
import signal
import stat
import subprocess
import sys
import time
from dataclasses import dataclass, field
from enum import Enum
from pathlib import Path
from typing import Mapping, Protocol, Sequence


LIFECYCLE_EXECUTABLE_ENV = "VPNKIT_TUI_LIFECYCLE_EXECUTABLE"
REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_LIFECYCLE_EXECUTABLE = Path(__file__).with_name("vpnkit-local.sh")
DEFAULT_SECRET_ROOT = REPO_ROOT / "secrets" / "vpnkit-local"
DEFAULT_SUBSCRIPTION_PATH = DEFAULT_SECRET_ROOT / "vibe-vpn" / "sub_url"
LOCAL_SECRETS_ENV = "VPNKIT_LOCAL_SECRETS_DIR"
MAX_SUBSCRIPTION_LENGTH = 16_384
MAX_STATUS_BYTES = 16_384
STATUS_TIMEOUT = 10.0
PROCESS_TERMINATION_GRACE = 0.25


class LifecycleAction(str, Enum):
    """The only lifecycle operations this UI may request."""

    START = "start"
    STOP = "stop"
    RETEST_SELECT = "retest/select"
    TOGGLE_MODE = "toggle-mode"
    DIAGNOSTICS = "diagnostics"


# Values are fixed, not assembled from user input.  The executable path is the
# sole caller-supplied argv element and is kept separate from these verbs.
LIFECYCLE_ARGV_SUFFIXES: Mapping[LifecycleAction, tuple[str, ...]] = {
    LifecycleAction.START: ("start",),
    LifecycleAction.STOP: ("stop",),
    LifecycleAction.RETEST_SELECT: ("retest", "select"),
    LifecycleAction.TOGGLE_MODE: ("toggle", "mode"),
    LifecycleAction.DIAGNOSTICS: ("diagnostics",),
}

BLOCKED_DIRECT_EXECUTABLES = frozenset(
    {
        "docker",
        "docker-compose",
        "podman",
        "podman-compose",
        "nmcli",
        "networkmanager",
        "sudo",
        "openvpn",
        "systemctl",
        "ip",
        "iptables",
        "nft",
    }
)


@dataclass(frozen=True)
class CommandResult:
    """Safe, output-free result returned by a lifecycle runner."""

    action: LifecycleAction
    returncode: int | None
    reason: str = "ok"

    @property
    def ok(self) -> bool:
        return self.returncode == 0 and self.reason == "ok"


class SafeCommandRunner(Protocol):
    """Interface for fixed lifecycle actions.

    Implementations must accept an action, construct an allowlisted argv array,
    and return a result without exposing command output.  The UI never accepts
    arbitrary command arguments.
    """

    def run(self, action: LifecycleAction) -> CommandResult:
        """Run one allowlisted action without a shell."""

    def query_status(self) -> Mapping[str, object]:
        """Return validated, redacted lifecycle status."""



def normalize_action(action: LifecycleAction | str) -> LifecycleAction:
    """Convert an action to the enum while rejecting unknown operations."""

    if isinstance(action, LifecycleAction):
        return action
    try:
        return LifecycleAction(action)
    except ValueError as exc:
        raise ValueError("unsupported lifecycle action") from exc


def _terminate_process_group(process: subprocess.Popen[bytes], *, grace: float = PROCESS_TERMINATION_GRACE) -> None:
    """Terminate a lifecycle process and every descendant in its session."""

    try:
        os.killpg(process.pid, signal.SIGTERM)
    except (OSError, ProcessLookupError):
        pass
    try:
        process.wait(timeout=grace)
    except (subprocess.TimeoutExpired, OSError, subprocess.SubprocessError):
        pass
    # Do this even when the process leader exited during the grace period: a
    # descendant can keep running after its parent has gone away.
    try:
        os.killpg(process.pid, signal.SIGKILL)
    except (OSError, ProcessLookupError):
        pass
    try:
        process.wait(timeout=grace)
    except (subprocess.TimeoutExpired, OSError, subprocess.SubprocessError):
        pass


def _read_bounded_output(
    process: subprocess.Popen[bytes], *, limit: int, timeout: float
) -> tuple[bytes, str | None]:
    """Read at most ``limit`` bytes before returning an error reason.

    ``communicate()`` is deliberately not used here: it buffers all child
    output before a caller can inspect its size.  A nonblocking pipe and
    selector keep the retained status payload bounded while preserving the
    fixed-argv subprocess boundary.
    """

    if process.stdout is None:
        return b"", "unavailable"
    selector = selectors.DefaultSelector()
    fd = process.stdout.fileno()
    os.set_blocking(fd, False)
    selector.register(fd, selectors.EVENT_READ)
    captured = bytearray()
    deadline = time.monotonic() + timeout
    stdout_open = True
    try:
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                return bytes(captured), "timeout"
            if stdout_open:
                events = selector.select(remaining)
                if not events:
                    return bytes(captured), "timeout"
                for key, _ in events:
                    del key
                    read_size = min(4096, limit - len(captured) + 1)
                    try:
                        chunk = os.read(fd, read_size)
                    except BlockingIOError:
                        continue
                    if not chunk:
                        stdout_open = False
                        selector.unregister(fd)
                        break
                    if len(captured) + len(chunk) > limit:
                        return bytes(captured), "oversized"
                    captured.extend(chunk)
            else:
                if process.poll() is not None:
                    return bytes(captured), None
                time.sleep(min(0.01, max(0.0, deadline - time.monotonic())))
    finally:
        try:
            selector.unregister(fd)
        except (KeyError, ValueError):
            pass
        selector.close()


_REDACTED_STATUS_VALUES = frozenset(
    {
        "yes",
        "no",
        "configured",
        "missing",
        "active",
        "inactive",
        "unknown",
        "not-configured",
        "not configured",
        "not-managed",
        "not-changed",
        "connected",
        "disconnected",
    }
)
_REDACTED_CONTAINER_VALUES = frozenset(
    {"absent", "stopped", "starting", "healthy", "unhealthy", "running", "inactive", "unknown"}
)
_REDACTED_POLICY_VALUES = frozenset({"strict", "smart"})
_REDACTED_SUBSCRIPTION_VALUES = frozenset({"configured", "missing"})


def _redacted_nm_value(value: object) -> str | None:
    if isinstance(value, bool):
        return "yes" if value else "no"
    if not isinstance(value, str):
        return None
    normalized = value.strip().lower()
    return normalized if normalized in _REDACTED_STATUS_VALUES else None


_NM_BINARY_ALIASES = {
    "yes": "yes",
    "no": "no",
    "configured": "yes",
    "missing": "no",
    "active": "yes",
    "inactive": "no",
    "connected": "yes",
    "disconnected": "no",
    "not-configured": "no",
    "not configured": "no",
    "not-managed": "not-managed",
}


def _redacted_nm_binary(value: object) -> str | None:
    if isinstance(value, bool):
        return "yes" if value else "no"
    if not isinstance(value, str):
        return None
    return _NM_BINARY_ALIASES.get(value.strip().lower())


def _sanitize_lifecycle_status(raw: object) -> dict[str, object]:
    if not isinstance(raw, dict):
        return {}
    result: dict[str, object] = {}
    scalar_keys = {
        "container",
        "routing_policy",
        "subscription",
        "networkmanager_configured",
        "networkmanager_active",
        "configured",
        "active",
    }
    if isinstance(raw.get("schema"), int) and not isinstance(raw["schema"], bool):
        result["schema"] = raw["schema"]
    for key in scalar_keys:
        if key == "container":
            value = raw.get(key)
            if isinstance(value, str) and value in _REDACTED_CONTAINER_VALUES:
                result[key] = value
        elif key == "routing_policy":
            value = raw.get(key)
            if isinstance(value, str) and value in _REDACTED_POLICY_VALUES:
                result[key] = value
        elif key == "subscription":
            value = raw.get(key)
            if isinstance(value, str) and value in _REDACTED_SUBSCRIPTION_VALUES:
                result[key] = value
        else:
            value = _redacted_nm_binary(raw.get(key))
            if value is not None:
                result[key] = value
    networkmanager = raw.get("networkmanager")
    if isinstance(networkmanager, dict):
        safe_networkmanager: dict[str, str] = {}
        for key in ("configured", "active", "state"):
            if key in {"configured", "active"}:
                value = _redacted_nm_binary(networkmanager.get(key))
            else:
                value = _redacted_nm_value(networkmanager.get(key))
            if value is not None:
                safe_networkmanager[key] = value
        if safe_networkmanager:
            result["networkmanager"] = safe_networkmanager
    else:
        value = _redacted_nm_value(networkmanager)
        if value is not None:
            result["networkmanager"] = value
    return result


class AllowlistedSubprocessRunner:
    """Run a configured lifecycle executable with fixed argv arrays only."""

    def __init__(self, executable: str | os.PathLike[str], *, timeout: float = 1800.0) -> None:
        value = os.fspath(executable)
        if not isinstance(value, str) or not value or "\x00" in value:
            raise ValueError("lifecycle executable must be a non-empty path")
        if any(character.isspace() for character in value):
            raise ValueError("lifecycle executable must be one argv token")
        if Path(value).name.lower() in BLOCKED_DIRECT_EXECUTABLES:
            raise ValueError("direct system and VPN executables are not lifecycle adapters")
        if timeout <= 0 or not math.isfinite(timeout):
            raise ValueError("lifecycle timeout must be finite and positive")
        self.executable = value
        self.timeout = timeout

    def argv_for(self, action: LifecycleAction | str) -> list[str]:
        """Return a fresh, fixed argv list for an allowlisted action."""

        normalized = normalize_action(action)
        try:
            suffix = LIFECYCLE_ARGV_SUFFIXES[normalized]
        except KeyError as exc:  # defensive if the enum and map drift
            raise ValueError("unsupported lifecycle action") from exc
        return [self.executable, *suffix]

    def run(self, action: LifecycleAction | str) -> CommandResult:
        normalized = normalize_action(action)
        argv = self.argv_for(normalized)
        process: subprocess.Popen[bytes] | None = None
        try:
            process = subprocess.Popen(
                argv,
                shell=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            try:
                returncode = process.wait(timeout=self.timeout)
            except subprocess.TimeoutExpired:
                _terminate_process_group(process)
                return CommandResult(normalized, None, "timeout")
        except (OSError, subprocess.SubprocessError):
            if process is not None and process.poll() is None:
                _terminate_process_group(process)
            # Do not expose exception text: a path or child output must never
            # become a UI/logging channel for private operator data.
            return CommandResult(normalized, None, "unavailable")
        return CommandResult(normalized, returncode, "ok" if returncode == 0 else "failed")

    def query_status(self) -> Mapping[str, object]:
        process: subprocess.Popen[bytes] | None = None
        failure: str | None = None
        try:
            process = subprocess.Popen(
                [self.executable, "status", "--json"],
                shell=False,
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            raw_bytes, failure = _read_bounded_output(process, limit=MAX_STATUS_BYTES, timeout=STATUS_TIMEOUT)
            if failure is not None:
                _terminate_process_group(process)
                return {}
            if process.returncode is None:
                try:
                    process.wait(timeout=PROCESS_TERMINATION_GRACE)
                except subprocess.TimeoutExpired:
                    _terminate_process_group(process)
                    return {}
            if process.returncode != 0:
                return {}
            raw = json.loads(raw_bytes.decode("utf-8"))
        except (OSError, subprocess.SubprocessError, UnicodeError, json.JSONDecodeError):
            if process is not None and process.poll() is None:
                _terminate_process_group(process)
            return {}
        finally:
            if process is not None and process.stdout is not None:
                process.stdout.close()
        return _sanitize_lifecycle_status(raw)


@dataclass
class MockLifecycleRunner:
    """Deterministic runner for tests and the non-interactive test mode."""

    returncode: int = 0
    actions: list[LifecycleAction] = field(default_factory=list)

    def run(self, action: LifecycleAction | str) -> CommandResult:
        normalized = normalize_action(action)
        self.actions.append(normalized)
        return CommandResult(normalized, self.returncode, "ok" if self.returncode == 0 else "failed")

    def query_status(self) -> Mapping[str, object]:
        return {}


class SubscriptionError(ValueError):
    """Raised when a subscription destination is outside the local secret root."""



def _canonical_secret_root() -> Path:
    """Return the one local secret root used by this process.

    ``VPNKIT_LOCAL_SECRETS_DIR`` is the same explicit isolated-lab override as
    the local lifecycle adapter.  It selects a different canonical BASE; it
    never turns ``--subscription-path`` into an arbitrary destination.
    """

    raw = os.environ.get(LOCAL_SECRETS_ENV)
    if raw is None or raw == "":
        return DEFAULT_SECRET_ROOT
    root = Path(os.path.expanduser(raw))
    if not root.is_absolute():
        root = REPO_ROOT / root
    if any(part == ".." for part in root.parts):
        raise SubscriptionError("local secret root must not contain parent traversal")
    return root



def _reject_symlink_components(path: Path) -> None:
    """Reject symlinks in every existing component without resolving them."""

    current = Path(path.anchor or os.sep)
    for part in path.parts[1:]:
        current /= part
        try:
            entry = os.lstat(current)
        except FileNotFoundError:
            return
        except OSError as exc:
            raise SubscriptionError("subscription path could not be inspected") from exc
        if stat.S_ISLNK(entry.st_mode):
            raise SubscriptionError("subscription path contains a symlink")



def _open_directory_no_symlinks(path: Path) -> int:
    """Open a directory by component, refusing symlink traversal."""

    if not path.is_absolute() or any(part == ".." for part in path.parts):
        raise SubscriptionError("subscription directory path is unsafe")
    directory_flags = os.O_RDONLY | getattr(os, "O_DIRECTORY", 0)
    directory_flags |= getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
    try:
        fd = os.open(os.sep, directory_flags)
    except OSError as exc:
        raise SubscriptionError("subscription directory is unavailable") from exc
    try:
        for part in path.parts[1:]:
            try:
                next_fd = os.open(part, directory_flags, dir_fd=fd)
            except OSError as exc:
                os.close(fd)
                raise SubscriptionError("subscription directory is unavailable") from exc
            os.close(fd)
            fd = next_fd
        return fd
    except SubscriptionError:
        raise



def _selected_path(path: str | os.PathLike[str] | None) -> Path:
    if path is None:
        raise SubscriptionError("an explicit subscription path is required")
    try:
        raw = os.fspath(path)
    except (TypeError, ValueError) as exc:
        raise SubscriptionError("subscription path is invalid") from exc
    if not isinstance(raw, str) or raw == "":
        raise SubscriptionError("an explicit subscription path is required")
    selected = Path(os.path.expanduser(raw))
    if not selected.is_absolute():
        raise SubscriptionError("subscription path must be absolute")
    if any(part == ".." for part in selected.parts):
        raise SubscriptionError("subscription path must not contain parent traversal")
    root = _canonical_secret_root()
    expected = root / "vibe-vpn" / "sub_url"
    if selected != expected:
        raise SubscriptionError("subscription path must be the canonical local sub_url")
    _reject_symlink_components(selected)
    parent_fd = _open_directory_no_symlinks(selected.parent)
    os.close(parent_fd)
    # The helper above is intentionally closed immediately; writes/status use
    # their own directory descriptor to avoid path-based parent traversal.
    # A missing final file is valid for a future write, but an existing final
    # symlink is never accepted.
    try:
        entry = os.lstat(selected)
    except FileNotFoundError:
        return selected
    if stat.S_ISLNK(entry.st_mode):
        raise SubscriptionError("subscription destination is a symlink")
    return selected



def _open_subscription_parent(selected: Path) -> int:
    return _open_directory_no_symlinks(selected.parent)



def write_subscription(path: str | os.PathLike[str] | None, value: str) -> None:
    """Write only the canonical local subscription file, without secret reads."""

    selected = _selected_path(path)
    if not isinstance(value, str) or not value or not value.strip():
        raise SubscriptionError("subscription value must not be empty")
    if len(value) > MAX_SUBSCRIPTION_LENGTH:
        raise SubscriptionError("subscription value is too long")
    if "\x00" in value or "\n" in value or "\r" in value:
        raise SubscriptionError("subscription value must be one line")
    try:
        encoded = value.encode("utf-8")
    except UnicodeEncodeError as exc:
        raise SubscriptionError("subscription value is not valid UTF-8") from exc
    if len(encoded) > MAX_SUBSCRIPTION_LENGTH:
        raise SubscriptionError("subscription value is too long")

    parent_fd = -1
    fd = -1
    try:
        parent_fd = _open_subscription_parent(selected)
        base_flags = os.O_WRONLY | getattr(os, "O_CLOEXEC", 0) | getattr(os, "O_NOFOLLOW", 0)
        base_flags |= getattr(os, "O_NONBLOCK", 0)
        for _ in range(2):
            try:
                fd = os.open(selected.name, base_flags, dir_fd=parent_fd)
                break
            except FileNotFoundError:
                try:
                    fd = os.open(
                        selected.name,
                        base_flags | os.O_CREAT | os.O_EXCL,
                        0o600,
                        dir_fd=parent_fd,
                    )
                    break
                except FileExistsError:
                    continue
        if fd == -1:
            raise SubscriptionError("subscription destination could not be opened")
        entry = os.fstat(fd)
        if not stat.S_ISREG(entry.st_mode) or entry.st_nlink != 1:
            raise SubscriptionError("subscription destination is not an owned regular file")
        os.ftruncate(fd, 0)
        view = memoryview(encoded)
        while view:
            written = os.write(fd, view)
            view = view[written:]
        os.fchmod(fd, 0o600)
        os.fsync(fd)
    except SubscriptionError:
        raise
    except OSError as exc:
        raise SubscriptionError("subscription destination could not be written") from exc
    finally:
        if fd != -1:
            os.close(fd)
        if parent_fd != -1:
            os.close(parent_fd)



def subscription_configured(path: str | os.PathLike[str] | None) -> bool:
    """Check only canonical-file metadata; never follow links or read content."""

    if path is None:
        return False
    try:
        selected = _selected_path(path)
        parent_fd = _open_subscription_parent(selected)
        try:
            entry = os.stat(selected.name, dir_fd=parent_fd, follow_symlinks=False)
        finally:
            os.close(parent_fd)
    except (OSError, SubscriptionError, TypeError, ValueError):
        return False
    return (
        stat.S_ISREG(entry.st_mode)
        and entry.st_nlink == 1
        and stat.S_IMODE(entry.st_mode) == 0o600
        and entry.st_size > 0
    )


@dataclass
class TuiState:
    """In-memory state intentionally limited to redacted, display-safe values."""

    subscription_path: str | os.PathLike[str] | None = None
    runner: SafeCommandRunner = field(default_factory=MockLifecycleRunner)
    mode: str = "strict"
    vpn_state: str = "unknown"
    diagnostics: str = "not-run"
    selection: str = "redacted"
    last_action: str = "none"
    last_result: str = "not-run"
    networkmanager_configured: str = "unknown"
    networkmanager_active: str = "unknown"

    def __post_init__(self) -> None:
        self.subscription_ready = subscription_configured(self.subscription_path)

    @property
    def runner_kind(self) -> str:
        return "mock" if isinstance(self.runner, MockLifecycleRunner) else "configured"

    def refresh(self) -> None:
        raw = self.runner.query_status()
        container = raw.get("container")
        policy = raw.get("routing_policy")
        subscription = raw.get("subscription")
        container_is_valid = container in {
            "absent",
            "stopped",
            "starting",
            "healthy",
            "unhealthy",
            "running",
            "inactive",
            "unknown",
        }
        if policy in {"strict", "smart"}:
            self.mode = str(policy)
        if subscription in {"configured", "missing"}:
            self.subscription_ready = subscription == "configured"

        # The structured NetworkManager object has precedence over legacy
        # top-level fields.  This prevents an untrusted/stale fallback from
        # turning an explicitly managed active=no result into active=yes.
        networkmanager = raw.get("networkmanager")
        configured: object = None
        active: object = None
        if isinstance(networkmanager, Mapping):
            configured = networkmanager.get("configured")
            active = networkmanager.get("active")
        if configured is None:
            configured = raw.get("networkmanager_configured", raw.get("configured"))
        if active is None:
            active = raw.get("networkmanager_active", raw.get("active"))
        safe_configured = _redacted_nm_binary(configured)
        safe_active = _redacted_nm_binary(active)
        if safe_configured is not None:
            self.networkmanager_configured = safe_configured
        if safe_active is not None:
            self.networkmanager_active = safe_active

        # A healthy container is only container evidence.  When the owned NM
        # profile is configured but inactive, reporting healthy/running would
        # falsely claim a host VPN path.  Explicit not-managed mode retains
        # container-only behavior.
        if self.networkmanager_active == "no" and self.networkmanager_configured in {"yes", "no"}:
            self.vpn_state = "inactive"
        elif container_is_valid:
            self.vpn_state = str(container)

    def save_subscription(self, value: str) -> None:
        write_subscription(self.subscription_path, value)
        self.subscription_ready = True
        self.last_action = "configure subscription"
        self.last_result = "ok"

    def dispatch(self, action: LifecycleAction | str) -> CommandResult:
        normalized = normalize_action(action)
        result = self.runner.run(normalized)
        self.last_action = normalized.value
        self.last_result = "ok" if result.ok else result.reason
        if not result.ok:
            return result

        if normalized is LifecycleAction.START:
            self.vpn_state = "inactive" if (
                self.networkmanager_configured == "yes" and self.networkmanager_active == "no"
            ) else "running"
        elif normalized is LifecycleAction.STOP:
            self.vpn_state = "stopped"
        elif normalized is LifecycleAction.RETEST_SELECT:
            self.selection = "redacted"
        elif normalized is LifecycleAction.TOGGLE_MODE:
            self.mode = "strict" if self.mode == "smart" else "smart"
        elif normalized is LifecycleAction.DIAGNOSTICS:
            self.diagnostics = "available"
        return result

    def status(self) -> dict[str, str | int]:
        """Return stable JSON-safe status with no paths, endpoints, or values."""

        return {
            "schema": 1,
            "vpn_state": self.vpn_state,
            "subscription": "configured" if self.subscription_ready else "not configured",
            "endpoint": "redacted",
            "routing_mode": self.mode,
            "selection": self.selection,
            "diagnostics": self.diagnostics,
            "last_action": self.last_action,
            "last_result": self.last_result,
            "networkmanager_configured": self.networkmanager_configured,
            "networkmanager_active": self.networkmanager_active,
            "runner": self.runner_kind,
        }


@dataclass(frozen=True)
class MenuAction:
    key: str
    label: str
    lifecycle_action: LifecycleAction | None = None


MENU_ACTIONS: tuple[MenuAction, ...] = (
    MenuAction("c", "Configure subscription"),
    MenuAction("s", "Start", LifecycleAction.START),
    MenuAction("x", "Stop", LifecycleAction.STOP),
    MenuAction("r", "Retest / select", LifecycleAction.RETEST_SELECT),
    MenuAction("m", "Toggle strict / smart", LifecycleAction.TOGGLE_MODE),
    MenuAction("d", "Diagnostics", LifecycleAction.DIAGNOSTICS),
    MenuAction("q", "Quit"),
)


def _draw_line(screen: object, row: int, text: str, *, bold: bool = False) -> None:
    """Best-effort clipped drawing that behaves well on small terminals."""

    height, width = screen.getmaxyx()  # type: ignore[attr-defined]
    if row < 0 or row >= height or width <= 1:
        return
    clipped = text[: max(0, width - 1)]
    attr = curses.A_BOLD if bold else 0
    try:
        screen.addstr(row, 0, clipped, attr)  # type: ignore[attr-defined]
    except curses.error:
        pass



def render(screen: object, state: TuiState, message: str = "") -> None:
    screen.erase()  # type: ignore[attr-defined]
    _draw_line(screen, 0, "VPNKIT local KDE TUI — skeleton", bold=True)
    _draw_line(screen, 1, "Status is redacted; lifecycle work stays behind the configured adapter.")
    _draw_line(screen, 3, "STATUS", bold=True)
    status = state.status()
    status_lines = (
        f"  VPN state       {status['vpn_state']}",
        f"  Subscription    {status['subscription']}",
        f"  Endpoint        {status['endpoint']}",
        f"  Routing mode    {status['routing_mode']}",
        f"  Selection       {status['selection']}",
        f"  Diagnostics     {status['diagnostics']}",
        f"  NetworkManager  {status['networkmanager_configured']} / {status['networkmanager_active']}",
        f"  Last action     {status['last_action']} ({status['last_result']})",
    )
    for offset, line in enumerate(status_lines, start=4):
        _draw_line(screen, offset, line)

    menu_start = 13
    _draw_line(screen, menu_start, "ACTIONS", bold=True)
    for offset, action in enumerate(MENU_ACTIONS, start=menu_start + 1):
        _draw_line(screen, offset, f"  [{action.key}] {action.label}")
    _draw_line(screen, menu_start + 9, message)
    _draw_line(screen, menu_start + 10, "Press q to quit.")
    screen.refresh()  # type: ignore[attr-defined]



def _hidden_input(screen: object) -> str:
    """Read a one-line subscription without enabling terminal echo."""

    height, width = screen.getmaxyx()  # type: ignore[attr-defined]
    row = max(0, height - 3)
    _draw_line(screen, row, "Subscription value (hidden; Enter saves, Esc cancels):")
    screen.refresh()  # type: ignore[attr-defined]
    curses.noecho()
    try:
        raw = screen.getstr(row + 1, 0, min(MAX_SUBSCRIPTION_LENGTH, max(1, width - 1)))  # type: ignore[attr-defined]
    finally:
        curses.noecho()
    if raw in (b"\x1b", "\x1b"):
        return ""
    if isinstance(raw, bytes):
        return raw.decode("utf-8", errors="strict").strip()
    return str(raw).strip()



def run_curses(screen: object, state: TuiState) -> None:
    state.refresh()
    try:
        curses.curs_set(0)
    except curses.error:
        pass
    message = ""
    while True:
        render(screen, state, message)
        key = screen.getch()  # type: ignore[attr-defined]
        if key in (ord("q"), ord("Q")):
            return
        if key in (curses.KEY_RESIZE,):
            message = ""
            continue
        try:
            key_text = chr(key).lower()
        except (TypeError, ValueError):
            message = "Press one of the listed action keys."
            continue
        selected = next((action for action in MENU_ACTIONS if action.key == key_text), None)
        if selected is None:
            message = "Press one of the listed action keys."
            continue
        if selected.key == "c":
            try:
                value = _hidden_input(screen)
                if not value:
                    message = "Subscription unchanged; value was not shown or logged."
                else:
                    state.save_subscription(value)
                    message = "Subscription saved to the selected path (value hidden)."
            except (SubscriptionError, UnicodeError):
                message = "Subscription was not saved; check the selected path and one-line value."
            continue
        assert selected.lifecycle_action is not None
        result = state.dispatch(selected.lifecycle_action)
        state.refresh()
        if result.ok:
            message = f"{selected.label} requested via the lifecycle adapter."
        else:
            message = f"{selected.label} was not completed ({result.reason})."



def _validate_subscription_argument(path: str | os.PathLike[str]) -> None:
    """Reject an explicit CLI path before status mode does any filesystem work."""

    try:
        raw = os.fspath(path)
    except (TypeError, ValueError) as exc:
        raise SubscriptionError("subscription path is invalid") from exc
    if not isinstance(raw, str) or raw == "":
        raise SubscriptionError("subscription path is invalid")
    selected = Path(os.path.expanduser(raw))
    if not selected.is_absolute() or any(part == ".." for part in selected.parts):
        raise SubscriptionError("subscription path must be an absolute canonical path")
    expected = _canonical_secret_root() / "vibe-vpn" / "sub_url"
    if selected != expected:
        raise SubscriptionError("subscription path must be the canonical local sub_url")
    _reject_symlink_components(selected)



def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--subscription-path",
        default=None,
        help="canonical local subscription file (default: BASE/vibe-vpn/sub_url)",
    )
    parser.add_argument(
        "--lifecycle-executable",
        help=f"one executable token for the fixed lifecycle adapter (or ${LIFECYCLE_EXECUTABLE_ENV})",
    )
    parser.add_argument(
        "--status-json",
        action="store_true",
        help="print redacted status JSON and do not initialize curses",
    )
    parser.add_argument(
        "--test",
        action="store_true",
        help="non-interactive mock mode; equivalent to --status-json for this skeleton",
    )
    parser.add_argument("--mode", choices=("smart", "strict"), default="strict")
    return parser



def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    executable = args.lifecycle_executable or os.environ.get(LIFECYCLE_EXECUTABLE_ENV) or str(DEFAULT_LIFECYCLE_EXECUTABLE)
    try:
        if args.test:
            runner: SafeCommandRunner = MockLifecycleRunner()
        else:
            runner = AllowlistedSubprocessRunner(executable)
        if args.subscription_path is not None:
            _validate_subscription_argument(args.subscription_path)
        subscription_path = args.subscription_path or str(_canonical_secret_root() / "vibe-vpn" / "sub_url")
        state = TuiState(subscription_path, runner=runner, mode=args.mode)
    except ValueError as exc:
        parser.error(str(exc))

    if args.status_json or args.test:
        # json.dumps is the only output path in non-interactive mode.  The
        # state object contains no subscription value or selected path.
        if not args.test:
            state.refresh()
        print(json.dumps(state.status(), sort_keys=True))
        return 0

    try:
        curses.wrapper(lambda screen: run_curses(screen, state))
    except KeyboardInterrupt:
        return 130
    return 0


if __name__ == "__main__":
    sys.exit(main())
