#!/usr/bin/env python3
"""Isolated Kill-Nano Linux tests. Never touches a real Chrome policy or home."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SOURCE = (ROOT / "kill-google-nano.sh").read_text()


class LinuxScriptTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="kill-nano-test-")
        self.addCleanup(self.temp.cleanup)
        self.base = Path(self.temp.name)
        self.base.chmod(0o777)
        self.home = self.base / "home"
        self.home.mkdir(mode=0o777)
        self.policies = self.base / "managed"
        self.bin = self.base / "bin"
        self.bin.mkdir(mode=0o777)
        self.script = self.base / "kill-google-nano.sh"
        self.script.write_text(SOURCE.replace("/etc/opt/chrome/policies/managed", str(self.policies)))
        self.script.chmod(0o755)
        # Mimic privilege escalation without touching host system directories.
        sudo = self.bin / "sudo"
        sudo.write_text('#!/bin/sh\nexec "$@"\n')
        sudo.chmod(0o755)
        pgrep = self.bin / "pgrep"
        pgrep.write_text('#!/bin/sh\nexit 1\n')
        pgrep.chmod(0o755)
        self.env = dict(os.environ, HOME=str(self.home), PATH=f"{self.bin}:{os.environ['PATH']}")
        # Run as a non-root user even in root-based CI/containers.
        if os.geteuid() == 0:
            self.uid, self.gid = 65534, 65534
            # Tests create fixtures before dropping privileges, but the paths
            # must still be accessible to the unprivileged process.
            self.home.chmod(0o777)
            self.script.chmod(0o755)
        else:
            self.uid = self.gid = None

    def run_script(self, *args, ok=True):
        def demote():
            if self.uid is not None:
                os.setgroups([])
                os.setgid(self.gid)
                os.setuid(self.uid)

        cp = subprocess.run(["bash", str(self.script), *args], env=self.env,
                            text=True, capture_output=True, preexec_fn=demote)
        if ok and cp.returncode:
            self.fail(f"exit {cp.returncode}: stdout={cp.stdout}\nstderr={cp.stderr}")
        return cp

    def model_dir(self):
        folder = self.home / ".config/google-chrome/OptGuideOnDeviceModel"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "weights.bin").write_text("fake, no real model data")
        if self.uid is not None:
            folder.parent.parent.chmod(0o777)
            folder.parent.chmod(0o777)
            folder.chmod(0o777)
        return folder

    def test_dry_run_does_not_touch_files(self):
        folder = self.model_dir()
        self.run_script("--dry-run", "--doh-automatic")
        self.assertTrue(folder.exists())
        self.assertFalse(self.policies.exists())

    def test_install_cleanup_status_restore_idempotent(self):
        folder = self.model_dir()
        unrelated = folder.parent / "Preferences"
        unrelated.write_text("do not delete")
        self.run_script()
        policy = self.policies / "disable-genai-local-model.json"
        self.assertEqual(json.loads(policy.read_text()), {"GenAILocalFoundationalModelSettings": 1})
        self.assertFalse(folder.exists())
        self.assertTrue(unrelated.exists())
        self.run_script()
        cp = self.run_script("--status")
        self.assertIn("installed", cp.stdout)
        self.run_script("--restore")
        self.assertFalse(policy.exists())
        self.assertTrue(unrelated.exists())

    def test_opt_in_dns_and_restore(self):
        self.run_script("--skip-cleanup", "--doh-automatic")
        dns = self.policies / "kill-nano-doh.json"
        self.assertEqual(json.loads(dns.read_text()), {"DnsOverHttpsMode": "automatic"})
        self.run_script("--restore")
        self.assertFalse(dns.exists())

    def test_do_not_overwrite_modified_policy(self):
        self.policies.mkdir(mode=0o777)
        policy = self.policies / "disable-genai-local-model.json"
        policy.write_text('{"OtherEnterpriseSetting":true}\n')
        cp = self.run_script(ok=False)
        self.assertNotEqual(cp.returncode, 0)
        self.assertIn("Refusing", cp.stderr)
        self.assertIn("OtherEnterpriseSetting", policy.read_text())

    def test_chrome_running_skips_cleanup(self):
        pgrep = self.bin / "pgrep"
        pgrep.write_text('#!/bin/sh\nexit 0\n')
        pgrep.chmod(0o755)
        folder = self.model_dir()
        cp = self.run_script()
        self.assertTrue(folder.exists())
        self.assertIn("Chrome is running", cp.stdout)

    def test_skip_cleanup_retains_model(self):
        folder = self.model_dir()
        self.run_script("--skip-cleanup")
        self.assertTrue(folder.exists())
        self.assertTrue((self.policies / "disable-genai-local-model.json").exists())

    def test_restore_refuses_tampered_dns_policy(self):
        self.run_script("--skip-cleanup", "--doh-automatic")
        dns = self.policies / "kill-nano-doh.json"
        dns.write_text('{"DnsOverHttpsMode":"secure"}\n')
        cp = self.run_script("--restore", ok=False)
        self.assertNotEqual(cp.returncode, 0)
        self.assertEqual(json.loads(dns.read_text()), {"DnsOverHttpsMode": "secure"})
        self.assertTrue((self.policies / "disable-genai-local-model.json").exists())

    def test_invalid_flag_is_rejected(self):
        cp = self.run_script("--delete-all", ok=False)
        self.assertEqual(cp.returncode, 2)
        self.assertFalse(self.policies.exists())

    def test_cleanup_does_not_follow_symlink(self):
        other = self.home / "precious"
        other.mkdir()
        (other / "keep.txt").write_text("keep")
        link = self.home / ".config/google-chrome/OptGuideOnDeviceModel"
        link.parent.mkdir(parents=True)
        link.symlink_to(other, target_is_directory=True)
        self.run_script()
        self.assertTrue(link.is_symlink())
        self.assertEqual((other / "keep.txt").read_text(), "keep")


if __name__ == '__main__':
    unittest.main(verbosity=2)
