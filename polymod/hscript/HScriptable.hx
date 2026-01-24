package polymod.hscript;

import haxe.Json;
import polymod.hscript._internal.Expr;
import polymod.Polymod;
import polymod.util.Util;

/**
 * This interface triggers the execution of a macro on any elements which use the `@:hscript` annotation.
 * Adding the annotation to the function will cause the associate script to be executed.
 * Adding the annotation to the class will allow specification of additional parameters which apply to all annotated functions.
 */
@:autoBuild(polymod.hscript._internal.HScriptableMacro.build())
interface HScriptable
{
}

/**
 * Used to provide additional parameters to a script function.
 *
 * `@:hscript({context, pathName, ...})` can be added to any function to make it scriptable.
 * Add constant identifiers to `context` to make values accessible to the script and use the other values to define the script's behavior.
 *
 * For the purposes of backwards compatibility, `@:hscript(A, B, C)` can also be used, which will specify the context.
 * `@:hscript(A, B, C)` is equivalent to `@:hscript({context: [A, B, C]})` but doesn't allow modifying other parameters.
 * The new syntax should be adopted where possible.
 */
class HScriptParams
{
	/**
	 * Provide an array of constants which will be accessible by the local script.
	 * This can be global utility classes, or variables/functions local to the current class.
	 * @default An empty array.
	 */
	public var context:Array<String> = [];

	/**
	 * If true, provides a `cancel()` function to the script.
	 * Calling it will cause the main body of the function to be ignored.
	 * @default false
	 */
	public var cancellable:Null<Bool> = null;

	public static final CANCELLABLE_DEFAULT:Bool = false;

	/**
	 * If true, the body of the function will run BEFORE the script does.
	 * Incompatible with `cancellable`.
	 * @default false
	 */
	public var runBefore:Null<Bool> = null;

	public static final RUN_BEFORE_DEFAULT:Bool = false;

	/**
	 * If true, no error will be thrown in the event that the script is missing.
	 * This is useful when the script you're calling might be empty or undefined.
	 * @default false
	 */
	public var optional:Null<Bool> = null;

	public static final OPTIONAL_DEFAULT:Bool = false;

	/**
	 * Force a specific script path name.
	 * If not specified, the path name will be the name of the function.
	 */
	public var pathName(default, set):String = null;

	function set_pathName(newValue:String):String
	{
		if (pathNameDynId != null)
			return null;

		this.pathName = newValue;
		return pathName;
	}

	/**
	 * A dynamic identifier which will be evaluated, at function call time,
	 * to determine the pathname of the script to run.
	 *
	 * This can be the name of a String variable, or of a function.
	 *
	 * DON'T SET `pathNameDynId` DIRECTLY!
	 * Just pass an identifier into `pathName` instead of a constant.
	 */
	public var pathNameDynId(default, set):String = null;

	function set_pathNameDynId(newValue:String):String
	{
		this.pathName = null;
		this.pathNameDynId = newValue;
		return this.pathNameDynId;
	}

	public function new()
	{
	}

	/**
	 * Concatenate the provided list of constant identifiers to the existing list.
	 * @returns Self, for chaining.
	 */
	public function mergeContext(newValues:Array<String>):HScriptParams
	{
		context = context.concat(newValues);
		return this;
	}

	public function mergeCancellable(newValue:Null<Bool>):HScriptParams
	{
		if (newValue != null)
			cancellable = newValue;
		return this;
	}

	public function mergeRunBefore(newValue:Null<Bool>):HScriptParams
	{
		if (newValue != null)
			runBefore = newValue;
		return this;
	}

	public function mergeOptional(newValue:Null<Bool>):HScriptParams
	{
		if (newValue != null)
			optional = newValue;
		return this;
	}

	public function mergePathName(newValue:String, ?newDynValue:String = null):HScriptParams
	{
		if (newDynValue != null)
		{
			pathNameDynId = newDynValue;
			pathName = null;
		}
		else
		{
			if (pathNameDynId == null && newValue != null)
				pathName = newValue;
		}
		return this;
	}

	/**
	 * Create a copy of this object.
	 * @return A new instance of HScriptParams.
	 */
	public function copy():HScriptParams
	{
		var result = new HScriptParams();

		result.cancellable = cancellable;
		result.context = context;
		result.optional = optional;
		result.pathName = pathName;
		result.pathNameDynId = pathNameDynId;
		result.runBefore = runBefore;

		return result;
	}

	/**
	 * Merge all values from the provided params into this one.
	 * @returns Self, for chaining.
	 */
	public function merge(newValue:HScriptParams)
	{
		return this.mergeCancellable(newValue.cancellable)
			.mergeContext(newValue.context)
			.mergeOptional(newValue.optional)
			.mergePathName(newValue.pathName, newValue.pathNameDynId)
			.mergeRunBefore(newValue.runBefore);
	}

	public function toString():String
	{
		return Json.stringify(this);
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

class ScriptRunner
{
	/**
	 * No reason not to make this static! Load a script once instead of 50 times.
	 */
	private static var scripts:Map<String, Script> = new Map<String, Script>();

	public function new()
	{
	}

	public static function clearScripts():Void
	{
		scripts.clear();
	}

	public function load(name:String, assetHandler:Dynamic):Script
	{
		if (assetHandler == null)
		{
			Polymod.error(PolymodErrorCode.SCRIPT_NO_ASSET_HANDLER, "Class does not import an Assets class for Polymod to fetch scripts with!");
			return null;
		}

		var scriptPath = scriptPath(name);
		Polymod.debug('Fetching script "$scriptPath"...');
		if (!assetHandler.exists(scriptPath))
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

	public function get(name:String, ?assetHandler:Dynamic = null):Script
	{
		// If the script isn't loaded yet, do that now.
		if (!scripts.exists(name))
		{
			Polymod.debug('Note: Late script load ($name). This is normal for dynamic pathNames.');
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
			Polymod.error(PolymodErrorCode.SCRIPT_NOT_FOUND, 'Could not load script $name for execution.');
		}
		return script.execute();
	}
}

class Script
{
	private static var parser:polymod.hscript._internal.PolymodParserEx;

	public var program:Expr;
	public var interp:polymod.hscript._internal.PolymodInterpEx;

	public static function buildParser():polymod.hscript._internal.PolymodParserEx
	{
		return new polymod.hscript._internal.PolymodParserEx();
	}

	public static function buildInterp():polymod.hscript._internal.PolymodInterpEx
	{
		// Arguments are only needed in a scripted class context.
		return new polymod.hscript._internal.PolymodInterpEx(null, null);
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
