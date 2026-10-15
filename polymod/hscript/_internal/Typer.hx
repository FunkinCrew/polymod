package polymod.hscript._internal;

import polymod.Polymod;
import polymod.Polymod.PolymodErrorCode;
import polymod.Polymod.PolymodErrorOrigin;
import polymod.hscript._internal.Checker;
import polymod.hscript._internal.Expr;
import polymod.hscript._internal.Parser;
import polymod.util.Util;

using Lambda;
using StringTools;

@:access(polymod.hscript._internal.Interp)
@:access(polymod.hscript._internal.PolymodScriptClass)
class Typer
{
  public static function run():Bool
  {
    var issues:Array<String> = [];
    var checked = analyze(issues);
    if (issues.length > 0)
    {
      Polymod.error(PolymodErrorCode.SCRIPT_TYPE_ERROR, issues.join('\n'), PolymodErrorOrigin.SCRIPT_RUNTIME);
      return false;
    }

    Polymod.info(
      PolymodErrorCode.SCRIPT_TYPE_CHECK_DONE,
      'Script type checking finished: ${checked} declaration/body checks completed with no errors.',
      PolymodErrorOrigin.SCRIPT_RUNTIME
    );
    return true;
  }

  public static function runWithIssues(issues:Array<String>):Int
  {
    return analyze(issues);
  }

  static function analyze(issues:Array<String>):Int
  {
    var types = new CheckerTypes();
    var checked = 0;

    types.loadRuntimeAliases();

    // Register every scripted type before filling any signatures. This allows forward references and mutually-recursive classes to be checked
    for (name => decl in Interp._scriptClassDescriptors)
      types.defineClass(name);

    for (name => decl in Interp._scriptInterfaceDescriptors)
    {
      var interfaceType = types.defineClass(name);
      interfaceType.isInterface = true;
    }

    for (name => decl in Interp._scriptEnumDescriptors)
      types.defineEnum(name);

    registerScriptEnumSignatures(types, issues);
    registerScriptClassSignatures(types, issues);
    validateOverrideSignatures(types, issues);

    var methodBodies:Array<{owner:String, decl:ClassDecl, field:FieldDecl}> = [];
    for (name => decl in Interp._scriptClassDescriptors)
    {
      configureAliases(types, decl);
      var cls = getClass(types, name);
      if (cls == null) continue;

      for (field in decl.fields.concat(decl.staticFields))
      {
        switch (field.kind)
        {
          case KFunction(fn) if (fn.expr != null):
            methodBodies.push({owner: name, decl: decl, field: field});
          case KFunction(_):
          case KVar(v) if (v.expr != null):
            var checker = new Checker(types);
            checker.currentClassName = name;
            configureCheckerGlobals(checker, types, decl, cls, field.access.contains(AStatic));
            var target = findMemberType(cls, field.name, field.access.contains(AStatic));
            if (target != null)
            {
              try
              {
                checker.checkExpected(v.expr, target.t);
                if (v.type == null)
                {
                  var inferredType = checker.follow(target.t);
                  v.type = typeToSourceType(inferredType);
                }
                checked++;
              }
              catch (error:Dynamic)
              {
                issues.push(formatIssue(name, field.name, v.expr, 'initializer type error: ${Std.string(error)}'));
              }
            }
          case KVar(_):
        }
      }
    }

    for (pass in 0...2)
    {
      for (entry in methodBodies)
      {
        configureAliases(types, entry.decl);
        var cls = getClass(types, entry.owner);
        if (cls == null) continue;
        var isStatic = entry.field.access.contains(AStatic);
        var fn = switch (entry.field.kind)
        {
          case KFunction(value): value;
          default: null;
        };
        if (fn == null || fn.expr == null) continue;

        var member = !isStatic && entry.field.name == 'new' ? cls.constructor : findMemberType(cls, entry.field.name, isStatic);
        if (member == null) continue;

        var checker = new Checker(types);
        checker.currentClassName = entry.owner;
        checker.allowAsync = true;
        configureCheckerGlobals(checker, types, entry.decl, cls, isStatic);
        try
        {
          checker.checkFunction(fn.args, fn.expr, entry.field.name, fn.ret, member.t);
          if (pass == 1)
          {
            switch (checker.follow(member.t))
            {
              case TFun(signatureArgs, signatureReturn):
                for (i in 0...fn.args.length)
                {
                  if (fn.args[i].t == null && i < signatureArgs.length)
                    fn.args[i].t = typeToSourceType(checker.follow(signatureArgs[i].t));
                }
                if (fn.ret == null) fn.ret = typeToSourceType(checker.follow(signatureReturn));
              default:
            }
          }
          checked++;
        }
        catch (error:Dynamic)
        {
          if (pass == 1)
            issues.push(formatIssue(entry.owner, entry.field.name, fn.expr, 'function type error: ${Std.string(error)}'));
        }
      }
    }

    return checked;
  }

