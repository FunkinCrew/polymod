package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import haxe.macro.Type.ClassType;
import polymod.util.MacroUtil;
#end
import haxe.rtti.Meta;

using StringTools;

/**
 * Provides a macro which, after types are generated, populates a list of classes which extend `polymod.hscript.HScriptedClass`.
 * We have to do weird shenanigans to make the data accessible at runtime though.
 */
class PolymodScriptClassMacro
{
  /**
   * Returns a `Map<String, Class<Dynamic>>` which maps superclass paths to scripted classes.
     * So `class ScriptedStage extends Stage implements HScriptable` will be `"Stage" -> ScriptedStage`
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

  public static macro function listAbstractImpls():ExprOf<Map<String, Class<Dynamic>>>
  {
    if (!onGenerateCallbackRegistered)
    {
      onGenerateCallbackRegistered = true;
      haxe.macro.Context.onGenerate(onGenerate);
    }

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchAbstractImpls();
  }

  public static macro function listAbstractStatics():ExprOf<Map<String, Class<Dynamic>>>
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

    return macro polymod.hscript._internal.PolymodScriptClassMacro.fetchAbstractStatics();
  }

  #if macro
  static var onGenerateCallbackRegistered:Bool = false;
  static var onAfterTypingCallbackRegistered:Bool = false;

  static function onGenerate(allTypes:Array<haxe.macro.Type>)
  {
    // Reset these, since onGenerate persists across multiple builds.
    var hscriptedClassType:ClassType = MacroUtil.getClassType('polymod.hscript.HScriptedClass');

    var hscriptedClassEntries:Array<Expr> = [];
    var abstractImplEntries:Array<Expr> = [];
    var abstractStaticEntries:Array<Expr> = [];

    for (type in allTypes)
    {
      switch (type)
      {
        case TInst(t, _params):
          // Check classes to see if they implement `HScriptedClass`, and do additional processing.

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
            var entryData = [
              macro $v{superClassPath},
              macro $v{classPath}
            ];
            hscriptedClassEntries.push(macro $a{entryData});
          }

        case TAbstract(t, _params):
          // Perform additional processing on abstracts classes to ensure they can be accessed at runtime.

          var abstractPath:String = t.toString();
          if (abstractPath == 'flixel.util.FlxColor')
          {
            var abstractType = t.get();
            var abstractImpl = abstractType.impl.get();
            var abstractImplPath:String = abstractType.impl?.toString() ?? '';

            if (abstractImpl == null) {
              // If the abstract doesn't have an implementation, it's usually an extern or something, so we always want to ignore it.
              continue;
            }

            var entryData = [macro $v{abstractPath}, macro $v{abstractImplPath}];

            abstractImplEntries.push(macro $a{entryData});

					for (field in abstractImpl.statics.get()) {
						switch (field.type) {
							case TAbstract(_, _):
								//
							case TType(_, _):
								//
								default:
								continue;
						}

						var key:String = '${abstractImplPath}.${field.name}';

						if (!staticFieldToClass.exists(key)) {
							continue;
						}

						var staticEntryData = [
							macro $v{key},
							macro $v{staticFieldToClass[key]},
						];

              abstractStaticEntries.push(macro $a{staticEntryData});
            }

            // Try to apply RTTI?
            abstractType.meta.add(':rtti', [], Context.currentPos());
            abstractImpl.meta.add(':rtti', [], Context.currentPos());
          }
        default:
          continue;
      }
    }

    Context.info('PolymodScriptClassMacro: Registering ${hscriptedClassEntries.length} HScriptedClasses, ${abstractImplEntries.length} abstract impls, ${abstractStaticEntries.length} abstract statics', Context.currentPos());

    var polymodScriptClassClassType:ClassType = MacroUtil.getClassType('polymod.hscript._internal.PolymodScriptClassMacro');
    polymodScriptClassClassType.meta.remove('hscriptedClasses');
    polymodScriptClassClassType.meta.add('hscriptedClasses', hscriptedClassEntries, Context.currentPos());
    polymodScriptClassClassType.meta.remove('abstractImpls');
    polymodScriptClassClassType.meta.add('abstractImpls', abstractImplEntries, Context.currentPos());
    polymodScriptClassClassType.meta.remove('abstractStatics');
    polymodScriptClassClassType.meta.add('abstractStatics', abstractStaticEntries, Context.currentPos());
  }

  static var iteration:Int = 0;
  static var staticFieldToClass:Map<String, String> = [];

  static function onAfterTyping(types:Array<ModuleType>):Void
  {
    var fields:Array<Field> = [];

    for (type in types)
    {
      switch (type)
      {
        case TAbstract(a):
          var abstractPath = a.toString();
          var abstractType = a.get();

					if (abstractPath != 'flixel.util.FlxColor') {
						continue;
					}

					if (abstractType.impl == null) {
						// Only a few classes end up here, generally ones that are implemented directly in code.
						// Includes like StdTypes.Float, StdTypes.Dynamic, StdTypes.Void, cpp.Int16, cpp.SizeT, Class, Enum
						continue;
					} else {
	          var abstractImplPath = abstractType.impl.toString();
	          var abstractImplType = abstractType.impl.get();
						var abstractImplStatics = abstractImplType.statics.get();
						var underlyingType = abstractType.type;

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

									if (canGet) {
										var fieldName:String = '${abstractImplPath.replace('.', '_')}_${field.name}';

		                fields.push(
                  {
		                    pos: Context.currentPos(),
		                    name: fieldName,
		                    access: [Access.APublic, Access.AStatic],
		                    kind: FProp(canGet ? 'get' : 'never', canSet ? 'set' : 'never', (macro: Dynamic), null)
		                  });

										var fieldExpr:Expr = null;
										try {
											// when this fails, this should mean that we are dealing with an enum abstract
											// so we need to handle it differently
											var fullPath:String = '${abstractType.module}.${abstractType.name}';
											Context.getType(fullPath);
											fieldExpr = Context.parse('${fullPath}.${field.name}', Context.currentPos());
										} catch (_) {
											fieldExpr = Context.getTypedExpr(field.expr());
										}

										if (canGet) {
											fields.push({
												pos: Context.currentPos(),
												name: 'get_${fieldName}',
												access: [Access.APublic, Access.AStatic],
												kind: FFun({
													args: [],
													ret: null,
													expr: macro {
														@:privateAccess
														return ${fieldExpr};
													}
												})
											});
										}

										if (canSet) {
											fields.push({
												pos: Context.currentPos(),
												name: 'set_${fieldName}',
												access: [Access.APublic, Access.AStatic],
												kind: FFun({
													args: [{name: 'value'}],
													ret: null,
													expr: macro {
														@:privateAccess
														return ${fieldExpr} = value;
													}
												})
											});
										}

		                staticFieldToClass.set('${abstractImplPath}.${field.name}', 'polymod.hscript._internal.AbstractStaticMembers_${iteration}');
									}

	              default:
	                continue;
							}
            }
          }
        default:
          continue;
      }
    }

    if (fields.length == 0)
    {
      return;
    }

    Context.defineType(
      {
        pos: Context.currentPos(),
        pack: ['polymod', 'hscript', '_internal'],
        name: 'AbstractStaticMembers_${iteration}',
        kind: TDClass(null, [], false, false, false),
        fields: fields
      });

    iteration++;
  }
  #end

  public static function fetchHScriptedClasses():Map<String, Class<Dynamic>>
  {
    var metaData = Meta.getType(PolymodScriptClassMacro);

    if (metaData.hscriptedClasses != null)
    {
      // trace('Got hscriptedClasses: ' + metaData.hscriptedClasses);

      var result:Map<String, Class<Dynamic>> = [];

      // Each element is formatted as `[superClassPath, classPath]`.

      for (element in metaData.hscriptedClasses)
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

  public static function fetchAbstractImpls():Map<String, Class<Dynamic>>
  {
    var metaData = Meta.getType(PolymodScriptClassMacro);

    if (metaData.abstractImpls != null)
    {
      var result:Map<String, Class<Dynamic>> = [];

      // Each element is formatted as `[abstractPath, abstractImplPath]`.

      for (element in metaData.abstractImpls)
      {
        if (element.length != 2)
        {
          throw 'Malformed element in abstractImpls: ' + element;
        }

        var abstractPath:String = element[0];
        var abstractImplPath:String = element[1];
        #if js
        var abstractImplType:Class<Dynamic> = resolveClass(abstractPath);

        if (abstractImplType == null)
        {
          throw 'Could not resolve ' + abstractPath;
        }
        #else
        // trace('Resolving using native method');
        var abstractImplType:Class<Dynamic> = cast Type.resolveClass(abstractImplPath);

        if (abstractImplType == null)
        {
          // trace('POLYMOD ABSTRACTS: Could not resolve $abstractImplPath');
        }
        #end

        result.set(abstractPath, abstractImplType);
      }

      return result;
    }
    else
    {
      throw 'No abstractImpls found in PolymodScriptClassMacro!';
    }
  }

  public static function fetchAbstractStatics():Map<String, Class<Dynamic>>
  {
    var metaData = Meta.getType(PolymodScriptClassMacro);

    if (metaData.abstractStatics != null)
    {
      var result:Map<String, Class<Dynamic>> = [];

      // Each element is formatted as `[abstractPathImpl.fieldName, reflectClass]`.

      for (element in metaData.abstractStatics)
      {
        if (element.length != 2)
        {
          throw 'Malformed element in abstractStatics: ' + element;
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
      throw 'No abstractStatics found in PolymodScriptClassMacro!';
    }
  }

  #if js
  static var PACKAGE_NAME_INVALID = ~/[^.a-zA-Z0-9]/;

  // Fucked up workaround, volatile and could break at any moment.
  static function resolveClass(clsName:String):Class<Dynamic>
  {
    // Sanitize just in case someone tries to exploit this.
    var sanitizedName = PACKAGE_NAME_INVALID.replace(clsName, '');
    var parsedName = StringTools.replace(sanitizedName, '.', '_');
    return js.Syntax.code('eval({0})', parsedName);
  }
  #end
}
