# Disk Image Manager

## 2.13.0 (28 November 2026)
### Changes
- Name the Supermat 192 2/82 format, and report any other unrecognised disk with a valid disk specification as an unknown XDPB format of its capacity
- Ask before overwriting existing files when extracting, one at a time or for all of them
- Refuse to save an image flagged as corrupt because of its signature or first track, which was previously saved anyway
- Show Spectrum block graphics in BASIC listings, string arrays and text files as Unicode block characters
- Use Cascadia Mono by default, where installed, in the file viewer, sector view and disk specification preview, with Consolas elsewhere. A sector view still set to the old default of Consolas 8pt moves to it
- Right-align Spectrum and Amstrad BASIC line numbers in four columns so that listings line up
- Show Spectrum user-defined graphics as underlined letters A to U, copied to the clipboard as `\A` to `\U`, with a real backslash in a BASIC listing or string array copied as `\\`. The two that 128K machines also use for SPECTRUM and PLAY are graphics inside a string and keywords outside one
### New
- Teledisk (.td0) image support: open normal and advanced-compressed images (including gzipped ones), showing the image's comment and keeping sector flags, FM tracks and data rate, and save any disk as a compressed .td0
- Opus Discovery support: open .opd and .opu images (including gzipped and zipped ones) and save disks as them, recognise Opus disks held in DSK or Teledisk images, list and extract their files with or without the 7-byte header, view their BASIC programs, string arrays and SCREEN$ files, and format new Opus disks
- DISCiPLE .img and SAM Coupe .sad image support: open them (including gzipped ones), save disks as either, and convert between them and the other formats
- Open disk images from .zip files: every image in one is opened, including gzipped ones and those in folders, and any that will not open are listed together. Saving one asks for a new name and leaves the zip alone
- Extract files from MGT disks, with or without their 9-byte header, by saving them or dragging them out
- MGT file listings show each file's actual size and its start address, length, autorun line, execute address, array name or screen mode
- View Spectrum BASIC programs, string arrays and SCREEN$ files on MGT disks
- View any other file as hex, text or Z80 code, listed from its load address, with a button to go to its execute address. Right-click to disassemble from a byte, and choose View as Hex to open any file this way
- Name MGT +D/DISCiPLE disks as such instead of calling them SAM Coupe SAMDOS
- Drag saved disk images from the tree, and files inside disks from the list, to Explorer and other applications
- Rename files on CP/M, MGT and Opus Discovery disks from the file list's right-click menu
- View protected Amstrad BASIC programs
- Sort the list by clicking a column header, clicking again to reverse it; numeric columns sort by value rather than as text
### Fixes
- Read and save .mgt images in their real layout, the two sides of each cylinder in turn. Everything past the first directory track was previously read from, and written to, the wrong place. Files saved as .mgt by earlier versions are really .img layout and are opened as such when they hold a file to tell by
- List MasterDOS directories longer than four tracks in full, and MasterDOS subdirectory entries
- List the files of an MGT disk held in a DSK or Teledisk image from the right tracks
- Format new MGT disks with a zero filler: the previous E5 left every directory slot looking occupied
- List each MGT file with its own type, size and location, instead of every second file taking those of the entry before it, and leave erased entries out
- Show +D and DISCiPLE file names as their catalogue prints them, with keywords in full, block graphics and user-defined graphics, instead of unrelated characters such as `/` for `CODE`. Renaming keeps the keywords and graphics the new name still shows
- Keep a newly formatted MGT disk identified as MGT instead of PCW
- Open gzipped .mgt images, which were refused as an unknown file type
- Save an image opened from a name ending .GZ in capitals through Save As, as a lowercase .gz already was, instead of writing it uncompressed over the gzipped file
- Refuse a .gz that unpacks to more than 64 MB instead of exhausting memory on it
- Offer the name without .gz when saving a copy of a gzipped image, instead of the gzipped file's own name
- Save a standard DSK image with sectors that hold fewer bytes than their size code: every sector after one was written short, so reloading read one sector's data as the tail of the one before it
- Keep a formatted track whose sectors carry no data field when saving, instead of dropping it from an extended image or zeroing its sector entries in a standard one
- Keep the sector IDs of a track whose interleave is as wide as the track or wider within the table, instead of indexing outside it and handing out duplicate and missing IDs
- Restore the selected file, not just the tree node, when navigating back and forward: the detail list is rebuilt during the navigation and the remembered row is picked in it
- Write the disk specification's sector size code from the size itself, so a size between two codes (such as the 6912 bytes the New dialog offers) describes sectors at least that big instead of rounding down, and a size of zero no longer divides by zero
- Hold the usable capacity and block count a boot sector describes to what they can represent, instead of letting individually plausible fields overflow into a negative capacity and a nonsense block count
- Stop saving a copy as Standard DSK from stripping the data rate and recording mode from the image that stays open
- Ask to save a modified image, including one changed in the track or sector windows, before closing it, and keep it open if the save is cancelled
- Leave the existing file intact when saving over it fails
- Save DSK images whose tracks differ in size, or do not fill their last 256-byte block, with every track where the header says it is
- Keep each track's sector size when saving an extended DSK, instead of recording 128-byte sectors, which also broke blanking a sector's data
- Reopen a Standard DSK saved from a disk with no formatted tracks, and open truncated images as far as they go
- Refuse to save a disk with more tracks or sectors than a DSK can describe, or sides with differing track counts, instead of writing a damaged file
- Show a sector's real fill byte in Sector Properties, so that OK no longer overwrites a filled sector with the track's filler
- Offer the right default sector size in Sector Properties
- Apply Track Properties without an error, keeping a typed bit length and updating the tree when the sector count changes
- Unformat only the track chosen in the list instead of every track on the side
- Reset the FDC flags of the sector clicked instead of writing into its track
- Give a new disk's sector headers the sector size chosen in the New dialog, keep the CPC format type on double-sided disks, and refuse formats too large to create
- Keep CP/M files of the same name under different user numbers apart
- Extract CP/M files of more than 32 extents in the right order, stop at their final partial sector, and report the right size for headered files spanning several extents
- List empty CP/M files, and ignore +3DOS headers with a bad checksum
- Read disk specifications with sectors larger than 512 bytes
- Detect sector interleaves above 1, and load Standard DSK sector size codes 7 and 8
- Name the FM and MFM recording modes the right way round
- Keep tildes in Spectrum BASIC listings and stop colour and position codes showing as text
- Show keywords held inside strings in the BASIC viewer instead of leaving them out
- Show BASIC listings, string arrays and text files longer than 32,000 characters in full instead of cutting them off
- Show the pound and copyright signs in Spectrum listings, string arrays and text files, instead of a backtick and a stray accented letter before the sign
- Fix the Strings view: identical strings listed once per copy found, the last string on the disk never shown, and a memory leak each time it was viewed
- Find text that begins within a run of the same character, and include the starting sector in a new search
- Stop reporting worn disks as unknown copy protection, and match protection signatures only within a sector's own data
- Fix crashes on empty, truncated and malformed images
- Fix crashes after closing an image whose disk map or properties windows were open, and from Close All Except, which now offers to save changes first
- Fix errors from double-clicking the tree and from menu items used on rows with nothing behind them
- Keep extracted files inside the chosen folder, whatever characters their names hold
- Make Close All Except work for Modified Images and Extended DSK (v5) Images
- Keep the string, restored-file and dark blank sector choices made in Options, and discard changes, including a reset, when Options is cancelled
- Save the disk map as a real PNG when named .png, adding a missing extension and asking before replacing a file
- Open recent files whose paths use characters outside the system code page
- Survive invalid values in the settings file, and saved navigation places that no longer exist
- Stop hidden viewer windows being left behind when a file cannot be displayed
- Fix memory leaks when closing images, listing files and closing windows

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
### Fixes
- Fix the New disk dialog: working filler byte, DPB preview, memory leaks and options
- Fix mode-0 CPC screens being misdetected as mode 1
- Fix truncation when extracting files without headers
- Fix tree context-menu actions operating on the selected node instead of the right-clicked one
- List all 64 directory entries on CPC Data and System disks instead of only the first 32
- Fix +3DOS files including 128 bytes of header data when viewed or extracted, which also stopped +3DOS SCREEN$ files from displaying
- Fix attribute-less 6144-byte SCREEN$ files rendering as white on black instead of black on white
- Open unformatted 256-byte Extended DSK images without crashing

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