  static function validateOverrideSignatures(types:CheckerTypes, issues:Array<String>):Void
  {
    for (name => decl in Interp._scriptClassDescriptors)
    {
      configureAliases(types, decl);
      var cls = getClass(types, name);
      if (cls == null) continue;

      for (field in decl.fields)
      {
        switch (field.kind)
        {
          case KFunction(fn):
            var inherited = findInheritedMemberType(types, cls, field.name, false);
            if (inherited == null) continue;

            var own = cls.fields.get(field.name);
            if (own == null) continue;

            var anchor = fn.expr == null ? classAnchor(decl) : fn.expr;
            var problem = compareOverrideFunctionTypes(types, own.t, inherited.t);
            if (problem != null)
              issues.push(formatIssue(name, field.name, anchor, 'override signature mismatch: ${problem}'));
          case KVar(_):
        }
      }
    }
  }

  static function findInheritedMemberType(types:CheckerTypes, cls:CClass, name:String, isStatic:Bool):Null<CField>
  {
    var checker = new Checker(types);
    var currentType = cls.superClass;
    var depth = 0;

    while (currentType != null && depth++ < 64)
    {
      var followed = checker.follow(currentType);
      switch (followed)
      {
        case TInst(parent, parentArgs):
          var fields = isStatic ? parent.statics : parent.fields;
          var member = fields.get(name);
          if (member != null && member.isPublic)
          {
            var instantiatedType = member.t;
            if (parent.params != null && parent.params.length == parentArgs.length && parent.params.length > 0)
              instantiatedType = checker.apply(instantiatedType, parent.params, parentArgs);
            return {
              name: member.name,
              isPublic: member.isPublic,
              canWrite: member.canWrite,
              complete: member.complete,
              params: member.params == null ? [] : member.params,
              t: instantiatedType,
              meta: member.meta,
            };
          }
          currentType = parent.superClass;
        case TAbstract(abs, args):
          var member = (isStatic ? abs.statics : abs.fields).get(name);
          if (member != null) return member;
          currentType = null;
        default:
          currentType = null;
      }
    }

    return null;
  }

