import h2d.Object;
import h2d.Text;
import h2d.Scene;

class ModWidget extends Object
{
  public var active(default, null):Bool;
  public var mod(default, null):String;

  public var status:Text;
  public var callback:ModWidget->Int->Void;

  public var button:CheapButton;

  private var moveLeft:CheapButton;
  private var moveRight:CheapButton;

  public var locX:Int;
  public var locY:Int;

  public function new(spr:Object, x:Int, y:Int, str:String, callback:ModWidget->Int->Void = null)
  {
    super(spr);

    mod = str;

    this.callback = callback;

    status = text(this);
    status.text = 'inactive';

    button = new CheapButton(this, str, onClick);
    moveLeft = new CheapButton(this, "<-", onMove.bind(-1));
    moveRight = new CheapButton(this, "->", onMove.bind(1));

    setLoc(x, y);
  }

  public function setLoc(x:Int, y:Int)
  {
    locX = x;
    locY = y;

    button.x = moveLeft.x = moveRight.x = x;
    button.y = moveLeft.y = moveRight.y = y;

    status.x = x;
    status.maxWidth = 72;
    status.y = button.y + 32 + 10;

    moveLeft.y = status.y + 32 + 10;
    moveRight.y = moveLeft.y + 32 + 4;
  }

  public function swap(other:ModWidget)
  {
    var otherMod = other.mod;
    var otherCallback = other.callback;
    var otherActive = other.active;

    other.mod = mod;
    other.active = active;
    other.button.setText(other.mod);
    other.status.text = other.active ? 'active' : 'inactive';

    mod = otherMod;
    active = otherActive;
    button.setText(mod);
    status.text = active ? 'active' : 'inactive';
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
    remove();
    removeChildren();
    button.destroy();
    moveLeft.destroy();
    moveRight.destroy();
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

  private function text(spr:Object):Text
  {
    var font = hxd.res.DefaultFont.get();
    var text = new h2d.Text(font, spr);
    text.textColor = 0x000000;
    text.scale(1);
    text.textAlign = Center;
    return text;
  }
}
