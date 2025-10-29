package polymod.hscript._internal;

#if hscript
import hscript.Parser;
import hscript.Expr;

#if hscript_typer
@:access(polymod.hscript._internal.PolymodTyperEx)
#end
class PolymodParserEx extends Parser
{
	#if (hscript > "2.5.0")
	public override function parseModule(content:String, ?origin:String = "hscript", ?position = 0)
	#else
	public override function parseModule(content:String, ?origin:String = "hscript")
	#end
	{
		#if (hscript > "2.5.0")
		var decls:Array<ModuleDecl> = super.parseModule(content, origin, position);
		#else
		var decls:Array<ModuleDecl> = super.parseModule(content, origin);
		#end
		#if hscript_typer
		PolymodTyperEx.allModules.push({
			decls: decls,
			code: content,
			origin: origin,
		});
		#end
		return decls;
	}
}
#end
