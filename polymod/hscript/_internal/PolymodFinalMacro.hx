package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#else
import polymod.util.Util;
#end
import haxe.rtti.Meta;

@:nullSafety
class PolymodFinalMacro
{
  #if !macro
  public static inline function getFinals(fullPath:String):Array<String> {
    return getAllFinals().get(fullPath) ?? [];
  }

  public static inline function getFinalsOf(obj:Dynamic):Array<String> {
    return getFinals(Util.getTypeNameOf(obj));
  }

  public static inline function getPrivateProperties(fullPath:String):Array<String> {
    return getAllPrivateProperties().get(fullPath) ?? [];
  }

  public static inline function getPrivatePropertiesOf(obj:Dynamic):Array<String> {
    return getFinals(Util.getTypeNameOf(obj));
  }

  private static var _allFinals:Null<Map<String, Array<String>>> = null;

  public static function getAllFinals():Map<String, Array<String>>
  {
    if (_allFinals == null) _allFinals = PolymodFinalMacro.fetchAllFinals();
    return _allFinals;
  }

  private static var _allPrivates:Null<Map<String, Array<String>>> = null;

  public static function getAllPrivateProperties():Map<String, Array<String>>
  {
    if (_allPrivates == null) _allPrivates = PolymodFinalMacro.fetchAllPrivateProperties();
    return _allPrivates;
  }
  #end

  public static macro function locateAllFinals():Void
  {
    Context.onAfterTyping((types) -> {
      if (calledBefore) return;

      var allFinals:Array<Expr> = [];
      var allPrivates:Array<Expr> = [];

      for (type in types)
      {
        switch (type)
        {
          case TClassDecl(t):
            var classType:ClassType = t.get();
            var classPath:String = t.toString();
            if (classType.isInterface) continue;

            var finals:Array<String> = [];
            var privates:Array<String> = [];
            for (field in classType.statics.get())
            {
              // Add final variables.
              if (field.isFinal) finals.push(field.name);

              // Add properties with `never`/`null` accessors.
              switch (field.kind) {
                case FVar(read, write):
                  switch (write) {
                    case AccNever:
                      finals.push(field.name);
                    case AccNo:
                      privates.push(field.name);
                    default: // Do nothing
                  }
                default: // Do nothing
              }
            }

            if (finals.length > 0) {
              var entryData = [macro $v{classPath}, macro $v{finals}];
              allFinals.push(macro $a{entryData});
            }

            if (privates.length > 0) {
              var entryData = [macro $v{classPath}, macro $v{privates}];
              allPrivates.push(macro $a{entryData});
            }

          default:
            continue;
        }
      }

      var finalMacroType:Type = Context.getType('polymod.hscript._internal.PolymodFinalMacro');

      switch (finalMacroType)
      {
        case TInst(t, _):
          var finalMacroClassType:ClassType = t.get();
          finalMacroClassType.meta.remove('finals');
          finalMacroClassType.meta.remove('privates');
          finalMacroClassType.meta.add('finals', allFinals, Context.currentPos());
          finalMacroClassType.meta.add('privates', allPrivates, Context.currentPos());
        default:
          throw 'Could not find PolymodFinalMacro type';
      }

      calledBefore = true;
    });
  }

  #if macro
  static var calledBefore:Bool = false;
  #end

  public static function fetchAllFinals():Map<String, Array<String>>
  {
    var metaData = Meta.getType(PolymodFinalMacro);

    if (metaData.finals != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in metaData.finals)
      {
        if (element.length != 2) throw 'Malformed element in finals: ' + element;

        var classPath:String = element[0];
        var finals:Array<String> = element[1];

        result.set(classPath, finals);
      }

      return result;
    }
    else
    {
      throw 'No finals found in PolymodFinalMacro';
    }
  }

  public static function fetchAllPrivateProperties():Map<String, Array<String>>
  {
    var metaData = Meta.getType(PolymodFinalMacro);

    if (metaData.privates != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in metaData.privates)
      {
        if (element.length != 2) throw 'Malformed element in privates: ' + element;

        var classPath:String = element[0];
        var privates:Array<String> = element[1];

        result.set(classPath, privates);
      }

      return result;
    }
    else
    {
      throw 'No private properties found in PolymodFinalMacro';
    }
  }
}
