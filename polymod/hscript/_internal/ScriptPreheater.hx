package polymod.hscript._internal;

import polymod.Polymod;
import polymod.Polymod.PolymodErrorCode;
import polymod.Polymod.PolymodErrorOrigin;
import polymod.hscript._internal.Expr.EnumDecl;
import polymod.hscript._internal.Expr.ClassDecl;
import polymod.hscript._internal.Expr.ClassImport;
import polymod.hscript._internal.Expr.FieldDecl;
import polymod.hscript._internal.Expr.FunctionDecl;
import polymod.hscript._internal.Expr.VarDecl;
import polymod.hscript._internal.Printer;
import polymod.util.Util;

using Lambda;
using StringTools;

@:access(polymod.hscript._internal.Interp)
@:access(polymod.hscript._internal.PolymodScriptClass)
class ScriptPreheater
{
  /**
   * Check registered script classes without executing their code.
   * Unknown identifiers and statically-resolvable member accesses are reported as errors,
   * but do not interrupt mod loading.
   */
  public static function run():Void
  {
    var assigned = new Map<String, Map<String, Bool>>();
    var issues:Array<String> = [];
    var checked = 0;
    var count = 0;

    for (name => decl in Interp._scriptClassDescriptors)
    {
      var fields:Map<String, Bool> = new Map();
      for (field in decl.fields) switch (field.kind)
      {
        case KFunction(fn) if (fn.expr != null):
          collectPreheatAssignments(fn.expr, fields);
        case KFunction(_):
        case KVar(v):
          if (v.expr != null) collectPreheatAssignments(v.expr, fields);
      }
      assigned.set(name, fields);
    }

    for (name => decl in Interp._scriptClassDescriptors)
    {
      count++;
      for (field in decl.staticFields) switch (field.kind)
      {
        case KFunction(fn) if (fn.expr != null):
          try
            PolymodScriptClass.scriptInterp.getScriptClassStaticField(name, field.name)
          catch (error:Dynamic)
          {
            issues.push(
              'Script preheat error in ${name}: could not prepare static method ${field.name} (${preheatPosition(fn.expr, name)}): ${Std.string(error)}'
            );
          }
        case KFunction(_):
        case KVar(_):
      }

      for (field in decl.fields.concat(decl.staticFields))
      {
        var isStatic = field.access.contains(AStatic);
        switch (field.kind)
        {
          case KFunction(fn) if (fn.expr != null):
            var locals:Map<String, Bool> = new Map();
            for (arg in fn.args) locals.set(arg.name, true);
            var stats = {
              checked: 0
            };
            preheatWalk(fn.expr, decl, name, isStatic, locals, assigned, issues, stats);
            checked += stats.checked;
          case KFunction(_):
          case KVar(v) if (v.expr != null):
            var stats = {
              checked: 0
            };
            preheatWalk(v.expr, decl, name, isStatic, new Map(), assigned, issues, stats);
            checked += stats.checked;
          case KVar(_):
        }
      }
    }

    if (issues.length > 0) Polymod.error(PolymodErrorCode.SCRIPT_PREHEAT_ERROR, issues.join('\n'), PolymodErrorOrigin.SCRIPT_RUNTIME);
    Polymod.info(
      PolymodErrorCode.SCRIPT_PREHEAT_DONE,
      'Script preheat finished: ${count} classes, ${checked} identifier/member checks completed, ${issues.length} error(s).',
      PolymodErrorOrigin.SCRIPT_RUNTIME
    );
  }

  static function collectPreheatAssignments(expr:Expr, fields:Map<String, Bool>):Void
  {
    switch (Tools.expr(expr))
    {
      case EBinop(op, target, _) if ([
        '=',
        '+=',
        '-=',
        '*=',
        '/=',
        '%=',
        '&=',
        '|=',
        '^=',
        '<<=',
        '>>=',
        '>>>='
      ].contains(op)):
        switch (Tools.expr(target))
        {
          case EField(receiver, name):
            if ( switch (Tools.expr(receiver))
              {
                case EIdent('this'):
                  true;
                default:
                  false;
              }) fields.set(name, true);
          default:
        }
      default:
    }
    Tools.iter(expr, child -> collectPreheatAssignments(child, fields));
  }

