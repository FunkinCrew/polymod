package polymod.hscript._internal;

import haxe.ds.ObjectMap;
import polymod.hscript._internal.Expr.EnumDecl;
import polymod.hscript._internal.Expr.ClassDecl;
import polymod.hscript._internal.Expr.ClassImport;
import polymod.hscript._internal.Expr.FieldDecl;
import polymod.hscript._internal.Expr.FunctionDecl;
import polymod.hscript._internal.Expr.VarDecl;
import polymod.hscript._internal.Printer;
import polymod.util.Util;

using StringTools;

/**
 * Provides handlers for scripted classes
 * Based on code by Ian Harrigan
 * @see https://github.com/ianharrigan/hscript-ex
 */
@:access(polymod.hscript._internal.Interp)
@:allow(polymod.Polymod)
class PolymodScriptClass
{
  /*
   * STATIC VARIABLES
   */
  private static final scriptInterp:Interp = new Interp(null, null);

  /**
   * Provide a class name along with a corresponding class to override imports.
   * You can set the value to `null` to prevent the class from being imported.
   */
  public static final importOverrides:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

  /**
   * Provide a class name along with a corresponding class to import it in every scripted class.
   */
  public static final defaultImports:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

  /**
   * Provide a class with an array of its static fields to blacklist them.
   * Blacklisted fields cannot be gotten or set.
   */
  public static final blacklistedStaticFields:ObjectMap<Dynamic, Array<String>> = new ObjectMap<Dynamic, Array<String>>();

  /**
   * Provide a class name with an array of its instance fields to blacklist them.
   * Needs to be a string map because class instances won't point to the same reference.
   * Blacklisted fields cannot be gotten or set.
   */
  public static final blacklistedInstanceFields:Map<String, Array<String>> = new Map<String, Array<String>>();

  /**
   * Field names that may not be reached even through a receiver whose type is not known.
   */
  public static final blacklistedDynamicFieldNames:Map<String, Bool> = new Map<String, Bool>();

  /**
   * Bumped whenever a blacklist changes, so anything caching a lookup can tell it went stale.
   */
  public static var blacklistGeneration(default, null):Int = 0;

  /**
   * `blacklistedStaticFields` re-keyed by class name, since a compiled script only knows names.
   */
  static var staticFieldsByNameCache:Null<Map<String, Array<String>>> = null;

  /**
   * Class name to every blacklisted instance field it has, inherited ones included.
   */
  static var resolvedInstanceFields:Map<String, Array<String>> = new Map<String, Array<String>>();

  /**
   * Throw away everything derived from the blacklists. Call after changing one.
   */
  public static function bumpBlacklistGeneration():Void
  {
    blacklistGeneration++;
    staticFieldsByNameCache = null;
    resolvedInstanceFields.clear();
  }

  /**
   * The blacklisted static fields, keyed by class name instead of by class.
   */
  public static function staticFieldsByName():Map<String, Array<String>>
  {
    if (staticFieldsByNameCache != null) return staticFieldsByNameCache;

    var result:Map<String, Array<String>> = new Map<String, Array<String>>();

    for (cls in blacklistedStaticFields.keys())
    {
      var name:Null<String> = null;
      try
      {
        name = Type.getClassName(cls);
      }
      catch (_:Dynamic) {}

      if (name == null) continue;
      result.set(name, blacklistedStaticFields.get(cls));
    }

    staticFieldsByNameCache = result;
    return result;
  }

  /**
   * Every name an instance of this class could be blacklisted under, itself first.
   */
  static function ancestorsOf(clsName:String):Array<String>
  {
    var result:Array<String> = [clsName];

    var cls:Null<Class<Dynamic>> = null;
    try
    {
      cls = Type.resolveClass(clsName);
    }
    catch (_:Dynamic) {}

    // A hand written script could name a class that is its own super, so do not trust the chain.
    var depth:Int = 0;
    while (cls != null && depth++ < 64)
    {
      try
      {
        cls = Type.getSuperClass(cls);
      }
      catch (_:Dynamic)
      {
        break;
      }

      if (cls == null) break;

      var name:Null<String> = Type.getClassName(cls);
      if (name == null || result.contains(name)) break;

      result.push(name);
    }

    return result;
  }

  /**
   * Every blacklisted instance field reachable on this class.
   */
  public static function blacklistedInstanceFieldsOf(clsName:String):Array<String>
  {
    var cached:Null<Array<String>> = resolvedInstanceFields.get(clsName);
    if (cached != null) return cached;

    var result:Array<String> = [];

    for (name in ancestorsOf(clsName))
    {
      var fields:Null<Array<String>> = blacklistedInstanceFields.get(name);
      if (fields == null) continue;

      for (field in fields)
        if (!result.contains(field)) result.push(field);
    }

    resolvedInstanceFields.set(clsName, result);
    return result;
  }

  /**
   * Whether this field is blacklisted on this exact class, ignoring what it inherits.
   */
  public static function isBlacklistedFieldExact(clsName:String, field:String):Bool
  {
    if (clsName == null || clsName.length == 0) return false;

    var statics:Null<Array<String>> = staticFieldsByName().get(clsName);
    if (statics != null && statics.contains(field)) return true;

    var fields:Null<Array<String>> = blacklistedInstanceFields.get(clsName);
    return fields != null && fields.contains(field);
  }

