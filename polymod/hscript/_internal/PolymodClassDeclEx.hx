package polymod.hscript._internal;

import polymod.hscript._internal.Expr.ClassDecl;
import polymod.hscript._internal.Expr.FieldDecl;
import polymod.hscript._internal.PolymodScriptClass;

using StringTools;

/**
 * A scripted class declaration, with a package declaration, imports, and potentially static fields.
 */
typedef PolymodClassDeclEx =
{
  > ClassDecl,

  /**
   * Save performance and improve sandboxing by resolving imports at interpretation time.
   */
  @:optional var imports:Map<String, PolymodClassImport>;

  @:optional var importsToValidate:Map<String, PolymodClassImport>;
  @:optional var pkg:Array<String>;

  @:optional var staticFields:Array<FieldDecl>;
  @:optional var usings:Map<String, PolymodClassImport>;
}

/**
 * An imported class or enumeration.
 */
typedef PolymodClassImport =
{
  @:optional var name:String;
  @:optional var pkg:Array<String>;
  @:optional var fullPath:String; // pkg.pkg.pkg.name

  @:optional var cls:Class<Dynamic>;
  @:optional var enm:Enum<Dynamic>;
  @:optional var abs:PolymodStaticAbstractReference;
}

/**
 * A class which holds a reference to another scripted class,
 * for use in a static context. This allows for instantiation,
 * or for accessing static fields or methods.
 */
class PolymodStaticClassReference
{
  public var cls:PolymodClassDeclEx;

  public function new(cls:PolymodClassDeclEx)
  {
    this.cls = cls;
  }

  public static function tryBuild(clsName:String):Null<PolymodStaticClassReference>
  {
    @:privateAccess {
      if (PolymodInterpEx._scriptClassDescriptors.exists(clsName))
      {
        return new PolymodStaticClassReference(PolymodInterpEx._scriptClassDescriptors.get(clsName));
      }
      else
      {
        return null;
      }
    }
  }

  /**
   * Return a scripted instance of this script class.
   * @param args
   * @return Dynamic
   */
  public function instantiate(?args:Array<Dynamic>):Dynamic
  {
    var asc:PolymodAbstractScriptClass = buildASC(args);

    if (asc == null)
    {
      polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${getFullyQualifiedName()})');
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

  public function buildASC(?args:Array<Dynamic>):PolymodAbstractScriptClass
  {
    return new PolymodScriptClass(cls, args);
  }

  public function callFunction(funcName:String, ?args:Array<Dynamic>):Dynamic
  {
    return PolymodScriptClass.callScriptClassStaticFunction(getFullyQualifiedName(), funcName, args);
  }

  public function getField(fieldName:String):Dynamic
  {
    return PolymodScriptClass.getScriptClassStaticField(getFullyQualifiedName(), fieldName);
  }

  public function setField(fieldName:String, fieldValue:Dynamic):Dynamic
  {
    return PolymodScriptClass.setScriptClassStaticField(getFullyQualifiedName(), fieldName, fieldValue);
  }

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

/**
 * A class which holds a reference to an abstract class implementation,
 * or (if the implementation class is not available) redirects
 * to the abstract static value store built by PolymodScriptClassMacro at compile time.
 */
@:nullSafety
class PolymodStaticAbstractReference {
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
  public function instantiate(args:Array<Dynamic>):Dynamic {
    if (this.absImpl == null) {
      throw 'Could not resolve abstract class ${absName}.';
    }

    return Type.createInstance(this.absImpl, args);
  }

  /**
   * Retrieve a static field of the abstract class.
   * @param fieldName The name of the field to retrieve.
   * @return The value of the field.
   */
  public function getField(fieldName:String):Dynamic {
    if (this.absImpl != null) {
      if (Reflect.hasField(this.absImpl, fieldName)) {
        var result:Dynamic = Reflect.getProperty(this.absImpl, fieldName);
        if (result != null) return result;
      }
    }

    return fetchAbstractClassStatic(fieldName);
  }

  /**
   * Call a static function of the abstract class.
   * @param funcName The name of the function to call.
   * @param args The arguments to pass to the function.
   * @return The return value of the function.
   */
  public function callFunction(funcName:String, args:Array<Dynamic>):Dynamic {
    // If we can just call the method directly, do that.
    var func = getField(funcName);
    if (func != null) {
      return Reflect.callMethod(this.absImpl, func, args);
    }

    throw 'Could not resolve abstract class static function ${funcName}';
  }

  function fetchAbstractClassStatic(fieldName:String):Dynamic {
    var key:String = '${this.absImplPath}.${fieldName}';

    if (PolymodScriptClass.abstractClassStatics.exists(key)) {
      var holder = PolymodScriptClass.abstractClassStatics.get(key);
      var property = key.replace('.', '_');

      return Reflect.getProperty(holder, property);
    } else {
      throw 'Could not resolve abstract class static field ${fieldName}';
    }
  }

  public function toString():String
  {
    return 'PolymodStaticAbstractReference(${absName} => ${absImpl})';
  }
}
