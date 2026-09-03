package polymod.fs;

import haxe.io.Bytes;
import polymod.Polymod.ModMetadata;
import polymod.Polymod.PolymodErrorOrigin;
import thx.semver.VersionRule;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.fs.PolymodFileSystem.PolymodFileSystemParams;
#if lime
import lime.app.Future;
#end

/**
 * This stub file system returns false for all requests.
 * This is the fallback used when the desired file system can't be accessed.
 *
 * Your program won't crash, but mods WILL NOT LOAD if this is used.
 */
@SuppressWarnings('checkstyle:FieldDocComment')
class StubFileSystem implements IFileSystem
{
  public final modRoot:String = '';
  public function new(params:PolymodFileSystemParams) {}

  public inline function exists(path:String):Bool
  {
    return false;
  }

  public inline function existsByModId(path:String, modId:String):Bool
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

  public inline function getFileBytes(path:String):Null<Bytes>
  {
    return null;
  }

  public inline function getFileBytesByModId(path:String, modId:String):Null<haxe.io.Bytes>
  {
    return null;
  }

  #if lime
  public inline function loadFileBytes(path:String):Future<haxe.io.Bytes>
  {
    return cast Future.withError('Cannot load file bytes from stub file system');
  }

  /**
   * Load the byte data for a file from a specific mod, asynchronously.
   *
   * @param path The path to retrieve byte data from, relative to the asset root.
   * @param modId A specific mod ID to retrieve an asset from.
   * @return A future which returns the file bytes.
   */
  public inline function loadFileBytesByModId(path:String, modId:String):Future<haxe.io.Bytes>
  {
    return cast Future.withError('Cannot load file bytes from stub file system');
  }
  #end

  public function onLoadMod(id:String):Void {}

  public function onUnloadMod(id:String):Void {}

  public inline function readDirectoryRecursive(path:String):Array<String>
  {
    return [];
  }

  public function readModDirectory(modDir:String, recursive:Bool = true):Array<String>
  {
    return [];
  }

  public inline function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    return [];
  }

  public inline function scanModDirectoriesForId(modId:String, ?origin:PolymodErrorOrigin):Null<String>
  {
    return null;
  }

  public inline function getMetadataByModDir(dir:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }

  public inline function getMetadataByModId(modId:String, ?origin:PolymodErrorOrigin):Null<ModMetadata>
  {
    return null;
  }
}
