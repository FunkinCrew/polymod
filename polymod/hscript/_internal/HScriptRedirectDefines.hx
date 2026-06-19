package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Compiler;
import haxe.macro.Expr.TypeDefinition;

using StringTools;

/**
 * The macro for the `POLYMOD_REDIRECT_HSCRIPT` define functionality.
 */
class HScriptRedirectDefines
{
  static inline final DEFINE:String = 'POLYMOD_REDIRECT_HSCRIPT';

  /**
   * The entry point for the macro.
   * Performs the preparations for the function that actually redirects the types.
   */
  public static function run():Void
  {
    if (Context.defined('hscript') && Context.defined(DEFINE))
    {
      Context.warning('"$DEFINE" present but hscript is installed. Not doing anything.', Context.currentPos());
      return;
    }

    Compiler.define('hscript');
    Context.onTypeNotFound(generateHScriptRedirect);
  }

  /**
   * Returns a typedef where a referenced hscript type could not be found which redirects to a Polymod HScript class.
   * @param typeName
   * @return TypeDefinition
   */
  static function generateHScriptRedirect(typeName:String):Null<TypeDefinition>
  {
    if (!typeName.startsWith('hscript')) return null;

    final POLY_PACK:Array<String> = ['polymod', 'hscript', '_internal'];
    var typePack:Array<String> = typeName.split('.');
    var name:String = typePack.pop();

    return {
      pack: typePack,
      name: name,
      pos: Context.currentPos(),
      kind: TDAlias(TPath(
        {
          pack: POLY_PACK,
          name: name,
        })),
      fields: []
    };
  }
}
#end