  static function compareOverrideFunctionTypes(types:CheckerTypes, actualType:TType, inheritedType:TType):Null<String>
  {
    var checker = new Checker(types);
    var actual = checker.follow(actualType);
    var inherited = checker.follow(inheritedType);

    return switch ([actual, inherited])
    {
      case [TFun(actualArgs, actualReturn), TFun(inheritedArgs, inheritedReturn)]:
        if (actualArgs.length != inheritedArgs.length)
          'expected ${inheritedArgs.length} argument(s), got ${actualArgs.length}';
        else
        {
          var problem:Null<String> = null;
          for (i in 0...actualArgs.length)
          {
            var actualArg = actualArgs[i];
            var inheritedArg = inheritedArgs[i];
            if (actualArg.opt != inheritedArg.opt)
            {
              problem = 'argument ${i + 1} optionality differs (expected ${inheritedArg.opt ? "optional" : "required"}, got ${actualArg.opt ? "optional" : "required"})';
              break;
            }
            if (!overrideTypesCompatible(types, actualArg.t, inheritedArg.t)
              || !overrideTypesCompatible(types, inheritedArg.t, actualArg.t))
            {
              problem = 'argument "${inheritedArg.name}" has type ${Checker.typeStr(actualArg.t)}, inherited type is ${Checker.typeStr(inheritedArg.t)}';
              break;
            }
          }

          if (problem != null) problem;
          else if (!overrideTypesCompatible(types, actualReturn, inheritedReturn))
            'return type ${Checker.typeStr(actualReturn)} is incompatible with inherited return type ${Checker.typeStr(inheritedReturn)}';
          else null;
        }
      case [_, TFun(_, _)]:
        'the overriding member is not a function';
      case [TFun(_, _), _]:
        null;
      default:
        null;
    }
  }

  static function overrideTypesCompatible(types:CheckerTypes, actual:TType, expected:TType):Bool
  {
    var checker = new Checker(types);
    actual = checker.follow(actual);
    expected = checker.follow(expected);
    if (isUnknownOverrideType(actual) || isUnknownOverrideType(expected)) return true;
    return checker.tryUnify(copyOverrideType(actual), copyOverrideType(expected));
  }

  static function isUnknownOverrideType(type:TType):Bool
  {
    return switch (type)
    {
      case TDynamic, TUnresolved(_): true;
      case TMono(ref): ref.r == null;
      default: false;
    }
  }

  static function copyOverrideType(type:TType, depth:Int = 0):TType
  {
    if (depth > 32) return TDynamic;
    return switch (type)
    {
      case TMono(ref):
        TMono({
          r: ref.r == null ? null : copyOverrideType(ref.r, depth + 1)
        });
      case TNull(inner):
        TNull(copyOverrideType(inner, depth + 1));
      case TInst(cls, args):
        TInst(cls, [for (arg in args) copyOverrideType(arg, depth + 1)]);
      case TEnum(en, args):
        TEnum(en, [for (arg in args) copyOverrideType(arg, depth + 1)]);
      case TType(td, args):
        TType(td, [for (arg in args) copyOverrideType(arg, depth + 1)]);
      case TAbstract(abs, args):
        TAbstract(abs, [for (arg in args) copyOverrideType(arg, depth + 1)]);
      case TFun(args, ret):
        TFun([for (arg in args) {
          name: arg.name,
          opt: arg.opt,
          t: copyOverrideType(arg.t, depth + 1)
        }], copyOverrideType(ret, depth + 1));
      case TAnon(fields):
        TAnon([for (field in fields) {
          name: field.name,
          opt: field.opt,
          t: copyOverrideType(field.t, depth + 1)
        }]);
      case TLazy(resolve):
        copyOverrideType(resolve(), depth + 1);
      default:
        type;
    }
  }

  static function registerScriptEnumSignatures(types:CheckerTypes, issues:Array<String>):Void
  {
    for (name => decl in Interp._scriptEnumDescriptors)
    {
      configureEnumAliases(types, decl);
      var enumType = switch (types.resolve(name))
      {
        case TEnum(value, _):
          value;
        default:
          null;
      };
      if (enumType == null) continue;

      for (field in decl.fields)
      {
        var args = [];
        for (arg in field.args)
        {
          var argType:TType = TDynamic;
          if (arg.type != null)
          {
            var resolver = new Checker(types);
            try
            {
              argType = resolver.resolveTypeAnnotation(arg.type, enumAnchor(decl));
            }
            catch (error:Dynamic)
            {
              issues.push(formatIssue(name, field.name, enumAnchor(decl), 'enum argument type error: ${Std.string(error)}'));
            }
          }
          args.push({name: arg.name, opt: false, t: argType});
        }
        enumType.constructors.push({name: field.name, args: args.length == 0 ? null : args});
      }
    }
  }

