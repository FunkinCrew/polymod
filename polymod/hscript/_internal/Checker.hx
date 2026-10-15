package polymod.hscript._internal;

import polymod.hscript._internal.Expr;
import polymod.hscript._internal.Parser;
import polymod.hscript._internal.PolymodScriptClass;
import haxe.rtti.Rtti;
import haxe.rtti.CType as RuntimeCType;

/**
  This is a special type that can be used in API.
  It will be type-checked as `Script` but will compile/execute as `Real`
**/
typedef TypeCheck<Real, Script> = Real;

enum TType
{
  TMono(r:{r:TType});
  TVoid;
  TInt;
  TFloat;
  TBool;
  TDynamic;
  TParam(name:String);
  TUnresolved(name:String);
  TNull(t:TType);
  TInst(c:CClass, args:Array<TType>);
  TEnum(e:CEnum, args:Array<TType>);
  TType(t:CTypedef, args:Array<TType>);
  TAbstract(a:CAbstract, args:Array<TType>);
  TFun(args:Array<{name:String, opt:Bool, t:TType}>, ret:TType);
  TAnon(fields:Array<{name:String, opt:Bool, t:TType}>);
  TLazy(f:Void->TType);
}

private enum WithType
{
  NoValue;
  Value;
  WithType(t:TType);
}

enum CTypedecl
{
  CTClass(c:CClass);
  CTEnum(e:CEnum);
  CTTypedef(t:CTypedef);
  CTAlias(t:TType);
  CTAbstract(a:CAbstract);
}

typedef CMetadata = Array<{name:String, params:Null<Array<Expr>>}>;

typedef CNamedType =
{
  var name:String;
  var params:Array<TType>;
  var ?meta:CMetadata;
}

typedef CClass =
{
  > CNamedType,
  var ?superClass:TType;
  var ?constructor:CField;
  var ?interfaces:Array<TType>;
  var ?isInterface:Bool;
  var fields:Map<String, CField>;
  var statics:Map<String, CField>;
}

typedef CField =
{
  var isPublic:Bool;
  var canWrite:Bool;
  var complete:Bool;
  var params:Array<TType>;
  var name:String;
  var t:TType;
  var ?meta:CMetadata;
}

typedef CEnum =
{
  > CNamedType,
  var constructors:Array<{name:String, ?args:Array<{name:String, opt:Bool, t:TType}>}>;
}

typedef CTypedef =
{
  > CNamedType,
  var t:TType;
}

typedef CAbstract =
{
  > CNamedType,
  var t:TType;
  var from:Array<TType>;
  var to:Array<TType>;
  var fields:Map<String, CField>;
  var statics:Map<String, CField>;
}

class Completion
{
  public var expr:Expr;
  public var t:TType;

  public function new(expr, t)
  {
    this.expr = expr;
    this.t = t;
  }
}

@:allow(polymod.hscript._internal.Checker)
class CheckerTypes
{
  var types:Map<String, CTypedecl> = new Map();
  var aliases:Map<String, String> = new Map();
  var t_string:TType;
  var localParams:Map<String, TType>;
  var parser:Parser;
  var triedRuntimeTypes:Map<String, Bool> = new Map();
  var runtimeAliases:Map<String, String> = new Map();
  var runtimeAliasesLoaded:Bool = false;

  public function new()
  {
    types = new Map();
    types.set("Void", CTAlias(TVoid));
    types.set("Int", CTAlias(TInt));
    types.set("Float", CTAlias(TFloat));
    types.set("Bool", CTAlias(TBool));
    types.set("Dynamic", CTAlias(TDynamic));
    parser = new Parser();

    var stringType = defineClass("String");
    stringType.fields.set("length", runtimeField("length", TInt));
    for (name in ["charAt", "charCodeAt", "indexOf", "lastIndexOf", "split", "substr", "substring", "toLowerCase", "toUpperCase", "toString", "copy", "iterator"])
      stringType.fields.set(name, runtimeField(name, TDynamic));
    stringType.statics.set("fromCharCode", runtimeField("fromCharCode", TDynamic));

    var arrayType = defineClass("Array");
    arrayType.params = [TParam("T")];
    arrayType.constructor = runtimeField("new", TDynamic);
    arrayType.fields.set("length", runtimeField("length", TInt));
    for (name in ["push", "pop", "shift", "unshift", "insert", "remove", "contains", "indexOf", "lastIndexOf", "join", "map", "filter", "forEach", "copy", "slice", "splice", "sort", "reverse", "iterator", "keyValueIterator", "toString"])
      arrayType.fields.set(name, runtimeField(name, TDynamic));

    var mapType = defineAbstract("Map");
    mapType.params = [TParam("K"), TParam("V")];
    mapType.t = TDynamic;
    for (name in ["get", "set", "exists", "remove", "keys", "iterator", "keyValueIterator", "copy", "clear", "toString"])
      mapType.fields.set(name, runtimeField(name, TDynamic));

    var typeCheck = defineTypedef("hscript.TypeCheck");
    typeCheck.params = [TParam("Real"), TParam("Script")];
    typeCheck.t = TParam("Script");
    t_string = TInst(stringType, []);
  }

  static function runtimeField(name:String, type:TType):CField
  {
    return {name: name, isPublic: true, canWrite: true, complete: !StringTools.startsWith(name, "__"), params: [], t: type};
  }

  public function loadRuntimeAliases():Void
  {
    if (runtimeAliasesLoaded) return;
    runtimeAliasesLoaded = true;
    // Reuse Polymod's existing typedef cache
    var typedefs:Map<String, Class<Dynamic>> = PolymodScriptClass.typedefs;
    for (name => targetClass in typedefs)
    {
      if (name == null || name.length == 0 || targetClass == null || types.exists(name)) continue;

      var target:Null<String> = Type.getClassName(targetClass);
      if (target != null && target.length > 0) runtimeAliases.set(name, target);
    }
  }

  function loadRuntimeType(name:String):Bool
  {
    if (types.exists(name)) return true;
    if (triedRuntimeTypes.exists(name)) return false;
    triedRuntimeTypes.set(name, true);

    var cls:Null<Class<Dynamic>> = Type.resolveClass(name);
    if (cls != null)
    {
      registerRuntimeClass(name, cls);
      return true;
    }

    var enm:Null<Enum<Dynamic>> = Type.resolveEnum(name);
    if (enm != null)
    {
      var enumName = Type.getEnumName(enm);
      var result = defineEnum(enumName == null ? name : enumName);
      result.constructors = [for (constructor in Type.getEnumConstructs(enm)) {name: constructor}];
      if (enumName != null && enumName != name) aliases.set(name, enumName);
      return true;
    }

    if (name == "Class" || name == "Enum" || PolymodScriptClass.abstractClassImpls.exists(name))
    {
      defineAbstract(name).t = TDynamic;
      return true;
    }
    return false;
  }

  function registerRuntimeClass(name:String, cls:Class<Dynamic>):Void
  {
    var canonical = Type.getClassName(cls) ?? name;
    var targetName = canonical;
    if (types.exists(targetName))
    {
      if (name != targetName) aliases.set(name, targetName);
      return;
    }

    var declaration = defineClass(targetName);
    declaration.constructor = runtimeField("new", TDynamic);
    if (name != targetName) aliases.set(name, targetName);
    if (!Rtti.hasRtti(cls))
    {
      for (fieldName in Type.getInstanceFields(cls)) declaration.fields.set(fieldName, runtimeField(fieldName, TDynamic));
      for (fieldName in Type.getClassFields(cls)) declaration.statics.set(fieldName, runtimeField(fieldName, TDynamic));
      return;
    }

    var rtti = Rtti.getRtti(cls);
    declaration.params = [for (param in rtti.params) TParam(param)];
    for (field in rtti.fields) declaration.fields.set(field.name, runtimeField(field.name, runtimeRttiType(field.type)));
    for (field in rtti.statics) declaration.statics.set(field.name, runtimeField(field.name, runtimeRttiType(field.type)));
    if (rtti.superClass != null)
      declaration.superClass = runtimeRttiPath(rtti.superClass.path, rtti.superClass.params);
    if (rtti.interfaces != null)
      declaration.interfaces = [for (item in rtti.interfaces) runtimeRttiPath(item.path, item.params)];
  }

  function runtimeRttiPath(name:String, args:Array<RuntimeCType>):TType
  {
    return resolve(name, [for (arg in args) runtimeRttiType(arg)]) ?? TDynamic;
  }

