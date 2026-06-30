package polymod.fs;

import thx.semver.VersionRule;

/**
 * This stub file system returns false for all requests.
 * This is the fallback used when the desired file system can't be accessed.
 *
 * Your program won't crash, but mods WILL NOT LOAD if this is used.
 */
@SuppressWarnings('checkstyle:FieldDocComment')
class StubFileSystem implements IFileSystem
{
  public function new(params:PolymodFileSystem.PolymodFileSystemParams) {}

  public inline function exists(path:String):Bool
  {
    return false;
  }

  public inline function isDirectory(path:String):Bool
  {
    return false;
  }

  public inline function readDirectory(path:String):Array<String>
  {
    return [];
  }

  public inline function getFileContent(path:String):Null<String>
  {
    return null;
  }

  public inline function getFileBytes(path:String):Null<haxe.io.Bytes>
  {
    return null;
  }

  public inline function readDirectoryRecursive(path:String):Array<String>
  {
    return [];
  }

  public inline function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    return [];
  }

  public inline function getMetadataByDir(dir:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }

  public inline function getMetadataById(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }
}
