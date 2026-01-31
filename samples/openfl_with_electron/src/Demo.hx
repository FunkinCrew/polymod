import lime.utils.Assets;
import openfl.Assets;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import openfl.utils.AssetType;
import polymod.fs.NodeFileSystem;
#if cpp
import sys.FileSystem;
#end

class Demo extends Sprite
{
  private var widgets:Array<ModWidget> = [];
  private var callback:Array<String>->Void;
  private var stuff:Array<Dynamic> = [];
  private var limeToggle:CheapButton;

  public static var usingOpenFL(default, null):Bool = true;

  public function new(callback:Array<String>->Void)
  {
    super();

    this.callback = callback;

    makeButtons();
    drawImages();
    drawText();
  }

  public function destroy()
  {
    for (w in widgets)
    {
      w.destroy();
    }
    callback = null;
    removeChildren();
  }

  public function refresh()
  {
    for (thing in stuff)
    {
      removeChild(cast thing);
    }
    stuff.splice(0, stuff.length);
    drawImages();
    drawText();
  }

  private function makeButtons()
  {
    var modDir:String = '../../../mods';
    #if mac
    // account for <APPLICATION>.app/Contents/Resources
    modDir = '../../../../../../mods';
    #end

    #if nodefs
    var mods = new NodeFileSystem({modRoot: modDir}).readDirectory(modDir);
    #else
    var mods = FileSystem.readDirectory(modDir);
    #end
    var xx = 10;
    var yy = 200;
    for (mod in mods)
    {
      var w = new ModWidget(mod, onWidgetMove);
      w.x = xx;
      w.y = yy;

      widgets.push(w);

      xx += Std.int(w.width) + 10;
      addChild(w);
    }

    updateWidgets();
    addToggle();
  }

  private function addToggle()
  {
    var limeLabel = getText(LEFT);
    limeLabel.x = 10;
    limeLabel.y = 400;
    limeLabel.text = 'Asset System:';

    limeToggle = new CheapButton(usingOpenFL ? 'openfl' : 'lime', onToggleOpenFL);
    limeToggle.x = 10;
    limeToggle.y = 420;

    addChild(limeLabel);
    addChild(limeToggle);
  }

  private function onToggleOpenFL()
  {
    usingOpenFL = !usingOpenFL;

    if (usingOpenFL)
    {
      limeToggle.setText('openfl');
    }
    else
    {
      limeToggle.setText('lime');
    }

    reloadMods();
    visible = false;
    haxe.Timer.delay(function() {
      visible = true;
    }, 10);
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

      var oldX = w.x;
      var oldY = w.y;

      widgets[newI] = w;
      widgets[temp] = other;

      w.x = other.x;
      w.y = other.y;

      other.x = oldX;
      other.y = oldY;
    }

    reloadMods();
    updateWidgets();
  }

  private function reloadMods()
  {
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
  }

  private function AssetsList(type:Dynamic)
  {
    if (usingOpenFL) return openfl.utils.Assets.list(cast type);
    else
      return lime.utils.Assets.list(cast type);
  }

  private function AssetsGetBitmapData(str:String, callback:BitmapData->Void)
  {
    if (usingOpenFL) openfl.utils.Assets.loadBitmapData(str).onComplete(callback);
    else
    {
      var img = lime.utils.Assets.getImage(str);
      callback(BitmapData.fromImage(img));
    }
  }

  private function AssetsGetText(str:String)
  {
    if (usingOpenFL) return openfl.utils.Assets.getText(str);
    else
      return lime.utils.Assets.getText(str);
  }

  private function drawImages()
  {
    var images = AssetsList(AssetType.IMAGE);
    images.sort(function(a:String, b:String):Int {
      if (a < b) return -1;
      if (a > b) return 1;
      return 0;
    });

    var loadedBData:Array<Bitmap> = [];

    function onBitmapDataLoaded()
    {
      var allBitmapsLoaded:Bool = true;
      allBitmapsLoaded = allBitmapsLoaded && loadedBData.length == images.length;

      for (i in 0...loadedBData.length)
      {
        allBitmapsLoaded = allBitmapsLoaded && loadedBData[i] != null;
      }

      if (!allBitmapsLoaded)
      {
        return;
      }

      var xx = 10;
      var yy = 10;
      var bmp:Bitmap;

      for (i in 0...loadedBData.length)
      {
        bmp = loadedBData[i];
        bmp.x = xx;
        bmp.y = yy;

        var text = getText();

        text.width = bmp.width;
        text.text = images[i];
        text.x = xx;
        text.y = bmp.y + bmp.height;

        addChild(bmp);
        addChild(text);
        stuff.push(bmp);
        stuff.push(text);

        xx += Std.int(bmp.width + 10);
      }
    }

    for (i in 0...images.length)
    {
      loadedBData.push(null);
      AssetsGetBitmapData(images[i], function(bData:BitmapData):Void {
        loadedBData[i] = new Bitmap(bData);
        onBitmapDataLoaded();
      });
    }
  }

  private function drawText()
  {
    var xx = 500;
    var yy = 10;

    var texts = AssetsList(AssetType.TEXT);

    texts.sort(function(a:String, b:String) {
      if (a < b) return -1;
      if (a > b) return 1;
      return 0;
    });

    for (t in texts)
    {
      var isXML:Bool = false;
      var align = TextFormatAlign.CENTER;
      if (t.indexOf('xml') != -1 || t.indexOf('json') != -1)
      {
        isXML = true;
        align = TextFormatAlign.LEFT;
      }

      var text = getText(align);
      text.x = xx;
      text.y = yy;
      text.height = 150;
      text.border = true;
      text.width = 250;
      text.wordWrap = true;
      text.multiline = true;

      var str = AssetsGetText(t);
      text.text = (str != null ? str : 'null');

      var caption = getText();
      caption.x = xx;
      caption.y = text.y + text.height;
      caption.text = t;
      caption.width = text.width;

      addChild(text);
      addChild(caption);
      stuff.push(text);
      stuff.push(caption);

      yy += Std.int(text.height + 35);
    }
  }

  private function getText(align:TextFormatAlign = CENTER):TextField
  {
    var text = new TextField();
    var dtf = text.defaultTextFormat;
    dtf.align = align;
    text.setTextFormat(dtf);
    text.selectable = false;
    return text;
  }
}
