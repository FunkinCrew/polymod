package polymod.hscript._internal;

import polymod.hscript._internal.PolymodCppiaScanner.CppiaScan;

/**
 * A class reference backed by a compiled cppia class instead of a parsed script.
 */
class PolymodCppiaClassReference extends PolymodStaticClassReference
{
  public static final MANIFEST_CLASS:String = 'PolymodCppiaManifest';

  static final registry:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

  /**
   * What each file gave us, kept across reloads.
   */
  static final loadedModules:Map<String, LoadedCppiaModule> = new Map<String, LoadedCppiaModule>();

  /**
   * Every class name any compiled script has ever provided, kept for the life of the process.
   */
  static final everProvided:Map<String, Bool> = new Map<String, Bool>();

  /**
   * Every class a compiled script declared, including the ones it did not put in its manifest.
   */
  static final declared:Map<String, Class<Dynamic>> = new Map<String, Class<Dynamic>>();

  /**
   * Whether this class name came out of a compiled script rather than the game.
   */
  public static function isScriptClass(clsName:String):Bool
  {
    return declared.exists(clsName);
  }

  /**
   * The class a compiled script declared under this name, if any.
   */
  public static function resolveScriptClass(clsName:String):Null<Class<Dynamic>>
  {
    return declared.get(clsName);
  }

  /**
   * The version a cppia must be stamped with to be accepted.
   */
  public static var expectedVersion:Null<String> = null;

  static var reportedMismatch:Bool = false;

  public static function clearCppiaClasses():Void
  {
    // Only the active registry is dropped. What was loaded stays known, because it cannot be undone.
    registry.clear();
    reportedMismatch = false;
  }

  /**
   * Signature of a file's contents, used to tell a reload of the same bytes from a rebuilt mod.
   */
  static function signatureOf(data:haxe.io.Bytes):String
  {
    return '${data.length}:${haxe.crypto.Crc32.make(data)}:${PolymodScriptClass.blacklistGeneration}';
  }

  public static function hasCppiaClass(clsName:String):Bool
  {
    return registry.exists(clsName);
  }

  /**
   * The class a loaded compiled script is providing under this name, if any.
   */
  public static function getCppiaClass(clsName:String):Null<Class<Dynamic>>
  {
    return registry.get(clsName);
  }

  /**
   * Whether an hscript class can extend this one.
   */
  public static function isExtendableCppiaClass(clsName:String):Bool
  {
    var cls:Null<Class<Dynamic>> = registry.get(clsName);
    if (cls == null) return false;

    try
    {
      return Reflect.field(cls, '_isHScriptedClass') == true;
    }
    catch (_:Dynamic)
    {
      return false;
    }
  }

  /**
   * Whether this name belongs to a compiled script that is no longer loaded.
   *
   * The class object still exists, because hxcpp cannot unload it, but nothing should resolve to it.
   */
  public static function isInactiveCppiaClass(clsName:String):Bool
  {
    return everProvided.exists(clsName) && !registry.exists(clsName);
  }

  /**
   * Free the code of every module whose classes are no longer registered.
   */
  public static function unloadInactiveModules():Void
  {
    #if (hxcpp && POLYMOD_CPPIA)
    // Snapshot the keys, the loop removes entries.
    for (path in [for (key in loadedModules.keys()) key])
    {
      var loaded:LoadedCppiaModule = loadedModules.get(path);

      var active:Array<String> = loaded.names.filter(name -> registry.exists(name));

      if (active.length == loaded.names.length) continue;

      if (active.length > 0)
      {
        // Another script re-registered part of this one's classes.
        Polymod.warning(SCRIPT_PARSE_FAILED,
          'Compiled script "$path" is partly still in use (${active.join(", ")} of ${loaded.names.join(", ")}), so it cannot be unloaded. Two scripts are probably providing the same class.',
          SCRIPT_RUNTIME);
        continue;
      }

      if (!unloadModule(loaded, path)) continue;

      loadedModules.remove(path);
      trace('[cppia] unloaded "$path", its mod is no longer enabled.');
    }
    #end
  }