  static function preheatWalk(expr:Expr,
    owner:ClassDecl,
    ownerName:String,
    isStatic:Bool,
    locals:Map<String, Bool>,
    assigned:Map<String, Map<String, Bool>>,
    issues:Array<String>,
    stats:
      {checked:Int},
    skipRoot:Bool = false):Void
  {
    switch (Tools.expr(expr))
    {
      case EIdent(name):
        if (!skipRoot)
        {
          stats.checked++;
          if (!preheatIdentifierExists(
            name,
            owner,
            ownerName,
            isStatic,
            locals,
            assigned
          )) issues.push('Script preheat error in ${ownerName}: unresolved identifier "${name}" (${preheatPosition(expr, ownerName)}).');
        }
      case EField(target, field):
        switch (Tools.expr(target))
        {
          case EIdent('this'):
            if (
              isStatic
              || !preheatHasMember(ownerName, field, false, true, assigned)
            ) issues.push('Script preheat error in ${ownerName}: invalid instance access "this.${field}" (${preheatPosition(expr, ownerName)}).');
            stats.checked++;
          case EIdent('super'):
            if (
              isStatic
              || !preheatHasMember(ownerName, field, false, false, assigned)
            ) issues.push('Script preheat error in ${ownerName}: invalid superclass access "super.${field}" (${preheatPosition(expr, ownerName)}).');
            stats.checked++;
          default:
            var targetClass = preheatClassPath(target, owner, ownerName, locals);
            if (
              targetClass != null
              && field != 'scriptInit'
              && field != 'listScriptClasses'
              && !preheatHasMember(targetClass, field, true, true, assigned)
            ) issues.push('Script preheat error in ${ownerName}: missing static member "${targetClass}.${field}" (${preheatPosition(expr, ownerName)}).');
            stats.checked++;
        }
        preheatWalk(target, owner, ownerName, isStatic, locals, assigned, issues, stats, true);
      case EBlock(expressions):
        var scope = preheatCopyLocals(locals);
        for (item in expressions)
        {
          preheatWalk(item, owner, ownerName, isStatic, scope, assigned, issues, stats);
          switch (Tools.expr(item))
          {
            case EVar(name, _, _) | EFinal(name, _, _):
              scope.set(name, true);
            case EFunction(_, _, name, _) if (name != null):
              scope.set(name, true);
            default:
          }
        }
      case EVar(_, _, value) | EFinal(_, _, value):
        if (value != null) preheatWalk(value, owner, ownerName, isStatic, locals, assigned, issues, stats);
      case EFunction(args, body, name, _):
        var scope = preheatCopyLocals(locals);
        if (name != null) scope.set(name, true);
        for (arg in args)
        {
          if (arg.value != null) preheatWalk(arg.value, owner, ownerName, isStatic, scope, assigned, issues, stats);
          scope.set(arg.name, true);
        }
        preheatWalk(body, owner, ownerName, isStatic, scope, assigned, issues, stats);
      case EFor(name, iterator, body):
        preheatWalk(iterator, owner, ownerName, isStatic, locals, assigned, issues, stats);
        var scope = preheatCopyLocals(locals);
        scope.set(name, true);
        preheatWalk(body, owner, ownerName, isStatic, scope, assigned, issues, stats);
      case EForGen(iterator, body):
        Tools.getKeyIterator(iterator, function(key, value, actualIterator)
        {
          preheatWalk(actualIterator, owner, ownerName, isStatic, locals, assigned, issues, stats);
          var scope = preheatCopyLocals(locals);
          if (key != null) scope.set(key, true);
          if (value != null) scope.set(value, true);
          preheatWalk(body, owner, ownerName, isStatic, scope, assigned, issues, stats);
          return true;
        });
      case ETry(body, catches):
        preheatWalk(body, owner, ownerName, isStatic, locals, assigned, issues, stats);
        for (catcher in catches)
        {
          var scope = preheatCopyLocals(locals);
          scope.set(catcher.name, true);
          preheatWalk(catcher.e, owner, ownerName, isStatic, scope, assigned, issues, stats);
        }
      case EArray(target, index):
        preheatWalk(target, owner, ownerName, isStatic, locals, assigned, issues, stats, true);
        preheatWalk(index, owner, ownerName, isStatic, locals, assigned, issues, stats);
      default:
        Tools.iter(expr, child -> preheatWalk(child, owner, ownerName, isStatic, locals, assigned, issues, stats));
    }
  }

  static function preheatCopyLocals(source:Map<String, Bool>):Map<String, Bool>
  {
    var copy:Map<String, Bool> = new Map();
    for (name in source.keys()) copy.set(name, true);
    return copy;
  }

  static function preheatIdentifierExists(name:String,
    owner:ClassDecl,
    ownerName:String,
    isStatic:Bool,
    locals:Map<String, Bool>,
    assigned:Map<String, Map<String, Bool>>):Bool
  {
    if (name == 'null' || name == 'true' || name == 'false' || name == 'trace') return true;
    if (name == 'this' || name == 'super') return !isStatic && (name != 'super' || owner.extend != null);
    if (
      locals.exists(name)
      || (PolymodScriptClass.scriptInterp.variables != null && PolymodScriptClass.scriptInterp.variables.exists(name))
      || (PolymodScriptClass.scriptInterp.functions != null && PolymodScriptClass.scriptInterp.functions.exists(name))
    ) return true;
    if ((owner.imports != null && owner.imports.exists(name)) || (owner.importsToValidate != null && owner.importsToValidate.exists(name))) return true;
    if (name == owner.name || name == ownerName || name == Util.getFullClassName(owner)) return true;
    if (
      Interp._scriptClassDescriptors.exists(name)
      || Interp._scriptInterfaceDescriptors.exists(name)
      || Interp._scriptEnumDescriptors.exists(name)
    ) return true;

    var pkg = owner.pkg == null ? '' : owner.pkg.join('.');
    if (
      pkg.length > 0
      && (
        Interp._scriptClassDescriptors.exists('${pkg}.${name}')
        || Interp._scriptInterfaceDescriptors.exists('${pkg}.${name}')
        || Interp._scriptEnumDescriptors.exists('${pkg}.${name}')
      )
    ) return true;
    if (Type.resolveClass(name) != null || Type.resolveEnum(name) != null) return true;

    if (owner.imports != null) for (imp in owner.imports)
    {
      if (imp.enm != null && Type.getEnumConstructs(imp.enm).contains(name)) return true;
      var enm = Interp._scriptEnumDescriptors.get(imp.fullPath);
      if (enm != null && enm.fields.exists(field -> field.name == name)) return true;
    }
    if (pkg.length > 0) for (enm in Interp._scriptEnumDescriptors) if (
      enm.pkg != null
      && enm.pkg.join('.') == pkg
      && enm.fields.exists(field -> field.name == name)
    ) return true;

    return preheatHasMember(ownerName, name, true, true, assigned) || (!isStatic && preheatHasMember(ownerName, name, false, true, assigned));
  }

