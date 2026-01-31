package polymod.hscript._internal;

import polymod.hscript._internal.Parser;
import polymod.hscript._internal.Expr;

#if hscript_typer
@:access(polymod.hscript._internal.PolymodTyperEx)
#end
class PolymodParserEx extends Parser
{
  public override function parseModule(content:String, ?origin:String = "hscript", ?position = 0)
  {
    var decls:Array<ModuleDecl> = super.parseModule(content, origin, position);
    #if hscript_typer
    PolymodTyperEx.allModules.push(
      {
        decls: decls,
        code: content,
        origin: origin,
      });
    #end
    return decls;
  }
}
