package polymod.fs;

import polymod.fs.PolymodFileSystem;
import thx.semver.VersionRule;
import polymod.Polymod.ModMetadata;

/**
 * This stub file system returns false for all requests.
 * This is the fallback used when the desired file system can't be accessed.
 *
 * Your program won't crash, but mods WILL NOT LOAD if this is used.
 */
class StubFileSystem implements PolymodFileSystem.IFileSystem
{
  public function new(params:PolymodFileSystem.PolymodFileSystemParams) {}

  public inline function exists(path:String)
    return false;

  public inline function isDirectory(path:String)
    return false;

  public inline function readDirectory(path:String):Array<String>
    return [];

  public inline function getFileContent(path:String)
    return null;

  public inline function getFileBytes(path:String)
    return null;

  public inline function readDirectoryRecursive(path:String)
    return [];

  public inline function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
    return [];

  public inline function getMetadata(modId:String)
    return null;
}
