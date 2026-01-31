package polymod.format;

import thx.semver.VersionRule;

class JsonHelp
{
  public static function bool(json:Dynamic, field:String, defaultValue:Bool = false):Bool
  {
    var str:String = '';
    if (Reflect.hasField(json, field)) str = Reflect.field(json, field);
    if (str == null || str == '') return defaultValue;
    str = str.toLowerCase();
    if (str == 'true') return true;
    return false;
  }

  public static function int(json:Dynamic, field:String, defaultValue:Int = 0):Int
  {
    var str:String = '';
    if (Reflect.hasField(json, field)) str = Reflect.field(json, field);
    if (str == null || str == '') return defaultValue;
    var i = Std.parseInt(str);
    if (i == null) return defaultValue;
    return i;
  }

  public static function float(json:Dynamic, field:String, defaultValue:Float = 0):Float
  {
    var str:String = '';
    if (Reflect.hasField(json, field)) str = Reflect.field(json, field);
    if (str == null || str == '') return defaultValue;
    var f = Math.NaN;
    try
    {
      f = Std.parseFloat(str);
    }
    catch (msg:Dynamic)
    {
      f = Math.NaN;
    }
    if (Math.isNaN(f)) return defaultValue;
    return f;
  }

  public static function mapStr(json:Dynamic, field:String):Map<String, String>
  {
    var map:Map<String, String> = new Map<String, String>();
    if (json == null || field == '' || field == null) return map;
    var val = null;
    if (Reflect.hasField(json, field)) val = Reflect.field(json, field);
    if (val != null)
    {
      for (field in Reflect.fields(val))
      {
        var fieldVal = Reflect.field(val, field);
        map.set(field, Std.string(fieldVal));
      }
    }
    return map;
  }

  public static function mapVersionRule(json:Dynamic, field:String):Map<String, VersionRule>
  {
    var map:Map<String, VersionRule> = new Map<String, VersionRule>();
    if (json == null || field == '' || field == null) return map;
    var val = null;
    if (Reflect.hasField(json, field)) val = Reflect.field(json, field);
    if (val != null)
    {
      for (field in Reflect.fields(val))
      {
        var fieldVal = Reflect.field(val, field);
        map.set(field, VersionRule.stringToVersionRule(fieldVal));
      }
    }
    return map;
  }

  public static function str(json:Dynamic, field:String, defaultValue:String = ''):String
  {
    var str:String = '';
    if (Reflect.hasField(json, field)) str = Reflect.field(json, field);
    if (str == null || str == '') return defaultValue;
    return str;
  }

  public static function type<T>(json:Dynamic, field:String, defaultValue:T = null):T
  {
    var value:T = null;
    if (Reflect.hasField(json, field)) value = Reflect.field(json, field);
    if (value == null) return defaultValue;
    return value;
  }

  public static function arrType<T>(json:Dynamic, field:String, defaultValue:Array<T> = null):Array<T>
  {
    var val:Array<T> = null;
    if (Reflect.hasField(json, field)) val = Reflect.field(json, field);
    if (val != null && Std.isOfType(val, Array))
    {
      return cast val;
    }
    return defaultValue;
  }

  public static function arrStr(json:Dynamic, field:String, defaultValue:Array<String> = null):Array<String>
  {
    var val = null;
    if (Reflect.hasField(json, field)) val = Reflect.field(json, field);
    if (val != null && Std.isOfType(val, Array))
    {
      return cast val;
    }
    return defaultValue;
  }
}