  static function registerScriptClassSignatures(types:CheckerTypes, issues:Array<String>):Void
  {
    for (name => decl in Interp._scriptClassDescriptors)
    {
      configureAliases(types, decl);
      var resolver = new Checker(types);
      resolver.currentClassName = name;
      var cls = getClass(types, name);
      if (cls == null) continue;

      if (decl.extend != null)
      {
        try
        {
          cls.superClass = resolver.resolveTypeAnnotation(decl.extend, classAnchor(decl));
        }
        catch (error:Dynamic)
        {
          issues.push(formatIssue(name, '<superclass>', classAnchor(decl), 'superclass type error: ${Std.string(error)}'));
        }
      }

      cls.interfaces = [];
      for (interfaceType in decl.implement)
      {
        try
        {
          cls.interfaces.push(resolver.resolveTypeAnnotation(interfaceType, classAnchor(decl)));
        }
        catch (error:Dynamic)
        {
          issues.push(formatIssue(name, '<interface>', classAnchor(decl), 'interface type error: ${Std.string(error)}'));
        }
      }

      registerFields(types, resolver, cls, decl.fields, false, name, issues);
      registerFields(types, resolver, cls, decl.staticFields, true, name, issues);
    }

    for (name => decl in Interp._scriptInterfaceDescriptors)
    {
      configureAliasesForInterface(types, decl);
      var resolver = new Checker(types);
      var cls = getClass(types, name);
      if (cls == null) continue;
      cls.isInterface = true;
      cls.interfaces = [];
      for (parent in decl.extend)
      {
        try
        {
          cls.interfaces.push(resolver.resolveTypeAnnotation(parent, classAnchorFromFields(decl.fields)));
        }
        catch (error:Dynamic)
        {
          issues.push(formatIssue(name, '<interface>', classAnchorFromFields(decl.fields), 'interface parent type error: ${Std.string(error)}'));
        }
      }
      registerFields(types, resolver, cls, decl.fields, false, name, issues);
    }
  }

  static function registerFields(types:CheckerTypes, resolver:Checker, cls:CClass, fields:Array<FieldDecl>, isStatic:Bool,
      owner:String, issues:Array<String>):Void
  {
    var target = isStatic ? cls.statics : cls.fields;
    for (field in fields)
    {
      var declaredPublic = field.access.contains(APublic) || !field.access.contains(APrivate);
      switch (field.kind)
      {
        case KFunction(fn):
          var args:Array<{name:String, opt:Bool, t:TType}> = [];
          var fnAnchor = fn.expr == null ? classAnchorFromFields(fields) : fn.expr;
          for (arg in fn.args)
          {
            var argType:TType = TMono({r: null});
            if (arg.t != null)
            {
              try
              {
                argType = resolver.resolveTypeAnnotation(arg.t, fnAnchor);
              }
              catch (error:Dynamic)
              {
                issues.push(formatIssue(owner, field.name, fnAnchor, 'argument "${arg.name}" type error: ${Std.string(error)}'));
              }
            }
            args.push({name: arg.name, opt: arg.opt == true || arg.value != null, t: argType});
          }

          var returnType:TType = TMono({r: null});
          if (fn.ret != null)
          {
            try
            {
              returnType = resolver.resolveTypeAnnotation(fn.ret, fnAnchor);
            }
            catch (error:Dynamic)
            {
              issues.push(formatIssue(owner, field.name, fnAnchor, 'return type error: ${Std.string(error)}'));
            }
          }

          var functionField:CField = {
            name: field.name,
            isPublic: declaredPublic,
            canWrite: false,
            complete: true,
            params: [],
            t: TFun(args, returnType),
          };
          if (!isStatic && field.name == 'new') cls.constructor = functionField;
          else target.set(field.name, functionField);
        case KVar(v):
          var fieldType:TType = TMono({r: null});
          if (v.type != null)
          {
            try
            {
              fieldType = resolver.resolveTypeAnnotation(v.type, v.expr == null ? classAnchorFromFields(fields) : v.expr);
            }
            catch (error:Dynamic)
            {
              issues.push(formatIssue(owner, field.name, v.expr == null ? classAnchorFromFields(fields) : v.expr,
                'field type error: ${Std.string(error)}'));
            }
          }
          target.set(field.name, {
            name: field.name,
            isPublic: declaredPublic,
            canWrite: v.isfinal != true && v.set != 'never',
            complete: true,
            params: [],
            t: fieldType,
          });
      }
    }
  }

