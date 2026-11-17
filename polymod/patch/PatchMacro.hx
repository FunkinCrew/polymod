package polymod.patch;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;

using StringTools;

/**
 * A macro that makes functions patchable. Patches can be added at runtime to change the behavior of a function.
 **/
class PatchMacro
{
  // Must match Patches.SLOT_PREFIX and Patches.ORIG_PREFIX. Not read from there so the macro context doesn't type Patches.
  public static final SLOT_PREFIX:String = '__patch_';
  public static final ORIG_PREFIX:String = '__orig_';

  static final ALWAYS_EXCLUDED:Array<String> = ['polymod', 'hl', 'haxe', 'cpp', 'sys'];

  static final SKIP_FIELD_META:Array<String> = [
    ':noPatch',
    ':generic',
    ':overload',
    ':native',
    ':functionCode',
    ':functionTailCode',
    ':extern',
    ':op',
    ':arrayAccess',
    ':resolve'
  ];

  static final DROP_ORIG_META:Array<String> = [':deprecated', ':inheritDoc', ':keep', ':allow', ':noCompletion'];

  static var includes:Null<Array<String>> = null;
  static var excludes:Null<Array<String>> = null;

  static function readList(define:String):Array<String>
  {
    var value:Null<String> = Context.definedValue(define);
    if (value == null) return [];
    return [for (part in value.split(',')) if (part.trim().length > 0) part.trim()];
  }

  static function matches(path:String, prefixes:Array<String>):Bool
  {
    for (prefix in prefixes)
      if (path == prefix || path.startsWith(prefix + '.')) return true;
    return false;
  }

  /**
   * Whether functions in this class should be made patchable.
   */
  public static function wantsClass(cls:ClassType):Bool
  {
    if (includes == null)
    {
      includes = readList('POLYMOD_PATCH');
      excludes = readList('POLYMOD_PATCH_EXCLUDE').concat(ALWAYS_EXCLUDED);
    }

    if (includes.length == 0) return false;

    // Skip contexts that require fast compiling and aren't actual runtime code.
    if (Context.defined('cppia') || Context.defined('display') || Context.defined('macro')) return false;

    if (cls.isInterface || cls.isExtern || cls.isPrivate) return false;
    if (!cls.kind.match(KNormal)) return false;
    if (cls.meta.has(':noPatch') || cls.meta.has(':coreApi') || cls.meta.has(':nativeGen') || cls.meta.has(':unreflective')) return false;

    var path:String = cls.pack.concat([cls.name]).join('.');
    return matches(path, includes) && !matches(path, excludes);
  }

  /**
   * Make every eligible function in the fields patchable.
   */
  public static function apply(cls:ClassType, fields:Array<Field>):Void
  {
    var classKey:String = cls.pack.concat([cls.name]).join('_');
    var added:Array<Field> = [];

    for (field in fields)
    {
      var f:Function = switch (field.kind)
      {
        case FFun(fn): fn;
        default: null;
      }
      if (f == null || !eligible(field, f)) continue;

      var isStatic:Bool = field.access.contains(AStatic);
      var slotName:String = SLOT_PREFIX + field.name;
      var origName:String = ORIG_PREFIX + classKey + '_' + field.name;
      var pos:Position = field.pos;

      added.push({
        name: slotName,
        access: [APublic, AStatic],
        meta: [{name: ':keep', pos: pos}, {name: ':noCompletion', pos: pos}],
        kind: FVar(macro :Null<polymod.patch.PatchSlot>, macro null),
        pos: pos
      });

      var origAccess:Array<Access> = [APrivate];
      var origMeta:Metadata = [for (m in field.meta ?? []) if (!DROP_ORIG_META.contains(m.name)) m];
      origMeta.push({name: ':noCompletion', pos: pos});
      if (isStatic)
      {
        origAccess.push(AStatic);
      }
      else
      {
        origAccess.push(AFinal);
        origMeta.push({name: ':nonVirtual', pos: pos});
      }

      added.push({
        name: origName,
        access: origAccess,
        meta: origMeta,
        kind: FFun({
          args: [for (arg in f.args) {name: arg.name, opt: arg.opt, type: arg.type, value: arg.value, meta: arg.meta}],
          ret: f.ret,
          expr: f.expr,
          params: f.params
        }),
        pos: pos
      });

      var argExprs:Array<Expr> = [for (arg in f.args) macro $i{arg.name}];
      var self:Expr = isStatic ? macro null : macro this;
      var bodyPos:Position = f.expr.pos;

      f.expr = returnsVoid(f) ? macro @:pos(bodyPos)
        {
          var __ps:Null<polymod.patch.PatchSlot> = $i{slotName};
          if (__ps != null)
          {
            polymod.patch.Patches.run(__ps, $self, [$a{argExprs}]);
            return;
          }
          $i{origName}($a{argExprs});
        } : macro @:pos(bodyPos)
        {
          var __ps:Null<polymod.patch.PatchSlot> = $i{slotName};
          if (__ps != null) return cast polymod.patch.Patches.run(__ps, $self, [$a{argExprs}]);
          return $i{origName}($a{argExprs});
        };
    }

    for (field in added)
      fields.push(field);
  }

