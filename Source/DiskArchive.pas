unit DiskArchive;

{$MODE Delphi}

{
  Disk Image Manager -  Disk images packed in .gz and .zip files

  Both are read only, and both are unpacked into memory. A zip can hold any
  number of disk images, each opened as an image of its own.

  Copyright (c) Damien Guard. All rights reserved.
  Licensed under the Apache License, Version 2.0 (the "License");
  you may not use this file except in compliance with the License.
  You may obtain a copy of the License at http://www.apache.org/licenses/LICENSE-2.0
}

interface

uses
  DskImage, Classes, SysUtils, FGL, ZStream, Zipper, crc;

const
  // No disk image unpacks to anything like this; the limit stops a file made to
  // exhaust memory
  MaxUnpackedSize = 64 * 1024 * 1024;

type
  TDSKImageList = TFPGList<TDSKImage>;

function IsZipFileName(const FileName: string): boolean;

// The contents of a gzip file. The caller frees the stream.
function UnpackGzip(const FileName: string): TMemoryStream;

// Add every disk image in a zip to Images, which the caller then owns, in the
// order the zip lists them. An entry that will not open is described in
// Problems and the rest are still read. A file that is not a zip raises.
procedure LoadZipImages(const FileName: string; Images: TDSKImageList; Problems: TStrings);

implementation

type
  // A memory stream that refuses to grow past what a disk image could be,
  // whatever the archive said it was going to unpack to
  TUnpackStream = class(TMemoryStream)
  public
    function Write(const Buffer; Count: longint): longint; override;
  end;

  // TUnZipper made to unpack one entry at a time into memory, so that one it
  // cannot unpack costs only itself
  TZipReader = class(TUnZipper)
  private
    FContents: TStream;
    procedure SupplyEntryStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
    procedure KeepEntryStream(Sender: TObject; var AStream: TStream; AItem: TFullZipFileEntry);
  public
    constructor Create(const ZipFileName: string);
    destructor Destroy; override;
    procedure Open;
    function Unpack(Entry: TFullZipFileEntry): TMemoryStream;
  end;

const
  ImageExtensions: array[0..6] of string = ('.dsk', '.mgt', '.img', '.sad', '.opd',
    '.opu', '.td0');

procedure RefuseOversize(Size: int64);
begin
  if Size > MaxUnpackedSize then
    raise EStreamError.CreateFmt('Unpacks to more than %d MB, which is not a disk image.',
      [MaxUnpackedSize div (1024 * 1024)]);
end;

function TUnpackStream.Write(const Buffer; Count: longint): longint;
begin
  RefuseOversize(Position + Count);
  Result := inherited Write(Buffer, Count);
end;

function IsZipFileName(const FileName: string): boolean;
begin
  Result := SameText(ExtractFileExt(FileName), '.zip');
end;

function UnpackGzip(const FileName: string): TMemoryStream;
var
  GZStream: TGZFileStream;
  Buffer: array[0..65535] of byte;
  BytesRead: integer;
begin
  GZStream := TGZFileStream.Create(FileName, gzopenread);
  try
    Result := TUnpackStream.Create;
    try
      repeat
        BytesRead := GZStream.Read(Buffer, SizeOf(Buffer));
        if BytesRead > 0 then
          Result.WriteBuffer(Buffer, BytesRead);
      until BytesRead < SizeOf(Buffer);
      Result.Position := 0;
    except
      Result.Free;
      raise;
    end;
  finally
    GZStream.Free;
  end;
end;

// TGZFileStream only reads from a file, so a gzip found inside a zip is given one
function UnpackGzippedEntry(Packed_: TMemoryStream): TMemoryStream;
var
  TempName: string;
begin
  TempName := GetTempFileName('', 'DIM');
  try
    Packed_.SaveToFile(TempName);
    Result := UnpackGzip(TempName);
  finally
    DeleteFile(TempName);
  end;
end;

// Zip reader

constructor TZipReader.Create(const ZipFileName: string);
begin
  inherited Create;
  FileName := ZipFileName;
  OnCreateStream := SupplyEntryStream;
  OnDoneStream := KeepEntryStream;
