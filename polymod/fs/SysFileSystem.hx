package polymod.fs;

#if sys
import polymod.Polymod;
import polymod.util.Util;
import sys.io.FileInput;

#if (!windows)
using StringTools;
#end

/**
 * An implementation of IFileSystem which accesses files from folders in the local directory.
 * This is currently the default file system for native/Desktop platforms.
 */
class SysFileSystem extends BaseFileSystem
{
  /**
   * By establishing and maintaining a file handle to the mod metadata,
   * we can stop other applications from trying to delete mods that are in use!
   *
   * Disable this with `PolymodConfig.fileLock = false;`.
   */
  var fileHandles:Map<String, FileInput> = [];

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
   * Check if the specified path is a directory.
   *
   * @param path The path to check.
   * @return True if the path is a directory, false otherwise.
   */
  public function isDirectory(path:String)
  {
    #if (!windows)
    path = getPathLike(path) ?? return false;
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
      path = getPathLike(path) ?? throw 'Invalid directory "$path".';
      #end
      return sys.FileSystem.readDirectory(path);
    }
    catch (e)
    {
      Polymod.warning(ASSET_MISSING_DIRECTORY, 'Could not find directory "${path}"');
      return [];
    }
  }

  /**
   * Get the byte data for a file.
   *
   * @param path The path to retrieve byte data from.
   * @return The file contents, or `null` if it couldn't be fetched.
   */
  public override function getFileContent(path:String):Null<String>
  {
    #if (!windows)
    path = getPathLike(path) ?? return null;
    #end

    return super.getFileContent(path);
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
    path = getPathLike(path) ?? return null;
    #else
    if (!exists(path)) return null;
    #end

    var fileHandle:Null<FileInput> = fileHandles.get(path);
    if (fileHandle != null)
    {
      fileHandle.seek(0, SeekBegin);
      return fileHandle.readAll();
    }

    return sys.io.File.getBytes(path);
  }

  public override function onLoadMod(modId:String):Void
  {
    if (!PolymodConfig.fileLock) return;

    var modDir:Null<String> = scanModDirectoriesForId(modId);
    var modPath:Null<String> = Util.pathJoin(modRoot, modDir);
    var metaFile:Null<String> = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);

    if (metaFile == null || !exists(metaFile))
    {
      Polymod.debug('Could not find mod metadata file for $modId');
      return;
    }

    fileHandles.set(metaFile, sys.io.File.read(metaFile));
  }

  public override function onUnloadMod(modId:String):Void
  {
    if (!PolymodConfig.fileLock) return;

    var modDir:Null<String> = scanModDirectoriesForId(modId);
    var modPath:Null<String> = Util.pathJoin(modRoot, modDir);
    var metaFile:Null<String> = Util.pathJoin(modPath, PolymodConfig.modMetadataFile);

    if (metaFile == null)
    {
      Polymod.debug('Could not find mod metadata file for $modId');
      return;
    }

    fileHandles.remove(metaFile);
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

    return (baseParts.length == 0 || keyParts.length == 0) ? null : findFile(baseParts.join('/'), keyParts);
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
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;

/**
 * Fallback used when the `sys` packages required by `SysFileSystem` are not available.
 */
class SysFileSystem extends polymod.fs.StubFileSystem
{
  public function new(params:PolymodFileSystemParams)
  {
    super(params);
    Polymod.error(POLYMOD_FUNCTIONALITY_NOT_IMPLEMENTED, 'This file system not supported for this platform, and is only intended for use on sys targets', INIT);
  }
}
#end