  /**
   * Whether this field is blacklisted on this class or on anything it extends.
   */
  public static function isBlacklistedField(clsName:String, field:String):Bool
  {
    if (clsName == null || clsName.length == 0) return false;

    var statics:Null<Array<String>> = staticFieldsByName().get(clsName);
    if (statics != null && statics.contains(field)) return true;

    return blacklistedInstanceFieldsOf(clsName).contains(field);
  }

  /**
   * Every field name any blacklist mentions.
   */
  public static function blacklistedFieldNames():Map<String, Bool>
  {
    var result:Map<String, Bool> = new Map<String, Bool>();

    for (fields in staticFieldsByName())
      for (field in fields)
        result.set(field, true);

    for (fields in blacklistedInstanceFields)
      for (field in fields)
        result.set(field, true);

    for (field in blacklistedDynamicFieldNames.keys())
      result.set(field, true);

    return result;
  }

  /*
   * STATIC METHODS
   */
  /**
   * Register a scripted class by parsing the text of that script.
   */
  static function registerScriptClassByString(body:String, ?path:String):Void
  {
    scriptInterp.addModule(body, path == null ? 'hscriptClass' : 'hscriptClass($path)');
  }

  /**
   * STATIC PROPERTIES
   */
  /**
   * Define a list of script classes to override the default behavior of Polymod.
   * For example, script classes should import `ScriptedSprite` instead of `Sprite`.
   */
  public static var scriptClassOverrides(get, never):Map<String, Class<Dynamic>>;

  static var _scriptClassOverrides:Map<String, Class<Dynamic>> = null;

  static function get_scriptClassOverrides():Map<String, Class<Dynamic>>
  {
    if (_scriptClassOverrides == null)
    {
      _scriptClassOverrides = new Map<String, Class<Dynamic>>();

      var baseScriptClassOverrides:Map<String, Class<Dynamic>> = PolymodScriptClassMacro.listHScriptedClasses();

      for (key => value in baseScriptClassOverrides)
      {
        _scriptClassOverrides.set(key, value);
      }
    }

    return _scriptClassOverrides;
  }

  /**
   * Define a list of all the abstracts we have available at compile time,
   * and map them to internal implementation classes.
   * We use this to access the functions of these abstracts.
   */
  public static var abstractClassImpls(get, never):Map<String, PolymodStaticAbstractReference>;

  static var _abstractClassImpls:Map<String, PolymodStaticAbstractReference> = null;

  static function get_abstractClassImpls():Map<String, PolymodStaticAbstractReference>
  {
    if (_abstractClassImpls == null)
    {
      _abstractClassImpls = new Map<String, PolymodStaticAbstractReference>();

      var baseAbstractClassImpls:Map<String,
        {
          cls:Class<Dynamic>,
          polymodCls:Null<Class<Dynamic>>,
        }> = PolymodScriptClassMacro.listAbstractImpls();

      for (key => value in baseAbstractClassImpls)
      {
        if (value == null) continue;

        _abstractClassImpls.set(key, new PolymodStaticAbstractReference(key, value.cls, value.polymodCls));
      }
    }

    return _abstractClassImpls;
  }

  /**
   * Define a list of `typeName -> Class` which provides a reference to each typedef,
   * since typedefs can't be normally resolved at runtime.
   */
  public static var typedefs(get, never):Map<String, Class<Dynamic>>;

  static var _typedefs:Map<String, Class<Dynamic>> = null;

  static function get_typedefs():Map<String, Class<Dynamic>>
  {
    if (_typedefs == null)
    {
      _typedefs = new Map<String, Class<Dynamic>>();

      var baseTypedefs:Map<String, Class<Dynamic>> = PolymodScriptClassMacro.listTypedefs();

      for (key => value in baseTypedefs)
      {
        _typedefs.set(key, value);
      }
    }

    return _typedefs;
  }

  static var _baseClassesByPackage:Map<String, Array<String>>;

  /**
   * Defines a list of classes that each package contains.
   * Compiled at runtime through a macro to then be stored here.
   */
  public static var baseClassesByPackage(get, never):Map<String, Array<String>>;

  static function get_baseClassesByPackage():Map<String, Array<String>>
  {
    if (_baseClassesByPackage == null)
    {
      _baseClassesByPackage = new Map<String, Array<String>>();
      for (pkg => cls in PolymodScriptClassMacro.listPackagesList())
      {
        _baseClassesByPackage.set(pkg, cls);
      }
    }
    return _baseClassesByPackage;
  }

  static var _scriptClassesByPackage:Map<String, Array<String>>;

  /**
   * Defines a list of scripted classes that each package contains.
   * Reset everytime scripts are re-registered.
   */
  public static var scriptClassesByPackage(get, never):Map<String, Array<String>>;

  static function get_scriptClassesByPackage():Map<String, Array<String>>
  {
    if (_scriptClassesByPackage == null)
    {
      _scriptClassesByPackage = new Map<String, Array<String>>();

      for (cls in Interp._scriptClassDescriptors)
      {
        if (cls.pkg == null || cls.pkg.length == 0) continue;

        var pack:String = cls.pkg.join('.');
        var list:Array<String> = _scriptClassesByPackage.get(pack) ?? [];
        var fullPath:String = Util.getFullClassName(cls);

        if (!list.contains(fullPath))
          list.push(fullPath);

        _scriptClassesByPackage.set(cls.pkg.join('.'), list);
      }
    }
    return _scriptClassesByPackage;
  }