  static function typeToSourceType(type:TType, depth:Int = 0):CType
  {
    if (depth > 24) return CTPath(['Dynamic']);
    return switch (type)
    {
      case TMono(ref):
        ref.r == null ? CTPath(['Dynamic']) : typeToSourceType(ref.r, depth + 1);
      case TVoid:
        CTPath(['Void']);
      case TInt:
        CTPath(['Int']);
      case TFloat:
        CTPath(['Float']);
      case TBool:
        CTPath(['Bool']);
      case TDynamic, TParam(_), TUnresolved(_):
        CTPath(['Dynamic']);
      case TNull(inner):
        CTPath(['Null'], [typeToSourceType(inner, depth + 1)]);
      case TInst(cls, args):
        CTPath(cls.name.split('.'), [for (arg in args) typeToSourceType(arg, depth + 1)]);
      case TEnum(en, args):
        CTPath(en.name.split('.'), [for (arg in args) typeToSourceType(arg, depth + 1)]);
      case TAbstract(abs, args):
        CTPath(abs.name.split('.'), [for (arg in args) typeToSourceType(arg, depth + 1)]);
      case TType(td, args):
        CTPath(td.name.split('.'), [for (arg in args) typeToSourceType(arg, depth + 1)]);
      case TFun(args, ret):
        CTFun([for (arg in args) arg.opt ? CTOpt(typeToSourceType(arg.t, depth + 1)) : typeToSourceType(arg.t, depth + 1)], typeToSourceType(ret, depth + 1));
      case TAnon(fields):
        CTAnon([for (field in fields) {
          name: field.name,
          t: field.opt ? CTOpt(typeToSourceType(field.t, depth + 1)) : typeToSourceType(field.t, depth + 1)
        }]);
      case TLazy(resolve):
        typeToSourceType(resolve(), depth + 1);
    }
  }


