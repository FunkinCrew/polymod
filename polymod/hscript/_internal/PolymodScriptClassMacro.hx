package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.ClassType;
import polymod.util.MacroUtil;
#end

using StringTools;

/**
 * Provides a macro which, after types are generated, populates a list of classes which extend `polymod.hscript.HScriptedClass`.
 * We have to do weird shenanigans to make the data accessible at runtime though.
 */
class PolymodScriptClassMacro
{
  /**
   * The name for the Haxe resource that stores Generation Metadata.
   */
  static inline final METADATA_RESOURCE_NAME:String = 'PolymodScriptClassMacro_METADATA';

  /**
   * Returns a `Map<String, Class<Dynamic>>` which maps superclass paths to scripted classes.
   * So `class ScriptedStage extends Stage implements HScriptable` will be `"Stage" -> ScriptedStage`
   *
   * @return An expression containing a map of superclasses to their scripted classes
   */
  public static macro function listHScriptedClasses():ExprOf<Map<String, Class<Dynamic>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchHScriptedClasses();
  }

  /**
   * @return An expression containing a map of abstract classes to their implementations
   */
  public static macro function listAbstractImpls():ExprOf<Map<String, AbstractImplEntry>>
  {
    if (!onAfterTypingCallbackRegistered)
    {
      onAfterTypingCallbackRegistered = true;
      haxe.macro.Context.onAfterTyping(onAfterTyping);
    }

    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchAbstractImpls();
  }

  /**
   * @return An expression containing a map of each typedef name to
   *  the underlying class type.
   */
  public static macro function listTypedefs():ExprOf<Map<String, Class<Dynamic>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchTypedefs();
  }

  #if macro
  static var onGenerateCallbackRegistered:Bool = false;
  static var onAfterTypingCallbackRegistered:Bool = false;

  static function onGenerate(allTypes:Array<haxe.macro.Type>)
  {
    // Reset these, since onGenerate persists across multiple builds.
    var hscriptedClassType:ClassType = MacroUtil.getClassType('polymod.hscript.HScriptedClass');

    var hscriptedClassEntries:Array<Array<String>> = [];
    var abstractImplEntries:Array<Array<String>> = [];
    var typedefEntries:Array<Array<String>> = [];

    var startTime:Float = Sys.time();

    for (type in allTypes)
    {
      switch (type)
      {
        case TInst(t, _params):
          // Parse classes to check if they are `HScriptedClass` implementations, for processing later.

          var classType:ClassType = t.get();
          var classPath:String = '${classType.pack.concat([classType.name]).join(".")}';

          if (classType.isInterface)
          {
            // Ignore interfaces.
          }
          else if (MacroUtil.implementsInterface(classType, hscriptedClassType))
          {
            var superClass:Null<ClassType> = classType.superClass != null ? classType.superClass.t.get() : null;

            if (superClass == null) throw 'No superclass for ' + classPath;

            var superClassPath:String = '${superClass.pack.concat([superClass.name]).join(".")}';
            var entryData = [superClassPath, classPath];
            hscriptedClassEntries.push(entryData);
          }

        case TType(t, _params):
          var typedefType:DefType = t.get();
          var typedefPath:String = t.toString();
          var typedefTarget:Type = Context.followWithAbstracts(type);

          switch (typedefTarget)
          {
            case TAnonymous(_):
              // Ignore typedefs to anonymous structures.
              continue;
            case TDynamic(_):
              // Ignore typedefs to Dynamic.
              continue;
            case TFun(_args, _ret):
              // Ignore typedefs to functions.
              continue;

            case TAbstract(t, _params):
              var targetPath:String = t.toString();

              var entryData = [typedefPath, targetPath];

              typedefEntries.push(entryData);

            case TEnum(t, _params):
              var targetEnum:EnumType = t.get();
              var targetEnumPath:String = '${targetEnum.pack.concat([targetEnum.name]).join(".")}';

              var entryData = [typedefPath, targetEnumPath];

              typedefEntries.push(entryData);

            case TInst(t, _params):
              var targetClass:ClassType = t.get();
              var targetClassPath:String = '${targetClass.pack.concat([targetClass.name]).join(".")}';

              var entryData = [typedefPath, targetClassPath];

              typedefEntries.push(entryData);

            default:
              // Unknown typedef target type?
              trace('TYPEDEF: ${typedefPath} -> ${typedefTarget}');
          }

        case TAbstract(t, _params):
          // Perform additional processing on abstracts classes to ensure they can be accessed at runtime.

          var abstractPath:String = t.toString();
          var abstractType = t.get();
          var abstractImpl = abstractType.impl?.get();

          if (abstractImpl == null)
          {
            // If the abstract doesn't have an implementation, it's usually an extern or something, so we always want to ignore it.
            continue;
          }

          var abstractImplPath:String = abstractType.impl?.toString() ?? '';

          var polymodImplPath:String = 'polymod.hscript._internal._abstract.${abstractPath}_PolymodImpl_';
          var hasPolymodImpl:Bool = false;

          try
          {
            var _ = Context.getType(polymodImplPath);
            hasPolymodImpl = true;
          }
          catch (e) {}

          var entryData = [
            abstractPath,
            abstractImplPath,
            hasPolymodImpl ? polymodImplPath : null
          ];

          abstractImplEntries.push(entryData);
        default:
          continue;
      }
    }

    var metaData = {
      hscriptedClasses: hscriptedClassEntries,
      abstractImpls: abstractImplEntries,
      typedefs: typedefEntries
    };

    var metaDataHXSF = haxe.Serializer.run(metaData);
    Context.addResource(METADATA_RESOURCE_NAME, haxe.io.Bytes.ofString(metaDataHXSF));

    var endTime:Float = Sys.time();

    var duration:Float = endTime - startTime;

    Context.info('PolymodScriptClassMacro: '
      + 'Registered ${hscriptedClassEntries.length} HScriptedClasses, '
      + '${abstractImplEntries.length} abstract impls, '
      + '${typedefEntries.length} typedefs '
      + 'in ${duration} sec.',
      Context.currentPos());
  }

  static function onAfterTyping(types:Array<ModuleType>):Void
  {
    var startTime:Float = Sys.time();

    var count:Int = 0;

    for (type in types)
    {
      var fields:Array<Field> = [];

      switch (type)
      {
        case TAbstract(a):
          var abstractPath = a.toString();
          var abstractType = a.get();

          if (abstractType.impl == null)
          {
            // Only a few classes end up here, generally ones that are implemented directly in code.
            // Includes like StdTypes.Float, StdTypes.Dynamic, StdTypes.Void, cpp.Int16, cpp.SizeT, Class, Enum
            continue;
          }
          else
          {
            var abstractImplPath = abstractType.impl.toString();
            var abstractImplType = abstractType.impl.get();
            var abstractImplStatics:Array<ClassField> = abstractImplType.statics.get();

            var isAbstractImplExtern = abstractImplType.isExtern;
            if (isAbstractImplExtern) {
              // TODO: abstract externs tend to be problematic and cause lots of build errors,
              // so we just skip them for now. If you can find a fix, feel free.
              continue;
            }

            for (field in abstractImplStatics)
            {
              switch (field.kind)
              {
                case FVar(read, write):
                  var canGet:Bool = read == AccInline || read == AccNormal;
                  if (read == AccCall)
                  {
                    var getter:Null<ClassField> = null;
                    for (f in abstractImplStatics)
                    {
                      if (f.name == 'get_${field.name}')
                      {
                        getter = f;
                        break;
                      }
                    }

                    if (getter == null)
                    {
                      throw 'Getter is null?';
                    }

                    switch (getter.type)
                    {
                      case TFun(args, _):
                        if (args.length != 0) continue;
                      default:
                        throw 'Getter has an unknown type?';
                    }

                    canGet = true;
                  }

                  var canSet:Bool = write == AccNormal;
                  if (write == AccCall)
                  {
                    var setter:Null<ClassField> = null;
                    for (f in abstractImplType.statics.get())
                    {
                      if (f.name == 'set_${field.name}')
                      {
                        setter = f;
                        break;
                      }
                    }

                    if (setter == null)
                    {
                      throw 'Setter is null?';
                    }

                    switch (setter.type)
                    {
                      case TFun(args, _):
                        if (args.length != 1) continue;
                      default:
                        throw 'Setter has an unknown type?';
                    }

                    canSet = true;
                  }

                  if (canGet || canSet)
                  {
                    fields.push(
                      {
                        pos: Context.currentPos(),
                        name: field.name,
                        access: [Access.APublic, Access.AStatic],
                        kind: FProp(canGet ? 'get' : 'never', canSet ? 'set' : 'never', (macro :Dynamic), null)
                      });

                    var fieldExpr:Expr = null;
                    try
                    {
                      // when this fails, this should mean that we are dealing with an enum abstract
                      // so we need to handle it differently
                      var fullPath:String = '${abstractType.module}.${abstractType.name}';
                      Context.getType(fullPath);
                      fieldExpr = Context.parse('${fullPath}.${field.name}', Context.currentPos());
                    }
                    catch (_)
                    {
                      fieldExpr = Context.getTypedExpr(field.expr());
                    }

                    if (canGet)
                    {
                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: 'get_${field.name}',
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [],
                              ret: null,
                              expr: macro
                              {@:privateAccess return ${fieldExpr};}
                            })
                        });
                    }

                    if (canSet)
                    {
                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: 'set_${field.name}',
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [
                                {name: 'value'}],
                              ret: null,
                              expr: macro
                              {@:privateAccess return ${fieldExpr} = value;}
                            })
                        });
                    }
                  }

                case FMethod(k):
                  if (k != MethInline) continue;
                  if (abstractPath.startsWith('cpp')) continue;
                  if (abstractPath.startsWith('hl')) continue;
                  if (abstractPath.startsWith('flixel.graphics.atlas.HashOrArray')) continue; // has to be ragebait
                  if (abstractType.isPrivate) continue;

                  switch (field.type)
                  {
                    case TFun(args, ret):
                      if (args.length == 0 || args[0].name != 'this') continue;

                      var fieldArgs = [for (a in args.slice(1)) {name: a.name, type: null}];

                      var absType = TPath(
                        {
                          pack: abstractType.pack,
                          name: abstractType.module.split('.').pop(),
                          sub: abstractType.name,
                          params: [for (_ in abstractType.params) TPType((macro :Dynamic))]
                        });

                      var isVoid = haxe.macro.TypeTools.toString(ret) == 'Void';
                      var callExprString = '${isVoid ? '' : 'returnValue = '}__typedThis.${field.name}(${[for (a in fieldArgs) a.name].join(', ')})';

                      fields.push(
                        {
                          pos: Context.currentPos(),
                          name: field.name,
                          access: [Access.APublic, Access.AStatic],
                          kind: FFun(
                            {
                              args: [
                                {name: '__interp', type: (macro :polymod.hscript._internal.Interp)},
                                {name: '__expr', type: (macro :polymod.hscript._internal.Expr)},
                                {name: '__this', type: (macro :Dynamic)}
                              ].concat(fieldArgs),
                              ret: (macro :Dynamic),
                              expr: macro
                              {
                                var __typedThis = (__this : $absType); // we do this instead of typing __this in the parameter because of haxe.Rest edge case
                                var returnValue:Dynamic = null;
                                @:privateAccess ${Context.parse(callExprString, Context.currentPos())};
                                @:privateAccess __interp.assignValue(__expr, __typedThis, true);
                                return returnValue;
                              }
                            }),
                          // dont generate warnings for this function
                          meta: [
                            {
                              pos: Context.currentPos(),
                              params: [macro "-WAll"],
                              name: ':haxe.warning'
                            }
                          ]
                        });

                    default:
                      throw 'Method is not a function?';
                  }

                default:
                  continue;
              }
            }

            if (fields.length == 0) continue;

            Context.defineType(
              {
                pos: Context.currentPos(),
                pack: ['polymod', 'hscript', '_internal', '_abstract'].concat(abstractType.pack),
                name: '${abstractType.name}_PolymodImpl_', // we need to give them a different name, because else types with an empty package will not work
                kind: TDClass(null, [], false, false, false),
                fields: fields
              }, 'polymod.hscript._internal.PolymodScriptClassMacro');

            count++;
          }
        default:
          continue;
      }
    }

    var endTime:Float = Sys.time();

    var duration:Float = endTime - startTime;

    if (count > 0)
    {
      Context.info('PolymodScriptClassMacro: Created ${count} custom abstract implementations in ${duration} sec.', Context.currentPos());
    }
  }
  #end

  public static function fetchHScriptedClasses():Map<String, Class<Dynamic>>
  {
    var metaData = fetchMetadata();

    if (metaData.hscriptedClasses != null)
    {
      var result:Map<String, Class<Dynamic>> = [];

      // Each element is formatted as `[superClassPath, classPath]`.

      var hscriptedClasses:Array<Array<String>> = cast metaData.hscriptedClasses;
      for (element in hscriptedClasses)
      {
        if (element.length != 2)
        {
          throw 'Malformed element in hscriptedClasses: ' + element;
        }

        var superClassPath:String = element[0];
        var classPath:String = element[1];
        var classType:Class<Dynamic> = cast Type.resolveClass(classPath);
        result.set(superClassPath, classType);
      }

      return result;
    }
    else
    {
      throw 'No hscriptedClasses found in PolymodScriptClassMacro!';
    }
  }

  public static function fetchAbstractImpls():Map<String, AbstractImplEntry>
  {
    var metaData = fetchMetadata();

    if (metaData.abstractImpls != null)
    {
      var result:Map<String, AbstractImplEntry> = [];

      // Each element is formatted as `[abstractPath, abstractImplPath, ?abstractPolymodImplPath]`.

      var abstractImpls:Array<Array<String>> = cast metaData.abstractImpls;
      for (element in abstractImpls)
      {
        if (element.length != 3)
        {
          throw 'Malformed element in abstractImpls: ' + element;
        }

        var abstractPath:String = element[0];
        var abstractImplPath:String = element[1];
        var abstractPolymodImplPath:Null<String> = element[2];
        #if js
        var abstractImplType:Null<Class<Dynamic>> = resolveClass(abstractPath);
        #else
        var abstractImplType:Null<Class<Dynamic>> = cast Type.resolveClass(abstractImplPath);
        #end

        if (abstractImplType == null)
        {
          // If the abstract type was found at compile time, but couldn't resolve at runtime,
          // it probably got optimized out.
          // We'll have to construct a PolymodStaticAbstractReference for it later.
        }

        var abstractPolymodImplType:Null<Class<Dynamic>> = null;

        if (abstractPolymodImplPath != null)
        {
          abstractPolymodImplType = cast Type.resolveClass(abstractPolymodImplPath);
        }

        result.set(abstractPath,
          {
            cls: abstractImplType,
            polymodCls: abstractPolymodImplType
          });
      }

      return result;
    }
    else
    {
      throw 'No abstractImpls found in PolymodScriptClassMacro!';
    }
  }

  public static function fetchTypedefs():Map<String, Class<Dynamic>>
  {
    var metaData = fetchMetadata();

    if (metaData.typedefs != null)
    {
      var result:Map<String, Class<Dynamic>> = [];

      var typedefs:Array<Array<String>> = cast metaData.typedefs;
      for (element in typedefs)
      {
        if (element.length != 2)
        {
          throw 'Malformed element in typedefs: ' + element;
        }

        var fieldPath:String = element[0];
        var reflectClassPath:String = element[1];
        var reflectClass:Class<Dynamic> = cast Type.resolveClass(reflectClassPath);

        result.set(fieldPath, reflectClass);
      }

      return result;
    }
    else
    {
      throw 'No typedefs found in PolymodScriptClassMacro!';
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

  #if js
  static var PACKAGE_NAME_INVALID = ~/[^.a-zA-Z0-9]/;

  // Fucked up workaround, volatile and could break at any moment.
  static function resolveClass(clsName:String):Class<Dynamic>
  {
    // Sanitize just in case someone tries to exploit this.
    var sanitizedName = PACKAGE_NAME_INVALID.replace(clsName, '');
    var parsedName = StringTools.replace(sanitizedName, '.', '_');
    try
    {
      return js.Syntax.code('eval({0})', parsedName);
    }
    catch (e)
    {
      return null;
    }
  }
  #end
}

typedef AbstractImplEntry =
{
  cls:Class<Dynamic>,
  polymodCls:Null<Class<Dynamic>>,
};
