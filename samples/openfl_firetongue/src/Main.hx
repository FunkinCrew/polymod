import firetongue.FireTongue;
import openfl.display.Sprite;
import openfl.Lib;
import polymod.Polymod;
import polymod.Polymod.Framework;

class Main extends Sprite
{
  private var demo:Demo = null;

  public static var tongue:FireTongue;

  public function new()
  {
    super();
    loadDemo();
  }

  private function loadDemo()
  {
    loadLocale('en-US');
    loadMods([]);

    demo = new Demo(onModChange, onLocaleChange);
    addChild(demo);
  }

  private function onModChange(arr:Array<String>)
  {
    loadMods(arr);
    Polymod.clearCache();
    if (demo != null) demo.refresh();
  }

  private function onLocaleChange(newLocale:String)
  {
    loadLocale(newLocale);
    Polymod.clearCache();
    if (demo != null) demo.refresh();
  }

  private function loadLocale(locale:String)
  {
    if (tongue == null) tongue = new FireTongue();
    tongue.initialize(
      {
        locale: locale,
        directory: 'locales/',
      });
  }

  private function loadMods(dirs:Array<String>)
  {
    var framework = Demo.usingOpenFL ? Framework.OPENFL : Framework.LIME;
    var modRoot = '../../../mods/';
    #if mac
    // account for <APPLICATION>.app/Contents/Resources
    var modRoot = '../../../../../../mods';
    #end

    trace('Initializing Polymod...');
    // Note: If you are using Polymod with FireTongue, you should call Polymod.init(),
    // regardless if you are loading any mods or not, in order to utilize the localized asset handler.
    var results = Polymod.init(
      {
        modRoot: modRoot,
        dirs: dirs,
        errorCallback: onError,
        ignoredFiles: Polymod.getDefaultIgnoreList(),
        framework: framework,
        assetPrefix: '',
        firetongue: tongue,
      });
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