  function runtimeRttiType(type:RuntimeCType):TType
  {
    return switch (type)
    {
      case CUnknown:
        TDynamic;
      case CClass(name, args), CEnum(name, args), CTypedef(name, args):
        var resolved = resolve(name, [for (arg in args) runtimeRttiType(arg)]);
        resolved ?? TDynamic;
      case CAbstract(name, args):
        var shortName = name.substr(name.lastIndexOf(".") + 1);
        switch (shortName)
        {
          case "Int": TInt;
          case "Float": TFloat;
          case "Bool": TBool;
          case "Void": TVoid;
          case "Null": TNull(args.length == 0 ? TDynamic : runtimeRttiType(args[0]));
          default:
            var resolved = resolve(name, [for (arg in args) runtimeRttiType(arg)]);
            resolved ?? TDynamic;
        }
      case CFunction(args, ret):
        TFun([for (arg in args) {name: arg.name, opt: arg.opt, t: runtimeRttiType(arg.t)}], runtimeRttiType(ret));
      case CAnonymous(fields):
        TAnon([for (field in fields) {name: field.name, opt: false, t: runtimeRttiType(field.type)}]);
      case CDynamic(_):
        TDynamic;
    }
  }

  public function addXmlApi(api:Xml)
  {
    var types = new haxe.rtti.XmlParser();
    types.process(api, "");
    var todo = [];
    for (v in types.root) addXmlType(v, todo);
    for (f in todo) f();
    t_string = getType("String");
  }

  public function defineClass(name:String, ?ct:CClass)
  {
    if (ct == null) ct =
      {
        name: name,
        fields: new Map(),
        statics: new Map(),
        params: [],
      };
    types.set(name, CTClass(ct));
    return ct;
  }

  public function defineEnum(name:String, ?en:CEnum):CEnum
  {
    if (en == null) en = {name: name, params: [], constructors: []};
    types.set(name, CTEnum(en));
    return en;
  }

  public function defineTypedef(name:String, ?td:CTypedef):CTypedef
  {
    if (td == null) td = {name: name, params: [], t: TDynamic};
    types.set(name, CTTypedef(td));
    return td;
  }

  public function defineAbstract(name:String, ?abs:CAbstract):CAbstract
  {
    if (abs == null) abs = {
      name: name,
      params: [],
      t: TDynamic,
      from: [],
      to: [],
      fields: new Map(),
      statics: new Map()
    };
    types.set(name, CTAbstract(abs));
    return abs;
  }

  public function setAlias(alias:String, target:String):Void
  {
    if (alias == null || alias.length == 0 || target == null || target.length == 0) return;
    aliases.set(alias, target);
  }

  public function clearAliases():Void
  {
    aliases.clear();
  }

  public function hasType(name:String):Bool
  {
    if (name == null || name.length == 0) return false;
    if (name == "Null") return true;
    if (types.exists(name) || aliases.exists(name) || runtimeAliases.exists(name)) return true;
    return loadRuntimeType(name);
  }

  function addXmlType(x:haxe.rtti.CType.TypeTree, todo:Array<Void->Void>)
  {
    switch (x)
    {
      case TPackage(name, full, subs):
        for (s in subs) addXmlType(s, todo);
      case TClassdecl(c):
        if (types.exists(c.path)) return;
        var cl:CClass = {
          name: c.path,
          params: [],
          fields: new Map(),
          statics: new Map(),
        };
        addMeta(c, cl);
        if (c.isInterface) cl.isInterface = true;
        for (p in c.params) cl.params.push(TParam(p));
        todo.push(function()
        {
          localParams = [for (t in cl.params) c.path + "." + Checker.typeStr(t) => t];
          if (c.superClass != null) cl.superClass = getType(c.superClass.path, [for (t in c.superClass.params) makeXmlType(t)]);
          if (c.interfaces != null)
          {
            cl.interfaces = [];
            for (i in c.interfaces) cl.interfaces.push(getType(i.path, [for (t in i.params) makeXmlType(t)]));
          }
          var pkeys = [];
          function initField(f:haxe.rtti.CType.ClassField, fields)
          {
            if (f.isOverride || f.name.substr(0, 4) == "get_" || f.name.substr(0, 4) == "set_") return;
            var complete = !StringTools.startsWith(f.name, "__"); // __uid, etc. (no metadata in such fields)
            for (m in f.meta)
            {
              if (m.name == ":noScript") return;
              if (m.name == ":noCompletion") complete = false;
            }
            var fl:CField = {
              isPublic: f.isPublic,
              canWrite: f.set.match(RNormal | RCall(_) | RDynamic),
              complete: complete,
              params: [],
              name: f.name,
              t: null
            };
            for (p in f.params)
            {
              var pt = TParam(p);
              var key = f.name + "." + p;
              pkeys.push(key);
              fl.params.push(pt);
              localParams.set(key, pt);
            }
            fl.t = makeXmlType(f.type);
            if (f.meta != null && f.meta.length > 0)
            {
              fl.meta = [];
              for (m in f.meta) fl.meta.push({
                name: m.name,
                params: [for (p in m.params) try parser.parseString(p) catch (e:Expr.Error) null]
              });
            }
            while (pkeys.length > 0)
              localParams.remove(pkeys.pop());
            if (fl.name == "new") cl.constructor = fl;
            else
              fields.set(f.name, fl);
          }
          for (f in c.fields) initField(f, cl.fields);
          for (f in c.statics) initField(f, cl.statics);
          localParams = null;
        });
        types.set(cl.name, CTClass(cl));
      case TEnumdecl(e):
        if (types.exists(e.path)) return;
        var en:CEnum = {
          name: e.path,
          params: [],
          constructors: [],
        };
        addMeta(e, en);
        for (p in e.params) en.params.push(TParam(p));
        todo.push(function()
        {
          localParams = [for (t in en.params) e.path + "." + Checker.typeStr(t) => t];
          for (c in e.constructors) en.constructors.push({
            name: c.name,
            args: c.args == null ? null : [for (a in c.args) {
              name: a.name,
              opt: a.opt,
              t: makeXmlType(a.t)
            }]
          });
          localParams = null;
        });
        types.set(en.name, CTEnum(en));
      case TTypedecl(t):
        if (types.exists(t.path)) return;
        var td:CTypedef = {
          name: t.path,
          params: [],
          t: null,
        };
        for (p in t.params) td.params.push(TParam(p));
        if (t.path == "hscript.TypeCheck") td.params.reverse();
        todo.push(function()
        {
          localParams = [for (pt in td.params) t.path + "." + Checker.typeStr(pt) => pt];
          td.t = makeXmlType(t.type);
          localParams = null;
        });
        types.set(t.path, CTTypedef(td));
      case TAbstractdecl(a):
        if (types.exists(a.path)) return;
        var ta:CAbstract = {
          name: a.path,
          params: [],
          t: null,
          from: [],
          to: [],
          fields: new Map(),
          statics: new Map(),
        };
        addMeta(a, ta);
        for (p in a.params) ta.params.push(TParam(p));
        todo.push(function()
        {
          localParams = [for (t in ta.params) a.path + "." + Checker.typeStr(t) => t];
          ta.t = makeXmlType(a.athis);
          for (f in a.from) if (f.field == null) ta.from.push(makeXmlType(f.t));
          for (t in a.to) if (t.field == null) ta.to.push(makeXmlType(t.t));
          localParams = null;
        });
        types.set(a.path, CTAbstract(ta));
    }
  }

  function addMeta(src:haxe.rtti.CType.TypeInfos, to:CNamedType)
  {
    if (src.meta == null || src.meta.length == 0) return;
    to.meta = [];
    for (m in src.meta) to.meta.push({
      name: m.name,
      params: [for (p in m.params) try parser.parseString(p) catch (e:Expr.Error) null]
    });
  }