  static function preheatHasMember(className:String,
    name:String,
    isStatic:Bool,
    includeCurrent:Bool,
    assigned:Map<String, Map<String, Bool>>):Bool
  {
    var current = Interp._scriptClassDescriptors.get(className);
    var currentName = className;
    var depth = 0;
    var printer = new Printer();
    while (current != null && depth++ < 64)
    {
      if (includeCurrent)
      {
        for (field in (isStatic ? current.staticFields : current.fields)) if (field.name == name) return true;
        var ownAssignments = assigned.get(currentName);
        if (!isStatic && ownAssignments != null && ownAssignments.exists(name)) return true;
        if (currentName == className && ['superClass', 'createSuperClass', 'findFunction', 'callFunction'].contains(name)) return true;
      }
      if (current.extend == null) return false;
      var superPath = printer.typeToString(current.extend);
      var superName = switch (current.extend)
      {
        case CTPath(path, _):
          path.length == 0 ? superPath : path[path.length - 1];
        default:
          superPath;
      };
      var imported = current.imports == null ? null : current.imports.get(superName);
      var fullPath = imported != null ? imported.fullPath : superPath;
      if (!Interp._scriptClassDescriptors.exists(fullPath) && fullPath.indexOf('.') == -1 && current.pkg != null)
      {
        var localPath = current.pkg.concat([fullPath]).join('.');
        if (Interp._scriptClassDescriptors.exists(localPath)) fullPath = localPath;
      }
      var parent = Interp._scriptClassDescriptors.get(fullPath);
      if (parent != null)
      {
        current = parent;
        currentName = fullPath;
        includeCurrent = true;
        continue;
      }
      var nativeClass:Null<Class<Dynamic>> = imported == null ? null : imported.cls;
      if (nativeClass == null) nativeClass = PolymodScriptClass.importOverrides.get(superPath);
      if (nativeClass == null) nativeClass = Type.resolveClass(superPath);
      if (nativeClass == null) nativeClass = Type.resolveClass(fullPath);
      if (nativeClass == null) return true;
      while (nativeClass != null)
      {
        var nativeFields = isStatic ? Type.getClassFields(nativeClass) : Type.getInstanceFields(nativeClass);
        if (nativeFields.contains(name) || (!isStatic && (nativeFields.contains('get_${name}') || nativeFields.contains('set_${name}')))) return true;
        nativeClass = Type.getSuperClass(nativeClass);
      }
      return false;
    }
    return current != null;
  }

  static function preheatClassPath(expr:Expr, owner:ClassDecl, ownerName:String, locals:Map<String, Bool>):Null<String>
  {
    var path = preheatDottedPath(expr);
    if (path == null || locals.exists(path.split('.')[0])) return null;
    if (path == owner.name || path == ownerName) return ownerName;
    if (Interp._scriptClassDescriptors.exists(path)) return path;
    if (path.indexOf('.') == -1)
    {
      var imported = owner.imports == null ? null : owner.imports.get(path);
      if (imported != null && imported.field != true && Interp._scriptClassDescriptors.exists(imported.fullPath)) return imported.fullPath;
      var pkg = owner.pkg == null ? '' : owner.pkg.join('.');
      var localPath = pkg.length == 0 ? path : '${pkg}.${path}';
      if (Interp._scriptClassDescriptors.exists(localPath)) return localPath;
    }
    return null;
  }

  static function preheatDottedPath(expr:Expr):Null<String>
  {
    return switch (Tools.expr(expr))
    {
      case EIdent(name):
        name;
      case EField(parent, field):
        var prefix = preheatDottedPath(parent);
        prefix == null ? null : '${prefix}.${field}';
      case EParent(inner):
        preheatDottedPath(inner);
      default:
        null;
    }
  }

  static function preheatPosition(expr:Expr, className:String):String
  {
    #if hscriptPos
    return '${expr.origin}:${expr.line}';
    #else
    return className;
    #end
  }
}
