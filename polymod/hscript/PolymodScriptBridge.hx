package polymod.hscript;

import polymod.Polymod;
import polymod.hscript._internal.PolymodAbstractScriptClass;
import polymod.hscript._internal.PolymodScriptClass;
import polymod.hscript._internal.PolymodStaticClassReference;

/**
 * Provides a bridge for interacting with script classes and their instances.
 */
class PolymodScriptBridge
{
  public static function findScript(asc:Dynamic, funcName:String):Dynamic
  {
    var cls:Dynamic = asc;

    while (cls != null && cls is PolymodScriptClass)
    {
      var scriptCls:PolymodScriptClass = cast cls;
      if (scriptCls.hasScriptFunction(funcName)) return scriptCls;

      cls = scriptCls.superClass;
    }

    return null;
  }

  public static function callOn(scriptCls:Dynamic, funcName:String, funcArgs:Array<Dynamic>):Dynamic
  {
    if (scriptCls == null) return null;

    var script:PolymodScriptClass = cast scriptCls;
    return script.callFunction(funcName, funcArgs ?? []);
  }

  /**
   * Returns the full name of the Polymod/HScript class attached to a generated
   * class instance, or null when no scripted class is attached.
   */
  public static function getScriptClassName(asc:Dynamic):Null<String>
  {
    if (asc == null) return null;

    var script:PolymodAbstractScriptClass = cast asc;
    return script.fullyQualifiedName;
  }

  public static function fieldRead(asc:Dynamic, varName:String):Dynamic
  {
    if (asc == null) return null;

    var script:PolymodAbstractScriptClass = cast asc;
    return script.fieldRead(varName);
  }

  public static function fieldWrite(asc:Dynamic, varName:String, varValue:Dynamic):Dynamic
  {
    if (asc == null) return null;

    var script:PolymodAbstractScriptClass = cast asc;
    return script.fieldWrite(varName, varValue);
  }

  public static function fieldExists(asc:Dynamic, fieldName:String):Bool
  {
    if (asc == null) return false;

    var script:PolymodAbstractScriptClass = cast asc;
    return script.fieldExists(fieldName);
  }

  public static function callFunction(asc:Dynamic, funcName:String, funcArgs:Array<Dynamic>):Dynamic
  {
    if (asc == null) return null;

    var script:PolymodAbstractScriptClass = cast asc;
    return script.callFunction(funcName, funcArgs ?? []);
  }

  public static function listExtending(clsPath:String):Array<String>
  {
    return PolymodScriptClass.listScriptClassesExtending(clsPath);
  }

  public static function instantiate(clsName:String, underlyingClass:String, args:Array<Dynamic>):Dynamic
  {
    var clsRef:Null<PolymodStaticClassReference> = PolymodStaticClassReference.tryBuild(clsName);

    if (clsRef == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
        'Could not construct instance of scripted class (${clsName} extends ${underlyingClass})\nUnknown error building class reference', SCRIPT_RUNTIME);
      return null;
    }

    try
    {
      var result:Dynamic = clsRef.instantiate(args ?? []);

      if (result == null)
      {
        Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
          'Could not construct instance of scripted class (${clsName} extends ${underlyingClass}):\nUnknown error instantiating class', SCRIPT_RUNTIME);
        return null;
      }

      return result;
    }
    catch (error)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
        'Could not construct instance of scripted class (${clsName} extends ${underlyingClass}):\n${error}', SCRIPT_RUNTIME);
      return null;
    }
  }

  public static function staticGet(clsName:String, fieldName:String):Dynamic
  {
    return PolymodScriptClass.getScriptClassStaticField(clsName, fieldName);
  }

  public static function staticSet(clsName:String, fieldName:String, fieldValue:Dynamic):Dynamic
  {
    return PolymodScriptClass.setScriptClassStaticField(clsName, fieldName, fieldValue);
  }

  public static function staticHas(clsName:String, fieldName:String):Bool
  {
    return PolymodScriptClass.hasScriptClassStaticField(clsName, fieldName);
  }

  public static function staticHasFunc(clsName:String, fieldName:String):Bool
  {
    return PolymodScriptClass.hasScriptClassStaticFunction(clsName, fieldName);
  }

  public static function staticCall(clsName:String, funcName:String, funcArgs:Array<Dynamic>):Dynamic
  {
    return PolymodScriptClass.callScriptClassStaticFunction(clsName, funcName, funcArgs ?? []);
  }
}