  function makeXmlType(t:haxe.rtti.CType.CType):TType
  {
    return switch (t)
    {
      case CUnknown:
        TUnresolved("Unknown");
      case CEnum(name, params):
        getType(name, [for (t in params) makeXmlType(t)]);
      case CClass(name, params):
        getType(name, [for (t in params) makeXmlType(t)]);
      case CTypedef(name, params):
        getType(name, [for (t in params) makeXmlType(t)]);
      case CFunction(args, ret):
        TFun([for (a in args) {
          name: a.name,
          opt: a.opt,
          t: makeXmlType(a.t)
        }], makeXmlType(ret));
      case CAnonymous(fields):
        inline function isOpt(m:haxe.rtti.CType.MetaData)
        {
          if (m == null) return false;
          var b = false;
          for (m in m) if (m.name == ":optional")
          {
            b = true;
            break;
          }
          return b;
        }
        TAnon([for (f in fields) {
          name: f.name,
          t: makeXmlType(f.type),
          opt: isOpt(f.meta)
        }]);
      case CDynamic(t):
        TDynamic;
      case CAbstract(name, params):
        switch (name)
        {
          default:
            getType(name, [for (t in params) makeXmlType(t)]);
        }
    }
  }

  function getType(name:String, ?args:Array<TType>):TType
  {
    if (localParams != null)
    {
      var t = localParams.get(name);
      if (t != null) return t;
    }
    var t = resolve(name, args);
    if (t == null)
    {
      var pack = name.split(".");
      if (pack.length > 1)
      {
        // bugfix for some args reported as pack._Name.Name while they are not private
        var priv = pack[pack.length - 2];
        if (priv.charCodeAt(0) == "_".code)
        {
          pack.remove(priv);
          return getType(pack.join("."), args);
        }
      }
      return TUnresolved(name); // most likely private class
    }
    return t;
  }

  public function resolve(name:String, ?args:Array<TType>):Null<TType>
  {
    var alias = aliases.get(name);
    if (alias != null) name = alias;

    var runtimeAliasSource:Null<String> = null;
    if (!types.exists(name))
    {
      var runtimeAlias = runtimeAliases.get(name);
      if (runtimeAlias != null)
      {
        runtimeAliasSource = name;
        name = runtimeAlias;
      }
    }
    if (name == "Null")
    {
      if (args == null || args.length != 1) throw "Missing Null<T> parameter";
      return TNull(args[0]);
    }
    var t = types.get(name);
    if (t == null)
    {
      if (!loadRuntimeType(name))
      {
        if (runtimeAliasSource != null)
        {
          types.set(runtimeAliasSource, CTAlias(TDynamic));
          return TDynamic;
        }
        return null;
      }
      t = types.get(name);
      if (t == null) return null;
    }
    if (args == null) args = [];
    return switch (t)
    {
      case CTClass(c):
        TInst(c, fillDefaultTypeArgs(c.params, args));
      case CTEnum(e):
        TEnum(e, fillDefaultTypeArgs(e.params, args));
      case CTTypedef(t):
        TType(t, fillDefaultTypeArgs(t.params, args));
      case CTAbstract(a):
        TAbstract(a, fillDefaultTypeArgs(a.params, args));
      case CTAlias(t):
        t;
    }
  }

  function fillDefaultTypeArgs(params:Array<TType>, args:Array<TType>):Array<TType>
  {
    if (args.length == 0 && params.length > 0) return[for (_ in params) TDynamic];
    return args;
  }
}

class Checker
{
  public var types:CheckerTypes;
  public var currentClassName:Null<String>;

  var locals:Map<String, TType>;
  var globals:Map<String, TType> = new Map();
  var events:Map<String, TType> = new Map();
  var currentFunType:TType;
  var isCompletion:Bool;
  var allowDefine:Bool;
  var hasReturn:Bool;

  public var allowAsync:Bool;
  public var allowReturn:Null<TType>;
  public var allowGlobalsDefine:Bool;
  public var allowUntypedMeta:Bool;

  public function new(?types)
  {
    if (types == null) types = new CheckerTypes();
    this.types = types;
  }

  public function setGlobals(cl:CClass, ?params:Array<TType>, allowPrivate = false)
  {
    if (params == null) params = [for (p in cl.params) makeMono()];
    var allowPrivateOnCurrentClass = allowPrivate;
    while (true)
    {
      for (f in cl.fields) if (f.isPublic || allowPrivateOnCurrentClass) setGlobal(f.name, f.params.length == 0 ? f.t : TLazy(function()
      {
        var t = apply(f.t, f.params, [for (i in 0...f.params.length) makeMono()]);
        return apply(t, cl.params, params);
      }));
      if (cl.superClass == null) break;
      cl = switch (follow(cl.superClass))
      {
        case TInst(csup, pl):
          params = [for (p in pl) apply(p, cl.params, params)];
          csup;
        default:
          throw "assert";
      }
      allowPrivateOnCurrentClass = false;
    }
  }

  public function removeGlobal(name:String)
  {
    globals.remove(name);
  }

  public function setGlobal(name:String, type:TType)
  {
    globals.set(name, type);
  }

  public function setEvent(name:String, type:TType)
  {
    events.set(name, type);
  }

  public function resolveTypeAnnotation(type:CType, at:Expr):TType
  {
    return makeType(type, at);
  }

  public function checkFunction(args:Array<Argument>, body:Expr, name:String, ret:CType, expected:TType):TType
  {
    currentFunType = expected;
    return check(mk(EFunction(args, body, null, ret), body), Value);
  }

  public function checkExpected(expr:Expr, expected:TType):TType
  {
    var result = check(expr, WithType(expected));
    unify(result, expected, expr);
    return expected;
  }

  public function getGlobals()
  {
    return globals;
  }

  public dynamic function onTopDownEnum(en:CEnum, field:String)
  {
    return false;
  }

  function typeArgs(args:Array<Argument>, pos:Expr)
  {
    return[for (i in 0...args.length)
    {
      var a = args[i];
      var at = a.t == null ? makeMono() : makeType(a.t, pos);
      {
        name: a.name,
        opt: a.opt,
        t: at
      };
    }];
  }

  public function check(expr:Expr, ?withType:WithType, ?isCompletion = false)
  {
    if (withType == null) withType = NoValue;
    locals = new Map();
    if (types.t_string == null) types.t_string = types.getType("String");
    allowDefine = allowGlobalsDefine;
    this.isCompletion = isCompletion;
    if (edef(expr).match(EFunction(_))) expr = mk(EBlock([expr]), expr); // single function might be self recursive
    switch (edef(expr))
    {
      case EBlock(el):
        var delayed = [];
        var last = TVoid;
        for (e in el)
        {
          while (true)
          {
            switch (edef(e))
            {
              case EMeta(_, _, e2):
                e = e2;
              default:
                break;
            }
          }
          switch (edef(e))
          {
            case EFunction(args, _, name, ret) if (name != null):
              var tret = ret == null ? makeMono() : makeType(ret, e);
              var ft = TFun(typeArgs(args, e), tret);
              locals.set(name, ft);
              delayed.push(function()
              {
                currentFunType = ft;
                typeExpr(e, NoValue);
                return ft;
              });
            default:
              for (f in delayed) f();
              delayed = [];
              if (el[el.length - 1] == e) last = typeExpr(e, withType); else typeExpr(e, NoValue);
          }
        }
        for (f in delayed) last = f();
        return last;
      default:
    }
    return typeExpr(expr, withType);
  }

  inline function edef(e:Expr)
  {
    #if hscriptPos
    return e.e;
    #else
    return e;
    #end
  }

  inline function error(msg:String, curExpr:Expr)
  {
    var e = ECustom(msg);
    #if hscriptPos var e = new Error(e, curExpr.pmin, curExpr.pmax, curExpr.origin, curExpr.line); #end
    if (!isCompletion) throw e;
  }

  function saveLocals()
  {
    return[for (k in locals.keys()) k => locals.get(k)];
  }

  function makeType(t:CType, e:Expr):Null<TType>
  {
    return switch (t)
    {
      case CTPath(path, params):
        var ct = types.resolve(path.join("."), params == null ? [] : [for (p in params) makeType(p, e)]);
        if (ct == null)
        {
          error("Unknown type " + path, e);
          ct = TDynamic;
        }
        return ct;
      case CTFun(args, ret):
        var i = 0;
        return TFun([for (a in args) switch (a)
        {
          case CTOpt(inner):
            {
              name: "p" + (i++),
              opt: true,
              t: makeType(inner, e)
            };
          default:
            {
              name: "p" + (i++),
              opt: false,
              t: makeType(a, e)
            };
        }], makeType(ret, e));
      case CTAnon(fields):
        return TAnon([for (f in fields) switch (f.t)
        {
          case CTOpt(inner):
            {
              name: f.name,
              opt: true,
              t: makeType(inner, e)
            };
          default:
            {
              name: f.name,
              opt: false,
              t: makeType(f.t, e)
            };
        }]);
      case CTParent(t):
        return makeType(t, e);
      case CTNamed(n, t):
        return makeType(t, e);
      case CTOpt(t):
        return TNull(makeType(t, e));
      case CTExpr(_):
        error("Unsupported expr type parameter", e);
        return null;
    }
  }

