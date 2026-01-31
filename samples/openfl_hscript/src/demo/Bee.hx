package demo;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.utils.Assets;

class Bee extends Mover
{
  public var flower:Flower;
  public var pollen:Float;
  public var maxPollen:Float;
  public var turnsSearching:Int = 0;

  public function new()
  {
    super();

    speed = 100;

    var bmp = new Bitmap(Assets.getBitmapData('img/bee.png'));
    addChild(bmp);

    bmp.scaleX = 0.5;
    bmp.scaleY = 0.5;
    bmp.x -= bmp.width / 2;
    bmp.y -= bmp.height / 2;
    bmp.smoothing = true;
  }
}
