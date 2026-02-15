package polymod.hscript._internal;

import polymod.hscript._internal.Expr.ClassDecl;
import polymod.hscript._internal.Expr.FieldDecl;
import polymod.hscript._internal.PolymodScriptClass;

using StringTools;

/**
 * A class which holds a reference to an abstract class implementation,
 * or (if the implementation class is not available) redirects
 * to the abstract static value store built by PolymodScriptClassMacro at compile time.
 */
@:nullSafety
class PolymodStaticAbstractReference
{
  /**
   * The name of the abstract class, as it was imported.
   */
  public var absName:String;

  /**
   * The internal class that implements the abstract class's static functions,
   * if it exists.
   */
  public var absImpl:Null<Class<Dynamic>>;

  /**
   * The path of the implementation class.
   * Used for resolving static fields cached at macro time.
   */
  public var absImplPath:String;

  public function new(absName:String, absImpl:Null<Class<Dynamic>>, absImplPath:String)
  {
    this.absName = absName;
    this.absImpl = absImpl;
    this.absImplPath = absImplPath;
  }

  /**
   * Instantiate an instance of the underlying implementation  class.
   * @param args The arguments to pass to the constructor.
   * @return The resulting instance.
   * @throws ex Thrown if the underlying implementation class is not available.
   */
  public function instantiate(args:Array<Dynamic>):Dynamic
  {
    if (this.absImpl == null)
    {
      throw 'Could not resolve abstract class ${absName}.';
    }

    var ctor = Reflect.field(this.absImpl, '_new');
    if (ctor == null)
    {
      throw 'Could not find constructor for abstract class ${absName}';
    }

    return Reflect.callMethod(this.absImpl, ctor, args);
  }

  /**
   * Retrieve a static field of the abstract class.
   * @param fieldName The name of the field to retrieve.
   * @return The value of the field.
   */
  public function getField(fieldName:String):Dynamic
  {
    if (this.absImpl != null)
    {
      if (Reflect.hasField(this.absImpl, fieldName))
      {
        var result:Dynamic = Reflect.getProperty(this.absImpl, fieldName);
        if (result != null) return result;
      }
      var getterName:String = 'get_$fieldName';
      if (Reflect.hasField(this.absImpl, getterName))
      {
        var getter = Reflect.field(this.absImpl, getterName);
        return Reflect.callMethod(this.absImpl, getter, []);
      }
    }

    return fetchAbstractClassStatic(fieldName);
  }

  /**
   * Assign a static field of the abstract class.
   * @param fieldName The name of the field to assign.
   * @param fieldValue The value to assign to the field.
   * @return The value of the field.
   */
  public function setField(fieldName:String, fieldValue:Dynamic):Dynamic
  {
    if (this.absImpl != null)
    {
      if (Reflect.hasField(this.absImpl, fieldName))
      {
        Reflect.setProperty(this.absImpl, fieldName, fieldValue);
        return fieldValue;
      }
      var setterName:String = 'set_$fieldName';
      if (Reflect.hasField(this.absImpl, setterName))
      {
        var setter = Reflect.field(this.absImpl, setterName);
        var result = Reflect.callMethod(this.absImpl, setter, [fieldValue]);
        return result;
      }
    }

    throw 'Could not resolve abstract static field ${fieldName}';
  }

  /**
   * Call a static function of the abstract class.
   * @param funcName The name of the function to call.
   * @param args The arguments to pass to the function.
   * @return The return value of the function.
   */
  public function callFunction(funcName:String, args:Array<Dynamic>):Dynamic
  {
    // If we can just call the method directly, do that.
    var func = getField(funcName);
    if (func != null)
    {
      return Reflect.callMethod(this.absImpl, func, args);
    }

    throw 'Could not resolve abstract class static function ${funcName}';
  }

  function fetchAbstractClassStatic(fieldName:String):Dynamic
  {
    var key:String = '${this.absImplPath}.${fieldName}';

    if (PolymodScriptClass.abstractClassStatics.exists(key))
    {
      var holder = PolymodScriptClass.abstractClassStatics.get(key);
      var property = key.replace('.', '_');

      return Reflect.getProperty(holder, property);
    }
    else
    {
      throw 'Could not resolve abstract class static field ${fieldName}';
    }
  }

  public function toString():String
  {
    return 'PolymodStaticAbstractReference(${absName} => ${absImpl})';
  }
}
