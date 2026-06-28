package polymod.hscript;

import polymod.Polymod;
import polymod.hscript._internal.Expr;
import polymod.util.Util;

class ScriptRunner
{
  /**
   * No reason not to make this static! Load a script once instead of 50 times.
   */
  private static var scripts:Map<String, Script> = new Map<String, Script>();

  public function new() {}

  public static function clearScripts():Void
  {
    scripts.clear();
  }

  public function load(name:String, assetHandler:Dynamic):Null<Script>
  {
    if (assetHandler == null)
    {
      Polymod.error(SCRIPT_NO_ASSET_HANDLER, "Class does not import an Assets class for Polymod to fetch scripts with!", SCRIPT_RUNTIME);
      return null;
    }

    var scriptPath = scriptPath(name);
    Polymod.debug('Fetching script "$scriptPath"...');
    if (!assetHandler.exists(scriptPath, null))
    {
      // Error will only be thrown if hscriptParams.optional == false (the default).
      Polymod.debug('Note: Script at path "$scriptPath" not found! This may cause problems if it is not optional...');
      return null;
    }

    var script = new Script(assetHandler.getText(scriptPath));
    scripts.set(name, script);
    Polymod.debug('Script $name loaded successfully.');
    return script;
  }

  static inline function scriptPath(pathName:String):String
  {
    return Util.pathJoin('${PolymodConfig.scriptLibrary}:${PolymodConfig.rootPath}', '$pathName${PolymodConfig.scriptExt}');
  }

  public function get(name:String, ?assetHandler:Dynamic = null):Null<Script>
  {
    // If the script isn't loaded yet, do that now.
    if (!scripts.exists(name))
    {
      Polymod.debug('Scripted function loaded late (this is fine if the pathname is dynamic).');
      load(name, assetHandler);
    }

    var result = scripts.get(name);

    if (result == null)
    {
      // An error will only be thrown if hscriptParams.optional == false (the default).
      return null;
    }

    return scripts.get(name);
  }

  public function execute(name:String, ?assetHandler:Dynamic = null):ScriptOutput
  {
    var script = get(name, assetHandler);
    if (script == null)
    {
      Polymod.error(SCRIPT_NOT_FOUND, 'Could not load script $name for execution.', SCRIPT_RUNTIME);
    }
    return script.execute();
  }
}

class Script
{
  private static var parser:polymod.hscript._internal.Parser;

  public var program:Expr;
  public var interp:polymod.hscript._internal.Interp;

  public static function buildParser():polymod.hscript._internal.Parser
  {
    return new polymod.hscript._internal.Parser();
  }

  public static function buildInterp():polymod.hscript._internal.Interp
  {
    // Arguments are only needed in a scripted class context.
    return new polymod.hscript._internal.Interp(null, null);
  }

  public function new(script:String, ?origin:String = null)
  {
    if (parser == null)
    {
      parser = buildParser();
      parser.allowTypes = true;
    }
    program = parser.parseString(script, origin);
    interp = buildInterp();
  }

  public function set(key:String, value:Dynamic)
  {
    interp.variables.set(key, value);
  }

  public function execute():ScriptOutput
  {
    var result:Dynamic = interp.execute(program);
    return {
      script_result: result,
      script_variables: interp.variables,
    };
  }
}

typedef ScriptOutput =
{
  /**
   * The output of the script. Can be any value type.
   */
  var script_result:Dynamic;

  /**
   * The functions and variables created within the scope of the script.
   */
  var script_variables:Map<String, Dynamic>;
}
