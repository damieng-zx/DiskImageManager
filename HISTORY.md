# Disk Image Manager

## 2.12.0 (14 July 2026)
### Changes
- Auto-detect the CPC screen graphics mode from banding artifacts instead of always defaulting to one mode
- Open the CPC screen viewer only for full screens, routing Advanced OCP Art Studio files appropriately on double-click
### New
- MGT disk image support: read 80-track double-sided MGT images and save disks as MGT
- View Advanced OCP Art Studio CPC screens, decompressing MJH-packed data and .WIN window files
- Save button in the CPC and Spectrum screen viewers to export the displayed screen as an image
- Interactive disk map: hover a sector for a floating panel (side, track, sector, ID, status, size, index offset and decoded FDC flags) or an unformatted track for its details, and click a sector or track to jump straight to it in the tree
- Navigate back and forward through places you've visited in the tree using the mouse back/forward buttons, the < and > toolbar buttons, the Navigate menu, or Alt+Left/Right; the history is remembered between sessions
- List the contents of +3DOS character (string) arrays in the file viewer, one string per line
- View +3DOS custom type 0x04 files as plain text in the file viewer
- Remember the last folders used for opening and saving files between sessions
- Sort the list by clicking a column header, clicking again to reverse it; numeric columns sort by value rather than as text
### Fixes
- Fix the New disk dialog: working filler byte, DPB preview, memory leaks and options
- Fix mode-0 CPC screens being misdetected as mode 1
- Fix truncation when extracting files without headers
- Fix tree context-menu actions operating on the selected node instead of the right-clicked one
- List all 64 directory entries on CPC Data and System disks instead of only the first 32
- Fix +3DOS files including 128 bytes of header data when viewed or extracted, which also stopped +3DOS SCREEN$ files from displaying
- Fix attribute-less 6144-byte SCREEN$ files rendering as white on black instead of black on white
- Open unformatted 256-byte Extended DSK images without crashing
- Fix the Strings view: identical strings listed once per copy found, the last string on the disk never shown, and a memory leak each time it was viewed

## 2.11.0 (05 June 2026)
### Changes
- Rewrote copy protection detection as a staged fingerprinting flow (T0 signature scan, T0 geometry classification, Track 1 family checks, high-track probes, and a mid-disk odd-sector sweep) instead of independent whole-disk scans
### New
- Amstrad (Locomotive) BASIC file viewer with syntax highlighting for AMSDOS tokenized BASIC files
- Amstrad CPC screen viewer for ~16K files with a Mode 0/1/2 selector (raw screen dumps carry no mode), an adjustable start offset for files with a few extra header/trailer bytes, and the firmware default palette
- Detect unsigned Alkatraz +3 (uniform 8x512 data tracks) and locate the 18-sector protection track wherever it sits
- Detect unsigned Speedlock data sides (uniform 5x1024 tracks)
- Distinguish Hexagon from Speedlock 1989 on CPC/+3 disks using the Track 0 sector count and deleted-data marks
- Detect the Speedlock 9x512 high-ID-filler variant
### Fixes
- Show AMSDOS binary load/execution addresses in hex and flag 16K binaries loading at &C000 as screens (real screens are saved as plain binary, not the rarely-used SCREEN type)
- Fix AMSDOS unknown file type label reporting the wrong header byte
- Recover Extended DSK images with a blank track-size table (e.g. some CPDRead output) by scanning for the real track data, with a warning instead of showing every track as unformatted
- Fix boot sector detection checking wrong sector (was checking T0S1 instead of T0S0)
- Always show boot sector status in disk info (shows "Unknown" if not detected)
- Fallback to default +3/PCW 180K spec when T0S0 contains invalid specification bytes
- Handle SAMdisk v5 multi-copy (weak) sectors correctly, fixing file extraction, CP/M block counts, and per-sector checksum/fill that previously ran over concatenated copies
- Keep later sectors aligned when a record's stored length exceeds the maximum sector size
- Fix PCW 720K directory blocks to 2 and CPC System reserved tracks to 2

## 2.10.0 (03 April 2026)
### New
- Sinclair BASIC file viewer with syntax highlighting
- Spectrum screen$ display
- FLASH attribute support
- Basic TS2068 disk detection
- High DPI support for all dialog forms

### Fixes
- Fix memory leaks across FileSystem, New, and Main units
- Fix allocation size on identified disks
- Do not consider end-of-cylinder status an error flag
- Handle invalid files better
- Better file share and error handling
- Fix build version label font

