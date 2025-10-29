package polymod.hscript._internal;

#if hscript_typer
import hscript.Expr;
import hscript.typer.Typer;
import hscript.typer.TypedExpr;

class PolymodTyperEx extends Typer 
{
  static var allModules:Array<TyperModule> = [];

  var blacklistImports:Array<String>;
  var aliasPaths:Map<String, String>;
  var defaultImports:Map<String, CType>;

  public static function clearAllModules():Void 
  {
    allModules = [];
  }

  public static function typeAllModules():Array<TypedModuleDecl> 
  {
    return new PolymodTyperEx(new PolymodInterpEx(null, null)).typeModules(allModules);
  }

  public function new(interp:PolymodInterpEx) 
  {
    super(interp);

    blacklistImports = [];
    aliasPaths = new Map<String, String>();
    for (k => imp in PolymodScriptClass.importOverrides) 
    {
      if (imp == null) 
        blacklistImports.push(k);
      else
        aliasPaths.set(k, Type.getClassName(imp));
    }
    for (k => imp in PolymodScriptClass.abstractClassImpls) 
    {
			aliasPaths.set(k, Type.getClassName(imp));
    }

    defaultImports = new Map<String, CType>();
    for (k => imp in PolymodScriptClass.defaultImports) 
    {
      defaultImports.set(k, CTPath([Type.getClassName(imp)], null));
    }
  }

  override function resolveType(path:String):Null<Dynamic>
  {
    if (blacklistImports.contains(path)) moduleError('"${path}" is a blacklisted type');
    path = aliasPaths.get(path) ?? path;

    var pathSplit:Array<String> = path.split('.');
    if (pathSplit.length == 1)
    {
      var imp:Null<CType> = imports.get(path) ?? defaultImports.get(path);
      if (imp != null)
      {
        switch (imp)
        {
          case CTPath(path, null):
            var path:String = path.join('.');
            if (blacklistImports.contains(path)) moduleError('"${path}" is a blacklisted type');
            path = aliasPaths.get(path) ?? path;
            var type:Null<Dynamic> = null;
            type ??= Type.resolveClass(path);
            type ??= Type.resolveEnum(path);
            type ??= scriptedTypes.get(path);
            if (type != null) return type;

          default:
            throw 'Should not happen: ${imp}';
        }
      }

      for (pack in everythingImports)
      {
        var path:String = pack.concat([path]).join('.');
        if (blacklistImports.contains(path)) moduleError('"${path}" is a blacklisted type');
        path = aliasPaths.get(path) ?? path;
        var type:Null<Dynamic> = null;
        type ??= Type.resolveClass(path);
        type ??= Type.resolveEnum(path);
        type ??= scriptedTypes.get(path);
        if (type != null) return type;
      }
    }

    var type:Null<Dynamic> = null;
    type ??= Type.resolveClass(path);
    type ??= Type.resolveEnum(path);
    type ??= scriptedTypes.get(path);

    return type;
  }
}
#end
