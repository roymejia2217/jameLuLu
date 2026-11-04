# LuLu Passive Mode Improvements Tests

> **Test provenance / release policy:** `test_passive_mode_improvements.m`
> copies hostname and presentation logic into standalone mock classes.
> Its results do **not** prove the production implementation, actual
> Network Extension behavior, or the macOS app's UI. This legacy test runner
> is for exploratory comparisons only, not a release gate. The authoritative
> automated checks are the production `JameFirewallPolicy.h` and
> `JameIdentityPolicy.h` unit tests plus the full Xcode build and analyzer
> in `.github/workflows/macos.yml`. Signed, approved macOS runtime tests
> remain mandatory for a release.

This directory contains tests for the passive mode FQDN rule creation improvements.

## What's Tested

### 🎯 Domain Name Prioritization
- Prioritizes `flow.URL.host` over `flow.remoteHostname` over `remoteEndpoint.hostname`
- Ensures rules use domain names like `github.com` instead of IP addresses like `140.82.112.3`

### 🎨 Smart Port Display  
- Hides common ports (80, 443) for cleaner UI display
- Shows uncommon ports (8080, 3000, etc.) to highlight important information
- Preserves full data internally for precise filtering

### 🔗 End-to-End Integration
- Validates complete flow from network traffic to final rule display
- Tests real-world scenarios with complex URLs and various port configurations

## Running Tests

```bash
# Run the complete test suite
./run_passive_mode_tests.sh
```

## Test Results

✅ **Historical claim: 9/9 legacy mock assertions** (not reverified as a production test)

### Before/After Examples

| Before (IP-based) | After (Domain-based) |
|------------------|---------------------|
| `140.82.112.3:443` | `github.com` |
| `52.36.184.210:443` | `api.slack.com` |
| `127.0.0.1:8080` | `localhost:8080` |

## Files

- `test_passive_mode_improvements.m` - Comprehensive test suite
- `run_passive_mode_tests.sh` - Build and run script
- `README.md` - This file
