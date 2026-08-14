#!/usr/bin/env python3
"""Focused stdlib regressions for the issue #40 local KDE TUI."""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import stat
import subprocess
import sys
import tempfile
import time
import unittest
from pathlib import Path
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "vpnkit" / "vpnkit_local_kde_tui.py"
SPEC = importlib.util.spec_from_file_location("vpnkit_local_kde_tui_issue40", MODULE_PATH)
assert SPEC is not None and SPEC.loader is not None
TUI = importlib.util.module_from_spec(SPEC)
sys.modules["vpnkit_local_kde_tui_issue40"] = TUI
SPEC.loader.exec_module(TUI)


@contextlib.contextmanager
def local_secret_tree(temp_dir: str):
    root = Path(temp_dir) / "secrets" / "vpnkit-local"
    subscription_dir = root / "vibe-vpn"
    subscription_dir.mkdir(parents=True, exist_ok=True)
    with mock.patch.dict(os.environ, {TUI.LOCAL_SECRETS_ENV: str(root)}, clear=False):
        yield root, subscription_dir / "sub_url"


class SubscriptionTests(unittest.TestCase):
    def test_writes_only_canonical_file_with_0600(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (_, path):
            path.write_text("old", encoding="utf-8")
            path.chmod(0o644)

            TUI.write_subscription(path, "hidden-subscription-value")

            self.assertEqual(path.read_text(encoding="utf-8"), "hidden-subscription-value")
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), 0o600)
            self.assertEqual(sorted(p.name for p in path.parent.iterdir()), ["sub_url"])

    def test_requires_canonical_absolute_destination_and_rejects_multiline_value(self) -> None:
        with self.assertRaises(TUI.SubscriptionError):
            TUI.write_subscription(None, "value")
        with self.assertRaises(TUI.SubscriptionError):
            TUI.write_subscription("relative-sub-url", "value")

        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (root, path):
            with self.assertRaises(TUI.SubscriptionError):
                TUI.write_subscription(root / "other", "value")
            with self.assertRaises(TUI.SubscriptionError):
                TUI.write_subscription(path, "line-one\nline-two")

    def test_rejects_final_parent_and_root_symlinks_without_touching_target(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir) / "secrets" / "vpnkit-local"
            subscription_dir = root / "vibe-vpn"
            subscription_dir.mkdir(parents=True)
            target = Path(temp_dir) / "outside"
            target.write_text("unchanged", encoding="utf-8")

            with local_secret_tree(temp_dir):
                link = subscription_dir / "sub_url"
                link.symlink_to(target)
                with self.assertRaises(TUI.SubscriptionError):
                    TUI.write_subscription(link, "hidden-value")
                self.assertFalse(TUI.subscription_configured(link))
                link.unlink()

                subscription_dir.rmdir()
                subscription_dir.symlink_to(target.parent, target_is_directory=True)
                with self.assertRaises(TUI.SubscriptionError):
                    TUI.write_subscription(root / "vibe-vpn" / "sub_url", "hidden-value")
                self.assertFalse(TUI.subscription_configured(root / "vibe-vpn" / "sub_url"))

            target_dir = Path(temp_dir) / "root-target" / "vibe-vpn"
            target_dir.mkdir(parents=True)
            symlink_root = Path(temp_dir) / "secrets-link"
            symlink_root.symlink_to(root, target_is_directory=True)
            with mock.patch.dict(os.environ, {TUI.LOCAL_SECRETS_ENV: str(symlink_root)}, clear=False):
                selected = symlink_root / "vibe-vpn" / "sub_url"
                with self.assertRaises(TUI.SubscriptionError):
                    TUI.write_subscription(selected, "hidden-value")
                self.assertFalse(TUI.subscription_configured(selected))
            self.assertEqual(target.read_text(encoding="utf-8"), "unchanged")

    def test_rejects_hardlink_before_truncation(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (_, path):
            outside = Path(temp_dir) / "outside"
            outside.write_text("unchanged", encoding="utf-8")
            path.hardlink_to(outside)
            with self.assertRaises(TUI.SubscriptionError):
                TUI.write_subscription(path, "replacement")
            self.assertEqual(outside.read_text(encoding="utf-8"), "unchanged")

    def test_status_requires_private_file_mode(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (_, path):
            path.write_text("configured", encoding="utf-8")
            path.chmod(0o644)
            self.assertFalse(TUI.subscription_configured(path))
            TUI.write_subscription(path, "configured-again")
            self.assertTrue(TUI.subscription_configured(path))


class RunnerTests(unittest.TestCase):
    def test_builds_only_fixed_argv_and_uses_a_new_process_group(self) -> None:
        runner = TUI.AllowlistedSubprocessRunner("/tmp/mock-vpnkit-lifecycle")
        process = mock.MagicMock()
        process.pid = 1234
        process.returncode = 0
        process.wait.return_value = 0
        with mock.patch.object(TUI.subprocess, "Popen", return_value=process) as popen:
            result = runner.run(TUI.LifecycleAction.RETEST_SELECT)

        self.assertTrue(result.ok)
        argv, kwargs = popen.call_args
        self.assertEqual(argv[0], ["/tmp/mock-vpnkit-lifecycle", "retest", "select"])
        self.assertFalse(kwargs["shell"])
        self.assertTrue(kwargs["start_new_session"])
        self.assertIs(kwargs["stdin"], subprocess.DEVNULL)
        self.assertIs(kwargs["stdout"], subprocess.DEVNULL)
        self.assertIs(kwargs["stderr"], subprocess.DEVNULL)
        process.wait.assert_called_once_with(timeout=1800.0)

    def test_timeout_terminates_descendant_process_group(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            executable = root / "lifecycle"
            ready = root / "child-ready"
            survivor = root / "child-survived"
            child_code = (
                "import pathlib,time; "
                f"pathlib.Path({str(ready)!r}).write_text('ready'); "
                "time.sleep(0.8); "
                f"pathlib.Path({str(survivor)!r}).write_text('survived'); "
                "time.sleep(5)"
            )
            executable.write_text(
                "#!/usr/bin/env python3\n"
                "import subprocess,sys,time\n"
                f"subprocess.Popen([sys.executable, '-c', {child_code!r}])\n"
                "time.sleep(5)\n",
                encoding="utf-8",
            )
            executable.chmod(0o700)
            runner = TUI.AllowlistedSubprocessRunner(str(executable), timeout=0.2)

            result = runner.run(TUI.LifecycleAction.START)
            self.assertEqual(result.reason, "timeout")
            self.assertTrue(ready.exists())
            time.sleep(1.0)
            self.assertFalse(survivor.exists(), "a timed-out descendant survived the process-group kill")

    def test_rejects_shell_tokens_and_direct_mutation_tools(self) -> None:
        with self.assertRaises(ValueError):
            TUI.AllowlistedSubprocessRunner("/bin/sh -c")
        with self.assertRaises(ValueError):
            TUI.AllowlistedSubprocessRunner("docker")
        with self.assertRaises(ValueError):
            TUI.AllowlistedSubprocessRunner("/usr/bin/sudo")

    def test_mock_runner_records_only_known_actions(self) -> None:
        runner = TUI.MockLifecycleRunner()
        result = runner.run("start")
        self.assertTrue(result.ok)
        self.assertEqual(runner.actions, [TUI.LifecycleAction.START])
        with self.assertRaises(ValueError):
            runner.run("arbitrary-command")


class StateAndStatusTests(unittest.TestCase):
    def test_status_is_redacted_and_toggle_is_deterministic(self) -> None:
        secret = "subscription-token-must-not-appear"
        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (_, path):
            TUI.write_subscription(path, secret)
            state = TUI.TuiState(path, runner=TUI.MockLifecycleRunner())

            before = json.dumps(state.status(), sort_keys=True)
            self.assertNotIn(secret, before)
            self.assertNotIn(str(path), before)
            self.assertEqual(state.status()["subscription"], "configured")
            self.assertEqual(state.status()["endpoint"], "redacted")

            self.assertEqual(state.status()["routing_mode"], "strict")
            state.dispatch(TUI.LifecycleAction.TOGGLE_MODE)
            self.assertEqual(state.status()["routing_mode"], "smart")
            state.dispatch(TUI.LifecycleAction.RETEST_SELECT)
            state.dispatch(TUI.LifecycleAction.DIAGNOSTICS)
            self.assertEqual(state.status()["selection"], "redacted")
            self.assertEqual(state.status()["diagnostics"], "available")

    def test_refresh_consumes_redacted_networkmanager_fields(self) -> None:
        class LifecycleStatus:
            def query_status(self):
                return {
                    "container": "healthy",
                    "routing_policy": "strict",
                    "subscription": "configured",
                    "networkmanager": {"configured": "yes", "active": "no"},
                }

            def run(self, action):
                return TUI.CommandResult(TUI.normalize_action(action), 0)

        state = TUI.TuiState(None, runner=LifecycleStatus())
        state.refresh()
        self.assertEqual(state.networkmanager_configured, "yes")
        self.assertEqual(state.networkmanager_active, "no")
        self.assertEqual(state.vpn_state, "inactive")
        self.assertNotIn(state.vpn_state, {"healthy", "running"})
        self.assertEqual(state.status()["networkmanager_configured"], "yes")
        self.assertEqual(state.status()["networkmanager_active"], "no")

        class MissingManagedProfileStatus:
            def query_status(self):
                return {
                    "container": "healthy",
                    "networkmanager": {"configured": "no", "active": "no"},
                }

            def run(self, action):
                return TUI.CommandResult(TUI.normalize_action(action), 0)

        missing_managed = TUI.TuiState(None, runner=MissingManagedProfileStatus())
        missing_managed.refresh()
        self.assertEqual(missing_managed.vpn_state, "inactive")

        class ContainerOnlyStatus:
            def query_status(self):
                return {
                    "container": "healthy",
                    "networkmanager": {"configured": "not-managed", "active": "not-managed"},
                }

            def run(self, action):
                return TUI.CommandResult(TUI.normalize_action(action), 0)

        container_only = TUI.TuiState(None, runner=ContainerOnlyStatus())
        container_only.refresh()
        self.assertEqual(container_only.vpn_state, "healthy")
        self.assertEqual(container_only.networkmanager_configured, "not-managed")

    def test_fixed_menu_contains_requested_actions_and_quit(self) -> None:
        labels = [action.label for action in TUI.MENU_ACTIONS]
        self.assertEqual(
            labels,
            [
                "Configure subscription",
                "Start",
                "Stop",
                "Retest / select",
                "Toggle strict / smart",
                "Diagnostics",
                "Quit",
            ],
        )
        self.assertEqual(TUI.MENU_ACTIONS[-1].lifecycle_action, None)


class CommandLineTests(unittest.TestCase):
    def test_status_json_is_noninteractive_and_contains_no_secret(self) -> None:
        secret = "cli-secret-never-printed"
        with tempfile.TemporaryDirectory() as temp_dir, local_secret_tree(temp_dir) as (root, path):
            TUI.write_subscription(path, secret)
            env = os.environ.copy()
            env[TUI.LOCAL_SECRETS_ENV] = str(root)
            completed = subprocess.run(
                [sys.executable, str(MODULE_PATH), "--status-json", "--test", "--subscription-path", str(path)],
                check=False,
                capture_output=True,
                text=True,
                env=env,
            )

        self.assertEqual(completed.returncode, 0, completed.stderr)
        status = json.loads(completed.stdout)
        self.assertEqual(status["subscription"], "configured")
        self.assertNotIn(secret, completed.stdout)
        self.assertNotIn(str(path), completed.stdout)

    def test_status_mode_queries_fixed_action_and_sanitizes_networkmanager(self) -> None:
        process = mock.MagicMock()
        process.pid = 1234
        process.returncode = 0
        process.poll.return_value = 0
        process.stdout = io.BytesIO()
        payload = (
            b'{"schema":1,"container":"healthy","routing_policy":"strict",'
            b'"subscription":"configured","networkmanager":{"configured":"yes","active":"no",'
            b'"private":"must-drop"}}'
        )
        with mock.patch.object(TUI.subprocess, "Popen", return_value=process) as popen:
            with mock.patch.object(TUI, "_read_bounded_output", return_value=(payload, None)):
                runner = TUI.AllowlistedSubprocessRunner("/tmp/mock-vpnkit-lifecycle")
                status = runner.query_status()

        argv, kwargs = popen.call_args
        self.assertEqual(argv[0], ["/tmp/mock-vpnkit-lifecycle", "status", "--json"])
        self.assertFalse(kwargs["shell"])
        self.assertTrue(kwargs["start_new_session"])
        self.assertEqual(status["networkmanager"], {"configured": "yes", "active": "no"})
        self.assertNotIn("private", json.dumps(status))
        self.assertEqual(status["container"], "healthy")

    def test_oversized_status_is_rejected_while_reading(self) -> None:
        with tempfile.TemporaryDirectory() as temp_dir:
            root = Path(temp_dir)
            executable = root / "lifecycle"
            survivor = root / "survivor"
            executable.write_text(
                "#!/usr/bin/env python3\n"
                "import pathlib,sys,time\n"
                "if sys.argv[1] == 'status':\n"
                f"    sys.stdout.write('x' * {TUI.MAX_STATUS_BYTES + 4096})\n"
                "    sys.stdout.flush()\n"
                "    time.sleep(5)\n"
                f"    pathlib.Path({str(survivor)!r}).write_text('survived')\n",
                encoding="utf-8",
            )
            executable.chmod(0o700)
            runner = TUI.AllowlistedSubprocessRunner(str(executable))
            started = time.monotonic()
            self.assertEqual(runner.query_status(), {})
            self.assertLess(time.monotonic() - started, 2.0)
            time.sleep(0.2)
            self.assertFalse(survivor.exists())


if __name__ == "__main__":
    unittest.main()
