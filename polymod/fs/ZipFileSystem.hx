package polymod.fs;

/**
 * Same as PolymodFileSystemParams but with additional parameters specific to the ZipFileSystem.
 */
typedef ZipFileSystemParams =
{
  // Import properties from PolymodFileSystemParams.
  > polymod.fs.PolymodFileSystem.PolymodFileSystemParams,

  /**
   * If `true`, the mods folder will be scanned for zip files and they will be added to the zip file system automatically.
   * If `false`, call `fileSystem.addZipFile` or `fileSystem.addAllZips` manually.
   * @default `true`
   */
  ?autoScan:Bool,
};

// Automatically chooses between MemoryZipFileSystem and SysZipFileSystem
#if sys
typedef ZipFileSystem = SysZipFileSystem;
#else
typedef ZipFileSystem = MemoryZipFileSystem;
#end
