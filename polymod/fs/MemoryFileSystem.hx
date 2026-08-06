package polymod.fs;

import haxe.io.Bytes;
import haxe.io.Path;
import polymod.util.Util;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;

#if lime
import lime.app.Future;
#end

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
class MemoryFileSystem extends BaseFileSystem
{
  var files:Map<String, Bytes> = [];
  var directories:Array<String> = [];

  /**
   * Receive parameters to instantiate the MemoryFileSystem.
   */
  public function new(params:PolymodFileSystemParams)
  {
    // No-op constructor.
    params.modRoot ??= '';
    super(params);
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
    files.clear();
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
   * Returns the content of a given file as Bytes.
   *
   * @param path The file to read.
   * @return The byte content of the file, or `null` if the file can't be found.
   */
  public function getFileBytes(path:String):Null<Bytes>
  {
    return files.get(path);
  }

  #if lime
  /**
   * Load the byte data for a file asynchronously.
   *
   * @param path The path to retrieve byte data from.
   * @return A future which returns the file bytes.
   */
  override public function loadFileBytes(path:String):Future<Bytes>
  {
    var performWork:Void->Bytes = () -> {
      var result = getFileBytes(path);
      if (result == null)
      {
        throw 'Could not load file bytes $path';
      }
      return result;
    };

    return new Future(performWork, true);
  }
  #end

  /**
   * Get the byte data for a file from a specific mod.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return The file bytes, or `null` if it couldn't be fetched.
   */
  override public function getFileBytesByModId(path:String, modId:String):Null<Bytes>
  {
    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null) return null;
    var relativeDir = Util.pathJoin(modRoot, modDir);

    return getFileBytes(Util.pathJoin(relativeDir, path));
  }

  #if lime
  /**
   * Load the byte data for a file from a specific mod, asynchronously.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return A future which returns the file bytes.
   */
  override public function loadFileBytesByModId(path:String, modId:String):Future<Bytes>
  {
    var modDir:Null<String> = scanModDirectoriesForId(modId);
    if (modDir == null) return null;
    var relativeDir = Util.pathJoin(modRoot, modDir);

    return loadFileBytes(Util.pathJoin(relativeDir, path));
  }
  #end

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
}
