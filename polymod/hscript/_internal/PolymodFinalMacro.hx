package polymod.hscript._internal;

import haxe.macro.Type.ClassField;
#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end

@:nullSafety
class PolymodFinalMacro
{
  /**
   * The name for the Haxe resource that stores Generation Metadata.
   */
  static inline final METADATA_RESOURCE_NAME:String = 'PolymodFinalMacro_METADATA';

  #if !macro
  private static var _allFinals:Null<Map<String, Array<String>>> = null;
  private static var _allPrivateProperties:Null<Map<String, Array<String>>> = null;
  private static var _allPrivatesFields:Null<Map<String, Array<String>>> = null;

  public static function getAllFinals():Map<String, Array<String>>
  {
    if (_allFinals == null) _allFinals = PolymodFinalMacro.fetchAllFinals();
    return _allFinals;
  }

  public static function getAllPrivateProperties():Map<String, Array<String>>
  {
    if (_allPrivateProperties == null) _allPrivateProperties = PolymodFinalMacro.fetchAllPrivateProperties();
    return _allPrivateProperties;
  }

  public static function getAllPrivateFields():Map<String, Array<String>>
  {
    #if POLYMOD_STRICT_SYNTAX
    if (_allPrivatesFields == null) _allPrivatesFields = PolymodFinalMacro.fetchAllPrivateFields();
    #else
    // Disable private fields.
    if (_allPrivatesFields == null) _allPrivatesFields = [];
    #end

    return _allPrivatesFields;
  }

  public static inline function getFinals(fullPath:String):Array<String> {
    return getAllFinals().get(fullPath) ?? [];
  }

  public static inline function getFinalsOf(obj:Dynamic):Array<String> {
    while (Std.isOfType(obj, PolymodScriptClass)) obj = obj.superClass;

    var typeName:String = polymod.util.Util.getTypeNameOf(obj);
    var result = getFinals(typeName);
    return result;
  }

  public static inline function getPrivateProperties(fullPath:String):Array<String> {
    return getAllPrivateProperties().get(fullPath) ?? [];
  }

  public static inline function getPrivatePropertiesOf(obj:Dynamic):Array<String> {
    while (Std.isOfType(obj, PolymodScriptClass)) obj = obj.superClass;

    var typeName:String = polymod.util.Util.getTypeNameOf(obj);
    var result = getPrivateProperties(typeName);
    return result;
  }

  public static inline function getPrivateFields(fullPath:String):Array<String> {
    return getAllPrivateFields().get(fullPath) ?? [];
  }

  public static inline function getPrivateFieldsOf(obj:Dynamic):Array<String> {
    while (Std.isOfType(obj, PolymodScriptClass)) obj = obj.superClass;

    var typeName:String = polymod.util.Util.getTypeNameOf(obj);
    var result = getPrivateFields(typeName);
    return result;
  }
  #end

  static var calledBefore:Bool = false;

  public static macro function locateAllFinals():Void
  {
    Context.onAfterTyping((types) -> {
      if (calledBefore) return;

      var startTime:Float = Sys.time();

      var allFinals:Array<Dynamic> = [];
      var allPrivateProperties:Array<Dynamic> = [];
      var allPrivateFields:Array<Dynamic> = [];

      for (type in types)
      {
        switch (type)
        {
          case TClassDecl(t):
            var classType:ClassType = t.get();
            var classPath:String = t.toString();
            if (classType.isInterface) continue;

            var fields:Array<ClassField> = listAllFieldsOfClassType(classType);

            var finals:Array<String> = listFinalFields(fields);
            if (finals.length > 0)
            {
              var entryData:Array<Dynamic> = [classPath, finals];
              allFinals.push(entryData);
            }

            var privatesProperties:Array<String> = listPrivateProperties(fields);
            if (privatesProperties.length > 0)
            {
              var entryData:Array<Dynamic> = [classPath, privatesProperties];
              allPrivateProperties.push(entryData);
            }

            #if POLYMOD_STRICT_SYNTAX
            var privateFields:Array<String> = listPrivateFields(fields);
            if (privateFields.length > 0)
            {
              var entryData:Array<Dynamic> = [classPath, privateFields];
              allPrivateFields.push(entryData);
            }
            #end
          default:
            continue;
        }
      }

      var metadataHXSF = haxe.Serializer.run({
        finals: allFinals,
        privateProperties: allPrivateProperties,
        privateFields: allPrivateFields,
      });
      Context.addResource(METADATA_RESOURCE_NAME, haxe.io.Bytes.ofString(metadataHXSF));

      var endTime:Float = Sys.time();

      var duration:Float = endTime - startTime;

      Context.info('PolymodFinalMacro: '
        + 'Detected ${allFinals.length} classes with final variables, '
        + '${allPrivateProperties.length} classes with (default,null) properties, '
        + '${allPrivateFields.length} classes with private variables '
        + 'in ${duration} sec.',
        Context.currentPos());

      calledBefore = true;
    });
  }

