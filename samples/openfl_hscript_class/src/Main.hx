import stage.ScriptedStage;
import openfl.display.Sprite;
import openfl.Lib;
import polymod.Polymod;
import polymod.Polymod.Framework;
import haxe.io.Path;

class Main extends Sprite
{
  private var demo:Demo = null;

  public function new()
  {
    super();
    // Initialize Polymod but load no mods
    loadMods([]);
    loadDemo();
    // test();
  }

  function test()
  {
    var defaultStageId:String = 'STAGE_${Std.random(256)}';
    var stage:ScriptedStage = ScriptedStage.scriptInit('BasicStage', defaultStageId);
    stage.create();
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
    var framework = Demo.usingOpenFL ? Framework.OPENFL : Framework.LIME;
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
        useScriptedClasses: true,
      });
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
