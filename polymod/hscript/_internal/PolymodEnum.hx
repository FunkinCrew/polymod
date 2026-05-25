package polymod.hscript._internal;

import polymod.hscript._internal.Expr;

@:allow(polymod.Polymod)
class PolymodEnum
{
  private static final scriptInterp = new Interp(null, null);

  private var _e:EnumDecl;

  private var _value:String;

  private var _args:Array<Dynamic>;

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
  }

  public static function clearScriptedEnums():Void
  {
    scriptInterp.clearScriptEnumDescriptors();
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
