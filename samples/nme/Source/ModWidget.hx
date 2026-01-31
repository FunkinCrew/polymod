import nme.display.Sprite;
import nme.text.TextField;
import nme.display.DisplayObjectContainer;
import nme.events.MouseEvent;
import nme.text.TextFormatAlign;

class ModWidget extends Sprite
{
  public var active(default, null):Bool;
  public var mod(default, null):String;

  private var status:TextField;
  private var callback:ModWidget->Int->Void;

  private var button:CheapButton;
  private var moveLeft:CheapButton;
  private var moveRight:CheapButton;

  public function new(str:String, callback:ModWidget->Int->Void = null)
  {
    super();

    mod = str;

    this.callback = callback;

    status = text();
    status.text = 'inactive';

    var button = new CheapButton(str, onClick);
    moveLeft = new CheapButton('←', onMove.bind(-1));
    moveRight = new CheapButton('→', onMove.bind(1));

    addChild(status);
    addChild(button);
    addChild(moveLeft);
    addChild(moveRight);

    status.y = button.y + button.height + 10;

    moveLeft.y = status.y + status.height + 10;
    moveRight.y = moveLeft.y + moveLeft.height + 4;
  }

  public function showButtons(left:Bool, right:Bool)
  {
    if (moveLeft == null) return;
    moveLeft.visible = left;
    moveRight.visible = right;
  }

  public function destroy()
  {
    callback = null;

    button.destroy();
    moveLeft.destroy();
    moveRight.destroy();

    removeChildren();
  }

  private function onClick()
  {
    active = !active;
    status.text = active ? 'active' : 'inactive';
    if (callback != null)
    {
      callback(this, 0);
    }
  }

  private function onMove(i:Int)
  {
    if (callback != null)
    {
      callback(this, i);
    }
  }

  private function text():TextField
  {
    var t:TextField = new TextField();
    t.width = 72;
    t.height = 32;
    var dtf = t.defaultTextFormat;
    dtf.size = 18;
    dtf.align = TextFormatAlign.CENTER;
    t.setTextFormat(dtf);
    t.selectable = false;
    return t;
  }
}
