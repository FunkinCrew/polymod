package polymod.hscript._internal;

#if hscript
import hscript.Expr;

typedef PolymodEnumDeclEx = 
{
    > EnumDecl,
    
    @:optional var pkg:Array<String>;
}

#end
