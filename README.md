# jameLuLu — development fork of LuLu

**Status: experimental; not yet an installable, signed macOS release.**
[jameLuLu](https://github.com/roymejia2217/jameLuLu) is a genuine GitHub fork of
[Objective-See/LuLu](https://github.com/objective-see/LuLu). Original source and
attribution are retained under GPL-3.0.

## Why this fork?

- **Bidirectional filtering:** register for inbound and outbound Network Extension flows.
  Existing per-application allow/block rules apply to both directions.
- **Recursive directory rules:** selecting a folder, including a `.app` bundle, creates
  a `/selected/path/*` rule. It covers current and future binaries in its nested folders
  without enumerating them during rule creation.
- **Strict directory isolation:** a full-directory block for `* : *` takes precedence
  over existing individual allow rules, localhost allowances, and endpoint allow lists.

**How to try the rule in the UI:** open the Rules window, add a rule, browse to
`/Applications/Adobe Photoshop.app` (or another chosen folder), select
**Block**, and leave endpoint address and port empty (the `* : *` wildcard).
The same rule covers each executable *whose actual process path falls under that folder*.

**Limitations:** Network Extension flow attribution is not a whole-vendor isolation
guarantee. Separate processes installed outside the selected directory, services
that communicate on another process's behalf, and traffic not exposed by macOS
Network Extension may require additional rules or controls. A disabled/unapproved
extension cannot enforce the rules. Build verification on macOS GitHub Actions is
not a substitute for installation and inbound/outbound runtime tests on macOS.
See [macOS verification](docs/MACOS-VERIFICATION.md).

**Signing:** Apple's Network Extension and system-extension capabilities require
appropriate developer signing and user approval. The CI build is unsigned and
**must not be represented as an installable firewall release**. The inherited
upstream signing identifiers, bundle IDs, and service naming require an isolated
fork-specific migration before distribution.

---

## Original LuLu project


[简体中文](README_zh-Hans.md) | [正體中文](README_zh-Hant.md)

LuLu is the free open-source macOS firewall:

<p align="center"><img src="https://objective-see.com/images/LL/alert.png"></p>

**Documentation:** \
Full details and usage instructions can be found [here](https://objective-see.com/products/lulu.html).

**To Support:** \
&#x2764;&nbsp; Love this product and want to support it? Please check out my [patreon page](https://www.patreon.com/objective_see).

<p align="center">
<a class="inlineLink" href="https://www.patreon.com/objective_see">
		<img src="https://objective-see.com/patreon/images/patreon.jpg" width="700" style="display:block; margin:auto;"/>
</a>
</p>