  public static function typeStr(t:TType)
  {
    inline function makeArgs(args:Array<TType>) return args.length == 0 ? "" : "<" +[for (t in args) typeStr(t)].join(",") + ">";
    return switch (t)
    {
      case TMono(r):
        r.r == null ? "Unknown" : typeStr(r.r);
      case TInst(c, args):
        c.name + makeArgs(args);
      case TEnum(e, args):
        e.name + makeArgs(args);
      case TType(t, args):
        if (t.name == "hscript.TypeCheck") typeStr(args[1]); else t.name + makeArgs(args);
      case TAbstract(a, args):
        a.name + makeArgs(args);
      case TFun(args, ret):
        "(" +[for (a in args) (a.opt ? "?" : "") + (a.name == "" ? "" : a.name + ":") + typeStr(a.t)].join(", ") + ") -> " + typeStr(ret);
      case TAnon(fields):
        "{" +[for (f in fields) (f.opt ? "?" : "") + f.name + ":" + typeStr(f.t)].join(", ") + "}";
      case TParam(name):
        var separator = name.lastIndexOf("#");
        separator == -1 ? name : name.substr(separator + 1);
      case TNull(t):
        "Null<" + typeStr(t) + ">";
      case TUnresolved(name):
        "?" + name;
      default:
        t.getName().substr(1);
    }
  }

  public static function typeIter(t:TType, callb:TType->Void)
  {
    switch (t)
    {
      case TMono(r) if (r.r != null):
        callb(r.r);
      case TNull(t):
        callb(t);
      case TInst(_, tl), TAbstract(_, tl), TEnum(_, tl), TType(_, tl):
        for (t in tl) callb(t);
      case TFun(args, ret):
        for (t in args) callb(t.t);
        callb(ret);
      case TAnon(fl):
        for (f in fl) callb(f.t);
      case TLazy(f):
        callb(f());
      default:
    }
  }

  function linkLoop(a:TType, t:TType)
  {
    if (t == a) return true;
    switch (t)
    {
      case TMono(r):
        if (r.r == null) return false;
        return linkLoop(a, r.r);
      case TEnum(_, tl), TInst(_, tl), TType(_, tl), TAbstract(_, tl):
        for (t in tl) if (linkLoop(a, t)) return true;
        return false;
      case TFun(args, ret):
        for (arg in args) if (linkLoop(a, arg.t)) return true;
        return linkLoop(a, ret);
      case TDynamic:
        if (t == TDynamic) return false;
        return linkLoop(a, TDynamic);
      case TAnon(fl):
        for (f in fl) if (linkLoop(a, f.t)) return true;
        return false;
      default:
        return false;
    }
  }

  function link(a:TType, b:TType, r:
    {r:TType})
  {
    if (linkLoop(a, b)) return follow(b) == a;
    if (b == TDynamic) return true;
    r.r = b;
    return true;
  }

  function typeEq(t1:TType, t2:TType)
  {
    if (t1 == t2) return true;
    switch ([t1, t2])
    {
      case [TMono(r), _]:
        if (r.r == null)
        {
          if (!link(t1, t2, r)) return false;
          r.r = t2;
          return true;
        }
        return typeEq(r.r, t2);
      case [_, TMono(r)]:
        if (r.r == null)
        {
          if (!link(t2, t1, r)) return false;
          r.r = t1;
          return true;
        }
        return typeEq(t1, r.r);
      case [TType(t1, pl1), TType(t2, pl2)] if (t1 == t2):
        for (i in 0...pl1.length) if (!typeEq(pl1[i], pl2[i])) return false;
        return true;
      case [TType(t1, pl1), _]:
        return typeEq(apply(t1.t, t1.params, pl1), t2);
      case [_, TType(t2, pl2)]:
        return typeEq(t1, apply(t2.t, t2.params, pl2));
      case [TInst(cl1, pl1), TInst(cl2, pl2)] if (cl1 == cl2):
        for (i in 0...pl1.length) if (!typeEq(pl1[i], pl2[i])) return false;
        return true;
      case [TEnum(e1, pl1), TEnum(e2, pl2)] if (e1 == e2):
        for (i in 0...pl1.length) if (!typeEq(pl1[i], pl2[i])) return false;
        return true;
      case [TAbstract(a1, pl1), TAbstract(a2, pl2)] if (a1 == a2):
        for (i in 0...pl1.length) if (!typeEq(pl1[i], pl2[i])) return false;
        return true;
      case [TNull(t1), TNull(t2)]:
        return typeEq(t1, t2);
      case [TNull(t1), _]:
        return typeEq(t1, t2);
      case [_, TNull(t2)]:
        return typeEq(t1, t2);
      case [TFun(args1, r1), TFun(args2, r2)] if (args1.length == args2.length):
        for (i in 0...args1.length) if (!typeEq(args1[i].t, args2[i].t)) return false;
        return typeEq(r1, r2);
      case [TAnon(a1), TAnon(a2)] if (a1.length == a2.length):
        var m = new Map();
        for (f in a2) m.set(f.name, f);
        for (f1 in a1)
        {
          var f2 = m.get(f1.name);
          if (f2 == null || f1.opt != f2.opt) return false;
          if (!typeEq(f1.t, f2.t)) return false;
        }
        return true;
      default:
    }
    return false;
  }

  public function tryUnify(t1:TType, t2:TType)
  {
    if (t1 == t2) return true;
    switch ([t1, t2])
    {
      case [TMono(r), _]:
        if (r.r == null)
        {
          if (!link(t1, t2, r)) return false;
          r.r = t2;
          return true;
        }
        return tryUnify(r.r, t2);
      case [_, TMono(r)]:
        if (r.r == null)
        {
          if (!link(t2, t1, r)) return false;
          r.r = t1;
          return true;
        }
        return tryUnify(t1, r.r);
      case [TType(t1, pl1), _]:
        return tryUnify(apply(t1.t, t1.params, pl1), t2);
      case [_, TType(t2, pl2)]:
        return tryUnify(t1, apply(t2.t, t2.params, pl2));
      case [TNull(t1), _]:
        return tryUnify(t1, t2);
      case [_, TNull(t2)]:
        return tryUnify(t1, t2);
      case [TFun(args1, r1), TFun(args2, r2)] if (args1.length == args2.length):
        for (i in 0...args1.length)
        {
          var a1 = args1[i];
          var a2 = args2[i];
          if (a2.opt && !a1.opt) return false;
          if (!tryUnify(a2.t, a1.t)) return false;
        }
        return tryUnify(r1, r2);
      case [_, TDynamic]:
        return true;
      case [TDynamic, _]:
        return true;
      case [TAnon(a1), TAnon(a2)]:
        if (a2.length == 0) // always unify with {}
          return true;
        var m = new Map();
        for (f in a1) m.set(f.name, f);
        for (f2 in a2)
        {
          var f1 = m.get(f2.name);
          if (f1 == null)
          {
            if (f2.opt) continue;
            return false;
          }
          if (!f2.opt && f1.opt) return false;
          if (!typeEq(f1.t, f2.t)) return false;
        }
        return true;
      case [TInst(cl1, pl1), TInst(cl2, pl2)]:
        while (cl1 != cl2)
        {
          if (cl1.interfaces != null)
          {
            for (i in cl1.interfaces)
            {
              switch (i)
              {
                case TInst(cli, args):
                  var i = TInst(cli, [for (a in args) apply(a, cl1.params, pl1)]);
                  if (tryUnify(i, t2)) return true;
                default:
                  throw "assert";
              }
            }
          }
          switch (cl1.superClass)
          {
            case null:
              return false;
            case TInst(c, args):
              pl1 = [for (a in args) apply(a, cl1.params, pl1)];
              cl1 = c;
            default:
              throw "assert";
          }
        }
        for (i in 0...pl1.length) if (!typeEq(pl1[i], pl2[i])) return false;
        return true;
      case [TInst(cl1, pl1), TAnon(fl)]:
        for (i in 0...fl.length)
        {
          var f2 = fl[i];
          var f1 = null;
          var cl = cl1;
          while (true)
          {
            f1 = cl.fields.get(f2.name);
            if (f1 != null) break;
            if (cl.superClass == null) return false;
            cl = switch (cl.superClass)
            {
              case TInst(c, _):
                c;
              default:
                throw "assert";
            }
          }
          if (!typeEq(apply(f1.t, cl1.params, pl1), f2.t)) return false;
        }
        return true;
      case [TInt, TFloat]:
        return true;
      case [
        TFun(_),
        TAbstract({
          name: "haxe.Function"
        }, _)
      ]:
        return true;
      case [_, TAbstract(a, args)]:
        for (ft in a.from)
        {
          var t = apply(ft, a.params, args);
          if (tryUnify(t1, t)) return true;
        }
      case [TAbstract(a, args), _]:
        for (tt in a.to)
        {
          var t = apply(tt, a.params, args);
          if (tryUnify(t, t2)) return true;
        }
      default:
    }
    return typeEq(t1, t2);
  }