  #if macro
  static function listAllFieldsOfClassType(classType:Null<ClassType>):Array<ClassField>
  {
    if (classType == null) return [];

    static final classCache:Map<String, Array<ClassField>> = [];
    final clsFullName:String = classType.pack.concat([classType.name]).join('.');
    if (classCache.exists(clsFullName))
    {
      return classCache.get(clsFullName);
    }

    var result:Array<ClassField> = [];

    result = result.concat(classType.fields.get());
    result = result.concat(classType.statics.get());
    result = result.concat(listAllFieldsOfClassType(classType.superClass?.t.get()));

    classCache.set(clsFullName, result);

    return result;
  }

  static function listFinalFields(fields:Array<ClassField>):Array<String>
  {
    var result:Array<String> = [];

    for (field in fields)
    {
      // Add final variables.
      if (field.isFinal)
      {
        result.push(field.name);
        // Move on to the next one; a final can't have accessors like a property does.
        continue;
      }

      // Add properties with `never` accessors.
      switch (field.kind)
      {
        case FVar(_, AccNever):
          result.push(field.name);
        default: // Do nothing
      }
    }

    return result;
  }

  static function listPrivateProperties(fields:Array<ClassField>):Array<String>
  {
    var result:Array<String> = [];

    for (field in fields)
    {
      // Add properties with `null` accessors.
      switch (field.kind)
      {
        case FVar(_, AccNo):
          result.push(field.name);
        default: // Do nothing
      }
    }

    return result;
  }

  static function listPrivateFields(fields:Array<ClassField>):Array<String>
  {
    var result:Array<String> = [];
    for (field in fields)
    {
      if (field.isPublic) continue;
      result.push(field.name);
    }
    return result;
  }
  #end

  public static function fetchAllFinals():Map<String, Array<String>>
  {
    var metaData = fetchMetadata();
    var finals:Array<Dynamic> = cast metaData.finals;

    if (finals != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in finals)
      {
        if (element.length != 2) throw 'Malformed element in finals: ' + element;

        var classPath:String = element[0];
        var finals:Array<String> = element[1];

        result.set(classPath, finals);
      }

      return result;
    }
    else
    {
      throw 'No finals found in PolymodFinalMacro';
    }
  }

  public static function fetchAllPrivateProperties():Map<String, Array<String>>
  {
    var metaData = fetchMetadata();
    var privates:Array<Dynamic> = cast metaData.privateProperties;

    if (privates != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in privates)
      {
        if (element.length != 2) throw 'Malformed element in privates properties: ' + element;

        var classPath:String = element[0];
        var privates:Array<String> = element[1];

        result.set(classPath, privates);
      }

      return result;
    }
    else
    {
      throw 'No private properties found in PolymodFinalMacro';
    }
  }

  public static function fetchAllPrivateFields():Map<String, Array<String>>
  {
    var metaData = fetchMetadata();
    var privateVars:Array<Dynamic> = cast metaData.privateFields;

    if (privateVars != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in privateVars)
      {
        if (element.length != 2) throw 'Malformed element in private fields: ' + element;

        var classPath:String = element[0];
        var privates:Array<String> = element[1];

        result.set(classPath, privates);
      }
      return result;
    }
    else
    {
      throw 'No private fields found in PolymodFinalMacro';
    }
  }

  static var _metadata:Dynamic = null;
  static function fetchMetadata():Dynamic
  {
    if (_metadata != null) return _metadata;

    var metaDataHXSF:String = haxe.Resource.getString(METADATA_RESOURCE_NAME);
    _metadata = haxe.Unserializer.run(metaDataHXSF);
    return _metadata;
  }
}
