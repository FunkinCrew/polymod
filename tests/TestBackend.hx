package tests;

import haxe.io.Bytes;
import polymod.Polymod.FrameworkParams;
import polymod.PolymodAssets.PolymodAssetType;
import polymod.backends.StubBackend;

class TestBackend extends StubBackend
{
  override public function init(?params:FrameworkParams):Bool
  {
    return true;
  }

  override public function exists(id:String):Bool
  {
    return getBytes(id) != null;
  }

  override public function getBytes(id:String):Null<Bytes>
  {
    for (modId in polymodLibrary.modIds)
    {
      var bytes = polymodLibrary.getBytesDirectly(id, modId);
      if (bytes != null) return bytes;
    }
    return null;
  }

  override public function getText(id:String):Null<String>
  {
    for (modId in polymodLibrary.modIds)
    {
      var text = polymodLibrary.getTextDirectly(id, modId);
      if (text != null) return text;
    }
    return null;
  }

  override public function list(?type:PolymodAssetType):Array<String>
  {
    var result:Array<String> = [];
    for (modId in polymodLibrary.modIds)
    {
      result = result.concat(polymodLibrary.listDirectly(modId, type));
    }
    return result;
  }
}
