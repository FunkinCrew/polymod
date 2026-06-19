package polymod.fs;

import polymod.Polymod;
import polymod.fs.PolymodFileSystem;
import thx.semver.VersionRule;

/**
 * This stub file system returns false for all requests.
 * This is the fallback used when the desired file system can't be accessed.
 *
 * Your program won't crash, but mods WILL NOT LOAD if this is used.
 */
class StubFileSystem implements IFileSystem
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

  public inline function getMetadataByDir(dir:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
    return null;

  public inline function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
    return null;
}
