# Known issues

Historical issue IDs are retained for reference; resolved items are removed.
No open findings are currently tracked. The application enables overflow
checks but not range checks
(`Source/DiskImageManager.lpi:53-56,249-252`): unchecked array indices can read
or write outside an array without a Pascal range exception. The test project has
its own compiler settings. Do not infer that every read beyond a sector's
`DataSize` is a heap overread: `TDSKSector.Data` is a separately allocated,
32,769-byte buffer.
