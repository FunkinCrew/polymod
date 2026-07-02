package polymod.fs;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.util.Util;
import polymod.util.VersionUtil;
import thx.semver.VersionRule;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;

/**
 * This simple virtual file system demonstrates that anything can be used
 * as the backend filesystem for Polymod, as long as you can fulfill the
 * IFileSystem interface.
 *
 * Instantiate the MemoryFileSystem, call `addFileBytes` to add mod files to it,
 * then pass it to Polymod. Any mod files you add will be available to Polymod
 * as though they were accessed from the file system.
 *
 * Using this file system directly is not recommended, as it is not optimized for native platforms.
 * If you can use a native file system, use `SysFileSystem` or `ZipFileSystem` instead.
 */
class MemoryFileSystem implements IFileSystem
{
  var files:Map<String, Bytes> = new Map<String, Bytes>();
  var directories:Array<String> = [];
  var modRoot:String = '';

  /**
   * Receive parameters to instantiate the MemoryFileSystem.
   */
  public function new(params:PolymodFileSystemParams)
  {
    // No-op constructor.
    modRoot = (params.modRoot == null) ? '' : params.modRoot;
  }

  /**
   * Call this function to add a text document to the virtual file system.
   *
   * Example: `addFileBytes("mod1/_polymod_meta.json", "...")`
   *
   * @param path The path name of the file to add.
   * @param data The text of the document.
   */
  public function addFileBytes(path:String, data:Bytes):Void
  {
    path = Path.removeTrailingSlashes(path);
    files.set(path, data);
    var parentDirs = Util.listAllParentDirs(Path.directory(path));
    // remove the actual path to the file from the directories array
    parentDirs.remove(path);
    directories = directories.concat(parentDirs);
    directories = Util.filterUnique(directories);
  }

  /**
   * Call this function to remove a given file from the virtual file system.
   *
   * @param path The path name of the file to remove.
   */
  public function removeFile(path:String):Void
  {
    files.remove(path);
  }

  /**
   * Call this function to clear all files from the virtual file system.
   */
  public function clear():Void
  {
    files = new Map<String, Bytes>();
    directories = [];
  }

  /**
   * Returns whether the file or directory at the given path exists.
   *
   * @param path The path to check.
   * @return Whether there is a file or directory there.
   */
  public function exists(path:String):Bool
  {
    path = Path.removeTrailingSlashes(path);
    return files.exists(path) || directories.contains(path); // checks both files and folders
  }

  /**
   * Return whether the file or directory exists in a specific mod.
   *
   * @param path The path to check.
   * @param modId A specific mod ID to check within.
   * @return Whether the file or directory exists in that mod.
   */
  public function existsByModId(path:String, modId:String):Bool
  {
    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null) return false;
    var relativeDir = Util.pathJoin(modRoot, modDir);

