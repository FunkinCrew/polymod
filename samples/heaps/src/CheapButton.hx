import hxd.Res;
import h2d.Object;
import h2d.Text;
import h2d.Scene;
import h2d.Bitmap;
import h2d.Tile;
import h2d.Interactive;

class CheapButton extends Object
{
  private var callback:Void->Void = null;
  private var up:Object;
  private var down:Object;
  private var over:Object;
  private var upT:Text;
  private var overT:Text;
  private var downT:Text;

  private var isOver:Bool = false;
  private var isDown:Bool = false;

  public function new(spr:Object, str:String, callback:Void->Void = null)
  {
    super(spr);

    this.callback = callback;

    var img = Tile.fromColor(0xC0C0C0, 72, 32);
    var img2 = Tile.fromColor(0xD0D0D0, 72, 32);
    var img3 = Tile.fromColor(0x000000, 72, 32);

    up = new Object(this);
    over = new Object(this);
    down = new Object(this);

    var upB = new Bitmap(img, up);
    var overB = new Bitmap(img2, over);
    var downB = new Bitmap(img3, down);

    upT = getText(Center);
    overT = getText(Center);
    downT = getText(Center);

    upT.text = str;
    overT.text = str;
    downT.text = str;

    overT.textColor = 0xFFFFFF;
    downT.textColor = 0xFFFFFF;

    var interaction = new Interactive(72, 32, this);
    interaction.onOver = onOver;
    interaction.onClick = onClick;
    interaction.onPush = onDown;
    interaction.onRelease = onUp;
    interaction.onOut = onOut;

    onUp(null);
  }

  public function setText(str:String)
  {
    upT.text = overT.text = downT.text = str;
  }

  public function destroy()
  {
    removeChildren();
    callback = null;
  }

  private function onUp(event:hxd.Event)
  {
    isDown = false;
    updateButton();
  }

  private function onClick(event:hxd.Event)
  {
    if (callback != null) callback();
    updateButton();
  }

  private function onOver(event:hxd.Event)
  {
    isOver = true;
    updateButton();
  }

  private function onDown(event:hxd.Event)
  {
    isDown = true;
    updateButton();
  }

  private function onOut(event:hxd.Event)
  {
    isOver = false;
    updateButton();
  }

  private function updateButton()
  {
    if (isOver)
    {
      down.visible = up.visible = false;
      over.visible = true;
      if (isDown)
      {
        over.visible = false;
        down.visible = true;
      }
    }
    else
    {
      down.visible = over.visible = false;
      up.visible = true;
    }
  }

  private function getText(align:h2d.Text.Align):h2d.Text
  {
    var font = hxd.res.DefaultFont.get();
    var text = new Text(font, this);
    text.textColor = 0x000000;
    text.scale(1);
    text.textAlign = align;
    text.maxWidth = 72;
    text.y = 12;
    return text;
  }
}
