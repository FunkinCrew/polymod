package demo;

import openfl.display.Sprite;
import lime.math.Vector2;

class Mover extends Sprite
{
  public var move:Vector2;
  public var speed:Float = 1;

  public function new()
  {
    super();
    move = new Vector2();
  }
}
