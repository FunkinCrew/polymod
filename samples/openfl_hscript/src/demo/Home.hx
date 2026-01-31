package demo;

import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.utils.Assets;

class Home extends Sprite
{
  public var honey:Float = 0;

  public function new()
  {
    super();
    var bmp = new Bitmap(Assets.getBitmapData('img/honey.png'));
    addChild(bmp);

    bmp.scaleX = 0.5;
    bmp.scaleY = 0.5;
    bmp.x -= bmp.width / 2;
    bmp.y -= bmp.height / 2;
    bmp.smoothing = true;
  }
}
