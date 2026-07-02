package polymod.fs;

import polymod.Polymod;
import thx.semver.VersionRule;
import haxe.io.Bytes;

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
      Polymod.error(FILESYSTEM_INIT_FAILED, 'Passed an unknown type for a custom filesystem. Reverting to default...', INIT);
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
   *
   * @param path The path to check.
   * @return Whether there is a file or directory there.
   */
  public function exists(path:String):Bool;

  /**
   * Return whether the file or directory exists in a specific mod.
   *
   * @param path The path to check.
   * @param modId A specific mod ID to check within.
   * @return Whether the file or directory exists in that mod.
   */
  public function existsByModId(path:String, modId:String):Bool;

  /**
   * Returns whether the provided path is a directory.
   *
   * @param path The path to check.
   * @return Whether the path is a directory.
   */
  public function isDirectory(path:String):Bool;

  /**
   * Returns a list of files and folders contained within the provided directory path.
   * Does not return files in subfolders, use readDirectoryRecursive for that.
   *
   * @param path The path to check.
   * @return An array of file paths and folder paths.
   */
  public function readDirectory(path:String):Array<String>;

  /**
   * Returns a list of files contained within the provided directory path.
   * Checks all subfolders recursively. Returns only files.
   *
   * @param path The path to check.
   * @return An array of file paths.
   */
  public function readDirectoryRecursive(path:String):Array<String>;

  public function readModDirectory(modDir:String, recursive:Bool = true):Array<String>;

  /**
   * Returns the content of a given file as a string.
   *
   * @param path The file to read.
   * @return The text content of the file, or `null` if the file can't be found.
   */
  public function getFileContent(path:String):Null<String>;

  /**
   * Returns the content of a given file as Bytes.
   *
   * @param path The file to read.
   * @return The byte content of the file, or `null` if the file can't be found.
   */
  public function getFileBytes(path:String):Null<Bytes>;

  /**
   * Get the byte data for a file from a specific mod.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return The file bytes, or `null` if it couldn't be fetched.
   */
  public function getFileBytesByModId(path:String, modId:String):Null<haxe.io.Bytes>;

  /**
   * Provide a list of valid mods for this file system to load.
   *
   * @param apiVersionRule (optional) A version query to match against the mod's API version.
   * @return An array of matching mods.
   */
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>;

  /**
   * Determines the mod directory associated with a given mod ID.
   *
   * @param modId The ID of the mod to look for.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The directory path where the mod was found, or `null` if not found.
   */
  public function scanModDirectoriesForId(modId:String, ?origin:PolymodErrorOrigin):Null<String>;

  /**
   * Provides the metadata for a given mod by its directory.
   *
   * @param dir The directory of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModDir(dir:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>;

  /**
   * Provides the metadata for a given mod by its ID.
   *
   * @param modId The ID of the mod.
   * @param origin The context the error occurred in (while scanning for mods, while initializing mods, etc.).
   *   Used for error reporting.
   * @return The mod metadata, or `null` if the mod does not exist.
   */
  public function getMetadataByModId(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>;
}