  static function eligible(field:Field, f:Function):Bool
  {
    if (f.expr == null) return false;
    if (field.name == 'new') return false;
    if (field.name.startsWith('__')) return false;

    // Accessors read the physical field by name, which only works inside the accessor itself.
    if (field.name.startsWith('get_') || field.name.startsWith('set_')) return false;

    for (access in field.access)
    {
      switch (access)
      {
        case AInline | AMacro | AExtern | ADynamic:
          return false;
        default:
      }
    }

    if (f.params != null && f.params.length > 0) return false;

    for (m in field.meta ?? [])
      if (SKIP_FIELD_META.contains(m.name)) return false;

    for (arg in f.args)
    {
      switch (arg.type)
      {
        case TPath({name: 'Rest'}) | TPath({sub: 'Rest'}):
          return false;
        default:
      }
      if (isNativeType(arg.type)) return false;
    }
    if (isNativeType(f.ret)) return false;

    return true;
  }

  static final NATIVE_TYPES:Array<String> = [
    'RawPointer',
    'RawConstPointer',
    'Pointer',
    'ConstPointer',
    'Star',
    'ConstStar',
    'Struct',
    'Reference',
    'ConstCharStar',
    'CastCharStar'
  ];

  /**
   * Whether a type is a native type that can't be used in a patchable function.
   */
  static function isNativeType(type:Null<ComplexType>):Bool
  {
    return switch (type)
    {
      case null: false;
      case TPath(p):
        if (NATIVE_TYPES.contains(p.sub ?? p.name)) return true;
        for (param in p.params ?? [])
        {
          switch (param)
          {
            case TPType(t) if (isNativeType(t)): return true;
            default:
          }
        }
        false;
      default: false;
    }
  }

  static function returnsVoid(f:Function):Bool
  {
    if (f.ret != null)
    {
      return switch (f.ret)
      {
        case TPath({name: 'Void', pack: []}) | TPath({name: 'StdTypes', sub: 'Void'}): true;
        default: false;
      }
    }

    return findValidReturn(f.expr) == null;
  }

  static function findValidReturn(expr:Null<Expr>):Null<Expr>
  {
    if (expr == null || expr.expr == null) return null;

    return switch (expr.expr)
    {
      case EReturn(e) if (e != null): expr;
      case EIf(_, e1, e2): findValidReturn(e1) ?? findValidReturn(e2);
      case EMeta(_, e) | EParenthesis(e) | EUntyped(e): findValidReturn(e);
      case EBlock(exprs):
        var found:Null<Expr> = null;
        for (e in exprs)
        {
          found = findValidReturn(e);
          if (found != null) break;
        }
        found;
      case ESwitch(_, cases, def):
        var found:Null<Expr> = findValidReturn(def);
        if (found == null)
        {
          for (c in cases)
          {
            found = findValidReturn(c.expr);
            if (found != null) break;
          }
        }
        found;
      case ETry(e, catches):
        var found:Null<Expr> = findValidReturn(e);
        if (found == null)
        {
          for (c in catches)
          {
            found = findValidReturn(c.expr);
            if (found != null) break;
          }
        }
        found;
      case EFor(_, e) | EWhile(_, e, _): findValidReturn(e);
      default: null;
    }
  }
}
#end
