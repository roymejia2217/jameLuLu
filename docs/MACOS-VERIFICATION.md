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

## Signed DMG packaging — release gate, not yet validated

An unsigned GitHub Actions build is **not** a functioning firewall. To test the
system extension on an actual Mac, rebuild/sign the application and embedded
extension in Xcode using an authorized Apple Developer team and the
`content-filter-provider-systemextension` capability. Install the required
Developer ID provisioning profiles, activate the system extension and content
filter, and complete the runtime acceptance checks above.

Once an already signed `jameLuLu.app` has passed those tests, the repository's
`DMG/createDMG.sh` can create a distributable image using macOS's standard
`codesign`, `hdiutil`, `notarytool`, `stapler`, and `spctl` utilities.
The packager requires these environment variables:

- `JAMELULU_DEVELOPER_ID`: your own **Developer ID Application** signing identity.
- `JAMELULU_TEAM_ID`: the corresponding 10-character Apple Team ID.
- `JAMELULU_NOTARY_PROFILE`: a local notarytool keychain profile (set up with
  `xcrun notarytool store-credentials`).

Run `bash DMG/createDMG.sh /path/to/signed/jameLuLu.app /path/to/output-directory`.
The script checks both bundle identifiers, validates signatures and signing
Team IDs, refuses to overwrite an existing output, signs the DMG and requires an
**Accepted** notarization status plus stapling and Gatekeeper assessment before
reporting success. It deletes a failed/incomplete DMG rather than leaving an
unverified release artifact behind.

These release operations cannot be exercised by the unsigned macOS CI workflow;
they must be verified on a Mac with your actual signing and notarization
configuration. Never reuse Objective-See's Developer ID or provisioning profiles.
## Safety checks for installation and coexistence

On a disposable test Mac, verify that a package located at
`/Applications/jameLuLu.app` with a different `CFBundleIdentifier` is
**never** removed or sent to Trash by jameLuLu's install, upgrade, first-run
relocation, or uninstall logic. Do not test by risking a real installed app:
use a restored VM/test Mac and a harmless, independently backed-up dummy bundle.
The check currently uses the destination bundle's metadata; it is **not**
cryptographic proof of ownership. A signed release needs signing Team ID
validation, TOCTOU protections and a recoverable atomic update strategy.

With upstream LuLu and jameLuLu both installed on that test system, verify
that restarting/upgrading/uninstalling jameLuLu does not stop the upstream
`LuLu` process or alter its rules, preferences or Network Extension.
`JameMayTerminateOwnedPeer` must match the fork's bundle ID and package name,
and must reject PID zero, the current PID, and unknown identities.
## Uninstaller state deletion boundary

The privileged XPC uninstall operation must remove only
`/Library/Application Support/jameLuLu`. It must **never** attempt to remove
the parent `/Library/Application Support`, even when empty, or data belonging
to `/Library/Objective-See/LuLu`. The precise path is enforced by a fail-closed
policy helper with native Objective-C regression tests.
