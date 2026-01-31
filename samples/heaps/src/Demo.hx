import hxd.Res;
import h2d.Object;
import h2d.Tile;
import h2d.Bitmap;
import h2d.Text;
import h2d.Text.Align;
import h2d.Scene;

class Demo extends Object
{
  private var widgets:Array<ModWidget> = [];
  private var callback:Array<String>->Void;
  private var sprites:Array<Object> = [];
  private var texts:Array<Text> = [];

  public function new(scene:Scene, callback:Array<String>->Void)
  {
    super(scene);
    this.callback = callback;

    makeButtons();
    drawImages();
    drawText();
  }

  public function destroy()
  {
    remove();
    removeChildren();
    sprites = null;
    texts = null;
    callback = null;
  }

  public function refresh()
  {
    for (spr in sprites)
    {
      spr.removeChildren();
      spr.remove();
    }
    for (txt in texts)
    {
      txt.removeChildren();
      txt.remove();
    }
    drawImages();
    drawText();
  }

  private function makeButtons()
  {
    var modDir:String = 'mods';
    var mods = sys.FileSystem.readDirectory(modDir);
    var xx = 10;
    var yy = 200;
    for (mod in mods)
    {
      var w = new ModWidget(this, xx, yy, mod, onWidgetMove);
      widgets.push(w);
      xx += (72 + 10);
    }
    updateWidgets();
  }

  private function updateWidgets()
  {
    if (widgets == null) return;
    for (i in 0...widgets.length)
    {
      var showLeft = i != 0;
      var showRight = i != widgets.length - 1;
      widgets[i].showButtons(showLeft, showRight);
    }
  }

  private function onWidgetMove(w:ModWidget, i:Int)
  {
    if (i != 0)
    {
      var temp = widgets.indexOf(w);
      var newI = temp + i;
      if (newI < 0 || newI >= widgets.length)
      {
        return;
      }
      var other = widgets[newI];
      other.swap(w);
    }

    if (callback != null)
    {
      var theMods = [];
      for (w in widgets)
      {
        if (w.active)
        {
          theMods.push(w.mod);
        }
      }
      callback(theMods);
    }

    updateWidgets();
  }

  private function list(str:String):Array<String>
  {
    var loader = Res.loader;
    var root = loader.fs.getRoot();
    var path = root.get(str);
    var files = [];
    for (asset in path)
    {
      files.push(asset.path);
    };
    return files;
  }

  private function drawImages()
  {
    var xx = 10;
    var yy = 10;

    var images = list('img');
    images.sort(function(a:String, b:String):Int {
      if (a < b) return -1;
      if (a > b) return 1;
      return 0;
    });
    for (image in images)
    {
      var spr = getSprite();
      var tile = Res.loader.load(image).toTile();
      var bmp = new Bitmap(tile, spr);
      bmp.x = 0;
      bmp.y = 0;
      spr.x = xx;
      spr.y = yy;

      var text = getText(Center);

      text.maxWidth = tile.width;
      text.text = image;
      text.x = xx;
      text.y = spr.y + tile.height;

      xx += Std.int(tile.width + 10);
    }
  }

  private function drawText()
  {
    var xx = 500;
    var yy = 10;

    var texts = list('data');
    texts.sort(function(a:String, b:String):Int {
      if (a < b) return -1;
      if (a > b) return 1;
      return 0;
    });
    for (t in texts)
    {
      var isXML:Bool = false;
      var align:Align = Center;
      var theWidth = 150;
      if (t.indexOf('xml') != -1 || t.indexOf('json') != -1)
      {
        isXML = true;
        align = Left;
        theWidth = 350;
      }

      var textBox = getBox(theWidth, 152, 1);
      textBox.x = xx - 1;
      textBox.y = yy - 1;

      var text = getText(align);
      text.x = xx;
      text.y = yy;
      text.maxWidth = theWidth;

      var str = Res.loader.load(t).toText();

      text.text = (str != null ? str : 'null');

      var caption = getText(Center);
      caption.x = xx;
      caption.y = yy + 152 + caption.textHeight;
      caption.text = t;
      caption.maxWidth = text.maxWidth;

      yy += Std.int(152 + caption.textHeight + 35);
    }
  }

  private function getBox(width:Int, height:Int, border:Int, color1:Int = 0x000000, color2:Int = 0xFFFFFF):Object
  {
    var spr = getSprite();
    spr.x = 0;
    spr.y = 0;
    var col1 = Tile.fromColor(color1, width, height);
    var bmp = new Bitmap(col1, spr);
    bmp.x = 0;
    bmp.y = 0;
    var col2 = Tile.fromColor(color2, width - 2, height - 2);
    var bmp2 = new Bitmap(col2, spr);
    bmp2.x = border;
    bmp2.y = border;
    return spr;
  }

  private function getText(align:Align):Text
  {
    var font = hxd.res.DefaultFont.get();
    var text = new Text(font, this);
    text.textColor = 0x000000;
    text.scale(1);
    text.textAlign = align;
    texts.push(text);
    return text;
  }

  private function getSprite():Object
  {
    var sprite = new Object(this);
    sprites.push(sprite);
    return sprite;
  }
}
