"""Real TCP/UDP loopback probes from executables inside and outside .app bundles.

The default (allow) mode is only a transport-fixture sanity check.
JAME_PROBE_EXPECT=block must run on a host with a signed, activated
Network Extension and a persistent directory Block rule covering the existing
directory named by JAME_PROBE_BLOCK_ROOT. The rule must include all endpoints,
ports and protocols; Outside.app must remain outside this blocked root.
An unfiltered runner must FAIL with FILTER BYPASS (negative control).
"""
import os
import plistlib
import select
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

SOURCE = Path(__file__).with_name("socket_probe.c")
EXPECT = os.environ.get("JAME_PROBE_EXPECT", "allow")
if EXPECT not in ("allow", "block"):
    raise RuntimeError("JAME_PROBE_EXPECT must be 'allow' or 'block'")


class RealSocketBundleProbes(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.tmp = tempfile.TemporaryDirectory(prefix="jamelulu-socket-")
        cls.protected_tmp = None
        root = Path(cls.tmp.name)
        protected_root = root
        configured_root = os.environ.get("JAME_PROBE_BLOCK_ROOT")
        if EXPECT == "block" and configured_root:
            parent = Path(configured_root)
            if parent.is_symlink() or not parent.is_dir():
                raise RuntimeError("JAME_PROBE_BLOCK_ROOT must be an existing, real directory")
            parent = parent.resolve()
            if parent == Path("/") or os.path.commonpath((str(root.resolve()), str(parent))) == str(parent):
                raise RuntimeError("Blocked root must not contain the unrelated control application")
            cls.protected_tmp = tempfile.TemporaryDirectory(
                prefix="jamelulu-protected-fixture-", dir=parent
            )
            protected_root = Path(cls.protected_tmp.name)
        binary = root / "socket_probe"
        subprocess.run(
            ["clang", "-std=c11", "-Wall", "-Wextra", "-Werror",
             str(SOURCE), "-o", str(binary)],
            check=True, capture_output=True, text=True,
        )
        cls.apps = {}
        for name in ("Protected", "Outside"):
            app_root = protected_root if name == "Protected" else root
            app = app_root / f"{name}.app"
            contents = app / "Contents"
            executable = contents / "MacOS" / "socket_probe"
            executable.parent.mkdir(parents=True)
            with (contents / "Info.plist").open("wb") as output:
                plistlib.dump({
                    "CFBundleIdentifier": f"io.github.roymejia2217.jamelulu.fixture.{name.lower()}",
                    "CFBundleExecutable": "socket_probe",
                    "CFBundlePackageType": "APPL",
                }, output)
            shutil.copy2(binary, executable)
            cls.apps[name] = executable

    @classmethod
    def tearDownClass(cls):
        if cls.protected_tmp is not None:
            cls.protected_tmp.cleanup()
        cls.tmp.cleanup()

    def exercise(self, family, transport, server, client):
        server_cmd = [str(self.apps[server]), "server", transport, str(family), "0"]
        process = subprocess.Popen(
            server_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        try:
            ready, _, _ = select.select([process.stdout], [], [], 4)
            self.assertTrue(ready, f"server not ready: {server_cmd}")
            first = process.stdout.readline().strip()
            self.assertTrue(first.startswith("READY "), f"bad server ready line: {first}")
            port = first.split()[-1]
            self.assertTrue(port.isdigit(), f"invalid bound port: {first}")

            client_cmd = [str(self.apps[client]), "client", transport,
                          str(family), port]
            client_result = subprocess.run(
                client_cmd, capture_output=True, text=True, timeout=9
            )

            # An unfiltered CI runner MUST demonstrate success in every case.
            # The signed filter test MUST show denial ONLY when the selected
            # bundle owns the client or the server.
            must_block = (EXPECT == "block" and
                          (server == "Protected" or client == "Protected"))
            if must_block:
                self.assertNotEqual(
                    client_result.returncode, 0,
                    f"FILTER BYPASS: {client_cmd} reached {server}; "
                    f"stdout={client_result.stdout} stderr={client_result.stderr}",
                )
            else:
                self.assertEqual(
                    client_result.returncode, 0,
                    f"connection failed unexpectedly: {client_cmd}; "
                    f"stdout={client_result.stdout} stderr={client_result.stderr}",
                )
                self.assertIn("REPLY pong", client_result.stdout)
                self.assertEqual(process.wait(timeout=5), 0,
                                 "server did not successfully answer the probe")
        finally:
            if process.poll() is None:
                process.terminate()
            try:
                process.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                process.kill()
                process.communicate()

    def test_socket_connections_for_both_directions_and_families(self):
        for family in (4, 6):
            for transport in ("tcp", "udp"):
                for server, client in (
                    ("Outside", "Protected"),  # selected app initiates (outbound)
                    ("Protected", "Outside"),  # selected app receives (inbound)
                    ("Outside", "Outside"),    # unrelated network remains working
                ):
                    with self.subTest(family=family, transport=transport,
                                      server=server, client=client,
                                      filter_expected=EXPECT):
                        self.exercise(family, transport, server, client)


if __name__ == "__main__":
    unittest.main()
