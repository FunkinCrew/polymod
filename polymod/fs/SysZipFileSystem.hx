package polymod.fs;

#if sys
import haxe.Constraints.IMap;
import haxe.ds.StringMap;
import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.fs.ZipFileSystem.ZipFileSystemParams;
import polymod.util.Util;
import polymod.util.InsensitiveMap;
import polymod.util.zip.ZipParser;
import thx.semver.VersionRule;

using StringTools;
using polymod.util.Util;

/**
 * An implementation of an IFileSystem that can access mod files
 * from both directories AND ZIP archives in the mod root.
 *
 * Supports compressed and uncompressed ZIP files.
 * Compatible only with native targets.
 */
class SysZipFileSystem extends SysFileSystem
{
  /**
   * Specifies the name of the ZIP that contains each file.
   */
  var filesLocations:IMap<String, String>;

  /**
   * Specifies the names of available directories within the ZIP files.
   */
  var fileDirectories:Array<String>;

  /**
   * The wrappers for each ZIP file that is loaded.
   */
  var zipParsers:Map<String, ZipParser>;

  public function new(params:ZipFileSystemParams)
  {
    super(params);
    filesLocations = PolymodConfig.caseInsensitiveZipLoading ? new InsensitiveMap() : new StringMap();
    zipParsers = [];
    fileDirectories = [];

    if (params.autoScan ?? true) addAllZips();
  }

  #if (!windows)
  public override function getPathLike(path:String):Null<String>
  {
    var filePath = filesLocations.get(path);
    if (filePath != null) return path;

    var dirIdx = fileDirectories.indexOfInsens(path);
    if (dirIdx != -1) return fileDirectories[dirIdx];

    return super.getPathLike(path);
  }
  #end

  public override function onLoadMod(modId:String):Void
  {
    if (!PolymodConfig.fileLock) return;

    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null)
    {
      Polymod.debug('Could not find mod dir for ID $modId');
      return;
    }

    var zipPath:Null<String> = filesLocations.get(Util.pathJoin(modRoot, modDir));
    if (zipPath == null)
    {
      // The mod is a folder mod. Establish a file lock on the metadata file.
      super.onLoadMod(modId);
      return;
    }

    var zipParser:Null<ZipParser> = (zipPath != null) ? zipParsers.get(zipPath) : null;

