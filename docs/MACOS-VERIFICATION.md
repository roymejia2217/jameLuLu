# macOS integration and acceptance checks

1. Configure a fork-specific Apple developer Team ID, bundle identifiers, shared
   app group and Network Extension entitlements before signing. Do not sign or
   ship with Objective-See's identifiers or identity.
2. Run the GitHub Actions macOS test/build jobs. They verify Objective-C policy
   helpers and the unsigned Xcode build, **not** system-extension activation.
3. On a designated test Mac, build/sign the app and extension with authorized
   Network Extension capabilities, approve the system extension and content filter,
   and verify the provider remains running.
4. Create a directory rule for an isolated test folder (e.g. a dedicated
   `~/jamelulu-firewall-test` folder). Select **Block**, any host and any port.
   Ensure that its executable and nested-helper paths are included.
5. Make outbound TCP/UDP attempts from executable files inside that directory;
   verify every attempted flow is denied, including IPv4, IPv6, and loopback.
6. Start a listener *implemented by an executable inside the selected directory*
   and connect from a second process outside the directory. Verify inbound flows
   to the target are dropped when macOS attributes them to that target process.
7. Add an existing per-binary Allow rule under the same directory and repeat the
   tests: the explicit wildcard directory Block must still take precedence.
8. Disable the directory rule and verify the expected previous allow/prompt
   behavior is restored. Re-enable it and verify the block returns without restart.
9. Repeat with a real application bundle, its helper app(s), symlinks, and an
   adjacent directory whose name shares the same prefix; the neighbor must not
   be blocked by this directory rule.
10. Test sleep/wake, extension restart, logout/login, macOS firewall coexistence
    and both Intel/Apple Silicon if those platforms will be distributed.

Do not claim absolute vendor isolation based solely on a directory rule.
Processes/services outside that directory and delegated networking need separate
verification. Record OS version, architecture, signed Team ID, filter status,
connection direction, process executable path and result for each test.

**Release gate:** No macOS installer/DMG should be published before successful
signed-provider runtime tests and clean coexistence testing with existing LuLu.
