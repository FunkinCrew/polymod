package polymod.fs;

#if sys
import polymod.Polymod;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
import polymod.util.Util;
import polymod.util.VersionUtil;
import thx.semver.VersionRule;

#if (!windows)
using StringTools;
#end

/**
 * An implementation of IFileSystem which accesses files from folders in the local directory.
 * This is currently the default file system for native/Desktop platforms.
 */
class SysFileSystem implements IFileSystem
{
  /**
   * The directory relative to the application path where mods are located.
   */
  public final modRoot:String;

  /**
   * A cache of the directories containing mod metadata, indexed by mod ID.
   */
  var modMetadataLocations:Map<String, String> = [];

  public function new(params:PolymodFileSystemParams)
  {
    this.modRoot = params.modRoot;
  }

  /**
   * Check if a file or directory exists.
   *
   * @param path The path to check.
   * @return `true` if the file or directory exists, false otherwise.
   */
  public function exists(path:String):Bool
  {
    #if (!windows)
    return getPathLike(path) != null;
    #else
    return sys.FileSystem.exists(path);
    #end
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
   * Check if the specified path is a directory.
   *
   * @param path The path to check.
   * @return True if the path is a directory, false otherwise.
   */
  public function isDirectory(path:String)
  {
    #if (!windows)
    path = getPathLike(path);
    #end
    return sys.FileSystem.isDirectory(path);
  }

  /**
   * Get a list of files and directories in the specified path.
   * Use `readDirectoryRecursive` for recursive listing.
   *
   * @param path The path to read.
   * @return Array<String> The list of files and directories.
   */
  public function readDirectory(path:String):Array<String>
  {
    try
    {
      #if (!windows)
      path = getPathLike(path);
      #end
      return sys.FileSystem.readDirectory(path);
    }
    catch (e)
    {
      Polymod.warning(ASSET_MISSING_DIRECTORY, 'Could not find directory "${path}"');
      return [];
    }
  }

  public function readModDirectory(modDir:String, recursive:Bool = true):Array<String>
  {
    return recursive
      ? readDirectoryRecursive(Util.pathJoin(modRoot, modDir))
      : readDirectory(Util.pathJoin(modRoot, modDir));
  }

  /**
   * Get the byte data for a file.
   *
   * @param path The path to retrieve byte data from.
   * @return The file contents, or `null` if it couldn't be fetched.
   */
  public function getFileContent(path:String):Null<String>
  {
    #if (!windows)
    path = getPathLike(path);
    #end
    return getFileBytes(path)?.toString();
  }

  /**
   * Get the byte data for a file.
   *
   * @param path The path to retrieve byte data from.
   * @return The file bytes, or `null` if it couldn't be fetched.
   */
  public function getFileBytes(path:String):Null<haxe.io.Bytes>
  {
    #if (!windows)
    path = getPathLike(path);
    if (path == null) return null;
    #else
    if (!exists(path)) return null;
    #end
    return sys.io.File.getBytes(path);
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
   * Retrieve a list of ModMetadata for each installed mod.
   *
   * @param apiVersionRule (optional) Specify a version rule that scanned mods must conform to.
   * @return The list of ModMetadata for found mods.
   */
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    if (apiVersionRule == null) apiVersionRule = VersionUtil.DEFAULT_VERSION_RULE;

    var result:Array<ModMetadata> = [];

    for (modId => modDir in modMetadataLocations)
    {
      if (!hasMetadataFile(modDir))
      {
        // Remove locations that no longer have metadata.
        modMetadataLocations.remove(modId);
        continue;
      }

      var meta:ModMetadata = this.getMetadataByModDir(modDir, PolymodErrorOrigin.SCAN);
      if (meta == null)
      {
        // Remove locations whose metadata can no longer be parsed.
        modMetadataLocations.remove(modId);
        continue;
      }

      if (!VersionUtil.match(meta.apiVersion, apiVersionRule))
      {
        // Remove locations whose metadata is no longer compatible with the current API version.
        Polymod.warning(MOD_API_VERSION_MISMATCH,
          'Mod "${modDir}" is not compatible with API version "${apiVersionRule.toString()}", got "${meta.apiVersion.toString()}"',
          SCAN);
        modMetadataLocations.remove(modId);
        continue;
      }

      // Leave the known metadata in place.
      result.push(meta);
    }

    // Now check EVERY directory.
    var knownDirectories:Array<String> = [for (key => value in modMetadataLocations) value];
    var dirsInModRoot:Array<String> = readDirectory(modRoot);
    for (modDir in dirsInModRoot)
    {
      if (knownDirectories.contains(modDir))
      {
        // We've already found mod metadata there.
        continue;
      }

      if (!hasMetadataFile(modDir))
      {
        // No mod metadata there.
        continue;
      }

      var meta:ModMetadata = this.getMetadataByModDir(modDir, PolymodErrorOrigin.SCAN);
      if (meta == null)
      {
        // Unparsable mod metadata there.
        continue;
      }

      if (!VersionUtil.match(meta.apiVersion, apiVersionRule))
      {
        // Incompatible mod metadata there.
        Polymod.warning(MOD_API_VERSION_MISMATCH,
          'Mod "${modDir}" is not compatible with API version "${apiVersionRule.toString()}", got "${meta.apiVersion.toString()}"',
          SCAN);
        continue;
      }

      // Found a new mod!
      modMetadataLocations.set(meta.id, modDir);
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

  function hasMetadataFile(dirName:String):Bool
  {
    var modPath = Util.pathJoin(modRoot, dirName);
    if (!isDirectory(modPath)) return false;
    var metaFile = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);
    return exists(metaFile);
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
    var modPath = Util.pathJoin(modRoot, dirName);
    if (exists(modPath))
    {
      var meta:ModMetadata = null;

      var metaFile = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);
      var iconFile = Util.pathJoin(modPath, PolymodConfig.modIconFile);

      if (!exists(metaFile))
      {
        Polymod.warning(MOD_MISSING_METADATA, 'Could not find mod metadata file: $metaFile', origin);
        return null;
      }
      else
      {
        var metaText = getFileContent(metaFile);
        meta = ModMetadata.fromJsonStr(metaText, origin);
      }

      if (meta == null)
      {
        return null;
      }

      meta.id = meta.id == '' ? dirName : meta.id;
      meta.dirName = dirName;
      meta.modPath = modPath;

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
      Polymod.error(MOD_MISSING_DIRECTORY, 'Could not find mod directory: $modPath', origin);
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
    var knownDirectory:Null<String> = scanModDirectoriesForId(modId, origin);
    if (knownDirectory != null)
    {
      var result = getMetadataByModDir(knownDirectory, origin);
      if (result != null)
      {
        return result;
      }
      else
      {
        trace('LOST metadata for mod $modId');
        modMetadataLocations.remove(modId);
      }
    }

    // We don't know where the mod is located.
    return null;
  }

  /**
   * Determines the mod directory associated with a given mod ID.
   *
   * @param modId The ID of the mod to look for.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The directory path where the mod was found, or `null` if not found.
   */
  public function scanModDirectoriesForId(modId:String, ?origin:PolymodErrorOrigin):Null<String>
  {
    // Get the directory that the mod metadata is in from cache.
    var knownDirectory:Null<String> = modMetadataLocations.get(modId);
    if (knownDirectory != null) return knownDirectory;

    // Otherwise, scan all the directories in the mod root.
    for (dir in readDirectory(modRoot))
    {
      var modPath = Util.pathJoin(modRoot, dir);
      if (exists(modPath))
      {
        var meta:ModMetadata = null;

        var metaFile = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);
        var iconFile = Util.pathJoin(modPath, PolymodConfig.modIconFile);

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

        modMetadataLocations.set(meta.id, dir);

        if (meta.id != modId && dir != modId) continue;
        meta.dirName = dir;
        meta.modPath = modPath;

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

        return dir;
      }
    }
    Polymod.error(MOD_MISSING_ID, 'Could not find mod with ID: $modId', origin);
    return null;
  }

  /**
   * Retrieve a list of files and directories in the given path, recursively.
   *
   * @param path The path to fetch the list of files/directories from.
   * @return The list of files/directories.
   */
  public function readDirectoryRecursive(path:String):Array<String>
  {
    var all = _readDirectoryRecursive(path);
    for (i in 0...all.length)
    {
      var f = all[i];
      var prefix = Util.withTrailingSlash(path);
      var stri = Util.uIndexOf(f, prefix);
      if (stri == 0)
      {
        f = Util.uSubstr(f, Util.uLength(prefix), Util.uLength(f));
        all[i] = f;
      }
    }
    return all;
  }

  #if (!windows)
  /**
   * Returns a path to the existing file similar to the given one.
   * (For instance "mod/firelight" and  "Mod/FireLight" are *similar* paths)
   * @param path The path to find
   * @return Null<String> Found path or null if such doesn't exist
   */
  private function getPathLike(path:String):Null<String>
  {
    if (sys.FileSystem.exists(path)) return path;

    var baseParts:Array<String> = path.replace('\\', '/').split('/');
    var keyParts = [];
    if (baseParts.length == 0) return null;

    while (!sys.FileSystem.exists(baseParts.join('/')) && baseParts.length != 0)
    {
      keyParts.insert(0, baseParts.pop());
    }

    return findFile(baseParts.join('/'), keyParts);
  }

  private function findFile(base_path:String, keys:Array<String>):Null<String>
  {
    var nextDir:String = base_path;
    for (part in keys)
    {
      if (part == '') continue;

      var foundNode = findNode(nextDir, part);

      if (foundNode == null)
      {
        return null;
      }
      nextDir = '$nextDir/$foundNode';
    }

    return nextDir;
  }

  /**
   * Searches a given directory and returns a name of the existing file/directory
   * *similar* to the **key**
   * @param dir Base directory to search
   * @param key The file/directory you want to find
   * @return Either a file name, or null if the one doesn't exist
   */
  private function findNode(dir:String, key:String):Null<String>
  {
    try
    {
      var allFiles:Array<String> = sys.FileSystem.readDirectory(dir);
      var fileMap:Map<String, String> = new Map();

      for (file in allFiles)
      {
        fileMap.set(file.toLowerCase(), file);
      }

      return fileMap.get(key.toLowerCase());
    }
    catch (e:Dynamic)
    {
      return null;
    }
  }
  #end

  private function _readDirectoryRecursive(str:String):Array<String>
  {
    if (exists(str) && isDirectory(str))
    {
      var all = readDirectory(str);
      if (all == null) return [];
      var results = [];
      for (thing in all)
      {
        if (thing == null) continue;
        var pathToThing = Util.pathJoin(str, thing);
        if (isDirectory(pathToThing))
        {
          var subs = _readDirectoryRecursive(pathToThing);
          if (subs != null)
          {
            results = results.concat(subs);
          }
        }
        else
        {
          results.push(pathToThing);
        }
      }
      return results;
    }
    return [];
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
