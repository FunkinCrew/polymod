import hxd.App;
import polymod.Polymod;
import polymod.Polymod.PolymodError;

class Main extends hxd.App
{
  static function main()
  {
    hxd.Res.initLocal();
    new Main();
  }

  function bkg()
  {
    var spr = new h2d.Object(s2d);
    spr.x = 0;
    spr.y = 0;
    var tile = h2d.Tile.fromColor(0xFFFFFF, 1, 1);
    tile.scaleToSize(s2d.width, s2d.height);
    var bmp = new h2d.Bitmap(tile, spr);
    bmp.x = 0;
    bmp.y = 0;
  }

  private var demo:Demo = null;

  override function init()
  {
    bkg();
    loadDemo();
  }

  private function loadDemo()
  {
    demo = new Demo(s2d, onModChange);
  }

  private function onModChange(arr:Array<String>)
  {
    loadMods(arr);
    demo.refresh();
  }

  private function loadMods(dirs:Array<String>)
  {
    var modRoot = 'mods';
    Polymod.init(
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