  static function configureCheckerGlobals(checker:Checker, types:CheckerTypes, owner:ClassDecl, cls:CClass, isStatic:Bool):Void
  {
    addInterpreterGlobals(checker, types);

    if (!isStatic)
    {
      checker.setGlobal('this', TInst(cls, []));
      checker.setGlobals(cls, [], true);
      if (cls.superClass != null) checker.setGlobal('super', cls.superClass);
      for (field in cls.statics) if (
        field.isPublic
        || checker.currentClassName == cls.name
      ) checker.setGlobal(field.name, instantiatedFieldType(types, field));
    }
    else
    {
      for (field in cls.statics) if (
        field.isPublic
        || checker.currentClassName == cls.name
      ) checker.setGlobal(field.name, instantiatedFieldType(types, field));
    }

    if (owner.imports != null) for (name in owner.imports.keys())
    {
      var imp = owner.imports.get(name);
      if (imp == null || imp.wildcard == true) continue;
      if (imp.field == true)
      {
        var fieldName = imp.fullPath.split('.').pop();
        var typePath = imp.fullPath.substr(0, imp.fullPath.length - fieldName.length - 1);
        var staticField = findStaticField(types, typePath, fieldName);
        if (staticField != null) checker.setGlobal(name, instantiatedFieldType(types, staticField));
      }
      else
      {
        var symbolType = classSymbolType(types, imp.fullPath);
        if (symbolType != null) checker.setGlobal(name, symbolType);
      }
    }

    if (owner.importsToValidate != null) for (name in owner.importsToValidate.keys())
    {
      var imp = owner.importsToValidate.get(name);
      if (imp == null || imp.wildcard == true || imp.field == true) continue;
      var symbolType = classSymbolType(types, imp.fullPath);
      if (symbolType != null) checker.setGlobal(name, symbolType);
    }

    var packageName = owner.pkg == null ? '' : owner.pkg.join('.');
    if (packageName.length > 0)
    {
      for (name in Interp._scriptClassDescriptors.keys())
      {
        if (!isDirectChild(packageName, name)) continue;
        var typeAlias = name.substr(packageName.length + 1);
        var symbolType = classSymbolType(types, name);
        if (symbolType != null) checker.setGlobal(typeAlias, symbolType);
      }
      for (name in Interp._scriptEnumDescriptors.keys())
      {
        if (!isDirectChild(packageName, name)) continue;
        var typeAlias = name.substr(packageName.length + 1);
        var symbolType = classSymbolType(types, name);
        if (symbolType != null) checker.setGlobal(typeAlias, symbolType);
      }
    }

    for (name => clsRef in PolymodScriptClass.defaultImports)
    {
      var path = Type.getClassName(clsRef);
      if (path == null) continue;
      var symbolType = classSymbolType(types, path);
      if (symbolType != null)
      {
        checker.setGlobal(name.split('.').pop(), symbolType);
        checker.setGlobal(name, symbolType);
      }
    }

    checker.setGlobal(owner.name, classSymbolType(types, Util.getFullClassName(owner)) ?? TDynamic);
    checker.setGlobal(Util.getFullClassName(owner), classSymbolType(types, Util.getFullClassName(owner)) ?? TDynamic);
  }

  static function addInterpreterGlobals(checker:Checker, types:CheckerTypes):Void
  {
    if (PolymodScriptClass.scriptInterp.variables != null)
    {
      for (name in PolymodScriptClass.scriptInterp.variables.keys())
      {
        var value = PolymodScriptClass.scriptInterp.variables.get(name);
        var symbolType = types.hasType(name) ? classSymbolType(types, name) : null;
        checker.setGlobal(name, symbolType == null ? runtimeValueType(types, value, 0) : symbolType);
      }
    }
    if (PolymodScriptClass.scriptInterp.functions != null)
    {
      for (name in PolymodScriptClass.scriptInterp.functions.keys()) checker.setGlobal(name, TDynamic);
    }
  }

  static function runtimeValueType(types:CheckerTypes, value:Dynamic, depth:Int):TType
  {
    if (value == null || depth > 4) return TDynamic;
    if (Std.isOfType(value, String)) return types.resolve('String') ?? TDynamic;

    return switch (Type.typeof(value))
    {
      case TInt:
        TInt;
      case TFloat:
        TFloat;
      case TBool:
        TBool;
      case TObject, TClass(_):
        if (Std.isOfType(value, Array))
        {
          types.resolve('Array', [TDynamic]) ?? TDynamic;
        }
        else
        {
          var runtimeClass = Type.getClass(value);
          var path = runtimeClass == null ? null : Type.getClassName(runtimeClass);
          path == null ? TDynamic : types.resolve(path) ?? TDynamic;
        }
      case TEnum(_), TFunction, TNull, TUnknown:
        TDynamic;
    }
  }