    return exists(Util.pathJoin(relativeDir, path));
  }

  /**
   * Returns whether the provided path is a directory.
   *
   * @param path The path to check.
   * @return Whether the path is a directory.
   */
  public function isDirectory(path:String):Bool
  {
    path = Path.removeTrailingSlashes(path);
    return directories.indexOf(path) != -1;
  }

  /**
   * Returns a list of files and folders contained within the provided directory path.
   * Does not return files in subfolders, use readDirectoryRecursive for that.
   *
   * @param path The path to check.
   * @return An array of file paths and folder paths.
   */
  public function readDirectory(path:String):Array<String>
  {
    path = Path.removeTrailingSlashes(path);
    var result = [];
    for (key => _v in files)
    {
      // Directory must exactly match.
      if (Path.directory(key) == path)
      {
        var parts = key.split('/');
        result.push(parts[parts.length - 1]);
      }
    }
    for (dir in directories)
    {
      // avoiding pushing duplicates
      if (Path.directory(dir) == path && !result.contains(dir))
      {
        var d = Path.directory(dir);
        var actualdir = dir.substring(d.length);
        if (actualdir.charAt(0) == '/') actualdir = actualdir.substring(1);
        result.push(actualdir);
      }
    }
    return result;
  }

  /**
   * Returns the content of a given file as a string.
   *
   * @param path The file to read.
   * @return The text content of the file, or `null` if the file can't be found.
   */
  public function getFileContent(path:String):Null<String>
  {
    var fileBytes = getFileBytes(path);
    if (fileBytes == null) return null;
    return fileBytes.toString();
  }

  /**
   * Returns the content of a given file as Bytes.
   *
   * @param path The file to read.
   * @return The byte content of the file, or `null` if the file can't be found.
   */
  public function getFileBytes(path:String):Null<Bytes>
  {
    return files.get(path);
  }

  /**
   * Get the byte data for a file from a specific mod.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return The file bytes, or `null` if it couldn't be fetched.
   */
  public function getFileBytesByModId(path:String, modId:String):Null<haxe.io.Bytes>
  {
    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null) return null;
    var relativeDir = Util.pathJoin(modRoot, modDir);

    return getFileBytes(Util.pathJoin(relativeDir, path));
  }

  /**
   * Returns a list of files contained within the provided directory path.
   * Checks all subfolders recursively. Returns only files.
   *
   * @param path The path to check.
   * @return An array of file paths.
   */
  public function readDirectoryRecursive(path:String):Array<String>
  {
    path = Path.removeTrailingSlashes(path);
    var result = [];
    for (key => _v in files)
    {
      // Directory OR PARENT must exactly match.
      if (key.indexOf(path) == 0)
      {
        result.push(key.substring(path.length + 1));
      }
    }
    // Nooo, only files needed
    // result.concat(directories.filter(function(dir)
    // {
    // 	return dir.indexOf(path) == 0;
    // }));
    return result;
  }

  /**
   * Provide a list of valid mods for this file system to load.
   *
   * @param apiVersionRule (optional) A version query to match against the mod's API version.
   * @return An array of matching mods.
   */
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    if (apiVersionRule == null) apiVersionRule = VersionUtil.DEFAULT_VERSION_RULE;

    var dirs = readDirectory(modRoot);
    var result:Array<ModMetadata> = [];
    for (dir in dirs)
    {
      var testDir = Util.pathJoin(modRoot, dir);

      if (!exists(testDir)) continue;

      if (!isDirectory(testDir)) continue;

      var meta:ModMetadata = getMetadataByModDir(dir, PolymodErrorOrigin.SCAN);

      if (meta == null) continue;

      if (!VersionUtil.match(meta.apiVersion, apiVersionRule)) continue;

      result.push(meta);
    }

    return result;
  }

  /**
   * Get the metadata for a given mod.
   * This function is DEPRECATED, use `getMetadataByModDir` for the same result.
   *
   * @param dirName The directory name of the mod.
   * @param origin The error reporting origin.
   * @return The mod metadata, or `null` if not found.
   */
  @:deprecated('getMetadata is deprecated, use getMetadataByModDir')
  public function getMetadata(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return getMetadataByModDir(dirName, origin);
  }

  /**
   * Provides the metadata for a given mod by its directory.
   *
   * @param dirName The directory of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModDir(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    var modpath = Util.pathJoin(modRoot, dirName);
    if (exists(modpath))
    {
      var meta:ModMetadata = null;

      var metaFile = Util.pathJoin(modpath, PolymodConfig.modMetadataFile);
      var iconFile = Util.pathJoin(modpath, PolymodConfig.modIconFile);

      if (!exists(metaFile))
      {
        Polymod.warning(MOD_MISSING_METADATA, 'Could not find mod metadata file: $metaFile', origin);
        return null;
      }
      else
      {
        var metaText = getFileContent(metaFile);
        meta = ModMetadata.fromJsonStr(metaText, origin);
        if (meta == null) return null;

        meta.id = meta.id == '' ? dirName : meta.id;
        meta.dirName = dirName;
        meta.modPath = modpath;
      }

      if (!exists(iconFile))
      {
        Polymod.warning(MOD_MISSING_ICON, 'Could not find mod icon file: $iconFile', origin);
      }
      else
      {
        var iconBytes = getFileBytes(iconFile);
        meta.icon = iconBytes;
        meta.iconPath = iconFile;
      }
      return meta;
    }
    else
    {
      Polymod.error(MOD_MISSING_DIRECTORY, 'Could not find mod directory: $dirName', origin);
    }
    return null;
  }

  /**
   * Provides the metadata for a given mod by its ID.
   *
   * @param modId The ID of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModId(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }
}
