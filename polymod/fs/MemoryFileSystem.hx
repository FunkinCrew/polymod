package polymod.fs;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.Polymod;
import polymod.fs.PolymodFileSystem;
import polymod.util.Util;
import polymod.util.VersionUtil;
import thx.semver.VersionRule;

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
  var files = new Map<String, Bytes>();
  var directories:Array<String> = [];
  var modRoot:String = "";

  /**
   * Receive parameters to instantiate the MemoryFileSystem.
   */
  public function new(params:PolymodFileSystemParams)
  {
    // No-op constructor.
    modRoot = (params.modRoot == null) ? "" : params.modRoot;
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

  public function exists(path:String)
  {
    path = Path.removeTrailingSlashes(path);
    return files.exists(path) || directories.contains(path); // checks both files and folders
  }

  public function isDirectory(path:String)
  {
    path = Path.removeTrailingSlashes(path);
    return directories.indexOf(path) != -1;
  }

  /**
   * List all files AND directories at the given path.
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
   * Directly retrieve the text contents of a file.
   *
   * @param path The path name of the file to read.
   * @return The text contents of the file.
   */
  public function getFileContent(path:String):String
  {
    var fileBytes = getFileBytes(path);
    if (fileBytes == null) return null;
    return fileBytes.toString();
  }

  /**
   * Directly retrieve the binary contents of a file.
   *
   * @param path The path name of the file to read.
   * @return The contents of the file as Bytes.
   */
  public function getFileBytes(path:String):Bytes
  {
    return files.get(path);
  }

  /**
   * List all files at or below the given path.
       *
       * @param path The path name of the directory to read.
   */
  public function readDirectoryRecursive(path:String)
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

      var meta:ModMetadata = getMetadataByDir(dir, PolymodErrorOrigin.SCAN);

      if (meta == null) continue;

      if (!VersionUtil.match(meta.apiVersion, apiVersionRule)) continue;

      result.push(meta);
    }

    return result;
  }

  @:deprecated("getMetadata is deprecated, use getMetadataByDir")
  public function getMetadata(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return getMetadataByDir(dirName, origin);
  }

  public function getMetadataByDir(dirName:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
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

  public function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }
}
