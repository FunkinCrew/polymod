package polymod.hscript._internal;

#if (!macro && hl)
@:build(polymod.hscript._internal.HLWrapperMacro.buildWrapperClass())
class HLMath extends Math {}

@:build(polymod.hscript._internal.HLWrapperMacro.buildWrapperClass())
@:haxe.warning("-WDeprecated")
class HLStd extends Std
{
  public static function is(v:Dynamic, t:Dynamic)
    return isOfType(v, t);

  public static function isOfType(v:Dynamic, t:Dynamic):Bool
  {
    // HL oddly uses hl.Bytes for strings sometimes
    // We do a hack since we can't just do isOfType(v, hl.Bytes)
    if (t == String && !Std.isOfType(v, String))
    {
      function bytesTest(_:hl.Bytes) {}
      try
      {
        bytesTest(v);
        return true;
      }
      catch (_)
      {
        return false;
      }
    }

    return Std.isOfType(v, t);
  }
}
#else
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using Lambda;
using haxe.macro.TypeTools;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using StringTools;

/**
 * Macro that generates wrapper fields for substitutes of `std` classes to make them available to Reflection.
 * Currently only works for static fields.
 */
class HLWrapperMacro
{
  public static macro function buildWrapperClass():Array<Field>
  {
    var localClass = Context.getLocalClass().get();
    var superClass = localClass.superClass;
    if (superClass == null) throw 'Class ${localClass.name} does not extend class it wants to wrap';
    var cls = superClass.t.get();
    var buildFields = Context.getBuildFields();

    for (field in cls.statics.get())
    {
      if (field.isPublic && !buildFields.exists((f) -> f.name == field.name))
      {
        var wrapper = generateWrapper(field, cls);
        if (wrapper != null) buildFields.push(wrapper);
      }
    }
    buildFields.push(generateToString(cls));

    return buildFields;
  }

  static function generateWrapper(field:ClassField, cls:ClassType):Null<Field>
  {
    if (field == null) throw 'Field is null';

    var newField:Field =
      {
        name: field.name,
        doc: field.doc,
        meta: null,
        pos: field.pos,
        access: [APublic, AStatic, AInline],
        kind: null
      };

    function populateNewField(t:Type):Bool
    {
      return switch (t)
      {
        case TLazy(lz):
          var ty = lz();
          return populateNewField(ty);
        case TFun(args, ret):
          var funcArgs:Array<FunctionArg> = [
            for (arg in args)
              {
                name: arg.name,
                opt: arg.opt,
                type: Context.toComplexType(arg.t)
              }
          ];
          var ret = Context.toComplexType(ret);
          var callArgs:Array<Expr> = [for (arg in funcArgs) macro $i{arg.name}];
          var funcParams:Array<TypeParamDecl> = [for (p in field.params) {name: p.name, constraints: getConstraints(p.t)}];
          var body:Expr = macro $p{[cls.name, field.name]}($a{callArgs});

          newField.kind = FFun(
            {
              args: funcArgs,
              params: funcParams,
              ret: ret,
              expr: doesReturnVoid(ret) ? (macro $body) : (macro return $body)
            });
          return true;
        default: false;
      }
    }

    if (populateNewField(field.type))
    {
      return newField;
    }
    else if (field.expr() == null)
    {
      var overKind = switch (field.kind)
      {
        case FVar(_, _):
          // We're overriding a VARIABLE, it shouldn't be modifiable
          FieldType.FProp('default', 'null', Context.toComplexType(field.type), macro $p{[cls.name, field.name]});
        default: throw "Not implemented!";
      }

      return {
        name: field.name,
        doc: field.doc,
        meta: field.meta.get(),
        pos: field.pos,
        access: [APublic, AStatic],
        kind: overKind
      };
    }

    return null;
  }

  static function generateToString(cls:ClassType):Field
  {
    return {
      name: 'toString',
      access: [APublic],
      pos: cls.pos,
      kind: FFun(
        {
          args: [],
          ret: macro :String,
          expr: macro return $v{cls.name}
        })
    };
  }

  static function getConstraints(t:Type)
  {
    return switch (t)
    {
      case TInst(_.get() => c, _):
        switch (c.kind)
        {
          case KTypeParameter(consts): [for (c in consts) Context.toComplexType(c)];
          default: throw 'Invalid class kind, it is not a TypeParameter';
        }
      case _: throw '$t has not been implemented!';
    }
  }

  static inline function doesReturnVoid(rt:ComplexType)
  {
    return switch (rt)
    {
      case TPath(tp): tp.name == "Void";
      default: false;
    }
  }
}
#end
