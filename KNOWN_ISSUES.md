# Known issues and hardening risks

Historical issue IDs are retained for reference; resolved items are removed.
No unresolved user-facing defects are currently tracked. Two open hardening
risks remain:

- Overflow checks are enabled, but range checks are disabled
  (`Source/DiskImageManager.lpi:53-56,249-252`). An invalid array index can
  therefore access memory without raising a Pascal range exception. The test
  project has independent compiler settings, so its checks do not change the
  application's behavior. This is a defense-in-depth concern, not a report of a
  specific observed failure; enabling range checks should be evaluated against
  the existing regression suite. Every index known to go out of range has been
  fixed at its source rather than left to a check.

- `Utils.AutoResizeColumn` assigns the win32 `LVSCW_AUTOSIZE` (-1),
  `LVSCW_AUTOSIZE_USEHEADER` (-2) and `LVSCW_AUTOSIZE_BESTFIT` (-3) sentinels to
  `TListColumn.Width`, which is declared `0..MaxInt`. The build reports a
  range-check warning at each of those five assignments. The negative values are
  what the win32 list view requires to autosize a column, so they must stay;
  these assignments would raise if range checks were ever enabled, and that has
  to be considered before turning them on.

Do not infer that every read beyond a sector's `DataSize` is a heap overread:
`TDSKSector.Data` is a separately allocated, 32,769-byte buffer.