  public function unify(t1:TType, t2:TType, e:Expr)
  {
    if (!tryUnify(t1, t2)) error(typeStr(t1) + " should be " + typeStr(t2), e);
  }

  public function apply(t:TType, params:Array<TType>, args:Array<TType>)
  {
    if (args.length != params.length) throw "Invalid number of type parameters";
    if (args.length == 0) return t;
    var subst = new Map();
    for (i in 0...params.length) subst.set(params[i], args[i]);
    function map(t:TType)
    {
      var st = subst.get(t);
      if (st != null) return st;
      return mapType(t, map);
    }
    return map(t);
  }

  public function mapType(t:TType, f:TType->TType)
  {
    switch (t)
    {
      case TMono(r):
        if (r.r == null) return t;
        return f(t);
      case TVoid, TInt, TFloat, TBool, TDynamic, TParam(_), TUnresolved(_):
        return t;
      case TEnum(_, []), TInst(_, []), TAbstract(_, []), TType(_, []):
        return t;
      case TNull(t):
        return TNull(f(t));
      case TInst(c, args):
        return TInst(c, [for (t in args) f(t)]);
      case TEnum(e, args):
        return TEnum(e, [for (t in args) f(t)]);
      case TType(t, args):
        return TType(t, [for (t in args) f(t)]);
      case TAbstract(a, args):
        return TAbstract(a, [for (t in args) f(t)]);
      case TFun(args, ret):
        return TFun([for (a in args) {
          name: a.name,
          opt: a.opt,
          t: f(a.t)
        }], f(ret));
      case TAnon(fields):
        return TAnon([for (af in fields) {
          name: af.name,
          opt: af.opt,
          t: f(af.t)
        }]);
      case TLazy(l):
        return f(l());
    }
  }

  public function follow(t:TType)
  {
    return switch (t)
    {
      case TMono(r):
        if (r.r != null) follow(r.r) else t;
      case TType(t, args):
        follow(apply(t.t, t.params, args));
      case TNull(t):
        follow(t);
      case TLazy(f):
        follow(f());
      default:
        t;
    }
  }

  public function getFields(t:TType):Array<
    {name:String, t:TType}>
  {
    var fields = [];
    switch (follow(t))
    {
      case TInst(c, args):
        var map = (t) -> apply(t, c.params, args);
        while (c != null)
        {
          for (fname in c.fields.keys())
          {
            var f = c.fields.get(fname);
            if (!f.isPublic || !f.complete) continue;
            var name = f.name, t = map(f.t);
            if (allowAsync && StringTools.startsWith(name, "a_"))
            {
              t = unasync(t);
              name = name.substr(2);
            }
            fields.push({
              name: name,
              t: t
            });
          }
          if (c.isInterface && c.interfaces != null)
          {
            for (i in c.interfaces)
            {
              for (f in getFields(i)) fields.push({
                name: f.name,
                t: map(f.t)
              });
            }
          }
          if (c.superClass == null) break;
          switch (c.superClass)
          {
            case TInst(csup, args):
              var curMap = map;
              map = (t) -> curMap(apply(t, csup.params, args));
              c = csup;
            default:
              break;
          }
        }
      case TAnon(fl):
        for (f in fl) fields.push({
          name: f.name,
          t: f.t
        });
      case TAbstract(a, args):
        for (name in a.fields.keys())
        {
          var f = a.fields.get(name);
          if (!f.isPublic || !f.complete) continue;
          fields.push({
            name: name,
            t: apply(f.t, a.params, args)
          });
        }
        if (fields.length == 0 && a.t != null) fields = getFields(apply(a.t, a.params, args));
      case TFun(args, ret):
        if (isCompletion) fields.push({
          name: "bind",
          t: TFun(args, TVoid)
        });
      default:
    }
    return fields;
  }

  function getField(t:TType, f:String, e:Expr, forWrite = false)
  {
    switch (follow(t))
    {
      case TInst(c, args):
        var cf = c.fields.get(f);
        if (cf == null && allowAsync)
        {
          cf = c.fields.get("a_" + f);
          if (cf != null)
          {
            var isPublic = true; // consider a_ prefixed as script specific
            cf = {
              isPublic: isPublic,
              canWrite: false,
              params: cf.params,
              name: cf.name,
              t: unasync(cf.t),
              complete: cf.complete
            };
            if (cf.t == null) cf = null;
          }
        }
        if (cf == null && c.isInterface && c.interfaces != null)
        {
          for (i in c.interfaces)
          {
            var ft = getField(i, f, e, forWrite);
            if (ft != null) return apply(ft, c.params, args);
          }
        }
        if (cf == null)
        {
          if (c.superClass == null) return null;
          var ft = getField(c.superClass, f, e, forWrite);
          if (ft != null) ft = apply(ft, c.params, args);
          return ft;
        }
        if (!cf.isPublic && currentClassName != c.name) error("Can't access private field " + f + " on " + c.name, e);
        if (forWrite && !cf.canWrite) error("Can't write readonly field " + f + " on " + c.name, e);
        var t = cf.t;
        if (cf.params != null) t = apply(t, cf.params, [for (i in 0...cf.params.length) makeMono()]);
        return apply(t, c.params, args);
      case TDynamic:
        return makeMono();
      case TAnon(fields):
        for (af in fields) if (af.name == f) return af.opt ? TNull(af.t) : af.t;
        return null;
      case TAbstract(a, args):
        var cf = a.fields.get(f);
        if (cf != null)
        {
          if (!cf.isPublic) error("Can't access private field " + f + " on " + a.name, e);
          if (forWrite && !cf.canWrite) error("Can't write readonly field " + f + " on " + a.name, e);
          var ft = cf.t;
          if (cf.params != null && cf.params.length > 0) ft = apply(ft, cf.params, [for (_ in cf.params) makeMono()]);
          return apply(ft, a.params, args);
        }
        if (!a.fields.keys().hasNext() && a.t != null)
        {
          var underlying = apply(a.t, a.params, args);
          var ft = getField(underlying, f, e, forWrite);
          if (ft != null) return ft;
        }
        return null;
      default:
        return null;
    }
  }

  public function unasync(t:TType):Null<TType>
  {
    switch (follow(t))
    {
      case TFun(args, ret) if (args.length > 0):
        var rargs = args.copy();
        switch (follow(rargs.shift().t))
        {
          case TFun([r], _):
            return TFun(rargs, r.t);
          default:
        }
      default:
    }
    return null;
  }

  function typeExprWith(expr:Expr, t:TType)
  {
    var et = typeExpr(expr, WithType(t));
    unify(et, t, expr);
    return t;
  }

  function makeMono()
  {
    return TMono({
      r: null
    });
  }

  function makeIterator(t):TType
  {
    return TAnon([
      {
        name: "next",
        opt: false,
        t: TFun([], t)
      },
      {
        name: "hasNext",
        opt: false,
        t: TFun([], TBool)
      }
    ]);
  }

  function mk(e, p):Expr
  {
    #if hscriptPos
    return {
      e: e,
      pmin: p.pmin,
      pmax: p.pmax,
      origin: p.origin,
      line: p.line
    };
    #else
    return e;
    #end
  }

  function isString(t:TType):Bool
  {
    return switch (follow(t))
    {
      case TInst({
        name: "String"
      }, _), TAbstract({
        name: "String"
      }, _):
        true;
      default:
        false;
    }
  }

  function onCompletion(expr:Expr, t:TType)
  {
    if (isCompletion) throw new Completion(expr, t);
  }