  /**
   * Register a scripted class by retrieving the script from the given path.
   *
   * @return `true` if the script was registered successfully, otherwise `false`.
   */
  static function registerScriptClassByPath(path:String):Bool
  {
    var scriptBody = Polymod.assetLibrary.getText(path);
    if (scriptBody == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Error while loading script "${path}", could not retrieve script contents!', SCRIPT_RUNTIME);
      return false;
    }
    try
    {
      registerScriptClassByString(scriptBody, path);
      return true;
    }
    catch (err:Expr.Error)
    {
      var errLine:String = #if hscriptPos '${err.line}' #else '#???' #end;
      #if hscriptPos
      switch (err.e)
      #else
      switch (err)
      #end
      {
        case EUnexpected(s):
          Polymod.error(SCRIPT_PARSE_FAILED,
            'Error while parsing function ${path}#${errLine}: EUnexpected' + '\n' + 'Unexpected token "${s}", is there invalid syntax on this line?',
            SCRIPT_RUNTIME);
          return false;
        case EClassUnresolvedSuperclass(cls, reason):
          Polymod.error(SCRIPT_PARSE_FAILED,
            'Error while parsing class ${path}#${errLine}: EClassUnresolvedSuperclass' + '\n' + 'Unresolved superclass "${cls}", ${reason}', SCRIPT_RUNTIME);
          return false;
        case EInvalidAccessorCombination(accessors):
          Polymod.error(
            SCRIPT_PARSE_FAILED,
            'Error while parsing function ${path}#${errLine}: EInvalidAccessorCombination' + '\n' + 'Invalid modifier combination: ${accessors.join(' + ')}', SCRIPT_RUNTIME);
            return false;
        default:
          Polymod.error(SCRIPT_PARSE_FAILED, 'Error while parsing script ${path}#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}', SCRIPT_RUNTIME);
          return false;
      }
    }
  }

  #if lime
  static function registerScriptClassByPathAsync(path:String):lime.app.Future<Bool>
  {
    var promise = new lime.app.Promise<Bool>();

    if (!Polymod.assetLibrary.exists(path))
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Error while loading script "${path}", could not retrieve contents of non-existent script!', SCRIPT_RUNTIME);
      return null;
    }

