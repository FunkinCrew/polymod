package tests;

import haxe.io.Path;
import polymod.PolymodAssets.PolymodAssetType;

class TestBackend extends polymod.backends.StubBackend
{
  override public function init(?params:polymod.Polymod.FrameworkParams):Bool
  {
    return true;
  }

  override public function exists(id:String):Bool
  {
    for (modDir in polymodLibrary.modDirs)
    {
      if (polymodLibrary.fileSystem.exists(Path.join([modDir, id]))) return true;
    }
    return false;
  }

  override public function getText(id:String):Null<String>
  {
    for (modDir in polymodLibrary.modDirs)
    {
      var path = Path.join([modDir, id]);
      var content = polymodLibrary.fileSystem.getFileContent(path);
      if (content != null) return content;
    }
    return null;
  }

  override public function list(type:PolymodAssetType = null):Array<String>
  {
    return polymodLibrary.listModFiles(type);
  }
}
