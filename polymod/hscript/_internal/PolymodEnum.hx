package polymod.hscript._internal;

import polymod.util.Util;
import polymod.hscript._internal.Expr;

class PolymodEnum
{
  private static final scriptInterp = new Interp(null, null);
  private static final _staticUsingFunctionsCache:Map<String, Map<String, Array<Dynamic>->Dynamic>> = [];

  private var _e:EnumDecl;

  public var value:String;
  public var args:Array<Dynamic>;

  public var usingFunctionsCache:Map<String, Array<Dynamic>->Dynamic> = [];

  public function new(e:EnumDecl, value:String, args:Array<Dynamic>)
  {
    this._e = e;

    var field = getField(e, value);

    if (field == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, '${e.name}.${value} does not exist.', SCRIPT_RUNTIME);
      return;
    }

    this.value = value;

    if (args.length != field.args.length)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, '${e.name}.${value} got the wrong number of arguments.', SCRIPT_RUNTIME);
      return;
    }

    this.args = args;

    buildUsingCache();
  }

  /**
   * Attempts to retrieve the full package of a scripted enum.
   * @param id
   */
  public static function tryResolve(id:String):Null<String>
  {
    // `id` is a package.
    if (id.indexOf('.') != -1)
    {
      // Enum exists so we can safely return the full package.
      @:privateAccess
      if (Interp._scriptEnumDescriptors.exists(id)) return id;
    }

    @:privateAccess
    for (fullEnumName => val in Interp._scriptEnumDescriptors)
    {
      var splitPkg:Array<String> = fullEnumName.split('.');
      var name:String = splitPkg[splitPkg.length - 1];

      if (name == id) return fullEnumName;
    }
    return null;
  }

  /**
   * Instantiates or returns a reference to a `PolymodEnum` constructor.
   * @param enmName The name of the scripted enum
   * @param field The target field
   * @return A `PolymodEnum` instance/constructor, or `null` if the enum is not found
   */
  public static function tryBuild(enmName:String, field:String):Dynamic
  {
    @:privateAccess
    if (Interp._scriptEnumDescriptors.exists(enmName))
    {
      @:privateAccess
      var enm = Interp._scriptEnumDescriptors.get(enmName);

      var fld = getField(enm, field);

      if ((fld?.args?.length ?? 0) >= 1)
      {
        return Reflect.makeVarArgs((args) -> new PolymodEnum(enm, field, args));
      }

      return new PolymodEnum(enm, field, []);
    }

    return null;
  }

  public static function clearScriptedEnums():Void
  {
    scriptInterp.clearScriptEnumDescriptors();
  }

  private static function getField(e:EnumDecl, name:String):Null<EnumFieldDecl>
  {
    for (field in e.fields)
    {
      if (field.name == name)
      {
        return field;
      }
    }
    return null;
  }

  public function buildUsingCache()
  {
    var fullEnumName:String = Util.getFullEnumClass(_e);

    if (_staticUsingFunctionsCache.exists(fullEnumName))
      return usingFunctionsCache = _staticUsingFunctionsCache.get(fullEnumName);

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

  public function toString():String
  {
    var result:String = '${_e.name}.${value}';
    if (args.length > 0) result += '(${args.join(',')})';
    return result;
  }
}