  function typeField(o:Expr, f:String, expr:Expr, forWrite:Bool)
  {
    var ot = typeExpr(o, Value);
    if (f == null) onCompletion(expr, ot);
    var ft = getField(ot, f, expr, forWrite);
    if (ft == null)
    {
      error(typeStr(ot) + " has no field " + f, expr);
      ft = TDynamic;
    }
    return ft;
  }


  function mergeComprehensionType(current:Null<TType>, next:TType):TType
  {
    if (current == null) return next;
    if (current == TDynamic) return TDynamic;
    if (tryUnify(next, current)) return current;
    if (tryUnify(current, next)) return next;
    return TDynamic;
  }

  function typeComprehension(body:Expr, isMap:Bool, withType:WithType):TType
  {
    var expectedElement:Null<TType> = null;
    var expectedKey:Null<TType> = null;
    var expectedValue:Null<TType> = null;

    switch (withType)
    {
      case WithType(expected):
        switch (follow(expected))
        {
          case TInst(c, args) if (!isMap && c.name == "Array" && args.length > 0):
            expectedElement = args[0];
          case TAbstract(a, args) if (isMap && a.name == "Map" && args.length == 2):
            expectedKey = args[0];
            expectedValue = args[1];
          default:
        }
      default:
    }

    var elementType:Null<TType> = expectedElement;
    var keyType:Null<TType> = expectedKey;
    var valueType:Null<TType> = expectedValue;

    function inferElement(value:Expr):Void
    {
      if (expectedElement != null)
      {
        var actual = typeExpr(value, WithType(expectedElement));
        unify(actual, expectedElement, value);
      }
      else
      {
        elementType = mergeComprehensionType(elementType, typeExpr(value, Value));
      }
    }

    function inferKey(key:Expr):Void
    {
      if (expectedKey != null)
      {
        var actual = typeExpr(key, WithType(expectedKey));
        unify(actual, expectedKey, key);
      }
      else
      {
        keyType = mergeComprehensionType(keyType, typeExpr(key, Value));
      }
    }

    function inferValue(value:Expr):Void
    {
      if (expectedValue != null)
      {
        var actual = typeExpr(value, WithType(expectedValue));
        unify(actual, expectedValue, value);
      }
      else
      {
        valueType = mergeComprehensionType(valueType, typeExpr(value, Value));
      }
    }

    function visit(e:Expr):Void
    {
      switch (edef(e))
      {
        case EFor(v, iterator, child):
          var savedLocals = saveLocals();
          var iteratorType = typeExpr(iterator, Value);
          locals.set(v, getIteratorType(iteratorType, iterator));
          visit(child);
          locals = savedLocals;

        case EForGen(iterator, child):
          Tools.getKeyIterator(iterator, function(vk, vv, iteratorExpr)
          {
            if (vk == null)
            {
              error("Invalid for expression", iteratorExpr);
              return;
            }
            var savedLocals = saveLocals();
            var iteratorType = typeExpr(iteratorExpr, Value);
            var iteratorTypes = getKeyIteratorTypes(iteratorType, iteratorExpr);
            locals.set(vk, iteratorTypes.key);
            locals.set(vv, iteratorTypes.value);
            visit(child);
            locals = savedLocals;
          });

        case EWhile(cond, child), EDoWhile(cond, child):
          typeExprWith(cond, TBool);
          visit(child);

        case EIf(cond, e1, e2):
          typeExprWith(cond, TBool);
          visit(e1);
          if (e2 != null) visit(e2);

        case EParent(inner):
          visit(inner);

        case EBlock([inner]):
          visit(inner);

        case EMeta(_, _, inner):
          visit(inner);

        case EBinop("=>", key, value):
          if (!isMap)
          {
            error("Invalid mixed comprehension (got key=>value pair in non-map comprehension)", e);
            typeExpr(key, Value);
            typeExpr(value, Value);
            return;
          }
          inferKey(key);
          inferValue(value);

        default:
          if (isMap)
          {
            error("Invalid mixed comprehension (got non key=>value pair in map comprehension)", e);
            typeExpr(e, Value);
          }
          else
          {
            inferElement(e);
          }
      }
    }

    visit(body);

    if (isMap)
    {
      if (keyType == null) keyType = TDynamic;
      if (valueType == null) valueType = TDynamic;
      return types.resolve("Map", [keyType, valueType]) ?? TDynamic;
    }

    if (elementType == null) elementType = TDynamic;
    return types.resolve("Array", [elementType]) ?? TDynamic;
  }
  
