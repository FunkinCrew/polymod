package polymod.hscript._internal;

import polymod.hscript._internal.Expr;
import polymod.hscript._internal.PolymodClassDeclEx.PolymodClassImport;
import polymod.hscript._internal.PolymodClassDeclEx.PolymodStaticClassReference;
import polymod.hscript._internal.PolymodExprEx;
import polymod.hscript._internal.Printer;
import polymod.util.Util;

using StringTools;

/**
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(polymod.hscript._internal.PolymodScriptClass)
@:access(polymod.hscript._internal.PolymodAbstractScriptClass)
@:access(polymod.hscript._internal.PolymodEnum)
class PolymodInterpEx extends Interp
{
  var targetCls:Class<Dynamic>;

  private var _proxy:PolymodAbstractScriptClass = null;

  var _classDeclOverride:PolymodClassDeclEx = null;

  var _propTrack:Map<String, Bool> = [];

  function getClassDecl():PolymodClassDeclEx
  {
    if (_classDeclOverride != null)
    {
      return _classDeclOverride;
    }
    else if (_proxy != null)
    {
      return _proxy._c;
    }
    else
    {
      return null;
    }
  }

  function getClassFullyQualifiedName():Null<String>
  {
    if (_proxy == null)
    {
      var clsDecl = getClassDecl() ?? return null;
      return Util.getFullClassName(clsDecl);
    }

    return _proxy.fullyQualifiedName;
  }

  public function new(targetCls:Class<Dynamic>, proxy:PolymodAbstractScriptClass)
  {
    super();
    _proxy = proxy;
    this.targetCls = targetCls;
  }

  function errorEx(e:#if hscriptPos ErrorDefEx #else ErrorEx #end, rethrow = false):Dynamic
  {
    #if hscriptPos var e = new ErrorEx(e, curExpr?.pmin ?? 0, curExpr?.pmax ?? 0, curExpr?.origin ?? 'unknown', curExpr?.line ?? 0); #end
    if (rethrow) this.rethrow(e)
    else
      throw e;
    return null;
  }

  override function cnew(cl:String, args:Array<Dynamic>):Dynamic
  {
    // Try to retrieve a scripted class with this name in the same package.
    if (getClassDecl().pkg != null && getClassDecl().pkg.length > 0)
    {
      var localClassId = getClassDecl().pkg.join('.') + "." + cl;
      var clsRef = PolymodStaticClassReference.tryBuild(localClassId);
      if (clsRef != null) return clsRef.instantiate(args);
    }

    // Try to retrieve a scripted class with this name in the base package.
    var clsRef = PolymodStaticClassReference.tryBuild(cl);
    if (clsRef != null) return clsRef.instantiate(args);
    @:privateAccess
    if (getClassDecl().imports != null && getClassDecl().imports.exists(cl))
    {
      var clsRef = PolymodStaticClassReference.tryBuild(getClassDecl().imports.get(cl).fullPath);
      if (clsRef != null) return clsRef.instantiate(args);
    }
    @:privateAccess
    if (getClassDecl()?.pkg != null)
    {
      @:privateAccess
      var packagedClass = getClassDecl().pkg.join(".") + "." + cl;
      if (_scriptClassDescriptors.exists(packagedClass))
      {
        // OVERRIDE CHANGE: Create a PolymodScriptClass instead of a ScriptClass
        var proxy:PolymodAbstractScriptClass = new PolymodScriptClass(_scriptClassDescriptors.get(packagedClass), args);
        return proxy;
      }
    }
    @:privateAccess
    if (getClassDecl()?.imports != null && getClassDecl().imports.exists(cl))
    {
      var importedClass:PolymodClassImport = getClassDecl().imports.get(cl);
      if (_scriptClassDescriptors.exists(importedClass.fullPath))
      {
        // OVERRIDE CHANGE: Create a PolymodScriptClass instead of a ScriptClass
        var proxy:PolymodAbstractScriptClass = new PolymodScriptClass(_scriptClassDescriptors.get(importedClass.fullPath), args);
        return proxy;
      }

      // Ignore importedClass.enm as enums cannot be instantiated.

      // Importing a blacklisted module creates an import with a `null` class, so we check for that here.
      var c = importedClass.cls;
      if (c == null)
      {
        errorEx(EBlacklistedModule(importedClass.fullPath));
      }
      else
      {
        return Type.createInstance(c, args);
      }
    }

    // Attempt to resolve the class without overrides.
    var cls = Type.resolveClass(cl);
    if (cls == null) cls = resolve(cl);
    if (cls == null) errorEx(EInvalidModule(cl));
    return Type.createInstance(cls, args);
  }

  /**
   * Note to self: Calls to `this.xyz()` will have the type of `o` as `polymod.hscript.PolymodScriptClass`.
   * Calls to `super.xyz()` will have the type of `o` as `stage.ScriptedStage`.
   */
  override function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic
  {
    // OVERRIDE CHANGE: Custom logic to handle super calls to prevent infinite recursion
    if (_proxy != null && o == _proxy.superClass && !Std.isOfType(o, PolymodScriptClass))
    {
      // Force call super function.
      return super.fcall(o, '__super_${f}', args);
    }
    else if (Std.isOfType(o, PolymodStaticClassReference))
    {
      var ref:PolymodStaticClassReference = cast(o, PolymodStaticClassReference);

      return ref.callFunction(f, args);
    }
    else if (Std.isOfType(o, PolymodScriptClass))
    {
      _nextCallObject = null;
      var proxy:PolymodScriptClass = cast(o, PolymodScriptClass);
      return proxy.callFunction(f, args);
    }

    var func = get(o, f);
    if (func != null)
    {
      return call(o, func, args);
    }
    @:privateAccess
    if (_proxy != null && _proxy._cachedUsingFunctions.exists(f))
    {
      return _proxy._cachedUsingFunctions[f]([o].concat(args));
    }
    else if (_classDeclOverride != null)
    {
      // TODO: Optimize with a cache
      var usingFuncs:Map<String, Array<Dynamic>->Dynamic> = [];
      PolymodScriptClass.buildExtensionFunctionCache(_classDeclOverride, usingFuncs);

      if (usingFuncs.exists(f))
      {
        return usingFuncs[f]([o].concat(args));
      }
    }

    #if html5
    // Workaround for an HTML5-specific issue.
    // https://github.com/HaxeFoundation/haxe/issues/11298
    if (f == "contains")
    {
      func = get(o, "includes");
    }
    // For web: remove is inlined so we have to use something else.
    else if (f == "remove")
    {
      @:privateAccess
      return HxOverrides.remove(cast o, args[0]);
    }
    #end

    if (Std.isOfType(o, HScriptedClass))
    {
      // This is a scripted class!
      // We should try to call the function on the scripted class.
      // If it doesn't exist, `asc.callFunction()` will handle generating an error message.
      if (o.scriptCall != null)
      {
        return o.scriptCall(f, args);
      }

      return errorEx(EInvalidScriptedFnAccess(f));
    }
    else
    {
      // Throw an error for a missing function.
      return errorEx(EInvalidAccess(f));
    }
  }

  private static var _scriptClassDescriptors:Map<String, PolymodClassDeclEx> = new Map<String, PolymodClassDeclEx>();

  private static function registerScriptClass(c:PolymodClassDeclEx)
  {
    var name = Util.getFullClassName(c);

    if (_scriptClassDescriptors.exists(name))
    {
      Polymod.error(SCRIPT_CLASS_ALREADY_REGISTERED,
        'Scripted class with fully qualified name "$name" has already been defined. Please change the class name or the package name to ensure uniqueness.');
      return;
    }
    else
    {
      Polymod.debug('Registering scripted class $name');
      _scriptClassDescriptors.set(name, c);
    }
  }

  override function resetVariables():Void
  {
    super.resetVariables();

    variables.set("Math", Math);
    variables.set("Std", Std);

    variables.set("Array", Array);
    variables.set("Bool", Bool);
    variables.set("Dynamic", Dynamic);
    variables.set("Float", Float);
    variables.set("Int", Int);
    variables.set("String", String);
  }

  public function clearScriptClassDescriptors():Void
  {
    // Clear the script class descriptors.
    _scriptClassDescriptors.clear();

    // Also destroy local variable scope.
    this.resetVariables();
  }

  public static function findScriptClassDescriptor(name:String)
  {
    return _scriptClassDescriptors.get(name);
  }

  private static var _scriptEnumDescriptors:Map<String, PolymodEnumDeclEx> = new Map<String, PolymodEnumDeclEx>();

  private static function registerScriptEnum(e:PolymodEnumDeclEx)
  {
    var name = e.name;
    if (e.pkg != null)
    {
      name = e.pkg.join(".") + "." + name;
    }

    if (_scriptEnumDescriptors.exists(name))
    {
      Polymod.error(SCRIPT_ENUM_ALREADY_REGISTERED,
        'An enum with the fully qualified name "$name" has already been defined. Please change the enum name to ensure a unique name.');
      return;
    }
    else
    {
      Polymod.debug('Registering enum $name');
      _scriptEnumDescriptors.set(name, e);
    }
  }

  public function clearScriptEnumDescriptors():Void
  {
    // Clear the script enum descriptors.
    _scriptEnumDescriptors.clear();

    // Also destroy local variable scope.
    this.resetVariables();
  }

  public static function validateImports():Void
  {
    for (cls in _scriptClassDescriptors)
    {
      var clsPath = Util.getFullClassName(cls);

      // Automatically import classes with the same package or a parent package.
      for (imp in _scriptClassDescriptors)
      {
        if (cls == imp) continue;

        var classImport =
          {
            name: imp.name,
            pkg: imp.pkg,
            fullPath: Util.getFullClassName(imp)
          }

        if ((imp.pkg?.length ?? 0) == 0)
        {
          cls.imports.set(imp.name, classImport);
          continue;
        }

        var hasPackage:Bool = cls.pkg != null && cls.pkg.length > 0;
        var fullPackage:String = hasPackage ? cls.pkg.join(".") + "." : "";
        if (hasPackage && clsPath.indexOf(fullPackage) == 0)
        {
          cls.imports.set(imp.name, classImport);
        }
      }

      for (key => imp in cls.importsToValidate)
      {
        if (_scriptClassDescriptors.exists(imp.fullPath))
        {
          cls.imports.set(key, imp);
          continue;
        }

        if (_scriptEnumDescriptors.exists(imp.fullPath))
        {
          cls.imports.set(key, imp);
          continue;
        }

        Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not import ${imp.fullPath}', clsPath);
      }

      // Check if the scripted classes extend the right type.
      if (cls.extend == null) continue;

      var superClassPath:String = new Printer().typeToString(cls.extend);
      if (!cls.imports.exists(superClassPath))
      {
        switch (cls.extend)
        {
          case CTPath(path, params):
            if (params != null && params.length > 0)
            {
              Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not extend ${superClassPath}, do not include type parameters in super class name', clsPath);
            }

          default:
            // Other error handling?
        }

        // Default
        Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not extend ${superClassPath}, is the type imported?', clsPath);
      }
      else
      {
        switch (cls.extend)
        {
          case CTPath(_, params):
            cls.extend = CTPath(cls.imports.get(superClassPath).fullPath.split('.'), params);
          case _:
        }
      }
    }
  }

  override function setVar(id:String, v:Dynamic)
  {
    if (_proxy != null && _proxy.superHasField(id))
    {
      if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
      {
        var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
        return superClass.fieldWrite(id, v);
      }

      Reflect.setProperty(_proxy.superClass, id, v);
      return;
    }

    // Fallback to setting in local scope.
    super.setVar(id, v);
  }

  override function assign(e1:Expr, e2:Expr):Dynamic
  {
    switch (Tools.expr(e1))
    {
      case EIdent(id):
        // Make sure setting superclass fields directly works.
        // Also ensures property functions are accounted for.
        if (_proxy != null && _proxy.superHasField(id))
        {
          var v = expr(e2);

          if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
          {
            var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
            return superClass.fieldWrite(id, v);
          }

          Reflect.setProperty(_proxy.superClass, id, v);
          return v;
        }

        @:privateAccess
        {
          if (_proxy != null)
          {
            var decl = _proxy.findVar(id);
            switch (decl?.set)
            {
              case "set":
                final setName = 'set_$id';
                if (!_propTrack.exists(setName))
                {
                  var v = expr(e2);
                  _propTrack.set(setName, true);
                  var out = _proxy.callFunction(setName, [v]);
                  _propTrack.remove(setName);
                  return (out == null) ? v : out;
                }

              case "never":
                errorEx(EInvalidPropSet(id));
                return null;
            }

            if ((decl?.isfinal ?? false) && decl?.expr != null)
            {
              errorEx(EInvalidAccess(id));
              return null;
            }
          }
        }
      case EField(e0, id):
        // Make sure setting superclass fields works when using this.
        // Also ensures property functions are accounted for.
        switch (Tools.expr(e0))
        {
          case EIdent(id0):
            if (id0 == "this")
            {
              if (_proxy != null && _proxy.superHasField(id))
              {
                var v = expr(e2);

                if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
                {
                  var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
                  return superClass.fieldWrite(id, v);
                }

                Reflect.setProperty(_proxy.superClass, id, v);
                return v;
              }
            }
            else
            {
              @:privateAccess
              {
                // Check if we are setting a final. If so, throw an error.
                if (_proxy != null && _proxy._c != null)
                {
                  for (imp in _proxy._c.imports)
                  {
                    if (imp.name != id0) continue;
                    var finals = PolymodFinalMacro.getAllFinals().get(imp.fullPath) ?? [];

                    if (finals.contains(id))
                    {
                      errorEx(EInvalidFinalSet(id));
                      return null;
                    }
                  }
                }
              }
            }
          default:
            // Do nothing
        }
      default:
    }
    // Fallback, which calls set()
    return super.assign(e1, e2);
  }

  override function increment(e:Expr, prefix:Bool, delta:Int)
  {
    switch (Tools.expr(e))
    {
      case EIdent(id):
        @:privateAccess
        {
          if (_proxy != null)
          {
            var decl = _proxy.findVar(id);
            if (decl != null)
            {
              var v = switch (decl.get)
              {
                case "never": errorEx(EInvalidPropGet(id));
                default: expr(e);
              }

              if (prefix) v += delta;

              switch (decl.set)
              {
                case "set":
                  final setName = 'set_$id';
                  if (!_propTrack.exists(setName))
                  {
                    _propTrack.set(setName, true);
                    var r = _proxy.callFunction(setName, [prefix ? v : (v + delta)]);
                    _propTrack.remove(setName);
                    return r;
                  }
                case "never":
                  return errorEx(EInvalidPropSet(id));
              }
            }
          }
        }
      default:
    }

    return super.increment(e, prefix, delta);
  }

  override function evalAssignOp(op:String, fop:Dynamic->Dynamic->Dynamic, e1:Expr, e2:Expr)
  {
    switch (Tools.expr(e1))
    {
      case EIdent(id):
        @:privateAccess
        {
          if (_proxy != null)
          {
            var decl = _proxy.findVar(id);
            if (decl != null)
            {
              var value = switch (decl.get)
              {
                case "never": errorEx(EInvalidPropGet(id));
                default: expr(e1);
              }

              var v = fop(value, expr(e2));

              switch (decl.set)
              {
                case "set":
                  final setName = 'set_$id';
                  if (!_propTrack.exists(setName))
                  {
                    _propTrack.set(setName, true);
                    var r = _proxy.callFunction(setName, [v]);
                    _propTrack.remove(setName);
                    return r;
                  }
                // Fallback
                case "never":
                  errorEx(EInvalidPropSet(id));
                  return v;
              }
            }
          }
        }
      default:
    }
    return super.evalAssignOp(op, fop, e1, e2);
  }

  public override function expr(e:Expr):Dynamic
  {
    // Override to provide some fixes, falling back to super.expr() when not needed.
    #if hscriptPos
    curExpr = e;
    switch (e.e)
    #else
    switch (e)
    #end
    {
      // These overrides are used to handle specific cases where problems occur.
      case EVar(name, type, expression):
        // Fix to ensure local variables are committed properly.
        declared.push({n: name, old: locals.get(name)});

        // Evaluate the expression before assigning, applying typing if possible.
        var result = (expression != null) ? exprWithType(expression, type) : null;

        locals.set(name, {r: result, isfinal: false});

        return null;
      case EFinal(name, type, expression):
        // Fix to ensure local variables are committed properly.
        declared.push({n: name, old: locals.get(name)});

        // Evaluate the expression before assigning, applying typing if possible.
        var result = (expression != null) ? exprWithType(expression, type) : null;

        locals.set(name, {r: result, isfinal: true});

        return null;
      case EIdent(id):
        // When resolving a variable, check if it is a property with a getter, and call it if necessary.
        @:privateAccess
        {
          if (_proxy != null)
          {
            var decl = _proxy.findVar(id);
            switch (decl?.get)
            {
              case "get":
                final getName = 'get_$id';
                if (_propTrack.exists(getName))
                {
                  switch (decl.set)
                  {
                    case 'set', 'never':
                      var field = _proxy.findField(id);
                      var hasIsVar = false;
                      for (m in field?.meta ?? [])
                        if (m.name == ':isVar')
                        {
                          hasIsVar = true;
                          break;
                        }
                      if (!hasIsVar) return errorEx(EPropVarNotReal(id));
                    default:
                  }
                }
                else
                {
                  _propTrack.set(getName, true);
                  var result = _proxy.callFunction(getName);
                  _propTrack.remove(getName);
                  return result;
                }
            }
          }
        }
      case EFunction(params, fexpr, name, _):
        // Fix to ensure callback functions catch thrown errors.
        // Using a clone to prevent locals getting wiped out.
        var clone = this.clone();
        var hasOpt = false, minParams = 0;
        for (p in params)
        {
          if (p.opt)
          {
            hasOpt = true;
          }
          else
          {
            minParams++;
          }
        }

        // This CREATES a new function in memory, that we call later.
        var newFun:Dynamic = function(args:Array<Dynamic>) {
          if (((args == null) ? 0 : args.length) != params.length)
          {
            if (args.length < minParams)
            {
              var str = "Invalid number of parameters. Got " + args.length + ", required " + minParams;
              if (name != null) str += " for function '" + name + "'";
              errorEx(ECustom(str));
            }
            // make sure mandatory args are forced
            var args2 = [];
            var extraParams = args.length - minParams;
            var pos = 0;
            for (p in params)
            {
              if (p.opt)
              {
                if (extraParams > 0)
                {
                  args2.push(args[pos++]);
                  extraParams--;
                }
                else
                {
                  args2.push(null);
                }
              }
              else
              {
                args2.push(args[pos++]);
              }
            }
            args = args2;
          }

          clone.depth++;

          for (i in 0...params.length)
          {
            clone.locals.set(params[i].name, {r: args[i]});
          }
          var r = null;

          if (inTry)
          {
            // True if the SCRIPT wraps the function in a try/catch block.
            try
            {
              r = clone.exprReturn(fexpr);
            }
            catch (e:Dynamic)
            {
              #if neko
              neko.Lib.rethrow(e);
              #else
              throw e;
              #end
            }
          }
          else
          {
            // There is no try/catch block. We can add some custom error handling.
            try
            {
              r = clone.exprReturn(fexpr);
            }
            catch (err:PolymodExprEx.ErrorEx)
            {
              PolymodScriptClass.reportErrorEx(err, getClassFullyQualifiedName(), name);
              r = null;
            }
            catch (err:Expr.Error)
            {
              PolymodScriptClass.reportError(err, getClassFullyQualifiedName(), name);
              r = null;
            }
            catch (err:Dynamic)
            {
              throw err;
            }
          }
          return r;
        };

        newFun = Reflect.makeVarArgs(newFun);
        if (name != null)
        {
          if (depth == 0)
          {
            // Store the function as a global.
            variables.set(name, newFun);
          }
          else
          {
            // function-in-function is a local function
            declared.push({n: name, old: locals.get(name)});
            var ref = {r: newFun};
            locals.set(name, ref);
            clone.locals.set(name, ref); // allow self-recursion
          }
        }
        return newFun;
      case EArrayDecl(arr):
        // Initialize an array (or map) from a declaration.
        var hasElements = arr.length > 0;
        var hasMapElements = (hasElements && Tools.expr(arr[0]).match(EBinop("=>", _)));

        if (hasMapElements)
        {
          return exprMap(arr);
        }
        else
        {
          return exprArray(arr);
        }
      case ETry(e, n, _, ecatch):
        var old = declared.length;
        var oldTry = inTry;
        try
        {
          inTry = true;
          var v:Dynamic = expr(e);
          restore(old);
          inTry = oldTry;
          return v;
        }
        catch (error:PolymodExprEx.ErrorEx)
        {
          #if hscriptPos
          var err = error.e;
          #else
          var err = error;
          #end
          // restore vars
          restore(old);
          inTry = oldTry;
          // declare 'v'
          declared.push({n: n, old: locals.get(n)});
          locals.set(n,
            {
              r: switch (err)
              {
                case EScriptThrow(errValue): errValue;
                default: error;
              }
            });
          var v:Dynamic = expr(ecatch);
          restore(old);
          return v;
        }
        catch (error:Dynamic)
        {
          var en = Type.getEnum(error);
          if (en != null && (en.getName() == "hscript._Interp.Stop" || en.getName() == "hscript.Interp.Stop"))
          {
            // HScript catches errors specifically of the type Stop, and uses them to handle
            // `break`, `continue`, and `return` statements without extensive logic to skip subsequent expressions.
            // This is safe to throw since it won't escalate outside of Polymod.
            inTry = oldTry;
            throw error;
          }
          // restore vars
          restore(old);
          inTry = oldTry;
          // declare 'v'
          declared.push({n: n, old: locals.get(n)});
          locals.set(n, {r: error});
          var v:Dynamic = expr(ecatch);
          restore(old);
          return v;
        }
      case EThrow(e):
        // If there is a try/catch block, the error will be caught.
        // If there is no try/catch block, the error will be reported.
        errorEx(EScriptThrow('${expr(e)}'));
      // Enums
      case EField(e, f):
        var name = getIdent(e);
        name = getClassDecl().imports.get(name)?.fullPath ?? name;
        if (name != null && _scriptEnumDescriptors.exists(name))
        {
          return new PolymodEnum(_scriptEnumDescriptors.get(name), f, []);
        }
      case ECall(e, params):
        switch (Tools.expr(e))
        {
          case EField(e, f):
            var name = getIdent(e);
            name = getClassDecl().imports.get(name)?.fullPath ?? name;
            if (name != null && _scriptEnumDescriptors.exists(name))
            {
              var args = new Array();
              for (p in params)
                args.push(expr(p));

              return new PolymodEnum(_scriptEnumDescriptors.get(name), f, args);
            }
          default:
        }
      case ESwitch(e, cases, def):
        var val:Dynamic = expr(e);

        if (Std.isOfType(val, PolymodEnum))
        {
          var old:Int = declared.length;
          var match = false;
          for (c in cases)
          {
            for (v in c.values)
            {
              switch (Tools.expr(v))
              {
                case ECall(e, params):
                  switch (Tools.expr(e))
                  {
                    case EField(_, f):
                      if (val._value == f)
                      {
                        for (i => p in params)
                        {
                          switch (Tools.expr(p))
                          {
                            case EIdent(n):
                              declared.push(
                                {
                                  n: n,
                                  old: {r: locals.get(n)}
                                });
                              locals.set(n, {r: val._args[i]});
                            default:
                          }
                        }
                        match = true;
                        break;
                      }
                    default:
                  }
                case EField(_, f):
                  if (val._value == f)
                  {
                    match = true;
                    break;
                  }
                default:
              }
            }
            if (match)
            {
              val = expr(c.expr);
              break;
            }
          }
          if (!match)
          {
            val = def == null ? null : expr(def);
          }
          restore(old);
          return val;
        }
      default:
        // Do nothing.
    }

    // Default case.
    return super.expr(e);
  }

  /**
   * Parse an expression, but optionally utilizing additional provided type information.
   * @param e The expression to parse.
   * @param t The explicit type of the expression, if provided.
   * @return The parsed expression.
   */
  public function exprWithType(e:Expr, ?t:CType):Dynamic
  {
    if (t == null)
    {
      return this.expr(e);
    }

    #if hscriptPos
    curExpr = e;
    switch (e.e)
    #else
    switch (e)
    #end
    {
      case EArrayDecl(arr):
        // Initialize an array (or map) from a declaration.
        var hasElements = arr.length > 0;
        var hasMapElements = (hasElements && Tools.expr(arr[0]).match(EBinop("=>", _)));
        var hasArrayElements = (hasElements && !hasMapElements);

        switch (t)
        {
          case CTPath(path, params):
            if (path.length > 0)
            {
              var last = path[path.length - 1];
              if (last == "Map")
              {
                if (!hasElements)
                {
                  // Properly handle maps with no keys.
                  return this.makeMapEmpty(params[0]);
                }
                else if (hasMapElements)
                {
                  // Properly handle maps with no keys.
                  return exprMap(arr);
                }
                else
                {
                  #if hscriptPos
                  curExpr = e;
                  #end
                  var error = 'Invalid expression in map initialization (expected key=>value, got ${Printer.toString(e)})';
                  errorEx(ECustom(error));
                }
              }
              else if (last == "Array")
              {
                if (!hasElements)
                {
                  // Create an empty Array<Dynamic>.
                  return exprArray([]);
                }
                if (hasArrayElements)
                {
                  // Create an array of elements.
                  return exprArray(arr);
                }
                else
                {
                  #if hscriptPos
                  curExpr = e;
                  #end
                  var error = 'Invalid expression in array initialization (expected no key=>value pairs, got ${Printer.toString(e)})';
                  errorEx(ECustom(error));
                }
              }
              else
              {
                // Whatever.
              }
            }
          default:
            // Whatever.
        }

      default:
        // Whatever.
    }

    // Fallthrough.
    return this.expr(e);
  }

  function exprMap(entries:Array<Expr>):Dynamic
  {
    if (entries.length == 0) return super.makeMap([], []);

    var keys = [];
    var values = [];
    for (e in entries)
    {
      switch (Tools.expr(e))
      {
        case EBinop("=>", eKey, eValue):
          // Look for map entries.
          keys.push(expr(eKey));
          values.push(expr(eValue));
        default:
          // Complain about anything else.
          // This error message has been modified to provide more information.
          #if hscriptPos
          curExpr = e;
          #end
          var error = 'Invalid expression in map initialization (expected key=>value, got ${Printer.toString(e)})';
          errorEx(ECustom(error));
      }
    }

    return super.makeMap(keys, values);
  }

  function makeMapEmpty(keyType:CType):Dynamic
  {
    switch (keyType)
    {
      case CTPath(path, params):
        if (path.length > 0)
        {
          var last = path[path.length - 1];
          switch (last)
          {
            case "Int":
              return new Map<Int, Dynamic>();
            case "String":
              return new Map<String, Dynamic>();
            default:
              // TODO: Properly handle distinguishing Enum maps from Object maps.
              return new Map<{}, Dynamic>();
          }
        }
      default:
        // Whatever.
        error(ECustom('Invalid key type for empty map initialization (${new Printer().typeToString(keyType)}).'));
    }
    return super.makeMap([], []);
  }

  function exprArray(entries:Array<Expr>):Dynamic
  {
    // Create an Array<Dynamic>
    var a = new Array();
    for (e in entries)
      a.push(expr(e));
    return a;
  }

  function getIdent(e:Expr):Null<String>
  {
    switch (#if hscriptPos e.e #else e #end)
    {
      case EIdent(v):
        return v;
      default:
        return null;
    }
  }

  override function makeIterator(v:Dynamic):Iterator<Dynamic>
  {
    if (v == null) errorEx(EInvalidIterator(v));
    if (v.iterator != null)
    {
      try
      {
        v = v.iterator();
      }
      catch (e:Dynamic) {};
    }
    if (Std.isOfType(v, Array))
    {
      v = new ArrayIterator(v);
    }
    if (v.hasNext == null || v.next == null)
    {
      errorEx(EInvalidIterator(v));
    }
    return v;
  }

  /**
   * Call a given function on a given target with the given arguments.
   * @param target The object to call the function on.
   *   If null, defaults to `this`.
   * @param fun The function to call.
   * @param args The arguments to apply to that function.
   * @return The result of the function call.
   */
  override function call(target:Dynamic, fun:Dynamic, args:Array<Dynamic>):Dynamic
  {
    // Calling fn() in hscript won't resolve an object first. Thus, we need to change it to use this.fn() instead.
    if (target == null && _nextCallObject != null)
    {
      target = _nextCallObject;
    }

    if (fun == null)
    {
      errorEx(EInvalidAccess(fun));
    }

    if (target != null && target == _proxy)
    {
      // If we are calling this.fn(), special handling is needed to prevent the local scope from being destroyed.
      // By checking `target == _proxy`, we handle BOTH fn() and this.fn().
      // super.fn() is exempt since it is not scripted.
      return callThis(fun, args);
    }
    else
    {
      try
      {
        var result = Reflect.callMethod(target, fun, args);
        _nextCallObject = null;
        return result;
      }
      catch (e:Dynamic)
      {
        _nextCallObject = null;

        if (Std.isOfType(e, PolymodExprEx.ErrorEx) || Std.isOfType(e, polymod.hscript._internal.Expr.Error))
        {
          throw e;
        }
        return errorEx(EScriptCallThrow(e));
      }
      return null;
    }
  }

  /**
   * Call a given function on the current proxy with the given arguments.
   * Ensures that the local scope is not destroyed.
   * @param fun The function to call.
   * @param args The arguments to apply to that function.
   * @return The result of the function call.
   */
  function callThis(fun:Dynamic, args:Array<Dynamic>):Dynamic
  {
    // If we are calling this.fn(), special handling is needed to prevent the local scope from being destroyed.
    // Store the local scope.
    var capturedLocals = this.duplicate(locals);
    var capturedDeclared = this.declared;
    var capturedDepth = this.depth;

    this.depth++;

    // Call the function.
    try
    {
      var result = Reflect.callMethod(_proxy, fun, args);

      // Restore the local scope.
      this.locals = capturedLocals;
      this.declared = capturedDeclared;
      this.depth = capturedDepth;

      return result;
    }
    catch (e:Dynamic)
    {
      // Restore the local scope.
      this.locals = capturedLocals;
      this.declared = capturedDeclared;
      this.depth = capturedDepth;

      if (Std.isOfType(e, PolymodExprEx.ErrorEx) || Std.isOfType(e, polymod.hscript._internal.Expr.Error))
      {
        throw e;
      }

      return errorEx(EScriptCallThrow(e));
    }
  }

  override function execute(expr:Expr):Dynamic
  {
    // If this function is being called (and not executeEx),
    // PolymodScriptClass is not being used to call the expression.
    // This happens during callbacks and in some other niche cases.
    // In this case, we know the parent caller doesn't have error handling!
    // That means we have to do it here.
    try
    {
      return super.execute(expr);
    }
    catch (err:PolymodExprEx.ErrorEx)
    {
      PolymodScriptClass.reportErrorEx(err, getClassFullyQualifiedName());
      return null;
    }
    catch (err:Expr.Error)
    {
      PolymodScriptClass.reportError(err, getClassFullyQualifiedName());
      return null;
    }
    catch (err:Dynamic)
    {
      throw err;
    }
  }

  public function executeEx(expr:Expr):Dynamic
  {
    // Directly call execute (assume error handling happens higher).
    return super.execute(expr);
  }

  override function get(o:Dynamic, f:String):Dynamic
  {
    if (o == null) errorEx(ENullObjectReference(f));

    var oCls:String = Util.getTypeName(Type.typeof(o));

    // Check if the field is a blacklisted static field.
    if (PolymodScriptClass.blacklistedStaticFields.exists(o) && PolymodScriptClass.blacklistedStaticFields.get(o).contains(f))
    {
      errorEx(EBlacklistedField(f));
      return null;
    }

    // If not, check if it is a blacklisted instance field.
    if (oCls.length > 0)
    {
      if (PolymodScriptClass.blacklistedInstanceFields.exists(oCls) && PolymodScriptClass.blacklistedInstanceFields.get(oCls).contains(f))
      {
        errorEx(EBlacklistedField(f));
        return null;
      }
    }

    // Otherwise, we assume the field is fine to use.
    if (Std.isOfType(o, PolymodStaticClassReference))
    {
      var ref:PolymodStaticClassReference = cast(o, PolymodStaticClassReference);

      return ref.getField(f);
    }
    else if (Std.isOfType(o, PolymodScriptClass))
    {
      var proxy:PolymodAbstractScriptClass = cast(o, PolymodScriptClass);
      if (proxy._interp.variables.exists(f))
      {
        return proxy._interp.variables.get(f);
      }
      else if (proxy.superClass != null && proxy.superHasField(f))
      {
        if (Std.isOfType(proxy.superClass, PolymodScriptClass))
        {
          var superClass:PolymodAbstractScriptClass = cast(proxy.superClass, PolymodScriptClass);
          return superClass.fieldRead(f);
        }

        return Reflect.getProperty(proxy.superClass, f);
      }
      else
      {
        try
        {
          return proxy.resolveField(f);
        }
        catch (e:Dynamic) {}

        // If we're here, the field doesn't exist on the proxy.
        errorEx(EUnknownVariable(f));
      }
    }
    else if (Std.isOfType(o, HScriptedClass))
    {
      if (o.scriptGet != null)
      {
        return o.scriptGet(f);
      }

      errorEx(EInvalidScriptedVarGet(f));

      // var result = Reflect.getProperty(o, f);
      // To save a bit of performance, we only query for the existence of the property
      // if the value is reported as null, AND only in debug builds.

      // #if debug
      // if (!Reflect.hasField(o, f))
      // {
      // 	  var propertyList = Type.getInstanceFields(Type.getClass(o));
      // 	  if (propertyList.indexOf(f) == -1)
      // 	  {
      // 	  	errorEx(EInvalidScriptedVarGet(f));
      // 	  }
      // }
      // #end
      // return result;
    }

    var abstractKey:String = Type.getClassName(o) + '.' + f;
    if (PolymodScriptClass.abstractClassStatics.exists(abstractKey))
    {
      return Reflect.getProperty(PolymodScriptClass.abstractClassStatics[abstractKey], abstractKey.replace('.', '_'));
    }

    // Default behavior
    if (Reflect.hasField(o, f))
    {
      return Reflect.field(o, f);
    }
    else
    {
      try
      {
        return Reflect.getProperty(o, f);
      }
      catch (e:Dynamic)
      {
        return Reflect.field(o, f);
      }
    }
    // return super.get(o, f);
  }

  override function set(o:Dynamic, f:String, v:Dynamic):Dynamic
  {
    if (o == null) errorEx(ENullObjectReference(f));

    var oCls:String = Util.getTypeName(Type.typeof(o));

    // Check if the field is a blacklisted static field.
    if (PolymodScriptClass.blacklistedStaticFields.exists(o) && PolymodScriptClass.blacklistedStaticFields.get(o).contains(f))
    {
      Polymod.error(SCRIPT_CLASS_FIELD_BLACKLISTED, 'Class field ${oCls}.${f} is blacklisted and cannot be used in scripts.');
      return null;
    }

    // If not, check if it is a blacklisted instance field.
    if (oCls.length > 0)
    {
      if (PolymodScriptClass.blacklistedInstanceFields.exists(oCls) && PolymodScriptClass.blacklistedInstanceFields.get(oCls).contains(f))
      {
        Polymod.error(SCRIPT_CLASS_FIELD_BLACKLISTED, 'Class field ${oCls}.${f} is blacklisted and cannot be used in scripts.');
        return null;
      }
    }

    // Otherwise, we assume the field is fine to use.
    if (Std.isOfType(o, PolymodStaticClassReference))
    {
      var ref:PolymodStaticClassReference = cast(o, PolymodStaticClassReference);

      return ref.setField(f, v);
    }
    else if (Std.isOfType(o, PolymodScriptClass))
    {
      var proxy:PolymodScriptClass = cast(o, PolymodScriptClass);
      if (proxy._interp.variables.exists(f))
      {
        proxy._interp.variables.set(f, v);
      }
      else if (proxy.superClass != null && proxy.superHasField(f))
      {
        if (Std.isOfType(proxy.superClass, PolymodScriptClass))
        {
          var superClass:PolymodAbstractScriptClass = cast(proxy.superClass, PolymodScriptClass);
          return superClass.fieldWrite(f, v);
        }

        Reflect.setProperty(proxy.superClass, f, v);
      }
      else
      {
        errorEx(EUnknownVariable(f));
      }
      return v;
    }
    else if (Std.isOfType(o, HScriptedClass))
    {
      if (o.scriptSet != null)
      {
        return o.scriptSet(f, v);
      }

      errorEx(EInvalidScriptedVarSet(f));

      // Reflect.setProperty(o, f, v);
      // return v;
    }

    try
    {
      Reflect.setProperty(o, f, v);
    }
    catch (e)
    {
      errorEx(EInvalidAccess(f));
    }
    return v;
  }

  private var _nextCallObject:Dynamic = null;

  override function exprReturn(expr:Expr):Dynamic
  {
    return super.exprReturn(expr);
    // catch (err:Expr.Error)
    // {
    // 	#if hscriptPos
    // 	throw err;
    // 	#else
    // 	throw err;
    // 	#end
    // }
  }

  override function resolve(id:String):Dynamic
  {
    _nextCallObject = null;
    if (id == "super")
    {
      if (_proxy == null)
      {
        errorEx(EInvalidInStaticContext("super"));
      }
      else if (_proxy.superClass == null)
      {
        if (_proxy._c.extend == null) errorEx(EClassInvalidSuper);
        return Reflect.makeVarArgs(_proxy.createSuperClass);
      }
      else
      {
        return _proxy.superClass;
      }
    }
    else if (id == "this")
    {
      if (_proxy != null)
      {
        return _proxy;
      }
      else
      {
        errorEx(EInvalidInStaticContext("this"));
      }
    }
    else if (id == "null")
    {
      return null;
    }

    if (locals.exists(id))
    {
      // NOTE: id may exist but be null
      return locals.get(id).r;
    }
    if (variables.exists(id))
    {
      // NOTE: id may exist but be null
      return variables.get(id);
    }

    // OVERRIDE CHANGE: Allow access to modules for calling static functions.

    // Attempt to access an import.
    if (getClassDecl() != null)
    {
      // This scripted class has imports.

      var importedClass:PolymodClassImport = getClassDecl().imports.get(id);
      if (importedClass != null)
      {
        if (importedClass.cls != null) return importedClass.cls;
        if (importedClass.enm != null) return importedClass.enm;

        // Resolve imported scripted classes.
        var result = PolymodStaticClassReference.tryBuild(importedClass.fullPath);
        if (result != null) return result;

        // If we are here, there is an imported class whose value is null, and it isn't a scripted class.
        // This means that we are attempting to access a BLACKLISTED module.
        errorEx(EBlacklistedModule(importedClass.fullPath));
      }
    }

    // Allow access to scripted classes for calling static functions.

    if (getClassDecl().name == id)
    {
      // Self-referencing
      return new PolymodStaticClassReference(getClassDecl());
    }
    else
    {
      // Try to retrieve a scripted class with this name in the same package.
      if (getClassDecl().pkg != null && getClassDecl().pkg.length > 0)
      {
        var localClassId = getClassDecl().pkg.join('.') + "." + id;
        var result = PolymodStaticClassReference.tryBuild(localClassId);
        if (result != null) return result;
      }

      // Try to retrieve a scripted class with this name in the base package.
      var result = PolymodStaticClassReference.tryBuild(id);
      if (result != null) return result;
    }

    // We are calling a LOCAL function from the same module.
    // We first check if any of the child classes has overriden the scripted function
    if (_proxy != null && _proxy.topASC?.hasScriptFunction(id) ?? false)
    {
      _nextCallObject = _proxy.topASC;
      return _proxy.topASC.resolveField(id);
    }
    if (_proxy != null && _proxy.findFunction(id, true) != null)
    {
      _nextCallObject = _proxy;
      return _proxy.resolveField(id);
    }
    else if (_proxy != null && _proxy.superHasField(id))
    {
      _nextCallObject = _proxy.superClass;

      if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
      {
        var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
        return superClass.fieldRead(id);
      }

      return Reflect.getProperty(_proxy.superClass, id);
    }
    else if (_proxy != null && _proxy.hasPurgedScriptFunction(id))
    {
      errorEx(EPurgedFunction(id));
    }
    else if (_proxy != null)
    {
      try
      {
        var r = _proxy.resolveField(id);
        _nextCallObject = _proxy;
        return r;
      }
      catch (e:Dynamic)
      {
        // Skip and fall through to the next case.
      }
    }

    if (getClassDecl() != null)
    {
      // We are retrieving an adjacent field from a static context.
      var cls = getClassDecl();
      var name = cls.name;
      if (cls.pkg != null && cls.pkg.length > 0)
      {
        name = cls.pkg.join('.') + "." + name;
      }
      return PolymodScriptClass.getScriptClassStaticField(name, id);
    }

    // If we're here, the field definitely doesn't exist.
    errorEx(EUnknownVariable(id));

    return null;
  }

  public function addModule(moduleContents:String, ?origin:String = "hscript")
  {
    var parser = new PolymodParserEx();
    var decls = parser.parseModule(moduleContents, origin);
    registerModules(decls, origin);
  }

  /**
   * Call a static function of a scripted class.
   * @param clsName The full classpath of the scripted class.
   * @param fnName The name of the function to call.
   * @param args The arguments to pass to the function.
   * @return The return value of the function.
   */
  public function callScriptClassStaticFunction(clsName:String, fnName:String, args:Array<Dynamic> = null):Dynamic
  {
    var fn:Null<FunctionDecl> = null;
    var imports:Map<String, PolymodClassImport> = [];

    var cls:Null<PolymodClassDeclEx> = _scriptClassDescriptors.get(clsName);
    if (cls != null)
    {
      imports = cls.imports;

      // TODO: Optimize with a cache?
      for (f in cls.staticFields)
      {
        if (f.name == fnName)
        {
          switch (f.kind)
          {
            case KFunction(func):
              fn = func;
            case _:
          }
        }
      }
    }
    else
    {
      Polymod.error(SCRIPT_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.');
      return null;
    }

    if (fn != null)
    {
      // Populate function arguments.

      // previousValues is used to restore variables after they are shadowed in the local scope.
      var previousClassDecl = _classDeclOverride;
      var previousValues:Map<String, Dynamic> = [];
      var i = 0;
      for (a in fn.args)
      {
        var value:Dynamic = null;

        if (args != null && i < args.length)
        {
          value = args[i];
        }
        else if (a.value != null)
        {
          value = this.expr(a.value);
        }

        // NOTE: We assign these as variables rather than locals because those get wiped when we enter the function.
        if (this.variables.exists(a.name))
        {
          previousValues.set(a.name, this.variables.get(a.name));
        }
        this.variables.set(a.name, value);
        i++;
      }

      this._classDeclOverride = cls;

      var result:Dynamic = null;
      try
      {
        result = this.exprReturn(fn.expr);
      }
      catch (err:PolymodExprEx.ErrorEx)
      {
        PolymodScriptClass.reportErrorEx(err, clsName, fnName);
        // A script error occurred while executing the script function.
        // Purge the function from the cache so it is not called again.
        // purgeStaticFunction(fnName);
        return null;
      }
      catch (err:Expr.Error)
      {
        PolymodScriptClass.reportError(err, clsName, fnName);
        // A script error occurred while executing the script function.
        // Purge the function from the cache so it is not called again.
        // purgeStaticFunction(fnName);
        return null;
      }

      // Restore previous values.
      for (a in fn.args)
      {
        if (previousValues.exists(a.name))
        {
          this.variables.set(a.name, previousValues.get(a.name));
        }
        else
        {
          this.variables.remove(a.name);
        }
      }
      this._classDeclOverride = previousClassDecl;

      return result;
    }
    else
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
        'Error while calling static function ${clsName}.${fnName}(): EInvalidAccess' + '\n' +
        'Static function "${fnName}" does not exist! Define it or call the correct function.');
      return null;
    }
  }

  public function hasScriptClassStaticFunction(clsName:String, fnName:String):Bool
  {
    var imports:Map<String, PolymodClassImport> = [];

    var cls:Null<PolymodClassDeclEx> = _scriptClassDescriptors.get(clsName);
    if (cls != null)
    {
      imports = cls.imports;

      // TODO: Optimize with a cache?
      for (f in cls.staticFields)
      {
        if (f.name == fnName)
        {
          switch (f.kind)
          {
            case KFunction(func):
              return true;
            case _:
          }
        }
      }
    }
    else
    {
      Polymod.error(SCRIPT_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.');
      return false;
    }

    return false;
  }

  public function getScriptClassStaticField(clsName:String, fieldName:String):Dynamic
  {
    var prefixedName = clsName + '#' + fieldName;
    var fieldDecl = getScriptClassStaticFieldDecl(clsName, fieldName);

    if (fieldDecl != null)
    {
      if (!this.variables.exists(prefixedName))
      {
        switch (fieldDecl.kind)
        {
          case KFunction(fn):
            var result = buildScriptClassStaticFunction(clsName, fieldName);
            this.variables.set(prefixedName, result);
            return result;
          case KVar(v):
            if (v.get != null)
            {
              switch (v.get)
              {
                case 'get':
                  var getterFunc = 'get_${fieldName}';
                  if (hasScriptClassStaticFunction(clsName, getterFunc))
                  {
                    return callScriptClassStaticFunction(clsName, getterFunc, []);
                  }
                  else
                  {
                    throw 'Could not resolve getter for property ${prefixedName}';
                  }
                case 'default':
                  var result = this.expr(v.expr);
                  this.variables.set(prefixedName, result);
                  return result;
                default:
                  throw 'Could not resolve getter for property ${prefixedName}';
              }
            }
            else if (v.expr != null)
            {
              var result = this.expr(v.expr);
              this.variables.set(prefixedName, result);
              return result;
            }
            else
            {
              throw 'Could not resolve field declaration for ${prefixedName}';
            }
          default:
            throw 'Could not resolve field kind for ${prefixedName}';
        }
      }
      else
      {
        return this.variables.get(prefixedName);
      }
    }
    else
    {
      errorEx(EInvalidAccess(fieldName));
      return null;
    }
  }

  private inline function buildScriptClassStaticFunction(clsName:String, fieldName:String):Dynamic
  {
    return Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
      return callScriptClassStaticFunction(clsName, fieldName, args);
    });
  }

  public function setScriptClassStaticField(clsName:String, fieldName:String, value:Dynamic):Dynamic
  {
    var prefixedName = clsName + '#' + fieldName;
    var fieldDecl = getScriptClassStaticFieldDecl(clsName, fieldName);
    if (fieldDecl != null)
    {
      if (!this.variables.exists(prefixedName))
      {
        switch (fieldDecl.kind)
        {
          case KFunction(_fn):
            throw 'Cannot override function ${prefixedName}';
          case KVar(v):
            if (v.set != null)
            {
              switch (v.set)
              {
                case 'set':
                  var setterFunc = 'set_${fieldName}';
                  if (hasScriptClassStaticFunction(clsName, setterFunc))
                  {
                    return callScriptClassStaticFunction(clsName, setterFunc, [value]);
                  }
                  else
                  {
                    throw 'Could not resolve setter for property ${prefixedName}';
                  }
                case 'default':
                  this.variables.set(prefixedName, value);
                  return value;
                default:
                  throw 'Could not resolve setter for property ${prefixedName}';
              }
            }
            else
            {
              this.variables.set(prefixedName, value);
              return value;
            }
        }
      }
      else
      {
        this.variables.set(prefixedName, value);
        return value;
      }
    }
    else
    {
      errorEx(EInvalidAccess(fieldName));
      return null;
    }
  }

  /**
   * Retrieve a static field declaration of a scripted class.
   * @param clsName The full classpath of the scripted class.
   * @param fieldName The name of the field to retrieve.
   * @return The value of the field.
   */
  public function getScriptClassStaticFieldDecl(clsName:String, fieldName:String):Null<FieldDecl>
  {
    if (_scriptClassDescriptors.exists(clsName))
    {
      var cls = _scriptClassDescriptors.get(clsName);
      var staticFields = cls.staticFields;

      // TODO: Optimize with a cache?
      for (f in staticFields)
      {
        if (f.name == fieldName)
        {
          return f;
        }
      }

      // Fallthrough.
      return null;
    }
    else
    {
      Polymod.error(SCRIPT_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.');
      return null;
    }
  }

  public function registerModules(module:Array<ModuleDecl>, ?origin:String = "hscript")
  {
    var pkg:Array<String> = null;
    var imports:Map<String, PolymodClassImport> = [];
    var importsToValidate:Map<String, PolymodClassImport> = [];
    var usings:Map<String, PolymodClassImport> = [];

    for (importPath in PolymodScriptClass.defaultImports.keys())
    {
      var splitPath = importPath.split(".");
      var clsName = splitPath[splitPath.length - 1];

      imports.set(clsName,
        {
          name: clsName,
          pkg: splitPath.slice(0, splitPath.length - 1),
          fullPath: importPath,
          cls: PolymodScriptClass.defaultImports.get(importPath),
        });
    }

    for (decl in module)
    {
      switch (decl)
      {
        case DPackage(path):
          pkg = path;
        case DImport(path, _, name):
          var clsName = path[path.length - 1];
          if (name != null) clsName = name;

          if (imports.exists(clsName))
          {
            if (imports.get(clsName) == null)
            {
              Polymod.error(SCRIPT_CLASS_MODULE_BLACKLISTED, 'Scripted class ${clsName} is blacklisted and cannot be used in scripts.', origin);
            }
            else
            {
              Polymod.warning(SCRIPT_CLASS_MODULE_ALREADY_IMPORTED, 'Scripted class ${clsName} has already been imported.', origin);
            }
            continue;
          }

          var importedClass:PolymodClassImport =
            {
              name: clsName,
              pkg: path.slice(0, path.length - 1),
              fullPath: path.join("."),
              cls: null,
              enm: null
            };

          if (PolymodScriptClass.importOverrides.exists(importedClass.fullPath))
          {
            // importOverrides can exist but be null (if it was set to null).
            // If so, that means the class is blacklisted.

            importedClass.cls = PolymodScriptClass.importOverrides.get(importedClass.fullPath);
          }
          else if (PolymodScriptClass.abstractClassImpls.exists(importedClass.fullPath))
          {
            // We used a macro to map each abstract to its implementation.
            importedClass.cls = PolymodScriptClass.abstractClassImpls.get(importedClass.fullPath);
            trace('RESOLVED ABSTRACT CLASS ${importedClass.fullPath} -> ${Type.getClassName(importedClass.cls)}');
            trace(Type.getClassFields(importedClass.cls));
          }
          else if (_scriptEnumDescriptors.exists(importedClass.fullPath))
          {
            // do nothing
          }
          else
          {
            var resultCls:Class<Dynamic> = Type.resolveClass(importedClass.fullPath);

            // If the class is not found, try to find it as an enum.
            var resultEnm:Enum<Dynamic> = null;
            if (resultCls == null) resultEnm = Type.resolveEnum(importedClass.fullPath);

            // If the class is still not found, skip this import entirely.
            if (resultCls == null && resultEnm == null)
            {
              // Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not import class ${importedClass.fullPath}', origin);
              // this could be a scripted class or enum that hasn't been registered yet
              importsToValidate.set(importedClass.name, importedClass);
              continue;
            }
            else if (resultCls != null)
            {
              importedClass.cls = resultCls;
            }
            else if (resultEnm != null)
            {
              importedClass.enm = resultEnm;
            }
          }

          Polymod.debug('Imported class ${importedClass.name} from ${importedClass.fullPath}');
          imports.set(importedClass.name, importedClass);
        case DUsing(path):
          var clsName = path[path.length - 1];

          if (usings.exists(clsName))
          {
            if (usings.get(clsName) == null)
            {
              Polymod.error(SCRIPT_CLASS_MODULE_BLACKLISTED, 'Scripted class ${clsName} is blacklisted and cannot be used in scripts.', origin);
            }
            else
            {
              Polymod.warning(SCRIPT_CLASS_MODULE_ALREADY_IMPORTED, 'Scripted class ${clsName} has already been used.', origin);
            }
            continue;
          }

          var importedClass:PolymodClassImport =
            {
              name: clsName,
              pkg: path.slice(0, path.length - 1),
              fullPath: path.join("."),
              cls: null,
              enm: null
            };

          if (PolymodScriptClass.importOverrides.exists(importedClass.fullPath))
          {
            // importOverrides can exist but be null (if it was set to null).
            // If so, that means the class is blacklisted.

            importedClass.cls = PolymodScriptClass.importOverrides.get(importedClass.fullPath);
          }
          else if (PolymodScriptClass.abstractClassImpls.exists(importedClass.fullPath))
          {
            // We used a macro to map each abstract to its implementation.
            importedClass.cls = PolymodScriptClass.abstractClassImpls.get(importedClass.fullPath);
            trace('RESOLVED ABSTRACT CLASS ${importedClass.fullPath} -> ${Type.getClassName(importedClass.cls)}');
            trace(Type.getClassFields(importedClass.cls));
          }
          else if (_scriptEnumDescriptors.exists(importedClass.fullPath))
          {
            // do nothing
          }
          else
          {
            var resultCls:Class<Dynamic> = Type.resolveClass(importedClass.fullPath);

            // If the class is still not found, skip this import entirely.
            if (resultCls == null)
            {
              // Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not import class ${importedClass.fullPath}', origin);
              // this could be a scripted class that hasn't been registered yet
              importsToValidate.set(importedClass.name, importedClass);
              continue;
            }
            else
            {
              importedClass.cls = resultCls;
            }
          }

          Polymod.debug('Using class ${importedClass.name} from ${importedClass.fullPath}');
          usings.set(importedClass.name, importedClass);
        case DClass(c):
          var instanceFields = [];
          var staticFields = [];
          for (f in c.fields)
          {
            if (f.access.contains(AStatic))
            {
              staticFields.push(f);
            }
            else
            {
              instanceFields.push(f);
            }
          }

          var classDecl:PolymodClassDeclEx =
            {
              imports: imports,
              importsToValidate: importsToValidate,
              usings: usings,
              pkg: pkg,
              name: c.name,
              params: c.params,
              meta: c.meta,
              isPrivate: c.isPrivate,
              extend: c.extend,
              implement: c.implement,
              fields: instanceFields,
              isExtern: c.isExtern,
              staticFields: staticFields,
            };
          registerScriptClass(classDecl);
        case DEnum(e):
          if (pkg != null)
          {
            imports.set(e.name,
              {
                name: e.name,
                pkg: pkg,
                fullPath: pkg.join(".") + "." + e.name,
                cls: null,
                enm: null,
              });
          }

          var enumDecl:PolymodEnumDeclEx =
            {
              pkg: pkg,
              name: e.name,
              fields: e.fields,
            };

          registerScriptEnum(enumDecl);
        case DTypedef(_):
      }
    }
  }

  public function clone():PolymodInterpEx
  {
    var _clone = new PolymodInterpEx(this.targetCls, this._proxy);

    // Pass the variables by reference
    _clone.variables = this.variables;

    for (k => v in this.locals)
    {
      _clone.locals.set(k, v);
    }

    for (v in this.declared)
    {
      if (!_clone.declared.contains(v)) _clone.declared.push(v);
    }

    _clone._nextCallObject = this._nextCallObject;
    _clone._classDeclOverride = this._classDeclOverride;
    _clone.depth = this.depth;
    _clone.curExpr = this.curExpr;
    _clone.inTry = this.inTry;
    return _clone;
  }
}

private class ArrayIterator<T>
{
  var a:Array<T>;
  var pos:Int;

  public inline function new(a)
  {
    this.a = a;
    this.pos = 0;
  }

  public inline function hasNext()
  {
    return pos < a.length;
  }

  public inline function next()
  {
    return a[pos++];
  }
}
