import openfl.display.Sprite;
import openfl.Lib;
import thx.semver.Version;
import thx.semver.VersionRule;
import polymod.Polymod;
import polymod.util.VersionUtil;
import polymod.Polymod.Framework;
import haxe.io.Path;

class Main extends Sprite
{
  private var demo:Demo = null;

  public static final API_VERSION:Version = "1.1.1";
  public static final API_VERSION_RULE:VersionRule = VersionUtil.anyPatch(API_VERSION);

  public function new()
  {
    super();
    loadDemo();
  }

  private function loadDemo()
  {
    loadMods([]);
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
    trace('Loading mods: ' + dirs);
    var framework = Demo.usingOpenFL ? Framework.OPENFL : Framework.LIME;
    var skipDepErrs = Demo.skipDependencyErrors;
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
        skipDependencyErrors: skipDepErrs,
        apiVersionRule: API_VERSION_RULE, // Accept 1.1.0+ but not 0.x or 1.0.x
        assetPrefix: '',
      });
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
