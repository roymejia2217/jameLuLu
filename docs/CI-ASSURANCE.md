# CI assurance and one-candidate acceptance policy

## Goal and non-goals

Deliver a **single candidate** that can be installed on a user's Mac for final
verification, without requiring iterative local development. Preserve upstream
LuLu's architecture and keep changes to inbound/outbound application filtering
as small as possible.

**Do not confuse**: compiling the extension, exercising a loopback socket,
getting a NetworkExtension rule with direction `Any`, signing an app, or
notarizing a DMG with *demonstrating enforcement by the macOS content filter*.
No CI tool can logically guarantee arbitrary future user-machine behavior.
This project does not ship an unsigned debug ZIP as a usable firewall.

## Established tools and source evidence

- **Xcode / Apple Clang Static Analyzer**: compile and analyze Objective-C
  production targets, including the embedded system extension.
  https://clang.llvm.org/docs/ClangStaticAnalyzer.html
- **actionlint v1.7.12**: validate the actual GitHub Actions YAML, expressions
  and embedded shell commands. This is the published upstream project
  `rhysd/actionlint`, not custom script validation.
  https://github.com/rhysd/actionlint
- **GitHub-hosted macOS 15 runners**: `macos-15-intel` is Intel,
  `macos-15` is Apple Silicon. CI should execute production-policy tests
  and unsigned **Release** builds on both architectures.
  https://docs.github.com/en/actions/how-tos/write-workflows/choose-where-workflows-run/choose-the-runner-for-a-job
- **Apple's code-signing, Developer ID, Network Extension capability and
  system extension approval** remain authoritative. An appropriate
  `content-filter-provider-systemextension` entitlement and provisioning
  configuration are necessary for direct distribution.
  https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.networking.networkextension
  https://support.apple.com/guide/deployment/depa5fb8376f/web

Do **not** use CodeQL C/C++ as an Objective-C firewall code-coverage claim.
CodeQL explicitly excludes Objective-C/Objective-C++.
https://codeql.github.com/docs/codeql-overview/supported-languages-and-frameworks/

## Evidence matrix (mandatory truth labels)

| Gate | What is measured | What it does not prove |
| --- | --- | --- |
| CI workflow integrity | Independent actionlint check on workflows | That the firewall is working |
| Pure policy and identity checks | Native Objective-C production helpers; real Apple Security framework requirement parser; directory boundary cases; rule direction/protocol | OS socket enforcement |
| Transport fixtures | Real TCP/UDP localhost IPv4/v6 client/server binaries inside Protected.app and Outside.app: 12 expected successful baseline connections | Filter activation |
| Negative control | Running the same fixture in `block` mode with **no filter** must report eight `FILTER BYPASS` assertions, while unrelated controls succeed | That a remote Mac will activate its extension |
| Compiler, analyzer and layouts | Unsigned Release app and embedded extension on Intel and Apple Silicon; Xcode analyze; bundle identifiers | Signature validity, notarization or socket drop |
| Signed release | Real Developer ID signatures, matching Team IDs, entitlements/profiles, notarized and Gatekeeper-validated DMG | Runtime activation and filtering |
| Remote macOS enforcement (required for E2E) | Approved, enabled system content filter plus verified inbound/outbound **drop verdicts** and TCP/UDP IPv4/v6/non-loopback control traffic | Unlimited future platform compatibility |

A signed release requires **all** gates, including the last one, to be recorded
as successful. Until then, use the status **release blocked**, not
`production ready`.

## Real enforcement gate when a controlled remote Mac is available

Run the same native socket probes against the signed app with a persistent
recursive blocking rule for `JAME_PROBE_BLOCK_ROOT/*`:
- Capture `systemextensionsctl list` and prove the **expected Team ID and
  extension identifier** are `activated enabled` (not waiting for approval).
- Prove `NEFilterManager` is enabled and the expected provider instance is
  operating; collect provider-side *drop verdict* evidence in addition to
  client-side socket errors. Mere nonzero exit codes can be unrelated errors.
- Verify inbound and outbound denial for TCP/UDP, IPv4/IPv6 and localhost;
  verify separate non-loopback interfaces, helpers, other applications,
  and original Objective-See LuLu coexistence.
- Test rule enable/disable, relaunch, wake/restart and false-positive cases.
- Record host OS version, CPU architecture, Xcode/SDK, signed Team ID, exact
  binary/DMG SHA-256, logs, all expected vs actual outcomes.

On unmanaged macOS, system extension activation can require local
administrator approval; on managed Macs a compatible MDM system extension
policy can preapprove it. Hosted GitHub macOS runners do not automatically
provide this release-level approval or a persistent provider. Do not infer
activation from `xcodebuild`, a valid Info.plist or an unsigned artifact.

## Release decision

A single installation opportunity is an engineering constraint, not a reason to
falsify certainty. Prepare a signed, notarized candidate only after credentials
and provisioning are available and the exact binary has passed the automated
gates. If remote signed enforcement cannot be executed, the candidate remains
**functionally unverified** even when every available unsigned GitHub CI check
passes; a one-shot user Mac test is then an acceptance test, not a prior
guarantee. Never merge a draft into `master` or label the artifact stable on
that evidence alone.
