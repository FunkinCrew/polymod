import flash.text.TextField;
import openfl.display.DisplayObjectContainer;
import openfl.events.MouseEvent;
import openfl.text.TextFormatAlign;

class ModWidget extends DisplayObjectContainer
{
  public var active(default, null):Bool;
  public var mod(default, null):String;

  public var status:TextField;

  private var callback:ModWidget->Int->Void;

  public var button:CheapButton;
  public var moveLeft:CheapButton;
  public var moveRight:CheapButton;

  public function new(str:String, callback:ModWidget->Int->Void = null)
  {
    super();

    mod = str;

    this.callback = callback;

    status = text();
    status.text = 'inactive';

    button = new CheapButton(str, onClick);
    var left = '←';
    var right = '→';
    #if mac
    left = "<--";
    right = "-->";
    #end
    #if linux
    left = "<--";
    right = "-->";
    #end
    moveLeft = new CheapButton(left, onMove.bind(-1));
    moveRight = new CheapButton(right, onMove.bind(1));

    addChild(status);
    addChild(button);
    addChild(moveLeft);
    addChild(moveRight);
  }

  public function fixButtons()
  {
    button.x = x;
    button.y = y;

    status.x = x;
    status.y = button.y + button.height + 10;

    moveLeft.x = x;
    moveRight.x = x;
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
