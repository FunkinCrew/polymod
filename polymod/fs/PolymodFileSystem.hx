package polymod.fs;

import polymod.Polymod.PolymodErrorOrigin;
import thx.semver.VersionRule;
import haxe.io.Bytes;
import polymod.Polymod.ModMetadata;

/**
 * Provides factory and utility functions for instantiating an IFileSystem.
 */
class PolymodFileSystem
{
  /**
   * Constructs a new PolymodFileSystem.
   * @param cls An input file system. Might be an IFileSystem or a Class<IFileSystem>.
   * @param params A set of parameters for initializing the file system.
   * @return The constructed file system.
   */
  public static function makeFileSystem(?cls:Dynamic, params:PolymodFileSystemParams):IFileSystem
  {
    if (cls == null)
    {
      // No IFileSystem provided, choose one to use as default.
      return detectFileSystem(params);
    }
    else if (Std.isOfType(cls, IFileSystem))
    {
      // This is an IFileSystem object, no need to instantiate.
      return cls;
    }
    else if (Std.isOfType(cls, Class))
    {
      // This is an IFileSystem class, instantiate it with the parameters.
      return cast Type.createInstance(cls, [params]);
    }
    else
    {
      Polymod.error(FILESYSTEM_INIT_FAILED, "Passed an unknown type for a custom filesystem. Reverting to default...", INIT);
      return makeFileSystem(null, params);
    }
  }

  /**
   * Automatically determine the file system to use, based on the current platform, and instantiate it.
   */
  static function detectFileSystem(params:PolymodFileSystemParams):IFileSystem
  {
    #if sys
    // Sys/native file system.
    return new polymod.fs.SysFileSystem(params);
    #elseif nodefs
    // Node file system.
    return new polymod.fs.NodeFileSystem(params);
    #else
    // No compatible file system.
    // If you're on HTML5, you should use MemoryFileSystem or ZipFileSystem.
    return new polymod.fs.StubFileSystem(params);
    #end
  }
}

/**
 * A set of parameters used to initialize the Polymod file system.
 */
typedef PolymodFileSystemParams =
{
  /**
   * The root directory which Polymod should read mods from.
   * May not be applicable for file systems which dictate the directory, or use no directory.
   */
  ?modRoot:String,
};

/**
 * A standard interface for the various file systems that Polymod supports.
 */
interface IFileSystem
{
  /**
   * Returns whether the file or directory at the given path exists.
   * @param path The path to check.
   * @return Whether there is a file or directory there.
   */
  public function exists(path:String):Bool;

  /**
   * Returns whether the provided path is a directory.
   * @param path The path to check.
   * @return Whether the path is a directory.
   */
  public function isDirectory(path:String):Bool;

  /**
   * Returns a list of files and folders contained within the provided directory path.
   * Does not return files in subfolders, use readDirectoryRecursive for that.
   * @param path The path to check.
   * @return An array of file paths and folder paths.
   */
  public function readDirectory(path:String):Array<String>;

  /**
   * Returns a list of files contained within the provided directory path.
   * Checks all subfolders recursively. Returns only files.
   * @param path The path to check.
   * @return An array of file paths.
   */
  public function readDirectoryRecursive(path:String):Array<String>;

  /**
   * Returns the content of a given file as a string.
   * Returns null if the file can't be found.
   * @param path The file to read.
   * @return The text content of the file.
   */
  public function getFileContent(path:String):Null<String>;

  /**
   * Returns the content of a given file as Bytes.
   * Returns null if the file can't be found.
   * @param path The file to read.
   * @return The byte content of the file.
   */
  public function getFileBytes(path:String):Null<Bytes>;

  /**
   * Provide a list of valid mods for this file system to load.
   *
   * @param apiVersionRule (optional) A version query to match against the mod's API version.
   * @return An array of matching mods.
   */
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>;

  /**
   * Provides the metadata for a given mod. Returns null if the mod does not exist.
   * @param modId The directory of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata.
   */
  public function getMetadataByDir(dir:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>;

  /**
   * Provides the metadata for a given mod. Returns null if the mod does not exist.
   * @param modId The ID of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata.
   */
  public function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>;
}
