package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
#end
import polymod.util.Util;

@:nullSafety
class PolymodFinalMacro
{
  /**
   * The name for the Haxe resource that stores Generation Metadata.
   */
  static inline final METADATA_RESOURCE_NAME:String = 'PolymodFinalMacro_METADATA';

  public static inline function getFinals(fullPath:String):Array<String> {
    return getAllFinals().get(fullPath) ?? [];
  }

  public static inline function getFinalsOf(obj:Dynamic):Array<String> {
    while (Std.isOfType(obj, PolymodScriptClass)) obj = obj.superClass;

    var typeName:String = Util.getTypeNameOf(obj);
    var result = getFinals(typeName);
    return result;
  }

  public static inline function getPrivateProperties(fullPath:String):Array<String> {
    return getAllPrivateProperties().get(fullPath) ?? [];
  }

  public static inline function getPrivatePropertiesOf(obj:Dynamic):Array<String> {
    while (Std.isOfType(obj, PolymodScriptClass)) obj = obj.superClass;

    var typeName:String = Util.getTypeNameOf(obj);
    var result = getPrivateProperties(typeName);
    return result;
  }

  private static var _allFinals:Null<Map<String, Array<String>>> = null;

  public static function getAllFinals():Map<String, Array<String>>
  {
    if (_allFinals == null) _allFinals = PolymodFinalMacro.fetchAllFinals();
    return _allFinals;
  }

  private static var _allPrivates:Null<Map<String, Array<String>>> = null;

  public static function getAllPrivateProperties():Map<String, Array<String>>
  {
    if (_allPrivates == null) _allPrivates = PolymodFinalMacro.fetchAllPrivateProperties();
    return _allPrivates;
  }

  public static macro function locateAllFinals():Void
  {
    Context.onAfterTyping((types) -> {
      if (calledBefore) return;

      var startTime:Float = Sys.time();

      var allFinals:Array<Dynamic> = [];
      var allPrivates:Array<Dynamic> = [];

      for (type in types)
      {
        switch (type)
        {
          case TClassDecl(t):
            var classType:ClassType = t.get();
            var classPath:String = t.toString();
            if (classType.isInterface) continue;

            var finals:Array<String> = listFinalsOfClassType(classType);
            if (finals.length > 0) {
              var entryData:Array<Dynamic> = [classPath, finals];
              allFinals.push(entryData);
            }

            var privates:Array<String> = listPrivatesOfClassType(classType);
            if (privates.length > 0) {
              var entryData:Array<Dynamic> = [classPath, privates];
              allPrivates.push(entryData);
            }

          default:
            continue;
        }
      }

      var metadataHXSF = haxe.Serializer.run({
        finals: allFinals,
        privates: allPrivates
      });
      Context.addResource(METADATA_RESOURCE_NAME, haxe.io.Bytes.ofString(metadataHXSF));

      var endTime:Float = Sys.time();

      var duration:Float = endTime - startTime;

      Context.info('PolymodFinalMacro: '
        + 'Detected ${allFinals.length} classes with final variables, '
        + '${allPrivates.length} classes with (default,null) properties '
        + 'in ${duration} sec.',
        Context.currentPos());

      calledBefore = true;
    });
  }

  #if macro
  static function listFinalsOfClassType(classType:Null<ClassType>):Array<String> {
    if (classType == null) return [];

    var result:Array<String> = [];

    for (field in classType.fields.get())
    {
      // Add final variables.
      if (field.isFinal) result.push(field.name);

      // Add properties with `never` accessors.
      switch (field.kind) {
        case FVar(read, write):
          switch (write) {
            case AccNever:
              result.push(field.name);
            default: // Do nothing
          }
        default: // Do nothing
      }
    }

    for (field in classType.statics.get())
    {
      // Add final variables.
      if (field.isFinal) result.push(field.name);

      // Add properties with `never` accessors.
      switch (field.kind) {
        case FVar(read, write):
          switch (write) {
            case AccNever:
              result.push(field.name);
            default: // Do nothing
          }
        default: // Do nothing
      }
    }

    return result.concat(listFinalsOfClassType(classType?.superClass?.t?.get()));
  }

  static function listPrivatesOfClassType(classType:Null<ClassType>):Array<String> {
    if (classType == null) return [];

    var result:Array<String> = [];

    for (field in classType.fields.get()) {
      // Add properties with `null` accessors.
      switch (field.kind) {
        case FVar(read, write):
          switch (write) {
            case AccNo:
              result.push(field.name);
            default: // Do nothing
          }
        default: // Do nothing
      }
    }

    for (field in classType.statics.get())
    {
      // Add properties with `null` accessors.
      switch (field.kind) {
        case FVar(read, write):
          switch (write) {
            case AccNo:
              result.push(field.name);
            default: // Do nothing
          }
        default: // Do nothing
      }
    }

    return result.concat(listPrivatesOfClassType(classType?.superClass?.t?.get()));
  }

  static var calledBefore:Bool = false;
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
    var privates:Array<Dynamic> = cast metaData.privates;

    if (privates != null)
    {
      var result:Map<String, Array<String>> = [];

      for (element in privates)
      {
        if (element.length != 2) throw 'Malformed element in privates: ' + element;

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

  static var _metadata:Dynamic = null;
  static function fetchMetadata():Dynamic
  {
    if (_metadata != null) return _metadata;

    var metaDataHXSF:String = haxe.Resource.getString(METADATA_RESOURCE_NAME);
    _metadata = haxe.Unserializer.run(metaDataHXSF);
    return _metadata;
  }
}