  static function classSymbolType(types:CheckerTypes, path:String):Null<TType>
  {
    if (path == null) return null;
    return switch (types.resolve(path))
    {
      case TInst(cls, _):
        staticMembersType(types, cls.statics);
      case TAbstract(abs, _):
        staticMembersType(types, abs.statics);
      case TEnum(en, args):
        enumSymbolType(types, en, args);
      case TType(td, args):
        switch (new Checker(types).follow(TType(td, args)))
        {
          case TInst(cls, _):
            staticMembersType(types, cls.statics);
          case TAbstract(abs, _):
            staticMembersType(types, abs.statics);
          case TEnum(en, args):
            enumSymbolType(types, en, args);
          default:
            null;
        }
      default:
        null;
    }
  }

  static function staticMembersType(types:CheckerTypes, fields:Map<String, CField>):TType
  {
    return TAnon([for (field in fields) if (field.isPublic) {
      name: field.name,
      opt: false,
      t: instantiatedFieldType(types, field)
    }]);
  }

  static function enumSymbolType(types:CheckerTypes, en:CEnum, args:Array<TType>):TType
  {
    var enumType:TType = TEnum(en, args);
    var checker = new Checker(types);
    return TAnon([for (constructor in en.constructors) {
      name: constructor.name,
      opt: false,
      t: constructor.args == null ? enumType : TFun([for (arg in constructor.args) {
        name: arg.name,
        opt: arg.opt,
        t: checker.apply(arg.t, en.params, args)
      }], enumType),
    }]);
  }

  static function findStaticField(types:CheckerTypes, path:String, name:String):Null<CField>
  {
    var resolved = types.resolve(path);
    if (resolved == null) return null;
    return switch (new Checker(types).follow(resolved))
    {
      case TInst(cls, _):
        findStaticMember(types, cls.statics, name);
      case TAbstract(abs, _):
        findStaticMember(types, abs.statics, name);
      case TEnum(en, args):
        var constructor = null;
        for (item in en.constructors) if (item.name == name)
        {
          constructor = item;
          break;
        }
        if (constructor == null) null else {
          name: name,
          isPublic: true,
          canWrite: false,
          complete: true,
          params: [],
          t: constructor.args == null ? TEnum(en, args) : TFun([for (arg in constructor.args) {
            name: arg.name,
            opt: arg.opt,
            t: new Checker(types).apply(arg.t, en.params, args)
          }], TEnum(en, args)),
        };
      default:
        null;
    }
  }

  static function findStaticMember(types:CheckerTypes, fields:Map<String, CField>, name:String):Null<CField>
  {
    var field = fields.get(name);
    return field == null ? null : copyStaticField(types, field);
  }

  static function copyStaticField(types:CheckerTypes, field:CField):CField
  {
    return {
      name: field.name,
      isPublic: field.isPublic,
      canWrite: field.canWrite,
      complete: field.complete,
      params: [],
      t: instantiatedFieldType(types, field),
    };
  }

  static function instantiatedFieldType(types:CheckerTypes, field:CField):TType
  {
    if (field.params == null || field.params.length == 0) return field.t;
    return new Checker(types).apply(field.t, field.params, [for (_ in field.params) TMono({
      r: null
    })]);
  }

  static function findMemberType(cls:CClass, name:String, isStatic:Bool):Null<CField>
  {
    var current:Null<CClass> = cls;
    var depth = 0;
    while (current != null && depth++ < 64)
    {
      var member = (isStatic ? current.statics : current.fields).get(name);
      if (member != null) return member;
      if (isStatic || current.superClass == null) break;
      current = switch (current.superClass)
      {
        case TInst(parent, _):
          parent;
        case TType(td, _):
          switch (td.t)
          {
            case TInst(parent, _):
              parent;
            default:
              null;
          }
        default:
          null;
      }
    }
    return null;
  }

  static function configureAliases(types:CheckerTypes, owner:ClassDecl):Void
  {
    configureAliasesCommon(types, owner.pkg, owner.imports, owner.importsToValidate, true);
  }

  static function configureAliasesForInterface(types:CheckerTypes, owner:InterfaceDecl):Void
  {
    configureAliasesCommon(types, owner.pkg, owner.imports, owner.importsToValidate, false);
  }

