import nme.display.Sprite;
import nme.Lib;
import polymod.Polymod;

class Main extends Sprite
{
  private var demo:Demo = null;

  public function new()
  {
    super();
    loadDemo();
  }

  private function loadDemo()
  {
    demo = new Demo(onModChange);
    addChild(demo);
  }

  private function onModChange(arr:Array<String>)
  {
    loadMods(arr);
    demo.refresh();
  }

  private function loadMods(dirs:Array<String>)
  {
    var modRoot = "../../../mods/";
    var results = Polymod.init(
      {
        modRoot: modRoot,
        dirs: dirs,
        errorCallback: onError,
        ignoredFiles: Polymod.getDefaultIgnoreList()
      });
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