  function typeExpr(expr:Expr, withType:WithType):TType
  {
    if (expr == null && isCompletion) return switch (withType)
    {
      case WithType(t):
        t;
      default:
        TDynamic;
    }
    switch (edef(expr))
    {
      case EConst(c):
        return switch (c)
        {
          case CInt(_):
            TInt;
          case CFloat(_):
            TFloat;
          case CString(_):
            types.t_string;
        }
      case EIdent(v):
        var l = locals.get(v);
        if (l != null) return l;
        var g = globals.get(v);
        if (g != null)
        {
          return switch (g)
          {
            case TLazy(f):
              f();
            default:
              g;
          }
        }
        if (allowAsync)
        {
          g = globals.get("a_" + v);
          if (g != null) g = unasync(g);
          if (g != null) return g;
        }
        switch (v)
        {
          case "null":
            return makeMono();
          case "true", "false":
            return TBool;
          case "trace":
            return TDynamic;
          default:
            switch (withType)
            {
              case WithType(et = TEnum(e, args)):
                for (c in e.constructors) if (c.name == v)
                {
                  if (onTopDownEnum(e, v))
                  {
                    var ct = c.args == null ? et : TFun(c.args, et);
                    return apply(ct, e.params, args);
                  }
                  break;
                }
              default:
            }
            if (isCompletion) return TDynamic;
            error("Unknown identifier " + v, expr);
        }
      case EBlock(el):
        var t = TVoid;
        var locals = saveLocals();
        for (e in el) t = typeExpr(e, e == el[el.length - 1] ? withType : NoValue);
        this.locals = locals;
        return t;
      case EVar(n, t, init):
        var vt = t == null ? makeMono() : makeType(t, expr);
        if (init != null)
        {
          var et = typeExpr(init, t == null ? Value : WithType(vt));
          if (t == null) vt = et
          else
            unify(et, vt, init);
        }
        locals.set(n, vt);
        return TVoid;
      case EFinal(n, t, init):
        var vt = t == null ? makeMono() : makeType(t, expr);
        if (init != null)
        {
          var et = typeExpr(init, t == null ? Value : WithType(vt));
          if (t == null) vt = et
          else
            unify(et, vt, init);
        }
        locals.set(n, vt);
        return TVoid;
      case EParent(e):
        return typeExpr(e, withType);
      case ECall(e, params):
        switch (edef(e))
        {
          case EField(val, "bind"):
            var ft = typeExpr(val, Value);
            switch (ft)
            {
              case TFun(args, ret):
                var remainArgs = args.copy();
                for (p in params)
                {
                  var a = remainArgs.shift();
                  if (a == null)
                  {
                    error("Too many arguments", p);
                    return TFun([], ret);
                  }
                  typeExprWith(p, a.t);
                }
                return TFun(remainArgs, ret);
              default:
            }
          default:
        }
        var ft = typeExpr(e, switch ([edef(e), withType])
        {
          case [EIdent(_), WithType(TEnum(_))]:
            withType;
          default:
            Value;
        });
        switch (follow(ft))
        {
          case TFun(args, ret):
            for (i in 0...params.length)
            {
              var a = args[i];
              if (a == null)
              {
                error("Too many arguments", params[i]);
                break;
              }
              var t = typeExpr(params[i], a == null ? Value : WithType(a.t));
              unify(t, a.t, params[i]);
            }
            for (i in params.length...args.length) if (!args[i].opt) error("Missing argument " + args[i].name + ":" + typeStr(args[i].t), expr);
            return ret;
          case TDynamic:
            for (p in params) typeExpr(p, Value);
            return makeMono();
          default:
            error(typeStr(ft) + " cannot be called", e);
            return makeMono();
        }
      case EField(o, f):
        return typeField(o, f, expr, false);
      case ECast(e, t):
        if (t == null)
        {
          typeExpr(e, Value);
          return TDynamic;
        }
        var castType = makeType(t, expr);
        var sourceType = typeExpr(e, Value);
        if (!tryUnify(sourceType, castType) && !tryUnify(castType, sourceType))
        {
          // Haxe casts can intentionally bridge otherwise unrelated types.
          // Keep this permissive but still resolve and validate the target type.
        }
        return castType;
      case ECheckType(v, t):
        var ct = makeType(t, expr);
        var vt = typeExpr(v, WithType(ct));
        unify(vt, ct, v);
        return ct;
      case EMeta(m, _, e):
        if (m == ":untyped" && allowUntypedMeta) return makeMono();
        return typeExpr(e, withType);
      case EIf(cond, e1, e2), ETernary(cond, e1, e2):
        typeExprWith(cond, TBool);
        var t1 = typeExpr(e1, withType);
        if (e2 == null) return t1;
        var t2 = typeExpr(e2, withType);
        if (withType == NoValue) return TVoid;
        if (tryUnify(t2, t1)) return t1;
        if (tryUnify(t1, t2)) return t2;
        unify(t2, t1, e2); // error
      case EWhile(cond, e), EDoWhile(cond, e):
        typeExprWith(cond, TBool);
        typeExpr(e, NoValue);
        return TVoid;
      case EObject(fl):
        switch (withType)
        {
          case WithType(follow(_) => TAnon(tfields)) if (tfields.length > 0):
            var map = [for (f in tfields) f.name => f];
            return TAnon([for (f in fl)
            {
              var ft = map.get(f.name);
              var ft = if (ft == null)
              {
                error("Extra field " + f.name, f.e);
                TDynamic;
              }
              else ft.t;
              {
                t: typeExprWith(f.e, ft),
                opt: false,
                name: f.name
              }
            }]);
          default:
            return TAnon([for (f in fl) {
              t: typeExpr(f.e, Value),
              opt: false,
              name: f.name
            }]);
        }
      case EBreak, EContinue:
        return TVoid;
      case EReturn(v):
        var et = v == null ? TVoid : typeExpr(v, allowReturn == null ? Value : WithType(allowReturn));
        hasReturn = true;
        if (allowReturn == null) error("Return not allowed here", expr);
        else
          unify(et, allowReturn, v == null ? expr : v);
        return makeMono();
      case EArrayDecl(el):
        var expectedElement:Null<TType> = null;
        switch (withType)
        {
          case WithType(expected):
            switch (follow(expected))
            {
              case TInst(arrayClass, args) if (arrayClass.name == "Array" && args.length > 0):
                expectedElement = args[0];
              default:
            }
          default:
        }
        if (expectedElement != null)
        {
          for (v in el)
          {
            var itemType = typeExpr(v, WithType(expectedElement));
            unify(itemType, expectedElement, v);
          }
          return types.getType("Array", [expectedElement]);
        }

        var et:Null<TType> = null;
        var heterogeneous = false;
        for (v in el)
        {
          var itemType = typeExpr(v, Value);
          if (et == null)
          {
            et = itemType;
            continue;
          }
          if (tryUnify(itemType, et)) continue;
          if (tryUnify(et, itemType))
          {
            et = itemType;
            continue;
          }
          heterogeneous = true;
        }
        if (heterogeneous) et = TDynamic;
        if (et == null) et = TDynamic;
        return types.getType("Array", [et]);

      case EComprehension(body, isMap):
        return typeComprehension(body, isMap, withType);

      case EArray(a, index):
        typeExprWith(index, TInt);
        var at = typeExpr(a, Value);
        switch (follow(at))
        {
          case TInst({
            name: "Array"
          }, [et]):
            return et;
          case TInst({
            name: "String"
          }, _), TAbstract({
            name: "String"
          }, _):
            return types.t_string;
          default:
            error(typeStr(at) + " is not an Array", a);
        }
      case EThrow(e):
        typeExpr(e, Value);
        return makeMono();
      case EFunction(args, body, name, ret):
        var ft = null, tret = null, targs = null;
        if (currentFunType != null)
        {
          switch (currentFunType)
          {
            case TFun(args, ret):
              ft = currentFunType;
              tret = ret;
              targs = args;
            default:
              throw "assert";
          }
          currentFunType = null;
        }
        else
        {
          tret = ret == null ? makeMono() : makeType(ret, expr);
        }
        var locals = saveLocals();
        var oldRet = allowReturn;
        var oldGDef = allowDefine;
        var oldHasRet = hasReturn;
        allowReturn = tret;
        allowDefine = false;
        hasReturn = false;
        var withArgs = null;
        if (name != null && !withType.match(WithType(follow(_) => TFun(_))))
        {
          var ev = events.get(name);
          if (ev != null) withType = WithType(ev);
        }
        switch (withType)
        {
          case WithType(follow(_) => TFun(args, ret)):
            withArgs = args;
            unify(tret, ret, expr);
          default:
        }
        if (targs == null) targs = typeArgs(args, expr);
        for (i in 0...targs.length)
        {
          var a = targs[i];
          if (withArgs != null)
          {
            if (i < withArgs.length) unify(withArgs[i].t, a.t, expr);
            else
              error("Extra argument " + a.name, expr);
          }
          if (i < args.length && args[i].value != null) typeExprWith(args[i].value, a.t);
          this.locals.set(a.name, a.t);
        }
        if (
          withArgs != null
          && targs.length < withArgs.length
        ) error(
          "Missing " + (withArgs.length - targs.length) + " arguments (" +[for (i in targs.length...withArgs.length) typeStr(withArgs[i].t)].join(",") + ")",
          expr
          );
        typeExpr(body, NoValue);
        if (!hasReturn && !tryUnify(tret, TVoid)) error("Missing return " + typeStr(tret), expr);
        allowDefine = oldGDef;
        allowReturn = oldRet;
        hasReturn = oldHasRet;
        this.locals = locals;
        if (ft == null)
        {
          ft = TFun(targs, tret);
          if (name != null) locals.set(name, ft);
        }
        return ft;
      case EUnop(op, _, e):
        var et = typeExpr(e, Value);
        switch (op)
        {
          case "++", "--", "-":
            unify(et, TInt, e);
            return et;
          case "!":
            unify(et, TBool, e);
            return et;
          default:
        }
      case EFor(v, it, e):
        var locals = saveLocals();
        var itt = typeExpr(it, Value);
        var vt = getIteratorType(itt, it);
        this.locals.set(v, vt);
        typeExpr(e, NoValue);
        this.locals = locals;
        return TVoid;
      case EForGen(it, e):
        Tools.getKeyIterator(it, function(vk, vv, it)
        {
          if (vk == null)
          {
            error("Invalid for expression", it);
            return;
          }
          var locals = saveLocals();
          var itt = typeExpr(it, Value);
          var types = getKeyIteratorTypes(itt, it);
          this.locals.set(vk, types.key);
          this.locals.set(vv, types.value);
          typeExpr(e, NoValue);
          this.locals = locals;
        });
        return TVoid;
      case EBinop(op, e1, e2):
        switch (op)
        {
          case "&", "|", "^", ">>", ">>>", "<<":
            typeExprWith(e1, TInt);
            typeExprWith(e2, TInt);
            return TInt;
          case "=":
            if (allowDefine)
            {
              switch (edef(e1))
              {
                case EIdent(i) if (!locals.exists(i) && !globals.exists(i)):
                  var vt = typeExpr(e2, Value);
                  locals.set(i, vt);
                  return vt;
                default:
              }
            }
            var vt = switch (edef(e1))
            {
              case EField(o, f):
                typeField(o, f, e1, true);
              default:
                typeExpr(e1, Value);
            }
            typeExprWith(e2, vt);
            return vt;
          case "+":
            var t1 = typeExpr(e1, WithType(TInt));
            var t2 = typeExpr(e2, WithType(t1));
            tryUnify(t1, t2);
            switch ([follow(t1), follow(t2)])
            {
              case [TInt, TInt]:
                return TInt;
              case [TFloat, TInt], [TInt, TFloat], [TFloat, TFloat]:
                return TFloat;
              case [TDynamic, _], [_, TDynamic]:
                return TDynamic;
              case [t1, t2]:
                if (isString(t1) || isString(t2)) return types.t_string;
                unify(t1, TFloat, e1);
                unify(t2, TFloat, e2);
            }
          case "-", "*", "/", "%":
            var t1 = typeExpr(e1, WithType(TInt));
            var t2 = typeExpr(e2, WithType(t1));
            if (!tryUnify(t1, t2)) unify(t2, t1, e2);
            switch ([follow(t1), follow(t2)])
            {
              case [TInt, TInt]:
                if (op == "/") return TFloat;
                return TInt;
              case [TFloat | TDynamic, TInt | TDynamic], [TInt | TDynamic, TFloat | TDynamic], [TFloat, TFloat]:
                return TFloat;
              default:
                unify(t1, TFloat, e1);
                unify(t2, TFloat, e2);
            }
          case "&&", "||":
            typeExprWith(e1, TBool);
            typeExprWith(e2, TBool);
            return TBool;
          case "...":
            typeExprWith(e1, TInt);
            typeExprWith(e2, TInt);
            return makeIterator(TInt);
          case "==", "!=":
            var t1 = typeExpr(e1, Value);
            var t2 = typeExpr(e2, WithType(t1));
            if (!tryUnify(t1, t2)) unify(t2, t1, e2);
            return TBool;
          case ">", "<", ">=", "<=":
            var t1 = typeExpr(e1, Value);
            var t2 = typeExpr(e2, WithType(t1));
            if (!tryUnify(t1, t2)) unify(t2, t1, e2);
            switch (follow(t1))
            {
              case TInt, TFloat, TBool, TInst({
                name: "String"
              }, _):
              default:
                error("Cannot compare " + typeStr(t1), expr);
            }
            return TBool;
          default:
            if (op.charCodeAt(op.length - 1) == "=".code)
            {
              return typeExpr(mk(EBinop("=", e1, e2), expr), withType);
            }
            error("Unsupported operation " + op, expr);
        }
      case ETry(etry, catches):
        var tryType = typeExpr(etry, withType);

        for (catcher in catches)
        {
          var old = locals.get(catcher.name);
          var catchType:TType = catcher.t == null ? TDynamic : makeType(catcher.t, catcher.e);
          locals.set(catcher.name, catchType);
          var catchExprType = typeExpr(catcher.e, withType);
          if (old != null) locals.set(catcher.name, old);
          else
            locals.remove(catcher.name);

          if (withType != NoValue && !tryUnify(tryType, catchExprType)) unify(catchExprType, tryType, catcher.e);
        }

        if (withType == NoValue) return TVoid;
        return tryType;
      case ESwitch(value, cases, defaultExpr):
        var tmin = null;
        var vt = typeExpr(value, Value);
        inline function mergeType(t, p)
        {
          if (withType != NoValue)
          {
            if (tmin == null) tmin = t;
            else if (!tryUnify(t, tmin))
            {
              unify(tmin, t, p);
              tmin = t;
            }
          }
        }
        for (c in cases)
        {
          for (v in c.values)
          {
            var ct = typeExpr(v, WithType(vt));
            unify(ct, vt, v);
          }
          var et = typeExpr(c.expr, withType);
          mergeType(et, c.expr);
        }
        if (defaultExpr != null) mergeType(typeExpr(defaultExpr, withType), defaultExpr);
        return withType == NoValue ? TVoid : tmin == null ? makeMono() : tmin;
      case ENew(cl, params):
        var classType = types.resolve(cl);
        if (classType == null)
        {
          error("Unknown type " + cl, expr);
          for (param in params) typeExpr(param, Value);
          return TDynamic;
        }
        switch (follow(classType))
        {
          case TInst(cls, typeArgs):
            if (typeArgs.length == 0 && cls.params.length > 0) typeArgs = [for (_ in cls.params) makeMono()];
            var constructor = cls.constructor;
            if (constructor != null)
            {
              if (!constructor.isPublic && currentClassName != cls.name) error("Can't access private constructor for " + cl, expr);
              var constructorFieldType = constructor.t;
              if (
                constructor.params != null
                && constructor.params.length > 0
              ) constructorFieldType = apply(constructorFieldType, constructor.params, [for (_ in constructor.params) makeMono()]);
              var constructorType = apply(constructorFieldType, cls.params, typeArgs);
              switch (follow(constructorType))
              {
                case TFun(args, _):
                  checkCallArguments(args, params, expr, "constructor " + cl);
                case TDynamic:
                  for (param in params) typeExpr(param, Value);
                default:
                  if (params.length > 0) error("Type " + cl + " has no callable constructor", expr);
              }
            }
            else if (params.length > 0)
            {
              error("Type " + cl + " has no constructor accepting arguments", expr);
              for (param in params) typeExpr(param, Value);
            }
            else
            {
              for (param in params) typeExpr(param, Value);
            }
            return TInst(cls, typeArgs);
          case TAbstract(abs, typeArgs):
            if (typeArgs.length == 0 && abs.params.length > 0) typeArgs = [for (_ in abs.params) makeMono()];
            switch (follow(apply(abs.t, abs.params, typeArgs)))
            {
              case TInst(cls, classArgs) if (cls.constructor != null):
                if (!cls.constructor.isPublic && currentClassName != cls.name) error("Can't access private constructor for " + cl, expr);
                var constructorFieldType = cls.constructor.t;
                if (
                  cls.constructor.params != null
                  && cls.constructor.params.length > 0
                ) constructorFieldType = apply(constructorFieldType, cls.constructor.params, [for (_ in cls.constructor.params) makeMono()]);
                var constructorType = apply(constructorFieldType, cls.params, classArgs);
                switch (follow(constructorType))
                {
                  case TFun(args, _):
                    checkCallArguments(args, params, expr, "constructor " + cl);
                  default:
                    for (param in params) typeExpr(param, Value);
                }
              default:
                if (params.length > 0) error("Abstract type " + cl + " cannot be constructed with arguments", expr);
                for (param in params) typeExpr(param, Value);
            }
            return TAbstract(abs, typeArgs);
          default:
            error("Type " + cl + " cannot be constructed", expr);
            for (param in params) typeExpr(param, Value);
            return TDynamic;
        }
    }
    error("Don't know how to type " + edef(expr).getName(), expr);
    return TDynamic;
  }

