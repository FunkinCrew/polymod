import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import openfl.utils.AssetType;

using StringTools;

class Demo extends Sprite
{
  private var widgets:Array<ModWidget> = [];
  private var stuff:Array<Dynamic> = [];

  private var onModChange:Array<String>->Void;
  private var onLocaleChange:String->Void;

  private var limeToggle:CheapButton;
  private var limeLabel:TextField;

  private var localeToggle:CheapButton;
  private var localeLabel:TextField;

  private var localeListLabel:TextField;

  public static var usingOpenFL(default, null):Bool = true;

  public function new(onModChange:Array<String>->Void, onLocaleChange:String->Void)
  {
    super();

    this.onModChange = onModChange;
    this.onLocaleChange = onLocaleChange;

    makeButtons();
    drawImages();
    drawText();

    drawFlag();

    reloadMods();
  }

  public function destroy()
  {
    for (w in widgets)
    {
      w.destroy();
    }
    onModChange = null;
    onLocaleChange = null;
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
    #if sys
    var mods = sys.FileSystem.readDirectory(modDir);
    #else
    var mods = [];
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

      w.fixButtons();

      addChild(w.button);
      addChild(w.status);
      addChild(w.moveLeft);
      addChild(w.moveRight);
    }

    updateWidgets();
    addToggle();
    reloadText();
  }

  private function reloadText()
  {
    // Make sure to redo any translation calls when you change language.
    // This won't matter as much if you put your language select in a separate menu.
    limeLabel.text = Main.tongue.get('ASSET_SYSTEM_LABEL');
    limeToggle.setText(Main.tongue.get(usingOpenFL ? 'ASSET_SYSTEM_OPENFL' : 'ASSET_SYSTEM_LIME'));
    localeLabel.text = Main.tongue.get('TRANSLATION_LABEL');
    localeToggle.setText(Main.tongue.locale);
    localeListLabel.text = Main.tongue.locales.join(', ');
  }

  private function addToggle()
  {
    limeLabel = getText(LEFT);
    limeLabel.x = 10;
    limeLabel.y = 400;

    limeToggle = new CheapButton('', onToggleOpenFL, 144);
    limeToggle.x = 10;
    limeToggle.y = 420;

    localeLabel = getText(LEFT);
    localeLabel.x = 10;
    localeLabel.y = 450;

    localeToggle = new CheapButton('', onToggleLocale);
    localeToggle.x = 10;
    localeToggle.y = 470;

    localeListLabel = getText(LEFT);
    localeListLabel.x = 10;
    localeListLabel.y = 510;

    addChild(limeLabel);
    addChild(limeToggle);
    addChild(localeLabel);
    addChild(localeToggle);
    addChild(localeListLabel);
  }

  private function onToggleOpenFL()
  {
    usingOpenFL = !usingOpenFL;

    reloadText();
    reloadMods();
    visible = false;
    haxe.Timer.delay(function() {
      visible = true;
    }, 10);
  }

  private function onToggleLocale()
  {
    reloadLocale();

    reloadText();
    drawFlag();
    updateWidgets();
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
      widgets[i].reloadText();
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

      w.fixButtons();
      other.fixButtons();
    }

    reloadMods();
    updateWidgets();
  }

  private function reloadMods()
  {
    if (onModChange != null)
    {
      var theMods = [];
      for (w in widgets)
      {
        if (w.active)
        {
          theMods.push(w.mod);
        }
      }
      onModChange(theMods);
    }
  }

  private function reloadLocale()
  {
    if (onLocaleChange != null)
    {
      var newLocale = Main.tongue.locale == "en-US" ? 'yr-HR' : 'en-US';
      onLocaleChange(newLocale);
    }
  }

  private function AssetsList(type:Dynamic)
  {
    if (usingOpenFL) return openfl.utils.Assets.list(cast type);
    else
      return lime.utils.Assets.list(cast type);
  }

  private function AssetsGetBitmapData(str:String)
  {
    if (usingOpenFL) return openfl.utils.Assets.getBitmapData(str);
    else
    {
      var img = lime.utils.Assets.getImage(str);
      return BitmapData.fromImage(img);
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
    var xx = 10;
    var yy = 10;

    var images = AssetsList(AssetType.IMAGE);

    // Exclude the flag images.
    images = images.filter(function(str:String) {
      return str.startsWith('img/');
    });

    images.sort(function(a:String, b:String):Int {
      if (a < b) return -1;
      if (a > b) return 1;
      return 0;
    });

    for (image in images)
    {
      var bData = AssetsGetBitmapData(image);
      var bmp = new Bitmap(bData);
      bmp.x = xx;
      bmp.y = yy;

      var text = getText();

      text.width = bmp.width;
      text.text = image;
      text.x = xx;
      text.y = bmp.y + bmp.height;

      addChild(bmp);
      addChild(text);
      stuff.push(bmp);
      stuff.push(text);

      xx += Std.int(bmp.width + 10);
    }
  }

  var flag:Bitmap;

  function drawFlag()
  {
    if (flag != null) removeChild(flag);

    var bData = AssetsGetBitmapData(Main.tongue.getIcon(Main.tongue.locale));
    flag = new Bitmap(bData);
    flag.x = 90;
    flag.y = 470;

    addChild(flag);
  }

  private function drawText()
  {
    var xx = 500;
    var yy = 10;

    var texts = AssetsList(AssetType.TEXT);

    // Exclude the locale configs.
    texts = texts.filter(function(str:String) {
      return str.startsWith('data/');
    });

    texts.sort(function(a:String, b:String) {
      if (a < b) return 1;
      if (a > b) return -1;
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
