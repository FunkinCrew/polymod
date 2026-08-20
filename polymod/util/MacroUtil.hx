package polymod.util;

import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

class MacroUtil
{
  #if macro
  public static function listSuperInterfaces(classType:ClassType):Array<String>
  {
    if (!classType.isInterface) return [];

    var superInterfaces:Array<String> = [];
    for (i in classType.interfaces)
    {
      superInterfaces.push(i.t.toString());

      // Will recursively do this until there's no nothing extends.
      var extend:Array<String> = listSuperInterfaces(i.t.get());
      for (e in extend)
      {
        if (!superInterfaces.contains(e))
          superInterfaces.push(e);
      }
    }
    return superInterfaces;
  }

  public static function implementsInterface(classType:ClassType, interfaceType:ClassType):Bool
  {
    for (i in classType.interfaces)
    {
      if (areClassesEqual(i.t.get(), interfaceType))
      {
        return true;
      }
    }

    if (classType.superClass != null)
    {
      return implementsInterface(classType.superClass.t.get(), interfaceType);
    }

    return false;
  }

  /**
   * Retrieve a ClassType from a string name.
   */
  public static function getClassType(name:String):ClassType
  {
    switch (Context.getType(name))
    {
      case TInst(t, _params):
        return t.get();
      default:
        throw 'Class type could not be parsed: ${name}';
    }
  }

	public static function nullable(complexType : ComplexType):ComplexType {
    return macro: Null<$complexType>;
  }

  public static function areClassesEqual(class1:ClassType, class2:ClassType):Bool
  {
    return class1.pack.join('.') == class2.pack.join('.') && class1.name == class2.name;
  }
  #end
}
