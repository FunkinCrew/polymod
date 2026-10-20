package tests;

<<<<<<< Updated upstream
import haxe.io.Bytes;
import polymod.Polymod.FrameworkParams;
import polymod.PolymodAssets.PolymodAssetType;
import polymod.backends.StubBackend;

class TestBackend extends StubBackend
{
  override public function init(?params:FrameworkParams):Bool
=======
import haxe.io.Path;
import polymod.PolymodAssets.PolymodAssetType;

class TestBackend extends polymod.backends.StubBackend
{
  override public function init(?params:polymod.Polymod.FrameworkParams):Bool
>>>>>>> Stashed changes
  {
    return true;
  }

  override public function exists(id:String):Bool
  {
<<<<<<< Updated upstream
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
=======
    for (modDir in polymodLibrary.modDirs)
    {
      if (polymodLibrary.fileSystem.exists(Path.join([modDir, id]))) return true;
    }
    return false;
>>>>>>> Stashed changes
  }

  override public function getText(id:String):Null<String>
  {
<<<<<<< Updated upstream
    for (modId in polymodLibrary.modIds)
    {
      var text = polymodLibrary.getTextDirectly(id, modId);
      if (text != null) return text;
=======
    for (modDir in polymodLibrary.modDirs)
    {
      var path = Path.join([modDir, id]);
      var content = polymodLibrary.fileSystem.getFileContent(path);
      if (content != null) return content;
>>>>>>> Stashed changes
    }
    return null;
  }

<<<<<<< Updated upstream
  override public function list(?type:PolymodAssetType):Array<String>
  {
    var result:Array<String> = [];
    for (modId in polymodLibrary.modIds)
    {
      result = result.concat(polymodLibrary.listDirectly(modId, type));
    }
    return result;
=======
  override public function list(type:PolymodAssetType = null):Array<String>
  {
    return polymodLibrary.listModFiles(type);
>>>>>>> Stashed changes
  }
}