  function checkCallArguments(args:Array<
    {name:String, opt:Bool, t:TType}>,
    params:Array<Expr>,
    at:Expr,
    callName:String):Void
  {
    for (i in 0...params.length)
    {
      var arg = i < args.length ? args[i] : null;
      if (arg == null)
      {
        error("Too many arguments for " + callName, params[i]);
        typeExpr(params[i], Value);
      }
      else
      {
        var actual = typeExpr(params[i], WithType(arg.t));
        unify(actual, arg.t, params[i]);
      }
    }
    for (i in params.length...args.length) if (!args[i].opt) error("Missing argument " + args[i].name + ":" + typeStr(args[i].t) + " for " + callName, at);
  }

  function getIteratorType(itt:TType, it:Expr)
  {
    switch (follow(itt))
    {
      case TInst({
        name: "Array"
      }, [t]):
        return t;
      default:
    }
    var ft = getField(itt, "iterator", it);
    if (ft == null) switch (itt)
    {
      case TAbstract(a, args):
        // special case : we allow unconditional access
        // to an abstract iterator() underlying value (eg: ArrayProxy)
        var at = apply(a.t, a.params, args);
        return getIteratorType(at, it);
      default:
    }
    if (ft != null) switch (ft)
    {
      case TFun([], ret):
        ft = ret;
      default:
        ft = null;
    }
    var t = makeMono();
    var iter = makeIterator(t);
    unify(ft != null ? ft : itt, iter, it);
    return t;
  }

  function getKeyIteratorTypes(itt:TType, it:Expr)
  {
    switch (follow(itt))
    {
      case TInst({
        name: "Array"
      }, [t]):
        return {
          key: TInt,
          value: t
        };
      default:
    }
    var ft = getField(itt, "keyValueIterator", it);
    if (ft == null) switch (itt)
    {
      case TAbstract(a, args):
        // special case : we allow unconditional access
        // to an abstract keyValueIterator() underlying value (eg: ArrayProxy)
        var at = apply(a.t, a.params, args);
        return getKeyIteratorTypes(at, it);
      default:
    }
    if (ft != null) switch (ft)
    {
      case TFun([], ret):
        ft = ret;
      default:
        ft = null;
    }
    var key = makeMono();
    var value = makeMono();
    var iter = makeIterator(TAnon([
      {
        name: "key",
        t: key,
        opt: false
      },
      {
        name: "value",
        t: value,
        opt: false
      }
    ]));
    unify(ft != null ? ft : itt, iter, it);
    return {
      key: key,
      value: value
    };
  }
}
