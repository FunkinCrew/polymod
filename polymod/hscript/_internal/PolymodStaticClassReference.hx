package polymod.hscript._internal;

import polymod.hscript._internal.Expr;

using StringTools;

/**
 * A class which holds a reference to another scripted class,
 * for use in a static context. This allows for instantiation,
 * or for accessing static fields or methods.
 */
class PolymodStaticClassReference
{
  public var cls:ClassDecl;

  public function new(cls:ClassDecl)
  {
    this.cls = cls;
  }

  /**
   * Build a static class reference for the given scripted class name, if it exists
   * @param clsName The name of the scripted class
   * @return The static class reference, or `null` if the scripted class doesn't exist
   */
  public static function tryBuild(clsName:String):Null<PolymodStaticClassReference>
  {
    @:privateAccess {
      if (Interp._scriptClassDescriptors.exists(clsName))
      {
        return new PolymodStaticClassReference(Interp._scriptClassDescriptors.get(clsName));
      }
      else
      {
        return null;
      }
    }
  }

  /**
   * Return an instance of this scripted class.
   * @param args The arguments to pass to the constructor
   * @return The resulting instance
   */
  public function instantiate(?args:Array<Dynamic>):Null<Dynamic>
  {
    var asc:PolymodAbstractScriptClass = buildASC(args);

    if (asc == null)
    {
      polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${getFullyQualifiedName()})', SCRIPT_RUNTIME);
      return null;
    }

    var scriptedObj:Null<Dynamic> = asc.superClass;
    while (Std.isOfType(scriptedObj, PolymodScriptClass))
    {
      scriptedObj.topASC = asc;
      scriptedObj = scriptedObj.superClass;
    }

    if (scriptedObj == null)
    {
      // We've hit a class that does not extend anything
      // The ASC will act like a scripted class for us instead.
      return asc;
    }

    Reflect.setField(scriptedObj, '_asc', asc);
    return scriptedObj;
  }

  /**
   * Build a PolymodAbstractScriptClass for this class
   * @param args The arguments to pass to the constructor
   * @return The resulting PolymodAbstractScriptClass
   */
  public function buildASC(?args:Array<Dynamic>):PolymodAbstractScriptClass
  {
    return new PolymodScriptClass(cls, args);
  }

  /**
   * Call a static function of the scripted class
   * @param funcName The name of the function to call
   * @param args The arguments to pass into the function
   * @return The return value of the function
   */
  public function callFunction(funcName:String, ?args:Array<Dynamic>):Dynamic
  {
    return PolymodScriptClass.callScriptClassStaticFunction(getFullyQualifiedName(), funcName, args);
  }

  /**
   * Retrieve a static field of the scripted class
   * @param fieldName The name of the field to retrieve
   * @return The value of the field
   */
  public function getField(fieldName:String):Dynamic
  {
    return PolymodScriptClass.getScriptClassStaticField(getFullyQualifiedName(), fieldName);
  }

  /**
   * Assign a static field of the scripted class
   * @param fieldName The name of the field to retrieve
   * @param fieldValue The value to assign to the field
   * @return The value of the field
   */
  public function setField(fieldName:String, fieldValue:Dynamic):Dynamic
  {
    return PolymodScriptClass.setScriptClassStaticField(getFullyQualifiedName(), fieldName, fieldValue);
  }

  /**
   * Retrieve the fully qualified name of the scripted class, prefixed by its package
   * @return The fully qualified name
   */
  public function getFullyQualifiedName():String
  {
    if (this.cls.pkg != null && this.cls.pkg.length > 0)
    {
      return this.cls.pkg.join(".") + "." + this.cls.name;
    }
    return this.cls.name;
  }

  public function toString():String
  {
    return 'PolymodStaticClassReference(${getFullyQualifiedName()})';
  }
}