end;

destructor TZipReader.Destroy;
begin
  CloseInput;
  inherited Destroy;
end;

procedure TZipReader.Open;
begin
  OpenInput;
  ReadZipDirectory;
end;

// Without a stream from here the unzipper writes a file, wherever the name in
// the zip says to
procedure TZipReader.SupplyEntryStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
  AStream := FContents;
end;

// And without this it frees the stream when it has finished with it
procedure TZipReader.KeepEntryStream(Sender: TObject; var AStream: TStream;
  AItem: TFullZipFileEntry);
begin
end;

function TZipReader.Unpack(Entry: TFullZipFileEntry): TMemoryStream;
var
  Size: int64;
  Checksum: longword;
begin
  // As the zip's directory gives them: unpacking overwrites both from the
  // entry's own header, which need not state either
  Size := Entry.Size;
  Checksum := Entry.CRC32;
  RefuseOversize(Size);

  Result := TUnpackStream.Create;
  try
    FContents := Result;
    try
      UnZipOneFile(Entry);
    finally
      FContents := nil;
    end;
    // A stored entry is copied without being checked, so check every one
    if (Result.Size <> Size) or
      (crc32(crc32(0, nil, 0), Result.Memory, Result.Size) <> Checksum) then
      raise EStreamError.Create('Did not unpack to what the zip says it holds.');
    Result.Position := 0;
  except
    Result.Free;
    raise;
  end;
end;

function IsDiskImageName(const Name: string): boolean;
var
  Extension, Wanted: string;
begin
  Extension := ExtractFileExt(Name);
  if SameText(Extension, '.gz') then
    Extension := ExtractFileExt(ChangeFileExt(Name, ''));
  for Wanted in ImageExtensions do
    if SameText(Extension, Wanted) then exit(True);
  Result := False;
end;

// Skips folders, and the hidden companions macOS adds beside each file
function IsDiskImageEntry(Entry: TFullZipFileEntry): boolean;
var
  Path, Name: string;
begin
  Path := StringReplace(Entry.ArchiveFileName, '\', '/', [rfReplaceAll]);
  Name := Copy(Path, LastDelimiter('/', Path) + 1, MaxInt);
  Result := not Entry.IsDirectory and (Name <> '') and (Name[1] <> '.') and
    not Path.StartsWith('__MACOSX/') and IsDiskImageName(Name);
end;

function LoadEntry(Reader: TZipReader; Entry: TFullZipFileEntry): TDSKImage;
var
  Contents, Unzipped: TMemoryStream;
  EntryName: string;
begin
  // Unpacking renames the entry from its own header
  EntryName := Entry.ArchiveFileName;
  Contents := Reader.Unpack(Entry);
  try
    if SameText(ExtractFileExt(EntryName), '.gz') then
    begin
      Unzipped := UnpackGzippedEntry(Contents);
      Contents.Free;
      Contents := Unzipped;
    end;

    Result := TDSKImage.CreateFromArchive(Contents, Reader.FileName, EntryName);
    if Result.FileFormat = diInvalid then
    begin
      Result.Free;
      raise EStreamError.Create('Not a disk image this app can read.');
    end;
  finally
    Contents.Free;
  end;
end;

procedure LoadZipImages(const FileName: string; Images: TDSKImageList; Problems: TStrings);
var
  Reader: TZipReader;
  Idx: integer;
  EntryName: string;
begin
  Reader := TZipReader.Create(FileName);
  try
    Reader.Open;
    for Idx := 0 to Reader.Entries.Count - 1 do
    begin
      if not IsDiskImageEntry(Reader.Entries[Idx]) then continue;
      EntryName := Reader.Entries[Idx].ArchiveFileName;
      try
        Images.Add(LoadEntry(Reader, Reader.Entries[Idx]));
      except
        on E: Exception do
          Problems.Add(EntryName + ': ' + E.Message);
      end;
    end;
  finally
    Reader.Free;
  end;
end;

end.
