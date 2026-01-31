import openfl.text.TextField;
import openfl.display.Sprite;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.DisplayObject;
import openfl.display.DisplayObjectContainer;
import openfl.events.MouseEvent;
import openfl.text.TextFormatAlign;

class CheapButton extends Sprite
{
  private var upT:TextField;
  private var overT:TextField;
  private var downT:TextField;

  public function new(str:String, callback:Void->Void = null, ?width = 72)
  {
    super();

    this.callback = callback;

    var img = new BitmapData(width, 32, false, 0xC0C0C0);
    var img2 = new BitmapData(width, 32, false, 0xD0D0F0);
    var img3 = new BitmapData(width, 32, false, 0x000000);

    up = new Sprite();
    over = new Sprite();
    down = new Sprite();

    var upB = new Bitmap(img);
    var overB = new Bitmap(img2);
    var downB = new Bitmap(img3);

    up.addChild(upB);
    over.addChild(overB);
    down.addChild(downB);

    upT = text(width);
    overT = text(width);
    downT = text(width);

    upT.text = str;
    overT.text = str;
    downT.text = str;

    overT.textColor = 0xFFFFFF;
    downT.textColor = 0xFFFFFF;

    up.addChild(upT);
    over.addChild(overT);
    down.addChild(downT);

    addChild(up);
    addChild(down);
    addChild(over);

    mouseEnabled = true;
    buttonMode = true;

    if (this.down == null)
    {
      this.down = this.up;
    }

    addEventListener(MouseEvent.MOUSE_OVER, onOver, false, 0, true);
    addEventListener(MouseEvent.MOUSE_OUT, onUp, false, 0, true);
    addEventListener(MouseEvent.MOUSE_DOWN, onDown, false, 0, true);
    addEventListener(MouseEvent.MOUSE_UP, onClick, false, 0, true);

    onUp(null);
  }

  public function setText(str:String)
  {
    upT.text = str;
    overT.text = str;
    downT.text = str;
  }

  public function destroy()
  {
    removeEventListener(MouseEvent.MOUSE_OVER, onOver, false);
    removeEventListener(MouseEvent.MOUSE_OUT, onUp, false);
    removeEventListener(MouseEvent.MOUSE_DOWN, onDown, false);
    removeEventListener(MouseEvent.MOUSE_UP, onClick, false);
    removeChildren();
    callback = null;
  }

  private function onUp(m:MouseEvent)
  {
    down.visible = over.visible = false;
    up.visible = true;
  }

  private function onClick(m:MouseEvent)
  {
    onOver(m);
    if (callback != null) callback();
  }

  private function onOver(m:MouseEvent)
  {
    down.visible = up.visible = false;
    over.visible = true;
  }

  private function onDown(m:MouseEvent)
  {
    over.visible = up.visible = false;
    down.visible = true;
  }

  private function text(?width = 72):TextField
  {
    var t:TextField = new TextField();
    t.width = width;
    t.height = 32;
    var dtf = t.defaultTextFormat;
    dtf.size = 18;
    dtf.align = TextFormatAlign.CENTER;
    t.setTextFormat(dtf);
    t.selectable = false;
    return t;
  }

  private var callback:Void->Void = null;
  private var up:DisplayObjectContainer;
  private var down:DisplayObjectContainer;
  private var over:DisplayObjectContainer;
}
