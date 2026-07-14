# Disk Image Manager

Disk Image Manager is an application for examining and manipulating disk images in the Standard and Extended DSK format used by many Spectrum, Amstrad PCW and CPC emulators.

Many of this tool's features and functions were driven by the Spectrum Disk Preservation team which used this format and tool to help manage the selection and testing of disk images archived to The World of Spectrum and The TZX Vault.

These images are traditionally created with CPDRead under DOS but Simon Owen's modern [SamDisk](http://simonowen.com/samdisk/) works great under Windows and provides for much more advanced imaging especially around copy-protected disks.

## Features

### Images

* Conversion between standard and extended image formats
* Read and save MGT/SAM Coupe disk images
* Identification of tool that created the image
* List all ASCII strings found on a disk image
* Copy a disk image's full path to the clipboard

### Analysis

* Display of extended disk parameter block (XDPB)
* Boot compatibility: Amstrad PCW 9512, Amstrad PCW 8256, Amstrad CPC 664/6128, Sinclair Spectrum +3
* Visual customisable map of space utilisation, track structure and controller flags
* Interactive disk map: hover a sector or track for its details and click to jump to it in the tree
* Save visual map to bitmap
* Hex and ASCII display of sector data
* Search sector data for ASCII data
* Navigate back and forward through visited locations with the mouse buttons, toolbar arrows or Alt+Left/Right
* Recovery of Extended DSK images that are missing their track-size table

### File viewers

* Sinclair BASIC viewer with syntax highlighting
* Amstrad (Locomotive) BASIC viewer with syntax highlighting
* Character (string) array viewer listing +3DOS DATA arrays
* Plain text viewer for +3DOS custom file types
* Spectrum SCREEN$ viewer with FLASH animation and zoom
* Amstrad CPC screen viewer for modes 0, 1 and 2 with automatic mode detection and zoom
* Advanced OCP Art Studio compressed screens (MJH run-length encoding) and window (.WIN) clips
* Save any displayed Spectrum or CPC image to PNG or BMP at native resolution

### Disk format identification

Capable of identifying the following original disk formats even when de-skewed by image tools.

* Amstrad PCW 9512
* Amstrad PCW 8256 (CF2/CF2DD variants)
* Amstrad CPC system
* Amstrad CPC data
* Spectrum +3
* Ultra 208 (Chris Pile)
* HiForm 208/203 (Ian Collier)
* Supermat 192/XCF2
* MGT SAM Coupe BDOS
* SAMDOS
* MasterDOS
* Timex TS2068

### Copy protection identification

Identification of copy-protection schemes both signed and somtimes unsigned:

* Alkatraz +3/CPC
* Frontier
* Hexagon
* Paul Owens
* Speedlock +3/CPC
* Three Inch Loader type 1/2/3
* Laser Load
* W.R.M Disc Protection (Martech)
* P.M.S. Loader 1986/1987
* Players 16-sector
* ERE/Remi HERBULOT
* KBI-19/KBI-10/CAAV
* DiscSYS 2/2.5/3/Mean
* Amsoft EXOPAL
* ARMORLOC
* Studio B Disc format
* DiscLoc by Oddball

### File system

* Can list a CP/M file system such as used on +3, PCW and CPC & Tatung Einstein
* Understands +3 DOS and AMSDOS (CPC) file headers, decoding load/exec addresses and file type
* Binary export/saving available for individual or all files with & without headers
* Rename files in place

### Modification

* Manipulation of controller flags, actual sector sizes and indicated FDC size
* Formatting and unformatting of specific sectors & tracks
* Compress out unused tracks and sectors option 

### Creation

* Formatting of new disk images to known formats
* Formatting of new disk images to custom tailored formats: Sides, tracks per side, sectors per track, sector size, first sector ID, interleave, reverse tracks, skew tracks, skew sides, gap read/write, gap format, directory blocks, block size, filler byte
* Writing of disk boot sectors as part of the image formatting process 

## Building

This application requires the [Lazarus development system](http://www.lazarus.freepascal.org/) and was tested using Lazarus IDE v4.8 on Windows 11 with high DPI support.

To be able to build and visually edit the forms you will need to install the supplied DIMComponents package. To do that:

1. Go to **Package > Open a Package File...**
2. Select the **DIMComponents.lpk** file from the DiskImageManager **Source** folder and press **Open**
3. Press the **Compile** button on the window "Package DimComponents" 
4. Once complete press the **Use >>** button and choose **Install**
5. On completion a DIM tab should appear next to the RTTI tab in the components area below the Lazarus main menu

## Screenshots

### Disk Image analysis
![Screenshot identifying a disk format and details](https://user-images.githubusercontent.com/118951/225836645-b26ccfed-e0f8-47ff-9ae0-404a803ae309.png)

### Disk format specification
![Screenshot showing specification](https://user-images.githubusercontent.com/118951/225836805-d8fd819b-c25d-4d35-9d5f-81cbfc47c211.png)

### Visual track/sector map
![Screenshot showing visual map](https://user-images.githubusercontent.com/118951/225836874-f8a8eb99-e4ce-4320-8412-88148b1ac05b.png)

### Track list with details
![Screenshot showing track list](https://user-images.githubusercontent.com/118951/225880528-54d417f6-27cc-41e7-88b1-c0af44923ff9.png)

### Sector list with details
![Screenshot showing sector list](https://user-images.githubusercontent.com/118951/225880787-3e223ca9-8243-47ee-afe8-a5bfe89a4561.png)

### Sector hex/ASCII view
![Screenshot with hex sector data](https://user-images.githubusercontent.com/118951/225837013-e97c4fdd-aa6c-4bff-81a4-134813175d57.png)

### Track properties
![Screenshot of track properties window](https://github.com/damieng/DiskImageManager/assets/118951/837f1945-0309-4f71-97eb-7322f4424467)

### Sector properties
![Screenshot of sector properties window](https://user-images.githubusercontent.com/118951/225837089-0b4b316e-65cb-4bec-8ba3-28b2e757a708.png)

### New disk formatter
![Screenshot of advanced formatter](https://user-images.githubusercontent.com/118951/216734979-edae81e3-bc49-44b1-80a8-fe19f41c2e13.png)

## Future plans

- File property sheet to view/modify directory entry and headers
- Optimize disk (+3, CPC) (defrag + interleave)
- Add files to disk
- Add/remove headers

## Licence

Copyright 2002-2026 Damien Guard.

Licensed under the Apache License, Version 2.0 (the "License"); you may not use this file except in compliance with the License. You may obtain a copy of the License at

http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software distributed under the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. See the License for the specific language governing permissions and limitations under the License.

Some icons courtesy of Mark James (FamFamFam) Silk Icon Pack licensed under a [Creative Commons Attribution 2.5 License](http://creativecommons.org/licenses/by/2.5/)