  static function configureEnumAliases(types:CheckerTypes, owner:EnumDecl):Void
  {
    configureAliasesCommon(types, owner.pkg, owner.imports, owner.importsToValidate, false);
  }

  static function configureAliasesCommon(types:CheckerTypes,
    packagePath:Null<Array<String>>,
    imports:Null<Map<String, ClassImport>>,
    importsToValidate:Null<Map<String, ClassImport>>,
    includeQualifiedDefaults:Bool):Void
  {
    types.clearAliases();
    var packageName = packagePath == null ? '' : packagePath.join('.');
    if (packageName.length > 0)
    {
      for (name in Interp._scriptClassDescriptors.keys()) if (isDirectChild(packageName, name)) types.setAlias(name.substr(packageName.length + 1), name);
      for (name in Interp._scriptInterfaceDescriptors.keys()) if (isDirectChild(packageName, name)) types.setAlias(name.substr(packageName.length + 1), name);
      for (name in Interp._scriptEnumDescriptors.keys()) if (isDirectChild(packageName, name)) types.setAlias(name.substr(packageName.length + 1), name);
    }

    for (name => clsRef in PolymodScriptClass.defaultImports)
    {
      var path = Type.getClassName(clsRef);
      if (path == null) continue;
      if (includeQualifiedDefaults) types.setAlias(name, path);
      types.setAlias(name.split('.').pop(), path);
    }

    if (imports != null) for (name => imp in imports) if (imp != null && imp.field != true && imp.wildcard != true) types.setAlias(name, imp.fullPath);
    if (importsToValidate != null) for (name => imp in importsToValidate) if (
      imp != null
      && imp.field != true
      && imp.wildcard != true
    ) types.setAlias(name, imp.fullPath);
    // Resolve wildcard imports against the portable metadata index.
    if (imports != null) for (imp in imports) if (imp != null && imp.wildcard == true) setWildcardAliases(types, imp.fullPath);
  }

  static function setWildcardAliases(types:CheckerTypes, packagePath:String):Void
  {
    if (packagePath == null || packagePath.length == 0) return;
    var packages = PolymodScriptClassMacro.fetchPackagesList();
    var names = packages.get(packagePath);
    if (names == null) return;
    for (name in names)
    {
      var prefix = packagePath + '.';
      if (!name.startsWith(prefix)) continue;
      var suffix = name.substr(prefix.length);
      if (suffix.indexOf('.') == -1) types.setAlias(suffix, name);
    }
  }

  static function isDirectChild(packageName:String, className:String):Bool
  {
    var prefix = packageName + '.';
    if (!className.startsWith(prefix)) return false;
    return className.substr(prefix.length).indexOf('.') == -1;
  }

  static function getClass(types:CheckerTypes, name:String):Null<CClass>
  {
    return switch (types.resolve(name))
    {
      case TInst(cls, _):
        cls;
      default:
        null;
    }
  }

  static function classAnchor(decl:ClassDecl):Expr
  {
    return classAnchorFromFields(decl.fields.concat(decl.staticFields));
  }

  static function classAnchorFromFields(fields:Array<FieldDecl>):Expr
  {
    for (field in fields) switch (field.kind)
    {
      case KFunction(fn) if (fn.expr != null):
        return fn.expr;
      case KVar(v) if (v.expr != null):
        return v.expr;
      default:
    }
    return new Parser().parseString('null', 'script typer');
  }

  static function enumAnchor(decl:EnumDecl):Expr
  {
    return new Parser().parseString('null', 'script typer (${decl.name})');
  }

  static function formatIssue(owner:String, field:String, expr:Expr, message:String):String
  {
    #if hscriptPos
    return 'Script type error in ${owner}.${field} (${expr.origin}:${expr.line}): ${message}';
    #else
    return 'Script type error in ${owner}.${field}: ${message}';
    #end
  }

}
