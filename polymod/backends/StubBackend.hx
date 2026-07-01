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

  #if openfl
  public function getBitmapData(id:String):Null<openfl.display.BitmapData>
  {
    return null;
  }

  public function getSound(id:String):Null<openfl.media.Sound>
  {
    return null;
  }

  public function loadBitmapData(id:String):lime.app.Future<openfl.display.BitmapData>
  {
    return null;
  }

  public function loadSound(id:String):lime.app.Future<openfl.media.Sound>
  {
    return null;
  }
  #end
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