    if (zipParser != null)
    {
      // The mod is a ZIP mod. Establish a file lock.
      zipParser.persistFileHandle = true;
    }
    else
    {
      Polymod.debug('Issue with zip parser?');
      return;
    }
  }

  public override function onUnloadMod(modId:String):Void
  {
    if (!PolymodConfig.fileLock) return;

    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null)
    {
      Polymod.debug('Could not find mod dir for ID $modId');
      return;
    }

    var zipPath:Null<String> = filesLocations.get(modDir);
    var zipParser:Null<ZipParser> = (zipPath != null) ? zipParsers.get(zipPath) : null;

    if (zipParser != null)
    {
      // The mod is a ZIP mod. Clear the file lock.
      zipParser.persistFileHandle = false;
    }
    else
    {
      // The mod is a folder mod. Clear a file lock on the metadata file.
      super.onUnloadMod(modId);
    }
  }

  function isModDirInZip(dirName:String):Bool
  {
    var modPath = Util.pathJoin(modRoot, dirName);
    if (!exists(modPath)) return false;

    return fileDirectories.contains(modPath);
  }

  /**
   * Retrieve file bytes by pulling them from the ZIP file.
   */
  public override function getFileBytes(path:String):Null<Bytes>
  {
    path = Util.filterASCII(path);
    if (!filesLocations.exists(path))
    {
      // Fallback to the inner SysFileSystem.
      return super.getFileBytes(path);
    }
    else
    {
      // Rather than going to the `files` map for the contents (which are empty),
      // we go directly to the zip file and extract the individual file.

      // Determine which zip the target file is in.
      var zipPath:Null<String> = filesLocations.get(path);
      var zipParser:Null<ZipParser> = zipPath != null ? zipParsers.get(zipPath) : null;

      // Check that the ZIP is valid.
      if (zipParser == null || !zipParser.isValid())
      {
        purgeZipPath(zipPath);
        return null;
      }

      var modId:String = Path.withoutExtension(Path.withoutDirectory(zipPath));

      var innerPath:String = path;
      // Remove mod root from path
      if (innerPath.startsWith(modRoot))
      {
        innerPath = innerPath.substring(modRoot.endsWith('/') ? modRoot.length : modRoot.length + 1);
      }
      // Remove mod ID from path
      if (innerPath.startsWith(modId))
      {
        innerPath = innerPath.substring(modId.length + 1);
      }

      var fileHeader = zipParser.getLocalFileHeaderOf(innerPath);
      if (fileHeader == null)
      {
        // Couldn't access file
        Polymod.debug('Could not access file $innerPath from ZIP ${zipParser.fileName}.');
        return null;
      }

      var fileBytes:Null<Bytes> = null;
      try
      {
        fileBytes = fileHeader.readData();
      }
      catch (e)
      {
        // An error occurred while reading the file from the ZIP.
        Polymod.error(MOD_ARCHIVE_READ_FAILED, 'Failed to read file bytes from archive, is it corrupt?\n$path\n${e}');
      }
      fileHeader.cleanupFileHandle();
      return fileBytes;
    }
  }

  public override function exists(path:String)
  {
    // Check ZIP files first.
    if (fileDirectories.containsInsens(path)) return true;
    if (filesLocations.exists(path)) return true;

    return super.exists(path);
  }

  public override function isDirectory(path:String)
  {
    // Check ZIP files first.
    if (fileDirectories.containsInsens(path)) return true;
    if (filesLocations.exists(path)) return false;

    return super.isDirectory(path);
  }

  public override function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    validateZipCache();

    var result:Array<ModMetadata> = super.scanMods(apiVersionRule);

    var knownDirectories:Array<String> = [for (key => value in this.modMetadataLocations) value];

    // Also add all mods in subdirectories in ZIP files.
    // This is needed because `SysFileSystem.scanMods` only finds metadata files at the root of the ZIP.
    for (modDir in fileDirectories)
    {
      // Get the directory relative to the mod root, rather than relative to the working dir.
      var baseDir:String = modDir.replace('$modRoot/', '');

      if (knownDirectories.contains(baseDir))
      {
        // We've already found mod metadata there.
        continue;
      }

      if (!exists(modDir))
      {
        // No directory there.
        continue;
      }

      var metaFile = Util.pathJoin(modDir, PolymodConfig.modMetadataFile);
      if (!exists(metaFile))
      {
        // No mod metadata there.
        continue;
      }

      var meta:ModMetadata = this.getMetadataByModDir(baseDir, PolymodErrorOrigin.SCAN);
      if (meta == null)
      {
        // Unparsable mod metadata there.
        continue;
      }

      if (!meta.isCompatible(apiVersionRule))
      {
        // Incompatible mod metadata there.
        Polymod.warning(MOD_API_VERSION_MISMATCH,
          'Mod "${baseDir}" is not compatible with API version "${apiVersionRule.toString()}", got "${meta.apiVersion.toString()}"',
          SCAN);
        continue;
      }

      // Found a new mod!
      modMetadataLocations.set(meta.id, baseDir);
      result.push(meta);
    }

    return result;
  }

  override public function scanModDirectoriesForId(modId:String, ?origin:PolymodErrorOrigin):Null<String>
  {
    // Get the directory that the mod metadata is in from cache.
    var knownDirectory:Null<String> = modMetadataLocations.get(modId);
    if (knownDirectory != null) return knownDirectory;

    // Scan ALL ZIP directories for mod metadata with the matching location.
    for (dir in fileDirectories)
    {
      var modPath = Util.pathJoin(modRoot, dir);
      if (exists(modPath))
      {
        var meta:ModMetadata = null;

        var metaFile = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);

        if (!exists(metaFile))
        {
          continue;
        }
        else
        {
          var metaText = getFileContent(metaFile);
          meta = ModMetadata.fromJsonStr(metaText, origin);
        }

        if (meta == null) continue;

        // If we found a mod metadata, cache its location for later!
        modMetadataLocations.set(meta.id, dir);

        if (meta.id != modId && dir != modId) continue;
        meta.dirName = dir;
        meta.modPath = modPath;

        var iconFile = getModIconPath(modId, origin);

        if (exists(iconFile))
        {
          var iconBytes:Null<Bytes> = getFileBytes(iconFile);

          if (iconBytes == null)
          {
            Polymod.warning(MOD_MISSING_ICON, 'Could not obtain mod icon data from file: $iconFile', origin);
          }
          else
          {
            meta.icon = iconBytes;
            meta.iconPath = iconFile;
          }
        }

        return dir;
      }
    }

    return super.scanModDirectoriesForId(modId, origin);
  }

  public override function readDirectory(path:String):Array<String>
  {
    // Remove trailing slash
    if (path.endsWith('/')) path = path.substring(0, path.length - 1);

    var result = super.readDirectory(path);
    result = (result == null) ? [] : result;

    if (fileDirectories.containsInsens(path))
    {
      final insensitive:Bool = PolymodConfig.caseInsensitiveZipLoading;
      if (insensitive) path = path.toLowerCase();

      // We check if directory ==, because
      // we don't want to read the directory recursively.
      for (file in filesLocations.keys())
      {
        if (Path.directory(insensitive ? file.toLowerCase() : file) == path)
        {
          if (!result.contains(Path.withoutDirectory(file))) result.push(Path.withoutDirectory(file));
        }
      }
      for (dir in fileDirectories)
      {
        if (Path.directory(insensitive ? dir.toLowerCase() : dir) == path)
        {
          if (!result.contains(Path.withoutDirectory(dir))) result.push(Path.withoutDirectory(dir));
        }
      }
    }

    result = result.filterUnique();

    return result;
  }

  /**
   * Scan the mod root for ZIP files and add each one to the SysZipFileSystem.
   */
  public function addAllZips():Void
  {
    Polymod.debug('Searching for archives (${PolymodConfig.archiveModExt}) in $modRoot');
    // Use SUPER because we don't want to add in files within the ZIPs.
    var modRootContents = super.readDirectory(modRoot);

    for (modRootFile in modRootContents)
    {
      var filePath = Util.pathJoin(modRoot, modRootFile);

      // Skip directories.
      if (isDirectory(filePath)) continue;

      // Only process ZIP files.
      for (archiveExt in PolymodConfig.archiveModExt)
      {
        if (StringTools.endsWith(filePath, archiveExt))
        {
          Polymod.debug('- $filePath');
          addZipFile(filePath);
        }
      }
    }

    var zipCount = [for (x in zipParsers.keys()) x].length;
    Polymod.debug('Loaded ${zipCount} archives files containing ${fileDirectories.length} directories.');
  }

  /**
   * Add a ZIP file to the PolymodFileSystem.
   *
   * @param zipPath The path to the ZIP file.
   */
  public function addZipFile(zipPath:String):Void
  {
    // Strip the path and extension to get the mod ID.
    var modId = Path.withoutExtension(Path.withoutDirectory(zipPath));

    var zipParser = new ZipParser(zipPath);

    // NOTE: If creating and freeing the file handle is too expensive,
    // you can set persistFileHandle to `true`.

    // SysZipFileSystem doesn't actually use the internal `files` map.
    // We populate it here simply so we know the files are there.
    for (fileName => fileHeader in zipParser.centralDirectoryRecords)
    {
      // File is empty. Skip.
      if (fileHeader.compressedSize == 0 || fileHeader.uncompressedSize == 0) continue;

      // File is a directory. Skip.
      if (StringTools.endsWith(fileName, '/')) continue;

      // Add to the list of files.
      // The file should appear in the mod list as though it was in a directory rather than a ZIP.
      var fullFilePath = Path.join([modRoot, modId, fileHeader.fileName]);
      filesLocations.set(fullFilePath, zipPath);

      // Generate the list of directories.
      var fileDirectory = Path.directory(fullFilePath);
      // Resolving recursively ensures parent directories are registered.
      // If the directory is already registered, its parents are already registered as well.
      while (fileDirectory != '' && !fileDirectories.contains(fileDirectory))
      {
        fileDirectories.push(fileDirectory);
        filesLocations.set(fileDirectory, zipPath);
        fileDirectory = Path.directory(fileDirectory);
      }
    }

    // Store the ZIP parser for later use.
    zipParsers.set(zipPath, zipParser);
  }

  function validateZipCache():Void
  {
    for (zipPath => zipParser in zipParsers)
    {
      // Check that the associated ZIP is still valid.
      if (zipParser == null || !zipParser.isValid())
      {
        purgeZipPath(zipPath);
      }
    }
  }

  /**
   * The provided ZIP path has been determined to be invalid.
   * Any files or directories u
   *
   * @param zipPath
   */
  function purgeZipPath(zipPath:String):Void
  {
    Polymod.debug('Purging invalid ZIP: ${zipPath}');

    zipParsers.remove(zipPath);

    for (filePath => fileZipPath in filesLocations)
    {
      if (fileZipPath == zipPath)
      {
        Polymod.debug('  - ${filePath}');
        filesLocations.remove(filePath);
        if (fileDirectories.contains(filePath)) fileDirectories.remove(filePath);
      }
    }
  }
}
#end

#if !sys
/**
 * Fallback used when the `sys` packages required by `SysZipFileSystem` are not available.
 */
class SysZipFileSystem extends polymod.fs.StubFileSystem
{
  public function new(params:ZipFileSystemParams)
  {
    super(params);
    Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED, 'This file system not supported for this platform, and is only intended for use on sys targets', INIT);
  }
}
#end
