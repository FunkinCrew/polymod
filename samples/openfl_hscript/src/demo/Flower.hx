package demo;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.utils.Assets;

@:hscript(
  {
    context: [Std, Math] // Std and Math will be included in all scripts.
  })
class Flower extends Sprite implements polymod.hscript.HScriptable
{
  public var pollen:Float = 0;
  public var maxPollen:Float = 0;

  public var cooldown:Float = 0;
  public var maxCooldown:Float = 30;

  public function new(i:Int = 1)
  {
    super();
    pollen = maxPollen = i;
    var bmp = new Bitmap(Assets.getBitmapData('img/flower${i}.png'));
    addChild(bmp);

    bmp.scaleX = 0.5;
    bmp.scaleY = 0.5;
    bmp.x -= bmp.width / 2;
    bmp.y -= bmp.height / 2;
    bmp.smoothing = true;

    onInit();
  }

  function buildPathName()
  {
    return 'test/flowers/flower$pollen';
  }

  /**
   * An example of calling a function defined within a script file.
   * The function can be stored and called multiple times.
   */
  @:hscript(
    {
      pathName: buildPathName,
      optional: false,
    })
  public function onInit()
  {
    var flowerNameFn = script_variables.get('getFlowerName');
    var flowerName = flowerNameFn();

    // The script will be loaded from the path based on the path name.
    trace('Script result: $flowerName');
  }
}
