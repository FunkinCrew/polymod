package polymod.hscript._internal;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.rtti.Meta;

class PolymodFinalMacro
{
  private static var _allFinals:Map<String, Array<String>> = null;

  public static function getAllFinals():Map<String, Array<String>>
  {
    // if (_allFinals == null)
    //   _allFinals = PolymodFinalMacro.fetchAllFinals();
    // return _allFinals;
    return [];
  }

  public static macro function locateAllFinals():Void
  {
    Context.onAfterTyping((types) ->
    {
      if (calledBefore)
        return;

      var allFinals:Array<Expr> = [];

      for (type in types)
      {
        switch (type)
        {
          case TClassDecl(t):
            var classType:ClassType = t.get();
            var classPath:String = t.toString();
            if (classType.isInterface) continue;

            var finals:Array<String> = [];
            for (field in classType.statics.get())
            {
              if (!field.isFinal) continue;
              finals.push(field.name);
            }

            if (finals.length == 0) continue;

            var entryData = [
              macro $v{classPath},
              macro $v{finals}
            ];

            allFinals.push(macro $a{entryData});
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
          finalMacroClassType.meta.add('finals', allFinals, Context.currentPos());
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
        if (element.length != 2)
          throw 'Malformed element in finals: ' + element;

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
}
