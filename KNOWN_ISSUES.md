# Known issues and hardening risks

Historical issue IDs are retained for reference; resolved items are removed.
No unresolved user-facing defects are currently tracked. One open hardening risk
is the application's compiler range-check setting:

- Overflow checks are enabled, but range checks are disabled
  (`Source/DiskImageManager.lpi:53-56,249-252`). An invalid array index can
  therefore access memory without raising a Pascal range exception. The test
  project has independent compiler settings, so its checks do not change the
  application's behavior. This is a defense-in-depth concern, not a report of a
  specific observed failure; enabling range checks should be evaluated against
  the existing regression suite.

Do not infer that every read beyond a sector's `DataSize` is a heap overread:
`TDSKSector.Data` is a separately allocated, 32,769-byte buffer.
