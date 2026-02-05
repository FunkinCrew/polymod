import openfl.events.KeyboardEvent;
import stage.Stage;
import stage.StubStage;
import stage.ScriptedStage;
import openfl.display.Bitmap;
import openfl.display.BitmapData;
import openfl.display.Sprite;
import openfl.text.TextField;
import openfl.text.TextFormatAlign;
import openfl.utils.AssetType;

class Demo extends Sprite
{
  private var widgets:Array<ModWidget> = [];
  private var stageButtons:Array<CheapButton> = [];
  private var callback:Array<String>->Void;
  private var stuff:Array<Dynamic> = [];
  private var limeToggle:CheapButton;

  private var curStage:Stage;

  public static var usingOpenFL(default, null):Bool = true;

  var dirty:Bool = false;

  public function new(callback:Array<String>->Void)
  {
    super();

    this.callback = callback;

    initStageData();
    setStage();

    makeButtons();

    drawStage();
    drawImages();
    drawText();
  }

  public function addListeners()
  {
    stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
  }

  function onKeyDown(e:KeyboardEvent)
  {
    if (curStage != null) curStage.onKeyDown(e);
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
    drawStage();
    drawImages();
    drawText();

    initStageData();
    drawStageButtons();

    addListeners();
  }

  private function makeButtons()
  {
    addModWidgets();
    drawStageButtons();
    updateWidgets();
    addToggle();
  }

  private function addModWidgets()
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
    var yy = 370;

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
  }

  var stageData:Array<Stage> = null;

  function initStageData():Void
  {
    stageData = [];
    var stageClassNames:Array<String> = ScriptedStage.listScriptClasses();

    stageData.push(new StubStage());
    for (stageClassName in stageClassNames)
    {
      var defaultStageId:String = 'STAGE_${Std.random(256)}';
      var stage:ScriptedStage = ScriptedStage.scriptInit(stageClassName, defaultStageId);
      if (stage != null)
      {
        stageData.push(stage);
      }
    }
  }

  function listStages():Array<String>
  {
    return [for (stage in stageData) stage.stageId];
  }

  function setStage(?stageId:String = 'stub'):Void
  {
    if (curStage != null)
    {
      removeChild(curStage);
      curStage = null;
    }
    for (stage in stageData)
    {
      if (stage.stageId == stageId)
      {
        curStage = stage;
      }
    }
  }

  private function drawStage()
  {
    curStage.x = 5;
    curStage.y = 5;
    addChild(curStage);
    curStage.create();
  }

  private function drawStageButtons()
  {
    stageButtons = [];
    for (stage in stageData)
    {
      trace('STAGE BUTTON : ${stage.stageName} : ${stage.stageId} : ${stage}');
      var button = new CheapButton(stage.stageName, function() {
        trace('Pressed button: ${stage.stageName}');
        setStage(stage.stageId);
        refresh();
      });
      stageButtons.push(button);
      stuff.push(button);
    }

    var xx = 10 + 72 + 10;
    for (button in stageButtons)
    {
      button.x = xx;
      button.y = 550;
      // Make sure the buttons get cleaned up when reloading mods.
      stuff.push(button);
      addChild(button);
      xx += 72 + 10;
    }
  }

  private function addToggle()
  {
    var limeLabel = getText(LEFT);
    limeLabel.x = 10;
    limeLabel.y = 530;
    limeLabel.text = 'Asset System:';

    limeToggle = new CheapButton(usingOpenFL ? 'openfl' : 'lime', onToggleOpenFL);
    limeToggle.x = 10;
    limeToggle.y = 550;

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

      w.fixButtons();
      other.fixButtons();
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
    images = images.filter(function(i:String) {
      return i.indexOf('img/stage') == -1;
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

      var text = getText();
      text.text = image;
      text.width = bmp.width;
      text.height = 20;
      text.x = xx;
      text.y = yy;

      bmp.x = xx;
      bmp.y = text.y + text.height;

      addChild(bmp);
      addChild(text);
      stuff.push(bmp);
      stuff.push(text);

      xx += Std.int(bmp.width + 10);
    }
  }

  private function drawText()
  {
    var xx = 500;
    var yy = 10;

    var texts = AssetsList(AssetType.TEXT);
    texts = texts.filter(function(i:String) {
      return i.indexOf('.hscript') == -1 && i.indexOf('.hclass') == -1;
    });
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
