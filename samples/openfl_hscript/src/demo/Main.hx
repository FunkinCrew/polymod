package demo;

import openfl.Lib;
import openfl.display.Sprite;
import polymod.Polymod;
import polymod.PolymodConfig;
import openfl.events.KeyboardEvent;
import openfl.text.TextField;

class Main extends Sprite
{
  private var sim:Simulation = null;
  private var mods:Array<String> = null;
  private var activeMods:Array<ModMetadata> = [];

  public function new()
  {
    super();
    mods = [];
    loadDemo();
    Lib.current.stage.addEventListener(KeyboardEvent.KEY_DOWN, onKeyDown);
    setupText();
  }

  private function setupText()
  {
    var text = new TextField();
    text.height = 16;
    text.width = 300;
    addChild(text);
    text.y = Lib.current.stage.stageHeight - text.height;
    text.text = "Press 1, 2, 3, or 4 to toggle a mod";

    var text2 = new TextField();
    text2.height = 16;
    text2.width = 300;
    addChild(text2);
    text2.y = text.y - text.height;
    var str = '';
    for (mod in activeMods)
    {
      if (str != '') str += ',';
      str += mod.title;
    }
    text2.text = 'Current mods: $str';
  }

  private function onKeyDown(e:KeyboardEvent)
  {
    var char = String.fromCharCode(e.keyCode);
    switch (char)
    {
      case 'R':
        reset();
      case '1':
        toggleMod('mod1');
      case '2':
        toggleMod('mod2');
      case '3':
        toggleMod('mod3');
      case '4':
        toggleMod('mod4');
      default: // donothing
    }
  }

  private function toggleMod(str:String)
  {
    if (mods.indexOf(str) == -1)
    {
      mods.push(str);
    }
    else
    {
      mods.remove(str);
    }
    loadMods();
  }

  private function reset()
  {
    sim.destroy();
    removeChild(sim);
    for (i in 0...numChildren)
    {
      removeChildAt(0);
    }
    loadDemo();
    setupText();
  }

  private function loadDemo()
  {
    sim = new Simulation();
    addChild(sim);
  }

  private function loadMods()
  {
    var modRoot = '../../../mods/';
    #if mac
    modRoot = '../../../../../../mods/';
    #end
    activeMods = Polymod.init(
      {
        modRoot: modRoot,
        dirs: mods.copy(),
        errorCallback: onError,
        ignoredFiles: Polymod.getDefaultIgnoreList()
      });
    reset();
  }

  private function onError(error:PolymodError)
  {
    trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
  }
}
