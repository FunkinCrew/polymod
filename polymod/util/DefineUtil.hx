package polymod.util;

#if macro
import haxe.macro.Context;
#end

class DefineUtil
{
  // Only macros should be able to use these.
  #if macro
  public static function getDefinesRaw()
  {
    return Context.getDefines();
  }

  public static function getDefineStringArrayRaw(key:String, ?defaultValue:Array<String>):Array<String>
  {
    if (defaultValue == null) defaultValue = new Array<String>();
    var value = Context.definedValue(key);
    return value == null ? defaultValue : value.split(',');
  }

  public static function getDefineStringRaw(key:String, defaultValue:String = ''):String
  {
    var value = Context.definedValue(key);
    return value == null ? defaultValue : value;
  }

  public static function getDefineBoolRaw(key:String, defaultValue:Bool = false):Bool
  {
    var value:String = getDefineStringRaw(key);
    return value == '' ? defaultValue : (value == 'true' || value == '1');
  }
  #end

  public static macro function getDefineStringArray(key:String, ?defaultValue:Array<String>):haxe.macro.Expr
  {
    return macro $v{getDefineStringArrayRaw(key, defaultValue)};
  }

  public static macro function getDefineString(key:String, defaultValue:String = ''):haxe.macro.Expr
  {
    return macro $v{getDefineStringRaw(key, defaultValue)};
  }

  public static macro function getDefineBool(key:String, defaultValue:Bool = false):haxe.macro.Expr
  {
    return macro $v{getDefineBoolRaw(key, defaultValue)};
  }

  public static macro function getDefines():haxe.macro.Expr
  {
    return macro $v{getDefinesRaw()};
  }
}
