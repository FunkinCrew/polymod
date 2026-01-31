import openfl.display.Sprite;
import openfl.Lib;
import polymod.Polymod;
import polymod.Polymod.Framework;

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
    #if nodefs
    var framework = Demo.usingOpenFL ? Framework.OPENFL_WITH_NODE : Framework.LIME;
    #else
    var framework = Demo.usingOpenFL ? Framework.OPENFL : Framework.LIME;
    #end
    var modRoot = '../../../mods/';
    #if mac
    // account for <APPLICATION>.app/Contents/Resources
    var modRoot = '../../../../../../mods';
    #end
    var results = Polymod.init(
      {
        modRoot: modRoot,
        dirs: dirs,
        errorCallback: onError,
        ignoredFiles: Polymod.getDefaultIgnoreList(),
        framework: framework,
        assetPrefix: '',
      });
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
