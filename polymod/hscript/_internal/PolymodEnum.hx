package polymod.hscript._internal;

import polymod.util.Util;
import polymod.hscript._internal.Expr;

@:allow(polymod.hscript._internal.PolymodEnumValue)
class PolymodEnum
{
  static final _staticUsingFunctionsCache:Map<String, Map<String, Array<Dynamic>->Dynamic>> = [];

  /**
   * Internal cache for active `PolymodEnum` instances to optimize and prevent redundant allocations.
   */
  static var _enumCache:Map<String, PolymodEnum> = new Map<String, PolymodEnum>();

  var _e:EnumDecl;


  /**
   * Cache storing resolved enum fields, which can either be a `PolymodEnumValue` (for constants) 
   * or a variadic function constructor (for enums requiring arguments).
   */
  var _fieldCach:Map<String, Dynamic> = new Map<String, Dynamic>();

  public var usingFunctionsCache:Map<String, Array<Dynamic>->Dynamic> = [];

  public function new(e:EnumDecl)
  {
    this._e = e;
    buildUsingCache();
  }

  /**
   * Attempts to build a `PolymodEnum` instance using its fully qualified name.
   * @param enmName The fully qualified name or path of the scripted enum.
   * @return A `PolymodEnum` instance, or `null` if the enum descriptor is not found.
   */
  public static function tryBuild(enmName:String):Null<PolymodEnum>
  {
    @:privateAccess
    if (Interp._scriptEnumDescriptors.exists(enmName))
    {
      @:privateAccess
      var enm = Interp._scriptEnumDescriptors.get(enmName);

      if (_enumCache.exists(enmName)) return _enumCache.get(enmName);

      var ref = new PolymodEnum(enm);
      _enumCache.set(enmName, ref);

      return ref;
    }

    return null;
  }

  /**
   * Compares two `PolymodEnumValue` instances for structural and identity equality.
   * Validates both the constructor name value and its parent enum reference.
   * @param a First enum value instance.
   * @param b Second enum value instance.
   * @return `true` if both enum values match precisely, `false` otherwise.
   */
  public static function enumEq(a:PolymodEnumValue, b:PolymodEnumValue):Bool
  {
    if (a == null || b == null) return false;

    if (a.value == b.value)
    {
      return a.parentEnum.getFullName() == b.parentEnum.getFullName();
    }
    return false;
  }

  /**
   * Clears all cached script enums, fields, and static using-functions caches.
   */
  public static function clearScriptedEnums():Void
  {
    for (name => enm in _enumCache)
    {
      enm._fieldCach.clear();
      _enumCache.remove(name);
    }

    _staticUsingFunctionsCache.clear();
  }

  /**
   * Retrieves an enum field (either a constant value or a constructor function) by its name.
   * @param name The name of the enum field.
   * @return The resolved field (`PolymodEnumValue` or a constructor for it).
   * @throws error if the specified field does not exist on this enum.
   */
  public function getField(name:String):Dynamic
  {
    if (_fieldCach.exists(name)) return _fieldCach.get(name);

    var field = getFieldDecl(name);
    if (field == null) throw '${_e.name}.${name} does not exist.';

    var fld:Dynamic = null;

    if (field.args.length >= 1)
    {
      fld = Reflect.makeVarArgs(function(args:Array<Dynamic>) return new PolymodEnumValue(this, field, args));
    }

    if (fld == null) fld = new PolymodEnumValue(this, field);
    _fieldCach.set(name, fld);
    return fld;
  }

  /**
   * Finds and returns the raw declaration of a specific enum field.
   * @param name The target field name.
   * @return The `EnumFieldDecl` structure, or `null` if not found.
   */
  public function getFieldDecl(name:String):Null<EnumFieldDecl>
  {
    for (field in _e.fields)
    {
      if (field.name == name)
      {
        return field;
      }
    }
    return null;
  }

  /**
   * Checks whether a specific field exists within this enum declaration.
   * @param field The field name to check.
   * @return `true` if the field exists, `false` otherwise.
   */
  public function hasField(field:String):Bool
  {
    return getFieldDecl(field) != null;
  }

  function buildUsingCache()
  {
    var fullEnumName:String = getFullName();

    if (_staticUsingFunctionsCache.exists(fullEnumName)) return usingFunctionsCache = _staticUsingFunctionsCache.get(fullEnumName);

    var list:Map<String, Array<Dynamic>->Dynamic> = [];
    for (m in _e.meta)
    {
      if (m.name == ':using')
      {
        var clsMetaName:String = new Printer().exprToString(m.params[0]);

        var usingList = PolymodScriptClass.buildUsingListCache(clsMetaName);
        for (name => func in usingList ?? [])
        {
          list.set(name, func);
        }
      }
    }
    _staticUsingFunctionsCache.set(fullEnumName, list);

    return usingFunctionsCache = list;
  }

  public function getFullName():String
  {
    return Util.getFullEnumClass(_e);
  }

  public function toString():String
  {
    return 'PolymodEnum(${getFullName()})';
  }
}

class PolymodEnumValue
{
  var _f:EnumFieldDecl;

  /**
   * A reference to the parent PolymodEnum instance
   */
  public var parentEnum:PolymodEnum;

  public var value:String;
  public var args:Array<Dynamic>;

  public function new(parent:PolymodEnum, f:EnumFieldDecl, ?args:Array<Dynamic>)
  {
    this.parentEnum = parent;
    this._f = f;

    this.value = f.name;

    if (f.args.length == 0 && args != null)
    {
      throw '${parent._e.name}.${value} is not callable.';
    }

    if ((args?.length ?? 0) != f.args.length)
    {
      throw '${parent._e.name}.${value} got the wrong number of arguments.';
    }

    this.args = args ?? [];
  }

  public function toString():String
  {
    var result:String = '${parentEnum._e.name}.${value}';
    if (args.length > 0) result += '(${args.join(',')})';
    return 'PolymodEnumValue($result)';
  }
}