## Build 50 (18 March 2009)
###	New
-	Now available under the BSD licence
-	Opens .dsk files passed on the command line or using Windows "Open With"
###	Changes
-	Ported to Turbo Delphi 10 and created new component package
-	Cleaned up file and unit names
-	Renamed from SPIN Disk Manager (SDM) to Disk Image Manager (DIM)
-	Temporarily disabled fingerprinting due to lack of SHA-1 component
-	Minor UI tweaks to the menus
-	Added to Subversion repository

## Build 48 (08 November 2005)
###	New
-	Now detects a number of SAM formats - SAMDOS, MasterDOS and BDOS
###	Changes
-	Copy protection can be on top of an identified format e.g. "Spectrum +3 with Three Inch Loader..."
- 	The "oversized" part of format detection now ignores unformatted tracks at the end of the disk

## Build 46 (07 November 2005)
### Fixes
-	Fixed runtime range error encountered with some disks during format detection
### New
-	Improved copy protection where signatures are damaged or missing on Frontier, Hexagon, Paul Owens and Speedlock.
-	Three Inch Loader now detected as type 1 and type 2 based on signature.

## Build 43 (26 October 2005)
### New
-	Right-click the list view to copy selected information to the clipboard
	Note: That this means sector properties must now be accessed from the tree view.
-	Added detection of unmarked Hexagon copy protection

## Build 42 (26 October 2005)
### Fixes
-	Regression that prevented loading of images with a zero length/unformatted track.

## Build 39 (25 October 2005)
This is a VERY untested version.
###	Changed
-	New "Corrupted" mode will continue to load bad DSK images, warning you about each problem:
	1. Tracks with data > 32767 bytes (no more sector data is loaded, sectors will contain random data)
	2. Sectors with data > 6144 bytes (only 6144 bytes are loaded, actual claimed size will be shown in brackets once loaded)
	3. Image file truncation (to some extent)
	These images will be loaded as best SDM can but you will not see the extra track or sector data - it did not load it after all.  Images considered bad when loading can not be resaved.

## Build 34 (04 April 2005)
This is a VERY untested version other than ensuring oddly sized extended DSK's re-save exactly as they should.  Standard disk formats have not yet been tested with the FDC Size changes detailed below.

###	Changed
-	The actual sector data size and the floppy disk controllers indicated size (FDC Size) are now independent
	This allows loading and saving of some copy-protected formats
	If editing a sectors size, or creating custom formats make sure you set these correctly
	FDC Size should be (128 << sector size)
### Fixes
-	Track sizes not an exact multiple of 256 will no longer loose data in extended format


## Build 32 (23 February 2005)

###	Note
-	Valid sector sizes are only 128,256,512,1024,2048,4096, 8192.  Should you format one with SDM with a different sector size it will choose the smallest from the valid ones that will accomodate your chosen sector size when saving to DSK.  The maximum sector size is 6144 bytes.
### Fixes
-	Sector sizes of 128 bytes now supported (reported by Obo)
-	Detect invalid sector sizes when loading


## Build 31 (23 February 2005)

### Fixes
-	Sector sizes above 512 are now correctly identified. (reported by Obo)
  	Disks created/modified with this tool prior to this build may have truncated track sizes and data!!!!!
-	8K sectors will only store 6K of data as per the DSK specification
-	Will only deal with disk images containing up to 6144 bytes of sector data (previously 6192 bytes)
-	Sector display in hex now shows the whole sector - was missing last line (reported by Obo)
-	Side/track/sector listings should be quicker to display

## Build 30 (02 August 2003)

### New
-	Disk properties window allows you to view & set FDC flags, size, status
-	Sector pad option when extending an existing sector
-	Sector status now more detailed
-	Warning setting added to options before modifying sectors
###	Changed
-	Sectors unformatted or filled with a byte are now classed as Unused in Disk map
-	Track sizes are now calculated on the fly from sector sizes within the track
This may cause issues with DSK file handling, please take care

## Build 29 (31 July 2003)

### New
-	Disk image now has an “SHA-1” fingerprint – sites making images available can publish the fingerprint to help detect corrupted or modified images
-	Click a sector then right-mouse button to reset the FDC status or blank the data
### Fixes
-	Workspace now saving again
-	Corrected the about box URL


## Build 28 (14 May 2003)

### Fixes
-	Usable space now takes block slack into consideration (thanks Cristian)
-	Removed stray “interleave is 0” warnings
-	Warning about +3 disk spec mentions PCW too
-	Fixed problem where data in track 0 sector 0 causes exception error because trying to interpret it as a disk specification.