  /**
   * Free one module's code, reporting rather than throwing if the native side refuses.
   * @return Whether the module was actually unloaded.
   */
  static function unloadModule(loaded:LoadedCppiaModule, path:String):Bool
  {
    try
    {
      loaded.unload();
      return true;
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
        'Failed to unload compiled script "$path": $e. Its code stays in memory until the game restarts.', SCRIPT_RUNTIME);
      return false;
    }
  }

  public static function listCppiaClasses():Array<String>
  {
    return [for (name in registry.keys()) name];
  }

  /**
   * A cppia class is a real class, so we can check its superclasses to see if it extends the given class path.
   */
  public static function listCppiaClassesExtending(clsPath:String):Array<String>
  {
    var result:Array<String> = [];

    for (name => cls in registry)
    {
      var superCls = Type.getSuperClass(cls);
      while (superCls != null)
      {
        if (Type.getClassName(superCls) == clsPath)
        {
          result.push(name);
          break;
        }
        superCls = Type.getSuperClass(superCls);
      }
    }

    return result;
  }

  /**
   * The names a compiled script may not reference.
   */
  static function deniedNames():Map<String, Bool>
  {
    var result:Map<String, Bool> = new Map<String, Bool>();

    for (name => alias in PolymodScriptClass.importOverrides)
    {
      if (alias == null || Type.getClassName(alias) != name) result.set(name, true);
    }
    result.remove(Type.getClassName(polymod.hscript.PolymodScriptBridge));

    return result;
  }

  /**
   * Which denied name a type resolves to, if any.
   */
  static function deniedNameFor(type:String, denied:Map<String, Bool>):Null<String>
  {
    if (denied.exists(type)) return type;

    var parts:Array<String> = type.split('.');
    for (i in 1...parts.length)
    {
      var suffix:String = parts.slice(i).join('.');
      if (denied.exists(suffix)) return suffix;
    }

    return null;
  }

  /**
   * Check a compiled script against the blacklist before any of it runs.
   * @return The denied names it references, or null if the file could not be read at all.
   */
  static function scanDenied(types:Array<String>):Array<String>
  {
    var denied:Map<String, Bool> = deniedNames();
    var found:Array<String> = [];

    for (type in types)
    {
      var name:Null<String> = deniedNameFor(type, denied);
      if (name != null && !found.contains(name)) found.push(name);
    }

    return found;
  }

  /**
   * The hxcpp builtins a compiled script may call, mapped to the only argument count that is safe.
   */
  static final ALLOWED_GLOBALS:Map<String, Int> = [
    '__hxcpp_memory_get_byte' => 2,
    '__hxcpp_memory_set_byte' => 3,
    '__hxcpp_memory_get_i32' => 2,
    '__hxcpp_memory_set_i32' => 3,
    '__hxcpp_memory_get_ui32' => 2,
    '__hxcpp_memory_set_ui32' => 3,
    '__hxcpp_memory_get_i16' => 2,
    '__hxcpp_memory_set_i16' => 3,
    '__hxcpp_memory_get_ui16' => 2,
    '__hxcpp_memory_set_ui16' => 3,
    '__hxcpp_memory_get_float' => 2,
    '__hxcpp_memory_set_float' => 3,
    '__hxcpp_memory_get_double' => 2,
    '__hxcpp_memory_set_double' => 3,
    '__hxcpp_thread_create' => 1,
    '__hxcpp_thread_send' => 2
  ];

  /**
   * Turn a name out of a compiled script's type table into one the game can compare.
   */
  static function normalizeTypeName(raw:String):String
  {
    if (raw == null) return '';

    var name:String = StringTools.replace(raw, '::', '.');

    while (name.length > 0 && name.charAt(0) == '.')
      name = name.substr(1);

    // A parameterised array is written with its element type, as `Array.String` and the like.
    if (StringTools.startsWith(name, 'Array.')) name = 'Array';

    return name;
  }

  /**
   * The name a type table entry refers to, empty if it is Dynamic or out of range.
   */
  static function nameOfType(typeId:Int, scan:CppiaScan):String
  {
    if (typeId < 0 || typeId >= scan.types.length) return '';
    return normalizeTypeName(scan.types[typeId]);
  }

  /**
   * Every class name a value of this type could be blacklisted under.
   */
  static function ancestryOf(typeId:Int, scan:CppiaScan, cache:Map<Int, Array<String>>):Array<String>
  {
    var cached:Null<Array<String>> = cache.get(typeId);
    if (cached != null) return cached;

    var result:Array<String> = [];
    var seen:Map<Int, Bool> = new Map<Int, Bool>();
    var id:Int = typeId;

    var depth:Int = 0;

    // Classes this module declares itself, which nothing can resolve until it has booted.
    while (scan.ancestry.exists(id) && !seen.exists(id) && depth++ < 64)
    {
      seen.set(id, true);

      var related:Array<Int> = scan.ancestry.get(id);
      result.push(nameOfType(id, scan));

      for (i in 1...related.length)
        result.push(nameOfType(related[i], scan));

      id = related[0];
      if (id <= 0)
      {
        cache.set(typeId, result);
        return result;
      }
    }

    // Past that, the rest of the chain is game classes, which can be resolved the usual way.
    var name:String = nameOfType(id, scan);

    if (name.length == 0)
    {
      cache.set(typeId, result);
      return result;
    }

    result.push(name);

    var cls:Null<Class<Dynamic>> = null;
    try
    {
      cls = Type.resolveClass(name);
    }
    catch (_:Dynamic) {}

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

      var resolved:Null<String> = Type.getClassName(cls);
      if (resolved == null || result.contains(resolved)) break;

      result.push(resolved);
    }

    cache.set(typeId, result);
    return result;
  }

  /**
   * Where in the mod's own source a reference came from, if the script was built with that in it.
   */
  static function siteOf(fileId:Int, line:Int, scan:CppiaScan):String
  {
    if (fileId <= 0 || fileId >= scan.strings.length) return '';

    var file:String = scan.strings[fileId];
    if (file.length == 0) return '';

    return ' ($file:$line)';
  }

  /**
   * Check the fields a compiled script names against the blacklist, before any of it runs.
   * @return The fields it may not use, described for a person to read.
   */
  static function scanDeniedFields(scan:CppiaScan):Array<String>
  {
    var found:Array<String> = [];
    var cache:Map<Int, Array<String>> = new Map<Int, Array<String>>();

    var i:Int = 0;

    while (i + 1 < scan.fieldRefs.length)
    {
      var classId:Int = scan.fieldRefs[i];
      var fieldId:Int = scan.fieldRefs[i + 1];
      var fileId:Int = scan.fieldSites[i];
      var line:Int = scan.fieldSites[i + 1];
      i += 2;

      if (fieldId < 0 || fieldId >= scan.strings.length) continue;

      var field:String = scan.strings[fieldId];
      if (field.length == 0) continue;

      var where:String = siteOf(fileId, line, scan);

      var owner:String = nameOfType(classId, scan);

      // A receiver whose type was not known hides which class the field belongs to, so only the names singled out as
      // unreachable by any route apply here. That is written either as the empty type or as a type literally named
      // Dynamic, depending on how the value lost its type, so both mean the same thing.
      if (owner.length == 0 || owner == 'Dynamic')
      {
        if (PolymodScriptClass.blacklistedDynamicFieldNames.exists(field))
        {
          var entry:String = '$field$where';
          if (!found.contains(entry)) found.push(entry);
        }

        continue;
      }

      for (name in ancestryOf(classId, scan, cache))
      {
        if (name.length == 0) continue;
        if (!PolymodScriptClass.isBlacklistedFieldExact(name, field)) continue;

        var entry:String = '$name.$field$where';
        if (!found.contains(entry)) found.push(entry);
        break;
      }
    }

    return found;
  }

  /**
   * Check the hxcpp builtins a compiled script calls, before any of it runs.
   * @return The calls it may not make, described for a person to read.
   */
  static function scanDeniedGlobals(scan:CppiaScan):Array<String>
  {
    var found:Array<String> = [];

    var i:Int = 0;

    while (i + 1 < scan.globalCalls.length)
    {
      var nameId:Int = scan.globalCalls[i];
      var argCount:Int = scan.globalCalls[i + 1];
      i += 2;

      if (nameId < 0 || nameId >= scan.strings.length) continue;

      var name:String = scan.strings[nameId];
      if (!StringTools.startsWith(name, '__hxcpp_')) continue;

      if (ALLOWED_GLOBALS.exists(name) && ALLOWED_GLOBALS.get(name) == argCount) continue;

      var entry:String = '$name with $argCount argument(s)';
      if (!found.contains(entry)) found.push(entry);
    }

    return found;
  }

  public static function tryBuildCppia(clsName:String):Null<PolymodCppiaClassReference>
  {
    var cls = registry.get(clsName);
    if (cls == null) return null;
    return new PolymodCppiaClassReference(clsName, cls);
  }

  /**
   * Load a compiled script and register the classes it declares.
   * @return The names of the classes registered, empty if the module was refused.
   */
  public static function registerModule(data:haxe.io.Bytes, path:String):Array<String>
  {
    #if (hxcpp && POLYMOD_CPPIA)
    if (data == null || data.length == 0)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" is empty, rebuild it with the current build command.', SCRIPT_RUNTIME);
      return [];
    }

    var signature:String = signatureOf(data);
    var previous:LoadedCppiaModule = loadedModules.get(path);

    if (previous != null && previous.signature == signature)
    {
      // Same bytes as last time. Put the classes we already have back in the registry.
      for (i in 0...previous.names.length)
      {
        registry.set(previous.names[i], previous.refs[i]);
        everProvided.set(previous.names[i], true);
      }

      trace('[cppia] reused "$path" providing ${previous.names.join(", ")}, unchanged since it was loaded.');
      return previous.names.copy();
    }

    if (previous != null)
    {
      Polymod.info(SCRIPT_PARSE_START, 'Compiled script "$path" changed since it was loaded, it will be replaced.', SCRIPT_RUNTIME);
    }

    var scan:CppiaScan = null;

    try
    {
      scan = PolymodCppiaScanner.scan(data, PolymodScriptClass.blacklistedFieldNames(), true);
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Could not read the header of compiled script "$path": $e', SCRIPT_RUNTIME);
      return [];
    }

    var types:Array<String> = scan.types;

    // Cannot be CPPIB, which is the binary form of CPPIA. Harder to check.
    if (scan.binary)
    {
      Polymod.error(SCRIPT_PARSE_FAILED,
        'Compiled script "$path" is in the binary cppia format, which cannot be checked against the blacklist. Rebuild it with the current build command.',
        SCRIPT_RUNTIME);
      return [];
    }

    if (scan.suspect)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" is malformed and could not be checked. It will not be loaded.', SCRIPT_RUNTIME);
      return [];
    }

    if (scan.unknownTokens.length > 0)
    {
      Polymod.warning(SCRIPT_PARSE_FAILED,
        'Compiled script "$path" contains instructions this version does not know about: ${scan.unknownTokens.join(", ")}. It was still checked, but polymod may need updating for this version of hxcpp.',
        SCRIPT_RUNTIME);
    }

    var denied:Array<String> = scanDenied(types);

    if (denied.length > 0)
    {
      Polymod.error(SCRIPT_PARSE_FAILED,
        'Compiled script "$path" references ${denied.length == 1 ? "a class" : "classes"} that mods are not allowed to use: ${denied.join(", ")}. It will not be loaded.',
        SCRIPT_RUNTIME);
      return [];
    }

    var deniedFields:Array<String> = scanDeniedFields(scan);

    if (deniedFields.length > 0)
    {
      Polymod.error(SCRIPT_PARSE_FAILED,
        'Compiled script "$path" uses ${deniedFields.length == 1 ? "a class field" : "class fields"} that mods are not allowed to use: ${deniedFields.join(", ")}. It will not be loaded.',
        SCRIPT_RUNTIME);
      return [];
    }

    var deniedGlobals:Array<String> = scanDeniedGlobals(scan);

    if (deniedGlobals.length > 0)
    {
      Polymod.error(SCRIPT_PARSE_FAILED,
        'Compiled script "$path" uses raw memory access that mods are not allowed to use: ${deniedGlobals.join(", ")}. It will not be loaded.',
        SCRIPT_RUNTIME);
      return [];
    }

    var module:cpp.cppia.Module = null;

    trace('[cppia] reading "$path" (${data.length} bytes)...');

    try
    {
      module = cpp.cppia.Module.fromData(data.getData());
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Failed to read compiled script "$path": $e', SCRIPT_RUNTIME);
      return [];
    }

    if (module == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" produced no module, it is probably corrupt.', SCRIPT_RUNTIME);
      return [];
    }

    trace('[cppia] booting "$path"...');

    try
    {
      module.boot();
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Failed to boot compiled script "$path": $e', SCRIPT_RUNTIME);
      return [];
    }

    var moduleClasses:Array<String> = [];

    for (type in types)
    {
      var cls:Null<Class<Dynamic>> = null;

      try
      {
        cls = module.resolveClass(type);
      }
      catch (e:Dynamic) {}

      if (cls == null) continue;

      declared.set(type, cls);
      moduleClasses.push(type);
    }

    var manifest:Class<Dynamic> = null;
    try
    {
      manifest = module.resolveClass(MANIFEST_CLASS);
    }
    catch (e:Dynamic)
    {
      manifest = null;
    }

    if (manifest == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" has no $MANIFEST_CLASS, rebuild it with the current build command.', SCRIPT_RUNTIME);
      return [];
    }

    var stamp:String = Std.string(Reflect.field(manifest, 'gameVersion'));
    if (expectedVersion != null && stamp != expectedVersion)
    {
      if (!reportedMismatch)
      {
        reportedMismatch = true;
        Polymod.error(SCRIPT_PARSE_FAILED,
          'Compiled script "$path" was built for game version "$stamp" but this game is "$expectedVersion". It will not be loaded, so the mod needs rebuilding.',
          SCRIPT_RUNTIME);
      }
      return [];
    }

    var declared:Array<Class<Dynamic>> = cast Reflect.field(manifest, 'classRefs');
    if (declared == null)
    {
      Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" has no classRefs, rebuild it with the current build command.', SCRIPT_RUNTIME);
      return [];
    }

    var expectedNames:Array<String> = cast Reflect.field(manifest, 'classes');

    var registered:Array<String> = [];
    var registeredRefs:Array<Class<Dynamic>> = [];
    for (i in 0...declared.length)
    {
      var cls = declared[i];
      var expectedName:String = (expectedNames != null && i < expectedNames.length) ? expectedNames[i] : 'entry $i';

      if (cls == null)
      {
        Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" declares "$expectedName" but the module did not provide it, rebuild it with the current build command.',
          SCRIPT_RUNTIME);
        continue;
      }

      var name = Type.getClassName(cls);
      if (name == null)
      {
        Polymod.error(SCRIPT_PARSE_FAILED, 'Compiled script "$path" provided an unnamed class for "$expectedName".', SCRIPT_RUNTIME);
        continue;
      }

      if (registry.exists(name))
      {
        Polymod.warning(SCRIPT_PARSE_FAILED, 'Compiled class "$name" was already registered, "$path" is replacing it.', SCRIPT_RUNTIME);
      }

      registry.set(name, cls);
      everProvided.set(name, true);
      registered.push(name);
      registeredRefs.push(cls);
    }

    if (previous != null)
    {
      unloadModule(previous, path);
      loadedModules.remove(path);
    }

    loadedModules.set(path, new LoadedCppiaModule(signature, registered, registeredRefs, module));

    trace('[cppia] loaded "$path" providing ${registered.join(", ")}, declaring ${moduleClasses.join(", ")}');

    return registered;
    #else
    return [];
    #end
  }

  final clsName:String;
  final cppiaClass:Class<Dynamic>;

  public function new(clsName:String, cppiaClass:Class<Dynamic>)
  {
    super();
    this.clsName = clsName;
    this.cppiaClass = cppiaClass;
  }

  override public function instantiate(?args:Array<Dynamic>, constructor:Bool = true):Null<Dynamic>
  {
    if (cppiaClass == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) is not loaded, so it cannot be constructed.', SCRIPT_RUNTIME);
      return null;
    }

    var callArgs:Array<Dynamic> = args ?? [];

    try
    {
      var result = Type.createInstance(cppiaClass, callArgs);
      if (result == null)
      {
        Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Constructing compiled class ($clsName) with ${callArgs.length} argument(s) returned null.', SCRIPT_RUNTIME);
      }
      return result;
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct compiled class ($clsName) with ${callArgs.length} argument(s): $e', SCRIPT_RUNTIME);
      return null;
    }
  }

  override public function buildASC(?args:Array<Dynamic>):PolymodAbstractScriptClass
  {
    Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) has no script class to build.', SCRIPT_RUNTIME);
    return null;
  }

  override public function callFunction(funcName:String, ?args:Array<Dynamic>):Dynamic
  {
    if (cppiaClass == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) is not loaded, so "$funcName" cannot be called.', SCRIPT_RUNTIME);
      return null;
    }

    if (PolymodScriptClass.isBlacklistedField(clsName, funcName))
    {
      Polymod.error(SCRIPTED_CLASS_BLACKLISTED_FIELD, 'Class field ${clsName}.${funcName} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
      return null;
    }

    var fn:Dynamic = Reflect.field(cppiaClass, funcName);
    if (fn == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) has no static function "$funcName".', SCRIPT_RUNTIME);
      return null;
    }

    if (!Reflect.isFunction(fn))
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) field "$funcName" is not a function.', SCRIPT_RUNTIME);
      return null;
    }

    // A script calling into compiled code must not take the whole game down on a bad call.
    try
    {
      return Reflect.callMethod(cppiaClass, fn, args ?? []);
    }
    catch (e:Dynamic)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) threw calling "$funcName": $e', SCRIPT_RUNTIME);
      return null;
    }
  }

  override public function getField(fieldName:String):Dynamic
  {
    if (cppiaClass == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) is not loaded, so "$fieldName" cannot be read.', SCRIPT_RUNTIME);
      return null;
    }

    if (PolymodScriptClass.isBlacklistedField(clsName, fieldName))
    {
      Polymod.error(SCRIPTED_CLASS_BLACKLISTED_FIELD, 'Class field ${clsName}.${fieldName} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
      return null;
    }

    return Reflect.field(cppiaClass, fieldName);
  }

  override public function setField(fieldName:String, fieldValue:Dynamic):Dynamic
  {
    if (cppiaClass == null)
    {
      Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Compiled class ($clsName) is not loaded, so "$fieldName" cannot be written.', SCRIPT_RUNTIME);
      return null;
    }

    if (PolymodScriptClass.isBlacklistedField(clsName, fieldName))
    {
      Polymod.error(SCRIPTED_CLASS_BLACKLISTED_FIELD, 'Class field ${clsName}.${fieldName} is blacklisted and cannot be used in scripts.', SCRIPT_RUNTIME);
      return null;
    }

    Reflect.setField(cppiaClass, fieldName, fieldValue);
    return fieldValue;
  }

  override public function getFullyQualifiedName():String
  {
    return clsName;
  }

  override public function toString():String
  {
    return 'PolymodCppiaClassReference($clsName)';
  }
}

@:headerInclude("hx/Scriptable.h")
private class LoadedCppiaModule
{
  public final signature:String;
  public final names:Array<String>;
  public final refs:Array<Class<Dynamic>>;

  #if (hxcpp && POLYMOD_CPPIA)
  var module:Null<cpp.cppia.Module>;
  #end

  public function new(signature:String, names:Array<String>, refs:Array<Class<Dynamic>>, module:Dynamic)
  {
    this.signature = signature;
    this.names = names;
    this.refs = refs;
    #if (hxcpp && POLYMOD_CPPIA)
    this.module = module;
    #end
  }

  /**
   * Free the module's code.
   */
  public function unload():Void
  {
    #if (hxcpp && POLYMOD_CPPIA)
    if (module == null) return;

    var m = module;
    module = null;
    untyped __cpp__("{0}->unload()", m);
    #end
  }
}
