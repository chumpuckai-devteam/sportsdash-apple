# S1.5 Security review — movie ratings API keys

**Date:** 2026-07-22  
**Reviewer:** Tech Lead (security-dev scope)  
**Scope:** `MovieRatingsService`, `KeychainStore`, `GeneralSettingsView`, git hygiene  

## Findings

| Severity | Finding | Status |
|----------|---------|--------|
| OK | Keys stored in Keychain (`omdb_api_key` / `tmdb_api_key`), service `com.samirpatel.sportsdash` | Pass |
| OK | `kSecAttrAccessibleAfterFirstUnlock` — appropriate for background-ish use | Pass |
| OK | `SecureField` for entry; empty save deletes Keychain item | Pass |
| OK | No keys in git / README / Info.plist (checked) | Pass |
| OK | Fail closed — missing keys return nil, no error toasts with secrets | Pass |
| OK | Disk cache is ratings JSON only (no keys) under Caches | Pass |
| Low | Keys briefly live in `@State` while typing | **Fixed** — clear SecureField after save |
| Low | OMDb/TMDB keys go in HTTPS query string (provider API design) | Accept — no POST alternative; URLSession does not log by default |
| Info | Env override `OMDB_API_KEY` / `TMDB_API_KEY` for sim/CI only | OK if scheme-only, not committed |
| Info | TMDB attribution required | **Fixed** — About section notice |

## Patches in this ship

1. Clear SecureField text after successful Keychain save.  
2. Settings About: KSPlayer wording (not stale VLC) + TMDB attribution.  

## Residual (non-blocking)

- Consider `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` if we never need keys before first unlock after reboot for EPG prefetch — optional later.
- Avoid printing full request URLs in any future debug logging.

**Verdict:** PASS with low-severity hardening applied.