## Build 27 (13 May 2003)

### Fixes
-	Solved issue creating disks with more than 255 logical tracks
-	Disk specification now written correctly
-	Workspace doesn’t pickup a stray specification on new specification-less images
###	General
-	Save now complements Save Copy As…
-	Now prompted to save unsaved imaged during exit or close all

## Build 26 (12 May 2003)

### Fixes
-	Saving standard format actually writes the file again
-	Disk > New now gets free space correct
###	General
-	Caption over left hand pane is much more useful as it shows context
-	Added Ian High, Ian Max (same as Ultra 208) and Amstrad CPC IBM formats
-	Added unformatted disk detection to analysis
-	Added Amstrad CPC boot detection
###	Disk > New
-	Rewritten to allow all these new features
-	Negative skew, side skew as well as negative and irregular interleaves
-	Disk specifications (makes custom formats not recognisable on +3)
-	Double(Reverse) sides - like alternate but counts tracks back in like DVD layers
(This reverse method is not supported by +3DOS)
-	Buttons changed so can write multiple disks easily
-	Boot option implemented and now shows offset, checksum etc.

## Build 25 (10 May 2003)
-	Added sector and block sizes to disk specifications
-	Tightened hexagon protection detection
-	Corrected major issues with sector data display
-	Added block size to Disk > New
-	Optimisations in way disks loaded/held in ram
-	Corrected specification gap’s – format and r/w were reversed
-	Switched Disk > New track gap back to gap format from r/w
-	Added Supermat 192 and Ultra 208 disk formats
-	Track skew rewritten to actually work
-	Detection of formats now handles images that have been de-interleaved or de-skewed such as those produced by DU54

## Build 24 (09 May 2003)
-	Skew now functional in Disk > New
-	Added “Is changed” status for future saving/manipulation
-	Added ‘Format analysis’ to image info that identify’s PCW/+3/CPC formats and some +3 copy protection (Alcatraz, Speedlock 1988/1989/+3, Paul Owen’s, Three Inch Loader, Hexagon) as well as under and oversized images
-	Fixed problem caused by r23 when workspace did not save
-	Added additional track-size warnings to Disk > New
-	Added new ‘Is uniform’ to image info (If drive’s tracks and sectors all the same size/number)
-	Reworked bootable UI in Disk > New although not yet functional
-	Added ‘Bootable on’ to image info
-	Changed Disk > New to use Gap read/write for gap sizes on tracks – can’t find any info on how they are exactly calculated.  Most emulators will ignore them but may cause issues if trying to write custom formats back to disk.
-	No longer give an icon for a disk specification if one isn’t present on disk
-	Added check during DSK loading to not exceed internal 6912 byte sector limit
-	Added FDC errors found indicator to image info
-	Close All no longer leaks – it previously did not remove the images from memory
-	Fixed problem with loading disks with small or non-existent sector 0 on track 0, side 0
-	Warn and abort if DSK file runs out before we finished loading
 
## Build 23 (08 May 2003)
-	Can now build new disk images from a variety of PCW/Spec/CPC formats as well as making your own
-	DSK images loaded in now correct actual track size and not track size inside DSK (which has a 256 byte header)
-	Note that: Disk specification, bootable and skew are not yet implemented

## Build 22 (07 May 2003)
-	Prototype UI only for Disk > New

## Build 21 (01 May 2003)

-	Save disk maps as bitmaps using right mouse button
-	Toggle dark blank sectors using right mouse button
-	Size of bitmaps controllable in View > Options > Saving

## Build 20 (30 April 2003)

-	Experimental saving between formats now supported – Use “Save Copy”
-	Dark unused sectors on map works again
-	Correctly read in images with compressed out tracks
-	Assume ‘E5’ specification disks are in fact +3 ones (A real +3 assumes practically anything is)

## Notes on saving
If going from standard to extended you can compress out all the tracks with 0 sectors if you turn on the option.

If going from extended to standard and the track sizes vary you will get a warning about all sizes being set to maximum. You can turn this off in the options.  Converting from extended to standard results in larger file sizes and potentially less accurate files.

Saving in standard format writes the header/creator as per the DSK format specification.  Most standard disk images out there are created by DU54 which write the creator/disk-info block wrongly (though we fudgingly read them in okay).

It’s called “Save copy as…” for a reason, don’t overwrite anything important, who knows what may happen.
