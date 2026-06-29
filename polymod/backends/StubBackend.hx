package polymod.backends;

import haxe.io.Bytes;
import polymod.Polymod.FrameworkParams;
import polymod.PolymodAssets.PolymodAssetType;
import polymod.backends.PolymodAssetLibrary;

class StubBackend implements IBackend
{
  public var polymodLibrary:PolymodAssetLibrary;

  public function new() {}

  public function init(?params:FrameworkParams):Bool
  {
    return false;
  }

  public function destroy():Void {}

  public function clearCache():Void {}

  public function exists(id:String):Bool
  {
    return false;
  }

  public function getBytes(id:String):Null<Bytes>
  {
    return null;
  }

  public function getText(id:String):Null<String>
  {
    return null;
  }

  #if lime
  public function loadBytes(id:String):lime.app.Future<Bytes>
  {
    return null;
  }

  public function loadText(id:String):lime.app.Future<String>
  {
    return null;
  }
  #end

  public function getPath(id:String):Null<String>
  {
    return null;
  }

  public function list(type:PolymodAssetType = null):Array<String>
  {
    return [];
  }

  public function listLibraries():Array<String>
  {
    return [];
  }

  public function stripAssetsPrefix(id:String):String
  {
    return id;
  }
}
