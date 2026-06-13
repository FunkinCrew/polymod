/*
 * Copyright (C)2008-2017 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

package polymod.hscript._internal;

import polymod.hscript._internal.Expr;
import polymod.util.Util;
import haxe.PosInfos;
import haxe.Constraints.IMap;

using StringTools;

private enum Stop
{
  SBreak;
  SContinue;
  SReturn;
}

/**
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(polymod.hscript._internal.PolymodAbstractScriptClass)
@:access(polymod.hscript._internal.PolymodScriptClass)
@:access(polymod.hscript._internal.PolymodEnum)
class Interp
{
  private var _proxy:PolymodAbstractScriptClass = null;
  var _classDeclOverride:ClassDecl = null;
  var targetCls:Class<Dynamic>;

  private static var _scriptClassImports:Map<String, Array<ClassImport>> = new Map<String, Array<ClassImport>>();
  private static var _scriptClassUsings:Map<String, Array<ClassImport>> = new Map<String, Array<ClassImport>>();
  private static var _scriptClassDescriptors:Map<String, ClassDecl> = new Map<String, ClassDecl>();
  private static var _scriptEnumDescriptors:Map<String, EnumDecl> = new Map<String, EnumDecl>();

  var _propTrack:Map<String, Bool> = [];

  static var defaultVariables:Map<String, Dynamic>;
  public var variables:Map<String, Dynamic>;

  var locals:Map<String, {r:Dynamic, ?isfinal:Bool}>;
  var binops:Map<String, Expr->Expr->Dynamic>;

  var depth:Int;
  var inTry:Bool;
  var declared:Array<{n:String, old:{r:Dynamic, ?isfinal:Bool}}>;
  var returnValue:Dynamic;

  #if hscriptPos
  var curExpr:Expr;
  #end

  function getClassDecl():ClassDecl
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
    locals = new Map();
    declared = [];
    depth = 0;
    inTry = false;
    resetVariables();
    initOps();
    _proxy = proxy;
    this.targetCls = targetCls;
  }

  function cnew(cl:String, args:Array<Dynamic>):Dynamic
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
      var importedClass:ClassImport = getClassDecl().imports.get(cl);
      if (_scriptClassDescriptors.exists(importedClass.fullPath))
      {
        // OVERRIDE CHANGE: Create a PolymodScriptClass instead of a ScriptClass
        var proxy:PolymodAbstractScriptClass = new PolymodScriptClass(_scriptClassDescriptors.get(importedClass.fullPath), args);
        return proxy;
      }

      // Ignore importedClass.enm as enums cannot be instantiated.

      // Importing a blacklisted module creates an import with a `null` class, so we check for that here.
      var abs = importedClass.abs;
      if (abs != null)
      {
        try
        {
          return abs.instantiate(args);
        }
        catch (e)
        {
          error(EInvalidModule(importedClass.fullPath));
        }
      }

      var cls = importedClass.cls;
      if (cls != null)
      {
        return Type.createInstance(cls, args);
      }

      error(EBlacklistedModule(importedClass.fullPath));
    }

    // Attempt to resolve the class without overrides.
    var cls = Type.resolveClass(cl);
    if (cls == null) cls = resolve(cl);
    if (cls == null) error(EInvalidModule(cl));
    return Type.createInstance(cls, args);
  }

  private var _nextCallObject:Dynamic = null;

  /**
   * Call a given function on a given target with the given arguments.
   * @param target The object to call the function on.
   *   If null, defaults to `this`.
   * @param fun The function to call.
   * @param args The arguments to apply to that function.
   * @return The result of the function call.
   */
  function call(target:Dynamic, fun:Dynamic, args:Array<Dynamic>):Dynamic
  {
    // Calling fn() in hscript won't resolve an object first. Thus, we need to change it to use this.fn() instead.
    if (target == null && _nextCallObject != null)
    {
      target = _nextCallObject;
    }

    if (fun == null)
    {
      error(EInvalidAccess(fun));
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

        if (Std.isOfType(e, Error))
        {
          throw e;
        }
        return error(EScriptCallThrow(e));
      }
      return null;
    }
  }

  /**
   * Note to self: Calls to `this.xyz()` will have the type of `o` as `polymod.hscript.PolymodScriptClass`.
   * Calls to `super.xyz()` will have the type of `o` as `stage.ScriptedStage`.
   */
  function fcall(o:Dynamic, f:String, args:Array<Dynamic>):Dynamic
  {
    // OVERRIDE CHANGE: Custom logic to handle super calls to prevent infinite recursion
    if (_proxy != null && o == _proxy.superClass && !Std.isOfType(o, PolymodScriptClass))
    {
      // Force call super function.
      return call(o, get(o, '__super_${f}'), args);
    }
    else if (Std.isOfType(o, PolymodStaticAbstractReference))
    {
      var ref:PolymodStaticAbstractReference = cast(o, PolymodStaticAbstractReference);
      return ref.callFunction(f, args);
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
      return get(o, "includes");
    }
    // For web: remove is inlined so we have to use something else.
    else if (f == "remove")
    {
      @:privateAccess
      return HxOverrides.remove(cast o, args[0]);
    }
    #end

    // Functions natively don't have the .bind() function, so we have to do them here.
    if (f == "bind" && Reflect.isFunction(o))
    {
      return Reflect.makeVarArgs(function(bindArgs:Array<Dynamic>)
      {
        return Reflect.callMethod(null, o, args.concat(bindArgs));
      });
    }

    if (Std.isOfType(o, HScriptedClass))
    {
      // This is a scripted class!
      // We should try to call the function on the scripted class.
      // If it doesn't exist, `asc.callFunction()` will handle generating an error message.
      if (o.scriptCall != null)
      {
        return o.scriptCall(f, args);
      }

      return error(EInvalidScriptedFnAccess(f));
    }
    else
    {
      // Throw an error for a missing function.
      return error(EInvalidAccess(f));
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

      if (Std.isOfType(e, Error))
      {
        throw e;
      }

      return error(EScriptCallThrow(e));
    }
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
    // For functions listScriptClasses and scriptInit, we want to return the needed values without much checking.
    if (fnName == "listScriptClasses")
    {
      return PolymodScriptClass.listScriptClassesExtending(clsName);
    }

    if (fnName == "scriptInit")
    {
      args = args ?? [];

      if (args.length < 1)
      {
        error(EInvalidArgCount(" for function 'scriptInit'", 1, args.length));
      }

      var clsToInit:String = Std.string(args.shift());
      var clsRef = PolymodStaticClassReference.tryBuild(clsToInit);

      if (clsRef == null)
      {
        Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
        'Could not construct instance of scripted class ($clsToInit extends ' + clsName + ')\nUnknown error building class reference');
        return null;
      }

      try
      {
        var result = clsRef.instantiate(args);
        if (result == null)
        {
          Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
          'Could not construct instance of scripted class ($clsToInit extends ' + clsName + '):\nUnknown error instantiating class');
          return null;
        }

        return result;
      }
      catch (error)
      {
        var callStack:String = polymod.util.Util.fetchCallStack();

        Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
          'An uncaught exception was thrown while constructing an instance of scripted class ($clsToInit extends ' + clsName + '):\n$error\n$callStack',
          SCRIPT_RUNTIME);
        return null;
      }
    }

    var fn:Null<FunctionDecl> = null;
    var imports:Map<String, ClassImport> = [];

    var cls:Null<ClassDecl> = _scriptClassDescriptors.get(clsName);
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
      Polymod.error(SCRIPTED_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.', SCRIPT_RUNTIME);
      return null;
    }

    if (fn != null)
    {
      // Populate function arguments.

      var previousClassDecl = _classDeclOverride;
      // previousValues is used to restore variables after they are shadowed in the local scope.
      var previousValues:Map<String, Dynamic> = setFunctionValues(fn, args, fnName);

      this._classDeclOverride = cls;

      var localsCopy:Map<String, {r:Dynamic, ?isfinal:Null<Bool>}> = this.locals.copy();
      var result:Dynamic = null;
      try
      {
        result = this.executeEx(fn.expr);
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
      this.locals = localsCopy;

      return result;
    }
    else
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
      'Error while calling static function ${clsName}.${fnName}(): EInvalidAccess' + '\n' +
      'Static function "${fnName}" does not exist! Define it or call the correct function.', SCRIPT_RUNTIME);
      return null;
    }
  }

  static function registerScriptClass(c:ClassDecl)
  {
    var name = Util.getFullClassName(c);

    if (_scriptClassDescriptors.exists(name))
    {
      Polymod.error(SCRIPTED_CLASS_ALREADY_REGISTERED,
      'Scripted class with fully qualified name "$name" has already been defined. Please change the class name or the package name to ensure uniqueness.',
      SCRIPT_RUNTIME);
      return;
    }
    else
    {
      Polymod.debug('Registering scripted class $name');
      _scriptClassDescriptors.set(name, c);
    }
  }

  private static function registerScriptEnum(e:EnumDecl)
  {
    var name = e.name;
    if (e.pkg != null)
    {
      name = e.pkg.join(".") + "." + name;
    }

    if (_scriptEnumDescriptors.exists(name))
    {
      Polymod.error(SCRIPTED_CLASS_ALREADY_REGISTERED,
      'An enum with the fully qualified name "$name" has already been defined. Please change the enum name to ensure a unique name.',
      SCRIPT_RUNTIME);
      return;
    }
    else
    {
      Polymod.debug('Registering scripted enum $name');
      _scriptEnumDescriptors.set(name, e);
    }
  }

  private static function registerImportForPackage(pkg:Null<Array<String>>, imp:ClassImport, isUsing:Bool = false)
  {
    var impFilePkg:String = pkg?.join(".") ?? "";
    var map:Map<String, Array<ClassImport>> = isUsing ? _scriptClassUsings : _scriptClassImports;

    if (!map.exists(impFilePkg))
    {
      map.set(impFilePkg, []);
    }

    map.get(impFilePkg).push(imp);
  }

  public static function findScriptClassDescriptor(name:String)
  {
    return _scriptClassDescriptors.get(name);
  }

  private function resetVariables()
  {
    variables = new Map<String, Dynamic>();
    variables.set("null", null);
    variables.set("true", true);
    variables.set("false", false);
    variables.set("trace", Reflect.makeVarArgs(function(el) {
      var inf = posInfos();
      var v = el.shift();
      if (el.length > 0) inf.customParams = el;
      haxe.Log.trace(Std.string(v), inf);
    }));

    variables.set("Math", #if hl polymod.hscript._internal.HLWrapperMacro.HLMath #else Math #end);
    variables.set("Std", #if hl polymod.hscript._internal.HLWrapperMacro.HLStd #else Std #end);

    variables.set("Array", Array);
    variables.set("Bool", Bool);
    variables.set("Dynamic", Dynamic);
    variables.set("Float", Float);
    variables.set("Int", Int);
    variables.set("String", String);

    if (defaultVariables == null)
    {
      defaultVariables = variables.copy();
    }
  }

  public function clearScriptClassDescriptors():Void
  {
    // Clear the script class descriptors.
    _scriptClassDescriptors.clear();

    // Also clear the imports from the import.hx files.
    _scriptClassImports.clear();
    _scriptClassUsings.clear();

    // Also destroy local variable scope.
    this.resetVariables();
  }

  public function clearScriptEnumDescriptors():Void
  {
    // Clear the script enum descriptors.
    _scriptEnumDescriptors.clear();

    // Also destroy local variable scope.
    this.resetVariables();
  }

  public function posInfos():PosInfos
  {
    #if hscriptPos
    if (curExpr != null) return cast {fileName: curExpr.origin, lineNumber: curExpr.line};
    #end
    return cast {fileName: "hscript", lineNumber: 0};
  }

  function initOps()
  {
    var me = this;
    binops = new Map();
    binops.set("+", function(e1, e2) return me.expr(e1) + me.expr(e2));
    binops.set("-", function(e1, e2) return me.expr(e1) - me.expr(e2));
    binops.set("*", function(e1, e2) return me.expr(e1) * me.expr(e2));
    binops.set("/", function(e1, e2) return me.expr(e1) / me.expr(e2));
    binops.set("%", function(e1, e2) return me.expr(e1) % me.expr(e2));
    binops.set("&", function(e1, e2) return me.expr(e1) & me.expr(e2));
    binops.set("|", function(e1, e2) return me.expr(e1) | me.expr(e2));
    binops.set("^", function(e1, e2) return me.expr(e1) ^ me.expr(e2));
    binops.set("<<", function(e1, e2) return me.expr(e1) << me.expr(e2));
    binops.set(">>", function(e1, e2) return me.expr(e1) >> me.expr(e2));
    binops.set(">>>", function(e1, e2) return me.expr(e1) >>> me.expr(e2));
    binops.set("==", function(e1, e2) return me.expr(e1) == me.expr(e2));
    binops.set("!=", function(e1, e2) return me.expr(e1) != me.expr(e2));
    binops.set(">=", function(e1, e2) return me.expr(e1) >= me.expr(e2));
    binops.set("<=", function(e1, e2) return me.expr(e1) <= me.expr(e2));
    binops.set(">", function(e1, e2) return me.expr(e1) > me.expr(e2));
    binops.set("<", function(e1, e2) return me.expr(e1) < me.expr(e2));
    binops.set("||", function(e1, e2) return me.expr(e1) == true || me.expr(e2) == true);
    binops.set("&&", function(e1, e2) return me.expr(e1) == true && me.expr(e2) == true);
    binops.set("=", assign);
    binops.set("...", function(e1, e2) return new IntIterator(me.expr(e1), me.expr(e2)));
    binops.set("is", function(e1, e2) return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (me.expr(e1), me.expr(e2)));
    binops.set("??", function(e1, e2) return me.expr(e1) ?? me.expr(e2));
    assignOp("+=", function(v1:Dynamic, v2:Dynamic) return v1 + v2);
    assignOp("-=", function(v1:Float, v2:Float) return v1 - v2);
    assignOp("*=", function(v1:Float, v2:Float) return v1 * v2);
    assignOp("/=", function(v1:Float, v2:Float) return v1 / v2);
    assignOp("%=", function(v1:Float, v2:Float) return v1 % v2);
    assignOp("&=", function(v1, v2) return v1 & v2);
    assignOp("|=", function(v1, v2) return v1 | v2);
    assignOp("^=", function(v1, v2) return v1 ^ v2);
    assignOp("<<=", function(v1, v2) return v1 << v2);
    assignOp(">>=", function(v1, v2) return v1 >> v2);
    assignOp(">>>=", function(v1, v2) return v1 >>> v2);
    assignOp("??" + "=", function(v1, v2) return v1 ?? v2);
  }

  function setVar(id:String, v:Dynamic):Dynamic
  {
    if (_proxy != null && _proxy.superHasField(id))
    {
      if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
      {
        var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
        return superClass.fieldWrite(id, v);
      } else {
        set(_proxy.superClass, id, v);
        return v;
      }
    }

    // Fallback to setting in local scope.
    variables.set(id, v);
    return v;
  }

  /**
   * Initializes function arguments within the interpreter scope.
   *
   * @param fn The function declaration to extract arguments from.
   * @param args The arguments to pass to the function.
   * @param name The function's name
   * @return The Map containing the variable values before they are shadowed in the local scope.
   */
  public function setFunctionValues(fn:Null<FunctionDecl>, args:Array<Dynamic> = null, name:String = "Unknown"):Map<String, Dynamic>
  {
    var previousValues:Map<String, Dynamic> = [];
    if (fn == null) return previousValues;

    validateArgumentCount(fn.args, args, name);

    var i = 0;
    for (a in fn.args)
    {
      var value:Dynamic = null;

      // Uses the passed value if provided and not null, if not fall back to the default value defined in the function argument.
      if (args != null && i < args.length && args[i] != null)
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

    return previousValues;
  }

  function assign(e1:Expr, e2:Expr):Dynamic
  {
    return assignValue(e1, expr(e2));
  }

  function assignValue(e1:Expr, v:Dynamic, _abstractInlineAssign:Bool = false):Dynamic
  {
    switch (Tools.expr(e1))
    {
      case EIdent(id):
        // Make sure setting superclass fields directly works.
        // Also ensures property functions are accounted for.
        if (_proxy != null && _proxy.superHasField(id))
        {
          if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
          {
            var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
            return superClass.fieldWrite(id, v);
          }

          // Directly assign the value.
          // This is needed because `assignValue` may sometimes be called from the constructor.
          PolymodAbstractScriptClass.setClassObjectField(_proxy.superClass, id, v);
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
                // Allow assigning to "null" only for local fields.
                final setName = 'set_$id';
                if (!_propTrack.exists(setName))
                {
                  _propTrack.set(setName, true);
                  var out = _proxy.callFunction(setName, [v]);
                  _propTrack.remove(setName);
                  return (out == null) ? v : out;
                }

              case "never":
                error(EInvalidPropSet(id));
                return null;

              case "null":
                // If the property setter is "null", it can only be assigned on local fields.
                // Thankfully, this is a local field!
                // So we can just fallthrough to the default case.
            }

            if ((decl?.isfinal ?? false) && decl?.expr != null)
            {
              error(EInvalidFinalSet(id));
              return null;
            }
          }
        }

        var l = locals.get(id);
        if (l != null && l.isfinal && l.r != null) return error(EInvalidAccess(id));
        if (l == null) setVar(id, v);
        else
          l.r = v;
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
                if (Std.isOfType(_proxy.superClass, PolymodScriptClass))
                {
                  var superClass:PolymodAbstractScriptClass = cast(_proxy.superClass, PolymodScriptClass);
                  return superClass.fieldWrite(id, v);
                }

                // Directly assign the value.
                // This is needed because `assignValue` may sometimes be called from the constructor.
                PolymodAbstractScriptClass.setClassObjectField(_proxy.superClass, id, v);
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
                    var finals = PolymodFinalMacro.getFinals(imp.fullPath);

                    if (finals.contains(id))
                    {
                      error(EInvalidFinalSet(id));
                      return null;
                    }

                    var privates = PolymodFinalMacro.getPrivateProperties(imp.fullPath);

                    if (privates.contains(id))
                    {
                      error(EInvalidPropSet(id));
                      return null;
                    }
                  }
                }
              }
            }
          default:
          // Do nothing
        }

        // Fallback to field set
        v = set(expr(e0), id, v);
      case EArray(e, index):
        var arr:Dynamic = expr(e);
        var index:Dynamic = expr(index);
        if (isMap(arr))
        {
          setMapValue(arr, index, v);
        }
        else
        {
          arr[index] = v;
        }

      default:
        if (!_abstractInlineAssign)
        {
          error(EInvalidOp("="));
        }
    }
    return v;
  }

  function assignOp(op, fop:Dynamic->Dynamic->Dynamic)
  {
    var me = this;
    binops.set(op, function(e1, e2) return me.evalAssignOp(op, fop, e1, e2));
  }

  function evalAssignOp(op, fop, e1, e2):Dynamic
  {
    var v:Dynamic = null;

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
                case "never": error(EInvalidPropGet(id));
                default: expr(e1);
              }

              v = fop(value, expr(e2));

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
                  error(EInvalidPropSet(id));
                  return v;
              }
            }
          }
        }

        // Fallback to local variable
        var l = locals.get(id);
        v = fop(expr(e1), expr(e2));
        if (l != null && l.isfinal && l.r != null) return error(EInvalidAccess(id));
        if (l == null) setVar(id, v)
        else
          l.r = v;
      case EField(e, f):
        var obj = expr(e);
        v = fop(get(obj, f), expr(e2));
        v = set(obj, f, v);
      case EArray(e, index):
        var arr:Dynamic = expr(e);
        var index:Dynamic = expr(index);
        if (isMap(arr))
        {
          v = fop(getMapValue(arr, index), expr(e2));
          setMapValue(arr, index, v);
        }
        else
        {
          v = fop(arr[index], expr(e2));
          arr[index] = v;
        }
      default:
        return error(EInvalidOp(op));
    }
    return v;
  }

  function increment(e:Expr, prefix:Bool, delta:Int):Dynamic
  {
    #if hscriptPos
    curExpr = e;
    #end

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
                case "never": error(EInvalidPropGet(id));
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
                  return error(EInvalidPropSet(id));
              }
            }
          }
        }

        var l = locals.get(id);
        var v:Dynamic = (l == null) ? resolve(id) : l.r;
        if (l != null && l.isfinal && l.r != null) return error(EInvalidFinalSet(id));
        if (prefix)
        {
          v += delta;
          if (l == null) setVar(id, v)
          else
            l.r = v;
        }
        else if (l == null) setVar(id, v + delta)
        else
          l.r = v + delta;
        return v;
      case EField(e, f):
        var obj = expr(e);
        var v:Dynamic = get(obj, f);
        if (prefix)
        {
          v += delta;
          set(obj, f, v);
        }
        else
          set(obj, f, v + delta);
        return v;
      case EArray(e, index):
        var arr:Dynamic = expr(e);
        var index:Dynamic = expr(index);
        if (isMap(arr))
        {
          var v = getMapValue(arr, index);
          if (prefix)
          {
            v += delta;
            setMapValue(arr, index, v);
          }
          else
          {
            setMapValue(arr, index, v + delta);
          }
          return v;
        }
        else
        {
          var v = arr[index];
          if (prefix)
          {
            v += delta;
            arr[index] = v;
          }
          else
            arr[index] = v + delta;
          return v;
        }
      default:
        return error(EInvalidOp((delta > 0) ? "++" : "--"));
    }
  }

  public function execute(expr:Expr):Dynamic
  {
    // If this function is being called (and not executeEx),
    // PolymodScriptClass is not being used to call the expression.
    // This happens during callbacks and in some other niche cases.
    // In this case, we know the parent caller doesn't have error handling!
    // That means we have to do it here.
    try
    {
      return executeEx(expr);
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
    depth = 0;
    locals = new Map();
    declared = new Array();
    return exprReturn(expr);
  }

  function exprReturn(e):Dynamic
  {
    try
    {
      return expr(e);
    }
    catch (e:Stop)
    {
      switch (e)
      {
        case SBreak:
          throw "Invalid break";
        case SContinue:
          throw "Invalid continue";
        case SReturn:
          var v = returnValue;
          returnValue = null;
          return v;
      }
    }
    return null;
    // catch (err:Expr.Error)
    // {
    // 	#if hscriptPos
    // 	throw err;
    // 	#else
    // 	throw err;
    // 	#end
    // }
  }

  function duplicate<T>(h:Map<String, T>)
  {
    var h2 = new Map();
    for (k in h.keys())
      h2.set(k, h.get(k));
    return h2;
  }

  function restore(old:Int)
  {
    while (declared.length > old)
    {
      var d = declared.pop();
      locals.set(d.n, d.old);
    }
  }

  public inline function error(e:#if hscriptPos ErrorDef #else Error #end, rethrow = false):Dynamic
  {
    #if hscriptPos var e = new Error(e, curExpr?.pmin ?? 0, curExpr?.pmax ?? 0, curExpr?.origin ?? 'unknown', curExpr?.line ?? 0); #end
    if (rethrow) this.rethrow(e)
    else
      throw e;
    return null;
  }

  inline function rethrow(e:Dynamic)
  {
    #if hl
    hl.Api.rethrow(e);
    #else
    throw e;
    #end
  }

  function resolve(id:String):Dynamic
  {
    _nextCallObject = null;
    if (id == "super")
    {
      if (_proxy == null)
      {
        error(EInvalidInStaticContext("super"));
      }
      else if (_proxy.superClass == null)
      {
        if (_proxy._c.extend == null) error(EClassInvalidSuper);
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
        error(EInvalidInStaticContext("this"));
      }
    }
    else if (id == "null")
    {
      return null;
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

      var importedClass:ClassImport = getClassDecl().imports.get(id);
      if (importedClass != null)
      {
        if (importedClass.cls != null) return importedClass.cls;
        if (importedClass.enm != null) return importedClass.enm;
        if (importedClass.abs != null) return importedClass.abs;

        // Resolve imported scripted classes.
        var result = PolymodStaticClassReference.tryBuild(importedClass.fullPath);
        if (result != null) return result;

        // If we are here, there is an imported class whose value is null, and it isn't a scripted class.
        // This means that we are attempting to access a BLACKLISTED module.
        error(EBlacklistedModule(importedClass.fullPath));
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
      error(EPurgedFunction(id));
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
    error(EUnknownVariable(id));

    return null;
  }

  /**
   * Tries to resolve the type of an imported class, which will end up in `cls`, `enm` or `abs`.
   * @param importedClass The import to resolve.
   * @param ignoreEnums Whether to skip resolving enums. Used when resolving a `using` import.
   * @return `false` if this import was blacklisted, otherwise always `true`.
   */
  function resolveImportedClass(importedClass:ClassImport, ignoreEnums:Bool = false):Bool
  {
    // The path without the possibly included module name, which resolve methods disregard.
    final modulelessPath:String = importedClass.pkg.slice(0, -1).concat([importedClass.name]).join('.');
    for (fullPath in [importedClass.fullPath, modulelessPath])
    {
      if (PolymodScriptClass.importOverrides.exists(fullPath))
      {
        // importOverrides can exist but be null (if it was set to null).
        // If so, that means the class is blacklisted.
        importedClass.cls = PolymodScriptClass.importOverrides.get(fullPath) ?? return false;
        break;
      }
      else if (PolymodScriptClass.abstractClassImpls.exists(fullPath))
      {
        // We used a macro to map each abstract to its implementation.
        importedClass.abs = PolymodScriptClass.abstractClassImpls.get(fullPath);
        break;
      }
      else if (PolymodScriptClass.typedefs.exists(fullPath))
      {
        importedClass.cls = PolymodScriptClass.typedefs.get(fullPath);
        break;
      }
      else
      {
        var resultCls:Class<Dynamic> = Type.resolveClass(fullPath);
        if (resultCls != null)
        {
          importedClass.cls = resultCls;
          break;
        }

        if (ignoreEnums) continue;
        // If the class is not found, try to find it as an enum.
        var resultEnm:Enum<Dynamic> = Type.resolveEnum(fullPath);
        if (resultEnm != null)
        {
          importedClass.enm = resultEnm;
          break;
        }
      }
    }

    return true;
  }

  public function expr(e:Expr):Dynamic
  {
    #if hscriptPos
    curExpr = e;
    #end
    switch (Tools.expr(e))
    {
      case EConst(c):
        switch (c)
        {
          case CInt(v): return v;
          case CFloat(f): return f;
          case CString(s): return s;
        }
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
                      if (!hasIsVar) return error(EPropVarNotReal(id));
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

        var l = locals.get(id);
        if (l != null) return l.r;
        return resolve(id);
      case EVar(name, type, expression):
        declared.push({n: name, old: locals.get(name)});

        // Evaluate the expression before assigning, applying typing if possible.
        var result = (expression != null) ? exprWithType(expression, type) : null;

        locals.set(name, {r: result, isfinal: false});

        return null;
      case EFinal(name, type, expression):
        declared.push({n: name, old: locals.get(name)});

        // Evaluate the expression before assigning, applying typing if possible.
        var result = (expression != null) ? exprWithType(expression, type) : null;

        locals.set(name, {r: result, isfinal: true});

        return null;
      case EParent(e0):
        return expr(e0);
      case EBlock(exprs):
        var old = declared.length;
        var v = null;
        for (e in exprs)
          v = expr(e);
        restore(old);
        return v;
      case EField(e, f):
        var name = getIdent(e);
        name = getClassDecl().imports.get(name)?.fullPath ?? name;
        if (name != null && _scriptEnumDescriptors.exists(name))
        {
          return new PolymodEnum(_scriptEnumDescriptors.get(name), f, []);
        }
        return get(expr(e), f);
      case EBinop(op, e1, e2):
        var fop = binops.get(op);
        if (fop == null) error(EInvalidOp(op));
        return fop(e1, e2);
      case EUnop(op, prefix, e):
        switch (op)
        {
          case "!":
            return expr(e) != true;
          case "-":
            return -expr(e);
          case "++":
            return increment(e, prefix, 1);
          case "--":
            return increment(e, prefix, -1);
          case "~":
            return ~expr(e);
          default:
            error(EInvalidOp(op));
        }
      case ECall(e, params):
        switch (Tools.expr(e))
        {
          case EField(e, f):
            var name = getIdent(e);
            if (name != null)
            {
              var imp = getClassDecl().imports.get(name);
              if (imp != null)
              {
                if (_scriptEnumDescriptors.exists(imp.fullPath))
                {
                  var args = new Array();
                  for (p in params)
                    args.push(expr(p));

                  return new PolymodEnum(_scriptEnumDescriptors.get(imp.fullPath), f, args);
                }
                else if (imp.abs != null && imp.abs.hasInlineFunction(f))
                {
                  var args = new Array();
                  for (p in params)
                    args.push(expr(p));

                  return imp.abs.callInlineFunction(this, params[0], f, args);
                }
              }
            }
          default:
        }

        var args = new Array();
        for (p in params)
          args.push(expr(p));

        switch (Tools.expr(e))
        {
          case EField(e, f):
            var obj = expr(e);
            if (obj == null) error(ENullObjectReference(f));
            return fcall(obj, f, args);
          default:
            return call(null, expr(e), args);
        }
      case EIf(econd, e1, e2):
        return if (expr(econd) == true) expr(e1) else if (e2 == null) null else expr(e2);
      case EWhile(econd, e):
        whileLoop(econd, e);
        return null;
      case EDoWhile(econd, e):
        doWhileLoop(econd, e);
        return null;
      case EFor(v, it, e):
        forLoop(v, it, e);
        return null;
      case EForGen(it, e):
        Tools.getKeyIterator(it, function(vk, vv, it) {
          if (vk == null)
          {
            #if hscriptPos
            curExpr = it;
            #end
            error(ECustom("Invalid for expression"));
            return;
          }
          forKeyValueLoop(vk, vv, it, e);
        });
        return null;
      case EBreak:
        throw SBreak;
      case EContinue:
        throw SContinue;
      case ECast(e, t):
        return expr(e);
      case EReturn(e):
        returnValue = e == null ? null : expr(e);
        throw SReturn;
      case EFunction(params, fexpr, name, _):
        var capturedLocals = duplicate(this.locals);
        var capturedVariables:Map<String, Dynamic> = [];
        var capturedCallObject = this._nextCallObject;
        var capturedClassDeclOverride = this._classDeclOverride;
        var me = this;

        // Retrieve only the non-default variables
        for (k => v in variables)
        {
          if (!defaultVariables.exists(k))
          {
            capturedVariables.set(k, v);
          }
        }

        // This CREATES a new function in memory, that we call later.
        var newFun:Dynamic = function(args:Array<Dynamic>) {
          if (args == null) args = [];

          validateArgumentCount(params, args, name);

          // make sure mandatory args are forced
          var args2 = [];
          var pos = 0;
          for (p in params)
          {
            if (pos < args.length)
            {
              var arg = args[pos++];
              if (arg == null && p.value != null)
              {
                args2.push(expr(p.value));
              }
              else
              {
                args2.push(arg);
              }
            }
            else
            {
              if (p.value != null)
              {
                args2.push(expr(p.value));
              }
              else
              {
                args2.push(null);
              }
            }
          }
          args = args2;

          var old = me.locals;
          var depth = me.depth;
          var oldCallObject = me._nextCallObject;
          var oldClsDeclOverride = me._classDeclOverride;
          me.depth++;
          me.locals = duplicate(capturedLocals);
          me._nextCallObject = capturedCallObject;
          me._classDeclOverride = capturedClassDeclOverride;

          // Restore removed variables (those are usually arguments)
          for (k => v in capturedVariables)
          {
            if (me.variables.exists(k))
            {
              capturedVariables.remove(k);
              continue;
            }
            me.variables.set(k, v);
          }

          for (i in 0...params.length)
          {
            me.locals.set(params[i].name, {r: args[i]});
          }
          var oldDecl = declared.length;
          var r = null;

          inline function restoreContext()
          {
            // Remove the restored arguments again
            for (k in capturedVariables.keys())
            {
              me.variables.remove(k);
            }

            restore(oldDecl);
            me.locals = old;
            me.depth = depth;
            me._nextCallObject = oldCallObject;
            me._classDeclOverride = oldClsDeclOverride;
          }

          if (inTry)
          {
            // True if the SCRIPT wraps the function in a try/catch block.
            try
            {
              r = me.exprReturn(fexpr);
            }
            catch (e:Dynamic)
            {
              restoreContext();
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
              r = me.exprReturn(fexpr);
            }
            catch (err:Expr.Error)
            {
              PolymodScriptClass.reportError(err, getClassFullyQualifiedName(), name);
              r = null;
            }
            catch (err:Dynamic)
            {
              restoreContext();
              throw err;
            }
          }

          restoreContext();
          return r;
        };

        newFun = Reflect.makeVarArgs(newFun);
        if (name != null)
        {
          // function-in-function is a local function
          declared.push({n: name, old: locals.get(name)});
          var ref = {r: newFun};
          locals.set(name, ref);
          capturedLocals.set(name, ref); // allow self-recursion
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
      case EArray(e, index):
        var arr:Dynamic = expr(e);
        var index:Dynamic = expr(index);
        if (isMap(arr)) return getMapValue(arr, index);
        return arr[index];
      case ENew(cl, params):
        var a = new Array();
        for (e in params)
          a.push(expr(e));
        return cnew(cl, a);
      case EThrow(e):
        // If there is a try/catch block, the error will be caught.
        // If there is no try/catch block, the error will be reported.
        error(EScriptThrow('${expr(e)}'));
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
        catch (error:Error)
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
          if (en != null && en.getName().endsWith("Interp.Stop"))
          {
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
      case EObject(fl):
        var o = {};
        for (f in fl)
          set(o, f.name, expr(f.e));
        return o;
      case ETernary(econd, e1, e2):
        return if (expr(econd) == true) expr(e1) else expr(e2);
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
        else
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
                      var valStr:String = cast val;
                      valStr = valStr.substring(0, valStr.indexOf("("));
                      if (valStr == f)
                      {
                        var valParams = Type.enumParameters(val);
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
                              locals.set(n, {r: valParams[i]});
                            default:
                          }
                        }
                        match = true;
                        break;
                      }
                    default:
                  }
                default:
                  if (expr(v) == val)
                  {
                    match = true;
                    break;
                  }
              }
            }
            if (match)
            {
              val = expr(c.expr);
              break;
            }
          }
          if (!match) val = def == null ? null : expr(def);
          restore(old);
          return val;
        }
      case EMeta(_, _, e):
        return expr(e);
      case ECheckType(e, _):
        return expr(e);

    }
    return null;
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
    #end

    switch (Tools.expr(e))
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
                  var err = 'Invalid expression in map initialization (expected key=>value, got ${Printer.toString(e)})';
                  error(ECustom(err));
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
                  var err = 'Invalid expression in array initialization (expected no key=>value pairs, got ${Printer.toString(e)})';
                  error(ECustom(err));
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
    if (entries.length == 0) return makeMap([], []);

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
          var err = 'Invalid expression in map initialization (expected key=>value, got ${Printer.toString(e)})';
          error(ECustom(err));
      }
    }

    return makeMap(keys, values);
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
    return makeMap([], []);
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
    switch (Tools.expr(e))
    {
      case EIdent(v):
        return v;
      default:
        return null;
    }
  }

  function doWhileLoop(econd, e)
  {
    var old = declared.length;
    do
    {
      if (!loopRun(() -> expr(e))) break;
    }
    while (expr(econd) == true);
    restore(old);
  }

  function whileLoop(econd, e)
  {
    var old = declared.length;
    while (expr(econd) == true)
    {
      if (!loopRun(() -> expr(e))) break;
    }
    restore(old);
  }

  function makeIterator(v:Dynamic):Iterator<Dynamic>
  {
    if (v == null) error(EInvalidIterator(v));
    if (v.iterator != null)
    {
      try
      {
        #if hl
        // HL is a bit weird with iterators with arguments
        v = Reflect.callMethod(v, v.iterator, []);
        #else
        v = v.iterator();
        #end
      }
      catch (e:Dynamic) {};
    }
    if (Std.isOfType(v, Array))
    {
      v = new ArrayIterator(v);
    }
    if (v.hasNext == null || v.next == null)
    {
      error(EInvalidIterator(v));
    }
    return v;
  }

  function makeKeyValueIterator(v:Dynamic):KeyValueIterator<Dynamic, Dynamic>
  {
    #if js
    // don't use try/catch (very slow)
    if (v is Array) return (v : Array<Dynamic>).keyValueIterator();
    if (v.keyValueIterator != null) v = v.keyValueIterator();
    #else
    try
      v = v.keyValueIterator()
    catch (e:Dynamic) {};
    #end
    if (v.hasNext == null || v.next == null) error(EInvalidIterator(v));
    return v;
  }

  function forLoop(n, it, e)
  {
    var old = declared.length;
    declared.push({n: n, old: locals.get(n)});
    var it = makeIterator(expr(it));
    while (it.hasNext())
    {
      locals.set(n, {r: it.next()});
      if (!loopRun(() -> expr(e))) break;
    }
    restore(old);
  }

  function forKeyValueLoop(vk, vv, it, e)
  {
    var old = declared.length;
    declared.push({n: vk, old: locals.get(vk)});
    declared.push({n: vv, old: locals.get(vv)});
    var it = makeKeyValueIterator(expr(it));
    while (it.hasNext())
    {
      var v = it.next();
      locals.set(vk, {r: v.key});
      locals.set(vv, {r: v.value});
      if (!loopRun(() -> expr(e))) break;
    }
    restore(old);
  }

  inline function loopRun(f:Void->Void)
  {
    var cont = true;
    try
    {
      f();
    }
    catch (err:Stop)
    {
      switch (err)
      {
        case SContinue:
        case SBreak:
          cont = false;
        case SReturn:
          throw err;
      }
    }
    return cont;
  }

  inline function isMap(o:Dynamic):Bool
  {
    return (o is IMap);
  }

  inline function getMapValue(map:Dynamic, key:Dynamic):Dynamic
  {
    return cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).get(key);
  }

  inline function setMapValue(map:Dynamic, key:Dynamic, value:Dynamic):Void
  {
    cast(map, haxe.Constraints.IMap<Dynamic, Dynamic>).set(key, value);
  }

  function makeMap(keys:Array<Dynamic>, values:Array<Dynamic>):Dynamic
  {
    var isAllString:Bool = true;
    var isAllInt:Bool = true;
    var isAllObject:Bool = true;
    var isAllEnum:Bool = true;
    for (key in keys)
    {
      isAllString = isAllString && (key is String);
      isAllInt = isAllInt && (key is Int);
      isAllObject = isAllObject && Reflect.isObject(key);
      isAllEnum = isAllEnum && Reflect.isEnumValue(key);
    }
    if (isAllInt)
    {
      var m = new Map<Int, Dynamic>();
      for (i => key in keys)
        m.set(key, values[i]);
      return m;
    }
    if (isAllString)
    {
      var m = new Map<String, Dynamic>();
      for (i => key in keys)
        m.set(key, values[i]);
      return m;
    }
    if (isAllEnum)
    {
      var m = new haxe.ds.EnumValueMap<Dynamic, Dynamic>();
      for (i => key in keys)
        m.set(key, values[i]);
      return m;
    }
    if (isAllObject)
    {
      var m = new Map<{}, Dynamic>();
      for (i => key in keys)
        m.set(key, values[i]);
      return m;
    }
    error(ECustom("Invalid map keys " + keys));
    return null;
  }

  function get(o:Dynamic, f:String):Dynamic
  {
    if (o == null) error(ENullObjectReference(f));

    // Backwards compatibility for scripts using HScriptedClass.init
    // Std.isOfType(o, HScriptedClass) only works with class instances
    // so we look for a specific field to double check the type
    if ((f == 'init' || f == 'scriptInit') && o._isHScriptedClass)
    {
      return Reflect.makeVarArgs((args:Array<Dynamic>) -> return o.scriptInit(args[0], args.slice(1)));
    }

    var oCls:String = Util.getTypeNameOf(o);
    #if hl oCls = oCls.replace('$', ''); #end

    // Check if the field is a blacklisted static field.
    if (PolymodScriptClass.blacklistedStaticFields.exists(o) && PolymodScriptClass.blacklistedStaticFields.get(o).contains(f))
    {
      error(EBlacklistedField(f));
      return null;
    }

    // If not, check if it is a blacklisted instance field.
    if (oCls.length > 0 && oCls != 'Object')
    {
      if (PolymodScriptClass.blacklistedInstanceFields.exists(oCls) && PolymodScriptClass.blacklistedInstanceFields.get(oCls).contains(f))
      {
        error(EBlacklistedField(f));
        return null;
      }
    }

    // Otherwise, we assume the field is fine to use.
    if (Std.isOfType(o, PolymodStaticAbstractReference))
    {
      var ref:PolymodStaticAbstractReference = cast(o, PolymodStaticAbstractReference);

      return ref.getField(f);
    }
    else if (Std.isOfType(o, PolymodStaticClassReference))
    {
      var ref:PolymodStaticClassReference = cast(o, PolymodStaticClassReference);

      return ref.getField(f);
    }
    else if (Std.isOfType(o, PolymodScriptClass))
    {
      var proxy:PolymodAbstractScriptClass = cast(o, PolymodScriptClass);
      if (proxy.fieldExists(f))
      {
        return proxy.fieldRead(f);
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
        error(EUnknownVariable(f));
      }
    }
    else if (Std.isOfType(o, HScriptedClass))
    {
      if (o.scriptGet != null)
      {
        return o.scriptGet(f);
      }

      error(EInvalidScriptedVarGet(f));
    }
    #if (hl && haxe4)
    else if (Std.isOfType(o, Enum))
    {
      try
      {
        return (o : Enum<Dynamic>).createByName(f);
      }
      catch (e)
      {
        error(EInvalidAccess(f));
      }
    }
    #end

    // Default behavior
    #if hl
    // On HL, hasField on properties returns true but Reflect.field
    // might return null so we have to check if a getter exists too.
    // This happens mostly when the programmer mistakenly makes the field access (get, null) instead of (get, never)
    return Reflect.getProperty(o, f);
    #else
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
    #end
  }

  function set(o:Dynamic, f:String, v:Dynamic):Dynamic
  {
    if (o == null) error(ENullObjectReference(f));

    var oCls:String = Util.getTypeNameOf(o);
    #if hl oCls = oCls.replace('$', ''); #end

    // Check if the field is a blacklisted static field.
    if (PolymodScriptClass.blacklistedStaticFields.exists(o) && PolymodScriptClass.blacklistedStaticFields.get(o).contains(f))
    {
      Polymod.error(SCRIPTED_CLASS_BLACKLISTED_FIELD, 'Class field ${oCls}.${f} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
      return null;
    }

    // If not, check if it is a blacklisted instance field.
    if (oCls.length > 0 && oCls != 'Object')
    {
      if (PolymodScriptClass.blacklistedInstanceFields.exists(oCls) && PolymodScriptClass.blacklistedInstanceFields.get(oCls).contains(f))
      {
        Polymod.error(SCRIPTED_CLASS_BLACKLISTED_FIELD, 'Class field ${oCls}.${f} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
        return null;
      }
    }

    // Otherwise, we assume the field is fine to use.
    if (Std.isOfType(o, PolymodStaticAbstractReference))
    {
      var ref:PolymodStaticAbstractReference = cast(o, PolymodStaticAbstractReference);

      try
      {
        return ref.setField(f, v);
      }
      catch (e:Dynamic)
      {
        error(EInvalidAccess(f));
      }
    }
    else if (Std.isOfType(o, PolymodStaticClassReference))
    {
      var ref:PolymodStaticClassReference = cast(o, PolymodStaticClassReference);

      try
      {
        return ref.setField(f, v);
      }
      catch (e:Dynamic)
      {
        error(EInvalidAccess(f));
      }
    }
    else if (Std.isOfType(o, PolymodScriptClass))
    {
      var proxy:PolymodAbstractScriptClass = cast(o, PolymodScriptClass);
      if (proxy.fieldExists(f))
      {
        return proxy.fieldWrite(f, v);
      }
      else if (proxy.superClass != null && proxy.superHasField(f))
      {
        if (Std.isOfType(proxy.superClass, PolymodScriptClass))
        {
          var superClass:PolymodAbstractScriptClass = cast(proxy.superClass, PolymodScriptClass);
          return superClass.fieldWrite(f, v);
        }

        set(proxy.superClass, f, v);
      }
      else
      {
        error(EUnknownVariable(f));
      }
      return v;
    }
    else if (Std.isOfType(o, HScriptedClass))
    {
      if (o.scriptSet != null)
      {
        return o.scriptSet(f, v);
      }

      error(EInvalidScriptedVarSet(f));
    }

    try
    {
      PolymodAbstractScriptClass.setClassObjectField(o, f, v);
    }
    catch (e)
    {
      error(EInvalidAccess(f));
    }
    return v;
  }

  public function registerModules(module:Array<ModuleDecl>, ?origin:String = "hscript"):Void
  {
    var isImportFile:Bool = (new haxe.io.Path(origin).file == "import");

    var pkg:Array<String> = null;
    var imports:Map<String, ClassImport> = [];
    var importsToValidate:Map<String, ClassImport> = [];
    var usings:Map<String, ClassImport> = [];

    // Don't add the default imports to import.hx since they're added to other script classes anyways.
    if (!isImportFile)
    {
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
    }

    for (decl in module)
    {
      switch (decl)
      {
        case DPackage(path):
          pkg = path;
        case DImport(path, _, name):
          var clsName:String = name != null ? name : path[path.length - 1];

          if (imports.exists(clsName))
          {
            if (imports.get(clsName) == null)
            {
              Polymod.error(SCRIPTED_CLASS_BLACKLISTED_MODULE, 'Scripted class ${clsName} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
            }
            else
            {
              Polymod.warning(SCRIPTED_CLASS_REDUNDANT_IMPORT, 'Scripted class ${clsName} has already been imported.', SCRIPT_RUNTIME);
            }
            continue;
          }

          var importedClass:ClassImport =
          {
            name: clsName,
            pkg: path.slice(0, path.length - 1),
            fullPath: path.join("."),
            cls: null,
            enm: null,
            abs: null
          };

          if (_scriptEnumDescriptors.exists(importedClass.fullPath))
          {
            // do nothing
          }
          else
          {
            if (resolveImportedClass(importedClass) && importedClass.cls == null && importedClass.enm == null && importedClass.abs == null)
            {
              if (isImportFile)
              {
                registerImportForPackage(pkg, importedClass);
                continue;
              }

              // Polymod.error(SCRIPT_CLASS_MODULE_NOT_FOUND, 'Could not import class ${importedClass.fullPath}', SCRIPT_RUNTIME);
              // this could be a scripted class or enum that hasn't been registered yet
              importsToValidate.set(importedClass.name, importedClass);
              continue;
            }
          }

          if (isImportFile)
          {
            registerImportForPackage(pkg, importedClass);
            continue;
          }

          // Polymod.debug('Imported class ${importedClass.name} from ${importedClass.fullPath}');
          imports.set(importedClass.name, importedClass);
        case DUsing(path):
          var clsName = path[path.length - 1];

          if (usings.exists(clsName))
          {
            if (usings.get(clsName) == null)
            {
              Polymod.error(SCRIPTED_CLASS_BLACKLISTED_MODULE, 'Scripted class ${clsName} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
            }
            else
            {
              Polymod.warning(SCRIPTED_CLASS_REDUNDANT_IMPORT, 'Scripted class ${clsName} has already been used.', SCRIPT_RUNTIME);
            }
            continue;
          }

          var importedClass:ClassImport =
          {
            name: clsName,
            pkg: path.slice(0, path.length - 1),
            fullPath: path.join("."),
            cls: null,
            enm: null,
            abs: null
          };

          if (_scriptEnumDescriptors.exists(importedClass.fullPath))
          {
            // do nothing
          }
          else
          {
            if (!resolveImportedClass(importedClass, true) || importedClass.cls == null && importedClass.enm == null && importedClass.abs == null) continue;
          }

          if (isImportFile)
          {
            registerImportForPackage(pkg, importedClass, true);
            continue;
          }
          usings.set(importedClass.name, importedClass);
        case DClass(c):
          if (isImportFile) continue;

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

          var classDecl:ClassDecl =
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
          if (isImportFile) continue;

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

          var enumDecl:EnumDecl =
          {
            pkg: pkg,
            name: e.name,
            meta: e.meta,
            params: e.params,
            isPrivate: e.isPrivate,
            fields: e.fields,
          };

          registerScriptEnum(enumDecl);
        case DTypedef(_):
        case DInterface(_):
      }
    }
  }

  public function addModule(moduleContents:String, ?origin:String = "hscript")
  {
    var parser = new Parser();
    var decls = parser.parseModule(moduleContents, origin);
    registerModules(decls, origin);
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

      // Import classes from the import.hx files.
      var pkg:String = cls.pkg?.join(".") ?? "";

      for (key => imps in _scriptClassImports)
      {
        if (!pkg.startsWith(key) && key.length != 0) continue;

        for (imp in imps)
          cls.imports.set(imp.name, imp);
      }

      for (key => imps in _scriptClassUsings)
      {
        if (!pkg.startsWith(key) && key.length != 0) continue;

        for (imp in imps)
          cls.usings.set(imp.name, imp);
      }

      // Add the scripted imports.
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

        Polymod.error(SCRIPTED_CLASS_UNRESOLVED_IMPORT, 'Could not import ${imp.fullPath}. Check to ensure the module exists and is spelled correctly.', SCRIPT_RUNTIME);
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
              Polymod.error(SCRIPTED_CLASS_UNRESOLVED_IMPORT, 'Could not extend ${superClassPath}, do not include type parameters in super class name.', SCRIPT_RUNTIME);
            }

          default:
          // Other error handling?
        }

        // Default
        Polymod.error(SCRIPTED_CLASS_UNRESOLVED_IMPORT, 'Could not extend ${superClassPath}. Make sure the type to extend has been imported.', SCRIPT_RUNTIME);
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

  /**
   * Validates the minimum argument requirement by using the rightmost required argument index
   * and ensures the param count is matching the actual length of the given arguments.
   * Throws an error if validation fails.
   *
   * @param param The function parameters
   * @param args The given arguments
   * @param name The function name
   */
  public function validateArgumentCount(params:Array<Argument>, args:Array<Dynamic>, name:Null<String>):Void
  {
    // getters/setters have null given arguments it seems, so we return early
    if (args == null) return;

    var minParams = 0;
//    var maxAllowed = params.length;

    for (i in 0...params.length)
    {
      var p = params[i];
      if (!p.opt && p.value == null) minParams = i + 1;
    }

    final funcName:String = (name != null) ? " for function '" + name + "'" : "";
    if (args.length < minParams)
    {
      error(EInvalidArgCount(funcName, minParams, args.length));
    }
//    else if (args.length > maxAllowed)
//    {
//      // Manual return for `new` as parameter count shouldn't matter here
//      if (name == "new") return;
//      error(EExceedArgsCount(funcName, maxAllowed, args.length));
//    }
  }

  private inline function buildScriptClassStaticFunction(clsName:String, fieldName:String):Dynamic
  {
    return Reflect.makeVarArgs(function(args:Array<Dynamic>):Dynamic {
      return callScriptClassStaticFunction(clsName, fieldName, args);
    });
  }

  public function hasScriptClassStaticFunction(clsName:String, fnName:String):Bool
  {
    // Every scripted class has these functions, so we force the check to return true.
    if (["scriptInit", "listScriptClasses"].contains(fnName)) return true;

    var imports:Map<String, ClassImport> = [];

    var cls:Null<ClassDecl> = _scriptClassDescriptors.get(clsName);
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
      Polymod.error(SCRIPTED_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.', SCRIPT_RUNTIME);
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
      error(EInvalidAccess(fieldName));
      return null;
    }
  }

  public function setScriptClassStaticField(clsName:String, fieldName:String, value:Dynamic):Dynamic
  {
    var prefixedName = clsName + '#' + fieldName;
    var fieldDecl = getScriptClassStaticFieldDecl(clsName, fieldName);
    if (fieldDecl != null)
    {
      switch (fieldDecl.kind)
      {
        case KFunction(_fn):
          throw 'Cannot override function ${prefixedName}';
        case KVar(v):
          if (v.isfinal) {
            throw 'Cannot override final static field ${prefixedName}';
          }
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

              case 'never':
                throw 'Cannot assign to property ${prefixedName}';

              case 'null':
                throw 'Cannot assign to property ${prefixedName}';

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
      error(EInvalidAccess(fieldName));
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
      Polymod.error(SCRIPTED_CLASS_NOT_REGISTERED, 'Scripted class $clsName has not been defined.', SCRIPT_RUNTIME);
      return null;
    }
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
