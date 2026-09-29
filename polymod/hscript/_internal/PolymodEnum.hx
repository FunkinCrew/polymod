package polymod.hscript._internal;

import polymod.util.Util;
import polymod.hscript._internal.Expr;

@:allow(polymod.Polymod)
class PolymodEnum
{
  private static final _staticUsingFunctionsCache:Map<String, Map<String, Array<Dynamic>->Dynamic>> = [];

  /**
   * The scripted enum declaration used for this enum value.
   */
  private var _e:EnumDecl;

  /**
   * The value itself of the enum.
   */
  private var _value:String;

  /**
   * The arguments provided for this enum value.
   */
  private var _args:Array<Dynamic>;

  /**
   * The current list of using functions from other classes that this value is able to have.
   */
  public var usingFunctionsCache:Map<String, Array<Dynamic>->Dynamic> = [];

  public function new(e:EnumDecl, value:String, args:Array<Dynamic>)
  {
    this._e = e;

    var field = getField(value);

    if (field == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, '${e.name}.${value} does not exist.', SCRIPT_RUNTIME);
      return;
    }

    this._value = value;

    if (args.length != field.args.length)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, '${e.name}.${value} got the wrong number of arguments.', SCRIPT_RUNTIME);
      return;
    }

    this._args = args;

    buildUsingCache();
  }

  /**
   * Attempts to retrieve the full package of a scripted enum.
   * @param id The id to and find.
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

  public static function clearScriptedEnums():Void
  {
    @:privateAccess
    Interp._scriptEnumDescriptors.clear();
    _staticUsingFunctionsCache.clear();
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

  private function getField(name:String):Null<EnumFieldDecl>
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

  public function toString():String
  {
    var result:String = '${_e.name}.${_value}';
    if (_args.length > 0) result += '(${_args.join(',')})';
    return result;
  }
}