    Polymod.assetLibrary.loadText(path).onComplete((text) -> {
      try
      {
        registerScriptClassByString(text, path);
        promise.complete(true);
      }
      catch (err:Expr.Error)
      {
        var errLine:String = #if hscriptPos '${err.line}' #else "#???" #end;
        #if hscriptPos
        switch (err.e)
        #else
        switch (err)
        #end
        {
          case EUnexpected(s):
            Polymod.error(SCRIPT_PARSE_FAILED,
              'Error while parsing script ${path}#${errLine}: EUnexpected' + '\n' +
              'Unexpected error: Unexpected token "${s}", is there invalid syntax on this line?',
              SCRIPT_RUNTIME);
          default:
            Polymod.error(SCRIPT_PARSE_FAILED, 'Error while parsing script ${path}#${errLine}: ' + '\n' + 'An unknown error occurred: ${err}', SCRIPT_RUNTIME);
        }
        promise.error(err);
      }
    }).onError((err) -> {
      if (err == '404')
      {
        Polymod.error(SCRIPT_PARSE_FAILED, 'Error while loading script "${path}", could not retrieve script contents (404 error)!', SCRIPT_RUNTIME);
      }
      else
      {
        Polymod.error(SCRIPT_PARSE_FAILED, 'Error while parsing script ${path}: ' + '\n' + 'An unknown error occurred: ${err}', SCRIPT_RUNTIME);
        promise.error(err);
      }
    });
    // Await the promise
    return promise.future;
  }
  #end

  /**
   * Returns a list of all registered classes.
   * @return Array<String>
   */
  public static function listScriptClasses():Array<String>
  {
    var result = [];
    @:privateAccess
    for (key => _value in Interp._scriptClassDescriptors)
    {
      result.push(key);
    }
    return result;
  }

  /**
   * Clears all parsed scripted class descriptors.
   * You can call `Polymod.registerAllScriptClasses()` to re-register them later.
   */
  public static function clearScriptedClasses():Void
  {
    scriptInterp.clearScriptClassDescriptors();
  }

  /**
   * Returns a list of all registered classes which extend the class specified by the given name.
   * @return Array<String>
   */
  public static function listScriptClassesExtending(clsPath:String):Array<String>
  {
    var result = [];

    #if POLYMOD_CPPIA
    // Do CPPIA first!
    for (key in PolymodCppiaClassReference.listCppiaClassesExtending(clsPath))
    {
      result.push(key);
    }
    #end

    @:privateAccess
    for (key => value in Interp._scriptClassDescriptors)
    {
      if (result.indexOf(key) != -1) continue;

      var superClasses = getSuperClasses(value);
      if (superClasses.indexOf(clsPath) != -1)
      {
        result.push(key);
      }
    }
    return result;
  }

  /**
   * Returns a list of all registered classes which extend the specified class.
       * @param cls Any Class which you expect scripted classes to be extending.
   * @return Array<String>
   */
  static function listScriptClassesExtendingClass(cls:Class<Dynamic>):Array<String>
  {
    return listScriptClassesExtending(Type.getClassName(cls));
  }

  static function getSuperClasses(classDecl:ClassDecl):Array<String>
  {
    if (classDecl.extend == null)
    {
      // No superclasses.
      return [];
    }

    // Get the super class name.
    var fullSuperClsName = (new Printer()).typeToString(classDecl.extend);
    var baseSuperClsName = switch (classDecl.extend)
    {
      case CTPath(pth, params):
        pth[pth.length - 1];
      default:
        fullSuperClsName;
    };

    // Check if the superclass is a scripted class.
    var classDescriptor:ClassDecl = Interp.findScriptClassDescriptor(fullSuperClsName);

    if (classDescriptor != null)
    {
      var result = [fullSuperClsName];

      // Parse the parent scripted class.
      return result.concat(getSuperClasses(classDescriptor));
    }
    else
    {
      // Templates are ignored completely since there's no type checking in HScript.
      if (fullSuperClsName.indexOf('<') != -1)
      {
        fullSuperClsName = fullSuperClsName.split('<')[0];
        baseSuperClsName = baseSuperClsName.split('<')[0];
      }

      var superCls:Dynamic = null;

      if (classDecl.imports.exists(baseSuperClsName))
      {
        var importedClass:ClassImport = classDecl.imports.get(baseSuperClsName);
        if (importedClass != null && importedClass.cls == null)
        {
          // importedClass was defined but `cls` was null. This class must have been blacklisted.
          var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
          Polymod.error(SCRIPT_PARSE_FAILED,
            'Could not parse superclass "${classDecl.name}" of scripted class "${clsName}". The superclass may be blacklisted.', SCRIPT_RUNTIME);
          return [];
        }
        else if (importedClass != null)
        {
          superCls = importedClass.cls;
        }
      }

      // Check if the superclass was resolved.
      if (superCls != null)
      {
        var result = [];
        // The superclass is a native class.
        while (superCls != null)
        {
          // Recursively add this class's superclasses.
          if (Std.isOfType(superCls, PolymodScriptClass)) result.push(superCls.fullyQualifiedName);
          else
            result.push(Type.getClassName(superCls));

          // This returns null when the class has no superclass.
          if (Std.isOfType(superCls, PolymodScriptClass)) superCls = superCls.superClass;
          else
            superCls = Type.getSuperClass(superCls);
        }
        return result;
      }
      else
      {
        // The superclass is not a scripted class or native class. Probably doesn't exist, throw an error.
        var clsName = classDecl.pkg != null ? '${classDecl.pkg.join('.')}.${classDecl.name}' : classDecl.name;
        Polymod.error(SCRIPT_PARSE_FAILED, 'Could not parse superclass "$fullSuperClsName" of scripted class "${clsName}". Did you forget to import it?',
          SCRIPT_RUNTIME);
        return [];
      }
    }
  }

  public static function callScriptClassStaticFunction(clsName:String, funcName:String, args:Array<Dynamic> = null):Dynamic
  {
    return scriptInterp.callScriptClassStaticFunction(clsName, funcName, args);
  }

  public static function hasScriptClassStaticField(clsName:String, funcName:String):Bool
  {
    return scriptInterp.hasScriptClassStaticField(clsName, funcName);
  }

  public static function hasScriptClassStaticFunction(clsName:String, funcName:String):Bool
  {
    return scriptInterp.hasScriptClassStaticFunction(clsName, funcName);
  }

  public static function getScriptClassStaticField(clsName:String, fieldName:String):Dynamic
  {
    return scriptInterp.getScriptClassStaticField(clsName, fieldName);
  }

  public static function setScriptClassStaticField(clsName:String, fieldName:String, fieldValue:Dynamic):Dynamic
  {
    return scriptInterp.setScriptClassStaticField(clsName, fieldName, fieldValue);
  }

  // Override version of Std.isOfType so we're able to test for scripted classes.
  public static function isOfType(v:Dynamic, t:Dynamic):Bool
  {
    if (t is String && Interp._scriptEnumDescriptors.exists(t))
    {
      if (v is PolymodEnum)
      {
        var enumDecl:EnumDecl = v._e;

        return Util.getFullEnumClass(enumDecl) == t;
      }
      return false;
    }

    var typeClassDecl:ClassDecl = null;
    var typeFullName:String = '';
    if (t is PolymodStaticClassReference)
    {
      var o = cast(t, PolymodStaticClassReference);
      typeClassDecl = o.cls;
      typeFullName = Util.getFullClassName(typeClassDecl);
    }
    else
    {
      typeFullName = Util.getTypeNameOf(t);
    }

    // Check again for a class descriptor just in case.
    // We check for the full package name in case the scripted class was packaged.
    if (typeClassDecl == null)
    {
      var typeNameSplit:Array<String> = typeFullName.split('.');
      var typeName:String = typeNameSplit.length < 1 ? typeFullName : typeNameSplit[typeNameSplit.length - 1];

      typeClassDecl = Interp.findScriptClassDescriptor(typeFullName) ?? Interp.findScriptClassDescriptor(typeName) ?? null;
      if (typeClassDecl != null)
      {
        // Re-assign full package.
        typeFullName = Util.getFullClassName(typeClassDecl);
      }
    }

    // `v` can be a PolymodScriptClass if you call `this` from a scripted class.
    if (v is HScriptedClass || v is PolymodStaticClassReference || v is PolymodScriptClass)
    {
      var proxy:PolymodAbstractScriptClass = switch (v)
      {
        case (_ is HScriptedClass) => true: v._asc;
        case (_ is PolymodStaticClassReference) => true: v.cls;
        default: cast v;
      }
      var allPackages:Array<String> = [proxy.fullyQualifiedName].concat(getSuperClasses(proxy._c));

      // Check whether the base class or any super classes are the same type as the type class.
      return allPackages.indexOf(typeFullName) != -1;
    }

    // If we're on this line then it means `v` isn't a scripted class and `t` is instead.
    // We can safely return false since source classes won't be able to extend scripted classes anyway.
    if (typeClassDecl != null)
    {
      return false;
    }

    // Fallback to using the regular Std.isOfType
    return #if (haxe_ver >= 4.2) Std.isOfType #else Std.is #end (v, t);
  }


  /**
   * INSTANCE METHODS
   */
  public function new(c:ClassDecl, args:Array<Dynamic>)
  {
    var targetClass:Class<Dynamic> = null;
    switch (c.extend)
    {
      case CTPath(pth, params):
        var clsPath = pth.join('.');
        var clsName = pth[pth.length - 1];

        if (Interp.findScriptClassDescriptor(clsPath) != null)
        {
          targetClass = null;
        }
        else if (scriptClassOverrides.exists(clsPath))
        {
          targetClass = scriptClassOverrides.get(clsPath);
        }
        #if POLYMOD_CPPIA
        else if (PolymodCppiaClassReference.hasCppiaClass(clsPath))
        {
          if (!PolymodCppiaClassReference.isExtendableCppiaClass(clsPath))
          {
            Polymod.error(SCRIPT_PARSE_FAILED,
              'Cannot extend compiled class ("${Util.getFullClassName(c)}" tried extending "$clsPath"). Mark it with @:hscriptExtendable and rebuild the compiled script.',
              SCRIPT_RUNTIME);
            return;
          }

          targetClass = PolymodCppiaClassReference.getCppiaClass(clsPath);
        }
        #end
        else if (c.imports.exists(clsName))
        {
          var importedClass:ClassImport = c.imports.get(clsName);
          if (importedClass != null && importedClass.cls != null)
          {
            if (untyped !importedClass.cls._isHScriptedClass)
            {
              Polymod.error(SCRIPT_PARSE_FAILED, 'Cannot extend non-scriptable class ("${Util.getFullClassName(c)}" tried extending "${pth.join('.')}").',
                SCRIPT_RUNTIME);
              return;
            }
            else
            {
              targetClass = importedClass.cls;
            }
          }
          else if (importedClass != null && importedClass.cls == null)
          {
            Polymod.error(SCRIPT_PARSE_FAILED, 'Could not determine target class for "${pth.join('.')}" (blacklisted type?)', SCRIPT_RUNTIME);
          }
          else
          {
            Polymod.error(SCRIPT_PARSE_FAILED, 'Could not determine target class for "${pth.join('.')}" (unregistered type?)', SCRIPT_RUNTIME);
          }
        }
        else
        {
          Polymod.error(SCRIPT_PARSE_FAILED, 'Could not determine target class for "${pth.join('.')}" (unregistered type?)', SCRIPT_RUNTIME);
        }
      default:
        if (c.extend != null)
        {
          Polymod.error(SCRIPT_PARSE_FAILED, 'Could not determine target class for "${c.extend}" (unknown type?)', SCRIPT_RUNTIME);
        }
    }
    _interp = new Interp(targetClass, this);
    _c = c;
    buildCaches();

    var ctorField = findField("new");
    if (ctorField != null)
    {
      callFunction("new", args);
      if (superClass == null && _c.extend != null)
      {
        _interp.error(EClassSuperNotCalled);
      }
    }
    else if (_c.extend != null)
    {
      createSuperClass(args);
    }
    _constructorArgs = args;

    validateClassFields();
  }

  var __superClassFieldList:Array<String> = null;

  public function superHasField(name:String):Bool
  {
    if (superClass == null) return false;
    // Reflect.hasField(this, name) is REALLY expensive so we use a cache.
    if (__superClassFieldList == null)
    {
      __superClassFieldList = [];

      // NOTE: Explicit Dynamic so Haxe doesn't infer it's a PolymodScriptClass
      var _superClass:Dynamic = superClass;
      while (Std.isOfType(_superClass, PolymodScriptClass))
      {
        var scriptFields:Array<String> = [
          for (key in ((_superClass : PolymodScriptClass)._cachedFieldDecls?.keys() ?? cast []))
            key
        ];
        __superClassFieldList = __superClassFieldList.concat(scriptFields);

        if (_superClass.superClass == null) break;
        _superClass = _superClass.superClass;
      }

      __superClassFieldList = __superClassFieldList.concat(Reflect.fields(_superClass));
      __superClassFieldList = __superClassFieldList.concat(Type.getInstanceFields(Type.getClass(_superClass)));
    }
    return __superClassFieldList.indexOf(name) != -1;
  }

  public function getConstructorArgs():Array<Dynamic>
  {
    return _constructorArgs;
  }

  private function createSuperClass(args:Array<Dynamic> = null)
  {
    if (_c.extend == null)
    {
      _interp.error(EClassInvalidSuper);
    }

    if (args == null)
    {
      args = [];
    }

    var fullExtendString = new Printer().typeToString(_c.extend);

    // Templates are ignored completely since there's no type checking in HScript.
    if (fullExtendString.indexOf('<') != -1)
    {
      fullExtendString = fullExtendString.split('<')[0];
    }

    // Build an unqualified path too.
    var fullExtendStringParts = fullExtendString.split('.');
    var extendString = fullExtendStringParts[fullExtendStringParts.length - 1];

    var classDescriptor = Interp.findScriptClassDescriptor(fullExtendString);
    if (classDescriptor != null)
    {
      var abstractSuperClass:PolymodAbstractScriptClass = new PolymodScriptClass(classDescriptor, args);
      superClass = abstractSuperClass;
    }
    else
    {
      var clsToCreate:Class<Dynamic> = null;

      if (scriptClassOverrides.exists(fullExtendString))
      {
        clsToCreate = scriptClassOverrides.get(fullExtendString);

        if (clsToCreate == null)
        {
          _interp.error(EClassUnresolvedSuperclass(fullExtendString, 'WHY?'));
        }
      }
      #if POLYMOD_CPPIA
      else if (PolymodCppiaClassReference.hasCppiaClass(fullExtendString))
      {
        clsToCreate = PolymodCppiaClassReference.getCppiaClass(fullExtendString);

        if (clsToCreate == null)
        {
          _interp.error(EClassUnresolvedSuperclass(fullExtendString, 'no loaded compiled script provides it'));
        }
      }
      #end
      else if (_c.imports.exists(extendString))
      {
        clsToCreate = _c.imports.get(extendString).cls;

        if (clsToCreate == null)
        {
          _interp.error(EClassUnresolvedSuperclass(extendString, 'target class blacklisted'));
        }
      }
      else
      {
        _interp.error(EClassUnresolvedSuperclass(extendString, 'missing import'));
      }

      superClass = Type.createInstance(clsToCreate, args);
    }
  }

  private function validateClassFields():Void
  {
    for (f in _c.fields)
    {
      switch (f.kind)
      {
        case KVar(v):
          if (!f.access.contains(AStatic) && superHasField(f.name))
          {
            // Throw an error if the script class has an instance field with the same name as one from the super class.
            throw 'Redefinition of variable "${f.name}" from superclass not allowed.';
          }
        case KFunction(fn):
          #if POLYMOD_STRICT_SYNTAX
          if (f.access.contains(AOverride) && !superHasField(f.name))
          {
            // Throw an error if a function is declared overwritten but isn't overriding anything.
            throw "Field " + f.name + " is declared 'override' but doesn't override any field.";
          }
          else if (!f.access.contains(AOverride) && superHasField(f.name))
          {
            var superClassPackage:String = '';
            if (superClass is PolymodScriptClass)
            {
              superClassPackage = Util.getFullClassName((cast superClass : PolymodScriptClass)._c);
            }
            else
            {
              // TODO: Fetch entire package name?
              superClassPackage = Util.getTypeNameOf(superClass);
            }

            // Throw an error if a function is overriden but doesn't have the override accessor.
            throw "Field " + f.name + " should be declared with 'override' since it is inherited from superclass " + superClassPackage + '.';
          }
          else if (f.access.contains(AOverride) && superClass == null)
          {
            // Throw an error if the override accessor is used with no super class.
            throw "Invalid modifier: override on field" + f.name + " of class that has no parent.";
          }
          #end
        default:
      }
    }
  }

  public static function reportError(err:Expr.Error, ?className:String, ?fnName:String):Void
  {
    var errLine:String = #if hscriptPos '${err.line}' #else "???" #end;
    var message:String = switch (#if hscriptPos err.e #else err #end)
    {
      case ECustom(msg):
        'An unknown error occurred: $msg';
      default:
        Printer.errorToString(err, false);
    }

    className ??= '???';
    fnName ??= '(anonymous)';

    Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Error while executing function ${className}.${fnName}()#${errLine}: ' + '\n' + message, SCRIPT_RUNTIME);
  }

  public function callFunction(fnName:String, ?args:Array<Dynamic>):Null<Dynamic>
  {
    var field = findField(fnName);
    var fn = (field != null) ? findFunction(fnName, true) : null;

    if (fn != null)
    {
      // previousValues is used to restore variables after they are shadowed in the local scope.
      var previousValues:Map<String, Dynamic> = [];

      // Copy the locals and store them for later.
      var localsCopy:Map<String, {r:Dynamic, ?isfinal:Null<Bool>}> = _interp.locals.copy();

      var r:Dynamic = null;
      try
      {
        previousValues = _interp.setFunctionValues(fn, args, fnName);
        r = _interp.executeEx(fn.expr);
      }
      catch (err:Expr.Error)
      {
        reportError(err, fullyQualifiedName, fnName);
        // A script error occurred while executing the script function.
        // Purge the function from the cache so it is not called again.
        purgeFunction(fnName);
      }

      // This NEEDS to run regardless of the function succeeding or not, or else the previous values might be lost.
      for (a in fn.args)
      {
        if (previousValues.exists(a.name))
        {
          _interp.variables.set(a.name, previousValues.get(a.name));
        }
        else
        {
          // We don't want to remove variables that were defined as globals in the script.
          if (this.findVar(a.name, true) != null) continue;

          _interp.variables.remove(a.name);
        }
      }

      // Restore the locals.
      _interp.locals = localsCopy;

      return r;
    }
    else
    {
      if (fnName == 'toString')
      {
        return toString();
      }

      var _super:Dynamic = superClass;
      while (Std.isOfType(_super, PolymodScriptClass))
      {
        if (_super.hasScriptFunction(fnName))
        {
          return _super.callFunction(fnName, args);
        }
        _super = _super.superClass;
      }

      var fn = findSuperFunction(fnName);
      if (fn == null)
      {
        Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
          'Error while calling function ${fnName}(): EInvalidAccess' + '\n' +
          'Script does not have function "${fnName}"! Define it or call the correct script function or superclass function.',
          SCRIPT_RUNTIME);
        return null;
      }

      var fixedArgs = (args?.length == 0) ? args : args.map((a) -> {
        if (Std.isOfType(a, PolymodScriptClass))
        {
          return cast(a, PolymodScriptClass).superClass;
        }
        else
        {
          return a;
        }
      });

      // OVERRIDE CHANGE: Make sure to call the `scriptCallSuper` function instead of using Reflect to prevent recursion.
      return this.superClass.scriptCallSuper(fnName, fixedArgs);
    }
  }

  /**
   * Checks if the class has a script function with the given name.
   * This is useful for checking whether the game should simply call the superclass function directly.
   * @param name The name of the function to check.
   * @return `true` if the class has a script function with the given name, `false` otherwise.
   */
  public function hasScriptFunction(name:String):Bool
  {
    var field = findField(name);
    var fn = (field != null) ? findFunction(name, true) : null;

    return fn != null;
  }

  /**
   * Checks if the class has a script function with the given name,
   * which has been purged due to an uncaught exception when it was previously called.
   * @param name
   * @return Bool
   */
  public function hasPurgedScriptFunction(name:String):Bool
  {
    if (hasScriptFunction(name)) return false;

    // Make sure to ignore the cache, which the function was purged from.
    final USE_CACHE:Bool = false;
    var field = findField(name);
    if (field == null) return false;

    var fn = findFunction(name, USE_CACHE);
    return fn != null;
  }

  private var _c:ClassDecl;
  private var _interp:Interp;

  public var superClass:Dynamic = null;
  public var topASC(default, null):Null<PolymodAbstractScriptClass>;

  public var fullyQualifiedName(get, null):String;

  private inline function get_fullyQualifiedName():String
  {
    return Util.getFullClassName(_c);
  }

  /**
   * Search for a function field with the given name. Excludes variables and static functions.
   * @param name The name of the function to search for.
   * @param cacheOnly If false, scan the full list of fields.
   *                  If true, ignore uncached fields.
   * @param excludeStatic If true, exclude static fields.
   */
  private function findFunction(name:String, cacheOnly:Bool = true, excludeStatic:Bool = true):Null<FunctionDecl>
  {
    if (_cachedFunctionDecls != null && _cachedFunctionDecls.exists(name))
    {
      return _cachedFunctionDecls.get(name);
    }
    if (cacheOnly) return null;

    var fn = findField(name);
    if (fn == null) return null;
    switch (fn.kind)
    {
      case KFunction(func):
        if (excludeStatic && fn.access.contains(AStatic)) return null;
        _cachedFunctionDecls.set(name, func);
        return func;
      default:
        return null;
    }
  }

  /**
   * Search for a function field on the superclass with the given name.
   */
  private function findSuperFunction(name:String):Null<Dynamic>
  {
    if (_cachedSuperFunctionDecls != null && _cachedSuperFunctionDecls.exists(name))
    {
      return _cachedSuperFunctionDecls.get(name);
    }

    if (Std.isOfType(superClass, PolymodScriptClass))
    {
      var func = Reflect.field(superClass, name);
      if (func == null) return null;

      _cachedSuperFunctionDecls.set(name, func);
      return func;
    }

    var func = Reflect.field(superClass, name);
    if (func == null) return null;
    _cachedSuperFunctionDecls.set(name, func);
    return func;
  }

  /**
   * Remove a function from the cache.
   *
   * If a scripted function throws an exception that isn't caught,
   * it will be purged so it can't be invoked again until the script is reloaded.
   * This prevents broken functions from causing errors every frame and locking the game, for example.
   *
   * @param name The name of the function to remove from the cache.
   */
  private function purgeFunction(name:String):Void
  {
    if (_cachedFunctionDecls != null)
    {
      _cachedFunctionDecls.remove(name);
      _cachedFunctionCalls.remove(name);
    }
  }

  /**
   * Search for a variable field with the given name. Excludes functions and static variables.
   * @param name The name of the variable to search for.
   * @param cacheOnly If false, scan the full list of fields.
   *                  If true, ignore uncached fields.
   * @param excludeStatic If true, exclude static fields.
   */
  private function findVar(name:String, cacheOnly:Bool = false, excludeStatic:Bool = true):Null<VarDecl>
  {
    if (_cachedVarDecls != null && _cachedVarDecls.exists(name))
    {
      return _cachedVarDecls.get(name);
    }
    if (cacheOnly) return null;

    for (f in _c.fields)
    {
      if (f.name == name)
      {
        switch (f.kind)
        {
          case KVar(v):
            if (excludeStatic && f.access.contains(AStatic)) return null;
            _cachedVarDecls?.set(name, v);
            return v;
          case _:
        }
      }
    }

    return null;
  }

  /**
   * Search for a field (function OR variable) with the given name.
   * @param name The name of the field to search for.
   * @param cacheOnly If false, scan the full list of fields.
   *                  If true, ignore uncached fields.
   */
  private function findField(name:String, cacheOnly:Bool = true):Null<FieldDecl>
  {
    if (_cachedFieldDecls != null && _cachedFieldDecls.exists(name))
    {
      return _cachedFieldDecls.get(name);
    }
    if (cacheOnly) return null;

    for (f in _c.fields)
    {
      if (f.name == name)
      {
        return f;
      }
    }
    return null;
  }

  public function listFunctions():Map<String, FunctionDecl>
  {
    return _cachedFunctionDecls;
  }

  private final _constructorArgs:Array<Dynamic>;

  private var _cachedFieldDecls:Map<String, FieldDecl> = [];
  private var _cachedSuperFunctionDecls:Map<String, Dynamic> = [];
  private var _cachedFunctionDecls:Map<String, FunctionDecl> = [];
  private var _cachedFunctionCalls:Map<String, Dynamic> = [];
  private var _cachedVarDecls:Map<String, VarDecl> = [];
  private var _cachedUsingFunctions:Map<String, Array<Dynamic>->Dynamic> = [];

  private function buildCaches()
  {
    _cachedFieldDecls.clear();
    _cachedSuperFunctionDecls.clear();
    _cachedFunctionDecls.clear();
    _cachedFunctionCalls.clear();
    _cachedVarDecls.clear();
    _cachedUsingFunctions.clear();

    buildExtensionFunctionCache(_c, _cachedUsingFunctions);

    for (f in _c.fields)
    {
      if (_cachedFieldDecls.exists(f.name))
      {
        throw 'Duplicate field name "${f.name}" in class "${_c.name}"';
      }

      _cachedFieldDecls.set(f.name, f);
      switch (f.kind)
      {
        case KFunction(fn):
          _cachedFunctionDecls.set(f.name, fn);
          _cachedFunctionCalls.set(f.name, Reflect.makeVarArgs(function(args:Array<Dynamic>)
          {
            return callFunction(f.name, args);
          }));
        case KVar(v):
          _cachedVarDecls.set(f.name, v);
          if (v.expr != null)
          {
            var varValue = this._interp.exprWithType(v.expr, v.type);
            this._interp.variables.set(f.name, varValue);
          }
        default:
          throw 'Unknown field kind: ${f.kind}';
      }
    }
  }

  // Acts like a HScriptedClass override would but for classes not extending anything
  public function toString():String
  {
    if (hasScriptFunction('toString'))
    {
      return callFunction('toString', []);
    }
    else if (Std.isOfType(superClass, PolymodScriptClass))
    {
      var spr = cast(superClass, PolymodScriptClass);
      // We call it only if it's a script override
      if (spr.hasScriptFunction('toString'))
      {
        return spr.callFunction('toString', []);
      }
    }

    return 'PolymodScriptClass<$fullyQualifiedName>';
  }

  /**
   * Populates a string map with functions from a 'using' class.
   * @param clsDecl The class to retrieve functions from.
   * @param usingCache The map to populate.
   */
  public static function buildExtensionFunctionCache(clsDecl:ClassDecl, usingCache:Map<String, Array<Dynamic>->Dynamic>):Void
  {
    for (_ => u in clsDecl.usings)
    {
      if (u.cls != null)
      {
        var fields = Type.getClassFields(u.cls);
        if (fields.length == 0) continue;

        for (fld in fields)
        {
          var field:Dynamic = Reflect.getProperty(u.cls, fld);
          if (!Reflect.isFunction(field)) continue;

          var func:Dynamic = function(params:Array<Dynamic>)
          {
            return Reflect.callMethod(u.cls, field, params);
          };

          usingCache.set(fld, func);
        }
      }
      else if (Interp._scriptClassDescriptors.exists(u.fullPath))
      {
        var scriptDecl = Interp._scriptClassDescriptors.get(u.fullPath);

        for (fld in scriptDecl.staticFields)
        {
          if (!fld.access.contains(AStatic)) continue;

          switch (fld.kind)
          {
            case KFunction(f):
              var fldName = fld.name;

              var func:Dynamic = function(params:Array<Dynamic>) {
                return callScriptClassStaticFunction(u.fullPath, fldName, params);
              };

              usingCache.set(fldName, func);

            default:
              //do nothing
          }
        }
      }
    }
  }
}
