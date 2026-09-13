package polymod.hscript._internal;

#if macro
import haxe.macro.Compiler;
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Type;
import Type as HaxeType;

using haxe.macro.Tools;
using StringTools;

/**
 * `PolymodBaseClassMacro` is responsible for adding fields to all classes to make the extendable.
 * Additionally, it makes the base functions named differently and creates new functions in their stead
 * to make them first pass through abstract script class, if it exists.
 */
@:access(haxe.macro.TypeTools)
class PolymodBaseClassMacro
{
  /**
   * A metadata that's added to the classes that have been run through this macro.
   * This tells the function that they shouldn't be checked again.
   */
  public static final PROCESS_FINISHED_META:String = ':hscriptBaseCreated';

  /**
   * A metadata a compiled script puts on one of its own classes to have these fields built for it.
   * That is what lets an hscript class extend a class a compiled script declares.
   */
  public static final CPPIA_EXTENDABLE_META:String = ':hscriptExtendable';

  /**
   * A list of package name prefixes for which this macro should not be executed.
   */
  public static final PACKAGE_FILTERS:Array<String> = ['polymod.', 'hxd.', 'hl.'];

  static function useBridge():Bool
  {
    return Context.defined('cppia');
  }

  public static function buildBaseClass():Array<Field>
  {
    var cls:ClassType = null;
    var pos:Position = Context.currentPos();

    try
    {
      cls = Context.getLocalClass().get();
    }
    catch (e)
    {
      // Building wasn't called from a class; skip.
      return null;
    }

    // Make sure the macro doesn't run twice on the class.
    if (cls.meta.has(PROCESS_FINISHED_META)) return null;
    cls.meta.add(PROCESS_FINISHED_META, [], pos);

    // Remove `inline` from function calls, since functions pointing towards `_asc` don't have a final return.
    var fields:Array<Field> = Context.getBuildFields().copy();
    removeInlinedFunctionCalls(fields);

    // Omit being able to extend some classes.
    if (cls.isInterface || cls.isAbstract || cls.isExtern || cls.isFinal) return fields;

    // Exclude classes that start with an underscore, as they indicate classes that were created through compilation from parameters.
    if (cls.name.startsWith('_') || (cls.pack.length > 0 && cls.pack[cls.pack.length - 1].startsWith('_'))) return fields;

    // Disallow generic classes, as they mess with this macro.
    if (!HaxeType.enumEq(cls.kind, KNormal)) return fields;

    // If a class has type parameters but without any constraints (default values), it wouldn't be possible to extend them on runtime.
    for (param in cls.params)
    {
      switch (param.t)
      {
        case TInst(_.get() => classType, params):
          switch (classType.kind)
          {
            case KTypeParameter(c) if (c.length == 0):
              return fields;
            default:
          }
        default:
      }
    }

    // Core api classes require type which can't be specified on runtime.
    if (cls.meta.has(':coreApi')) return fields;

    // Classes specified to act as anonymous structures shouldn't be extended.
    if (cls.meta.has(':structInit')) return fields;

    // :nativeGen makes the class get treated as an extern, so it shouldn't be extended.
    if (cls.meta.has(':nativeGen')) return fields;

    var fullClsName:String = formatClassString(cls);
    // Disallow extending certain classes.
    for (filter in PACKAGE_FILTERS)
    {
      if (fullClsName.indexOf(filter) == 0) return fields;
    }

    if (Context.defined('cppia') && !isHostClass(fullClsName) && !cls.meta.has(CPPIA_EXTENDABLE_META)) return fields;

    // Check if a class already has one of the fields needed for the scripts before attempting to build fields.
    // We only need to check (and add) instance fields if a class doesn't extend anything, considering extending classes inherit them.
    var neededStaticFields:Array<String> = [
      'scriptInit',
      'listScriptClasses',
      'scriptStaticCall',
      'scriptStaticGet',
      'scriptStaticSet',
      'scriptStaticHas',
      'scriptStaticHasFunc',
      '_isHScriptedClass'
    ];
    var neededInstFields:Array<String> = [
      '_asc',
      '_skipAscFrom',
      'scriptCallSuper',
      'scriptCall',
      'scriptGet',
      'scriptSet',
      'scriptHas'
    ];

    for (fld in fields)
    {
      if (fld.access.contains(AStatic) && neededStaticFields.contains(fld.name))
      {
        Context.info(
          'PolymodBaseClassMacro: Couldn\'t build hscript fields for the class $fullClsName since it already has the static field ${fld.name}.',
          pos
        );
        return fields;
      }
      else if (cls.superClass == null && neededInstFields.contains(fld.name))
      {
        Context.info(
          'PolymodBaseClassMacro: Couldn\'t build hscript fields for the class $fullClsName since it already has the instance field ${fld.name}.',
          pos
        );
        return fields;
      }
    }

    // Build the hscript needed fields.
    fields = fields.concat(buildBaseClassInstanceFields(cls));
    fields = fields.concat(buildBaseClassStaticFields(cls));

    // Override the functions now since the `_asc` field was generated.
    overrideBaseFunctions(cls, fields, neededInstFields);

    return fields;
  }

  /**
   * Overrides the provided functions of the class to point directly to `_asc`.
   * Overriding functions works by overriding the base function to first point to the script class and its subclasses if the function shouldn't be skipped.
   * @param cls     The class whose fields to use to check for things such as if they already have the `_asc` field.
   * @param fields  The fields to override.
   * @param exclude Which functions to exclude from being overriden.
   */
  static function overrideBaseFunctions(cls:ClassType, fields:Array<Field>, ?exclude:Array<String>):Void
  {
    // Skip overriding functions during `display` mode. This avoids issues with code completion.
    // We cannot check using an #if conditional because those are evaluated at parse time.
    if (Context.defined('display')) return;

    // Don't override anything if the class (or the superclass) doesn't have the _asc field.
    if (cls.findField('_asc') == null && ![for (f in fields) f.name].contains('_asc')) return;

    for (i in 0...fields.length)
    {
      // Exclude fields specified in the array.
      if (exclude != null && exclude.contains(fields[i].name)) continue;

      // Skip overriding functions which are Generics.
      // This is because this actually creates several different functions at compile time.
      // TODO: Can we somehow override these functions?
      if ([for (m in fields[i].meta ?? []) m.name].contains(':generic')) continue;

      // We need to skip overriding functions which are inline.
      // Normal Haxe classes can't override these functions anyway, so we can skip them.
      if (fields[i].access.contains(AInline)) continue;

      // Macro functions cannot be overriden on runtime so they should be excluded.
      if (fields[i].access.contains(AMacro)) continue;

      // Don't override static functions since `_asc` is an instance field.
      if (fields[i].access.contains(AStatic)) continue;

      // Don't override constructors since script classes are instantiated differently anyways.
      if (fields[i].name == 'new') continue;

      switch (fields[i].kind)
      {
        case FFun(f):
          if (f.expr == null) continue;

          var argExprs:Array<Expr> = [for (arg in f.args) macro $i{arg.name}];

          // Sometimes a function can have dectorators to indicate the return type, but for other cases we need to check
          // if the function itself returns something by looking at the expression itself.
          var doesReturnVoid:Bool = true;
          if (f.ret == null)
          {
            function findValidReturn(expr:Expr):Null<Expr>
            {
              return switch (expr?.expr)
              {
                case EReturn(e) if (e != null):
                  expr;
                case EIf(_, e1, e2):
                  findValidReturn(e1) ?? findValidReturn(e2); // It's possible for a function to end with `if/else`, each with a return.
                case EMeta(_, e):
                  findValidReturn(e);
                case EBlock(exprs) if (exprs?.length > 0):
                  exprs.filter((e) -> findValidReturn(e) != null)[0];
                case ESwitch(_, cases, ret):
                  findValidReturn(ret) ?? cases.filter((c) -> findValidReturn(c?.expr) != null)[0]?.expr;
                case ETry(expr, catches):
                  findValidReturn(expr) ?? catches.filter((c) -> findValidReturn(c?.expr) != null)[0]?.expr;
                default:
                  null;
              }
            }

            doesReturnVoid = (findValidReturn(f.expr) == null);
          }
          else
          {
            doesReturnVoid = (f.ret.toString() == 'Void');
          }

          var oldPos:haxe.macro.Expr.Position = f.expr.pos;
          f.expr = useBridge() ? (macro
            {
              if (_asc != null && !_skipAscFrom.contains($v{fields[i].name}))
              {
                var scriptCls:Dynamic = polymod.hscript.PolymodScriptBridge.findScript(_asc, $v{fields[i].name});
                if (scriptCls != null) $
                {
                  doesReturnVoid ? (macro
                    {
                      polymod.hscript.PolymodScriptBridge.callOn(scriptCls, $v{fields[i].name}, [$a{argExprs}]);
                      return;
                    }) : (macro return cast polymod.hscript.PolymodScriptBridge.callOn(scriptCls, $v{fields[i].name}, [$a{argExprs}]))
                }
              }

              // Fallback, call the original function.
              ${f.expr}
            }) : (macro
            {
              if (_asc != null && !_skipAscFrom.contains($v{fields[i].name}))
              {
                var cls:Dynamic = _asc;
                while (cls != null && cls is polymod.hscript._internal.PolymodScriptClass)
                {
                  var scriptCls = (cls : polymod.hscript._internal.PolymodScriptClass);
                  if (scriptCls.hasScriptFunction($v{fields[i].name})) $
                  {
                    doesReturnVoid ? (macro
                      {
                        scriptCls.callFunction($v{fields[i].name}, [$a{argExprs}]);
                        return;
                      }) : (macro return cast scriptCls.callFunction($v{fields[i].name}, [$a{argExprs}]))
                  }

                  cls = cls.superClass;
                }
              }

              // Fallback, call the original function.
              ${f.expr}
            });

          f.expr.pos = oldPos;

        default:
          // Do nothing.
      }
    }
  }

  /**
   * Builds the hscript instance fields for the class. Doesn't do anything if a class extends something.
   * @param cls    The class to build the instance fields for.
   * @return       The hscript instance fields.
   */
  static function buildBaseClassInstanceFields(cls:ClassType):Array<Field>
  {
    if (cls.superClass != null) return [];

    var buildPos = Context.currentPos();

    var ascField:Field = {
      name: '_asc',
      doc: 'The AbstractScriptClass instance which any variable or function calls are redirected to internally.',
      access: [APrivate], // Private instance variable
      meta: [
        {
          name: ':noCompletion',
          pos: buildPos,
        },
        {
          name: ':jignored',
          pos: buildPos
        }
      ],
      kind: FieldType.FVar(useBridge() ? (macro :Null<Dynamic>) : (macro :Null<polymod.hscript._internal.PolymodAbstractScriptClass>)),
      pos: buildPos,
    };

    var skipASCField:Field = {
      name: '_skipAscFrom',
      doc: 'An array of functions from which to skip passing down to the abstract script class. Used the best in combination with `scriptCallSuper`.',
      access: [APrivate], // Private instance variable
      meta: [
        {
          name: ':noCompletion',
          pos: buildPos
        },
        {
          name: ':jignored',
          pos: buildPos
        }
      ],
      kind: FieldType.FVar(macro :Array<String>, macro []),
      pos: buildPos,
    };

    var getField:Field = {
      name: 'scriptGet',
      doc: 'Retrieves the value of a local variable of a scripted class.',
      access: [APublic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [{
          name: 'varName',
          type: macro :String
        }],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.fieldRead(_asc, varName);
        }) : (macro
        {
          return _asc?.fieldRead(varName);
        }),
      }),
    };

    var setField:Field = {
      name: 'scriptSet',
      doc: 'Directly modifies the value of a local variable of a scripted class.',
      access: [APublic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'varName',
            type: macro :String
          },
          {
            name: 'varValue',
            type: macro :Dynamic,
            value: macro null
          }
        ],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.fieldWrite(_asc, varName, varValue);
        }) : (macro
        {
          return _asc?.fieldWrite(varName, varValue);
        }),
      })
    };

    var hasField:Field = {
      name: 'scriptHas',
      doc: 'Determines if a field of a scripted class exists or not.',
      access: [APublic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [{
          name: 'fieldName',
          type: macro :String
        }],
        ret: macro :Bool,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.fieldExists(_asc, fieldName);
        }) : (macro
        {
          return _asc?.fieldExists(fieldName) ?? false;
        }),
      }),
    };

    var callField:Field = {
      name: 'scriptCall',
      doc: 'Calls a function of the scripted class with the given name and arguments.',
      access: [APublic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'funcName',
            type: macro :String
          },
          {
            name: 'funcArgs',
            type: macro :Array<Dynamic>,
            opt: true
          }
        ],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.callFunction(_asc, funcName, funcArgs ?? []);
        }) : (macro
        {
          return _asc?.callFunction(funcName, funcArgs ?? []);
        }),
      }),
    };

    var callSuperField:Field = {
      name: 'scriptCallSuper',
      doc: 'Calls the super function directly, skipping the attached script.',
      access: [APublic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'funcName',
            type: macro :String
          },
          {
            name: 'funcArgs',
            type: macro :Array<Dynamic>,
            opt: true
          }
        ],
        ret: macro :Dynamic,
        expr: macro
        {
          _skipAscFrom.push(funcName);

          var output:Dynamic = Reflect.callMethod(this, Reflect.field(this, funcName), funcArgs ?? []);
          _skipAscFrom.remove(funcName);

          return output;
        },
      }),
    }

    return [
      ascField,
      skipASCField,
      getField,
      setField,
      hasField,
      callField,
      callSuperField
    ];
  }

  /**
   * Builds the hscript static fields for the class, while incorporating backwards compatibility for the old system.
   * @param cls    The class to build the static fields for.
   * @return       The hscript static fields.
   */
  static function buildBaseClassStaticFields(cls:ClassType):Array<Field>
  {
    var underlyingClass:String = formatClassString(cls);
    var complexType:ComplexType = getComplexTypeFromClass(cls);

    // BACKWARDS COMPAT: If a class has the `:hscriptClass` metadata, we should use the class its extending as the underlying class.
    if (cls.meta.has(':hscriptClass') && cls.superClass != null)
    {
      var superCls:ClassType = cls.superClass.t.get();
      underlyingClass = formatClassString(superCls);
    }

    var buildPos = Context.currentPos();

    var isClassField:Field = {
      name: '_isHScriptedClass',
      doc: 'Field used to identify a HScriptedClass.',
      access: [APrivate, AStatic],
      meta: [
        {
          name: ':noCompletion',
          pos: buildPos
        },
        {
          name: ':jignored',
          pos: buildPos
        }
      ],
      pos: buildPos,
      kind: FieldType.FVar(macro :Bool, macro true)
    };

    var listClassesField:Field = {
      name: 'listScriptClasses',
      doc: "Returns a list of all the scripted classes which extend this class.",
      access: [APublic, AStatic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [],
        ret: macro :Array<String>,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.listExtending($v{underlyingClass});
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.listScriptClassesExtending($v{underlyingClass});
        }),
      }),
    };

    var initField:Field = {
      name: 'scriptInit',
      doc: "Initializes a scripted class instance using the given scripted class name and constructor arguments.",
      access: [APublic, AStatic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'args',
            type: macro :...
            Dynamic
          }
        ],
        ret: macro :Null<$complexType>,
        expr: useBridge() ? (macro
        {
          // The whole of this lives in the bridge, so a script names neither the class
          // reference nor the error reporter.
          return cast polymod.hscript.PolymodScriptBridge.instantiate(clsName, $v{underlyingClass}, (cast args) ?? []);
        }) : (macro
        {
          var clsRef = polymod.hscript._internal.PolymodStaticClassReference.tryBuild(clsName);

          if (clsRef == null)
          {
            polymod.Polymod.error(
              SCRIPT_RUNTIME_EXCEPTION,
              'Could not construct instance of scripted class (${clsName} extends ' + $v{underlyingClass} + ')\nUnknown error building class reference',
              SCRIPT_RUNTIME
            );
            return null;
          }

          try
          {
            var result = clsRef.instantiate((cast args) ?? []);
            if (result == null)
            {
              polymod.Polymod.error(
                SCRIPT_RUNTIME_EXCEPTION,
                'Could not construct instance of scripted class (${clsName} extends ' + $v{underlyingClass} + '):\nUnknown error instantiating class',
                SCRIPT_RUNTIME
              );
              return null;
            }

            return result;
          }
          catch (error)
          {
            polymod.Polymod.error(
              SCRIPT_RUNTIME_EXCEPTION,
              'Could not construct instance of scripted class (${clsName} extends ' + $v{underlyingClass} + '):\n${error}',
              SCRIPT_RUNTIME
            );
            return null;
          }
        }),
      }),
    }

    var staticGetField:Field = {
      name: 'scriptStaticGet',
      doc: "Retrieves a custom static variable on a scripted class, by the given name.",
      access: [APublic, AStatic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'fieldName',
            type: macro :String
          },
        ],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.staticGet(clsName, fieldName);
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.getScriptClassStaticField(clsName, fieldName);
        })
      })
    };

    var staticSetField:Field = {
      name: 'scriptStaticSet',
      doc: "Sets the value of a custom static variable on a scripted class, by the given name.",
      access: [APublic, AStatic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'fieldName',
            type: macro :String
          },
          {
            name: 'fieldValue',
            type: macro :Dynamic,
            value: macro null
          },
        ],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.staticSet(clsName, fieldName, fieldValue);
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.setScriptClassStaticField(clsName, fieldName, fieldValue);
        })
      })
    };

    var staticHasField:Field = {
      name: 'scriptStaticHas',
      doc: 'Determines if a static field of a scripted class exists or not.',
      access: [APublic, AStatic],
      meta: null,
      pos: buildPos,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'fieldName',
            type: macro :String
          }
        ],
        ret: macro :Bool,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.staticHas(clsName, fieldName);
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.hasScriptClassStaticField(clsName, fieldName);
        }),
      }),
    };

    var staticHasFunc:Field = {
      name: 'scriptStaticHasFunc',
      doc: 'Determines if a static function of a scripted class exists or not.',
      access: [APublic, AStatic],
      meta: null,
      pos: buildPos,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'fieldName',
            type: macro :String
          }
        ],
        ret: macro :Bool,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.staticHasFunc(clsName, fieldName);
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.hasScriptClassStaticFunction(clsName, fieldName);
        }),
      }),
    };

    var staticCallField:Field = {
      name: 'scriptStaticCall',
      doc: "Call a custom static function on a scripted class, by the given name, with the given arguments.",
      access: [APublic, AStatic],
      pos: buildPos,
      meta: null,
      kind: FFun({
        args: [
          {
            name: 'clsName',
            type: macro :String
          },
          {
            name: 'funcName',
            type: macro :String
          },
          {
            name: 'funcArgs',
            type: macro :Array<Dynamic>,
            opt: true
          }
        ],
        ret: macro :Dynamic,
        expr: useBridge() ? (macro
        {
          return polymod.hscript.PolymodScriptBridge.staticCall(clsName, funcName, funcArgs ?? []);
        }) : (macro
        {
          return polymod.hscript._internal.PolymodScriptClass.callScriptClassStaticFunction(clsName, funcName, funcArgs ?? []);
        })
      })
    };

    return [
      isClassField,
      listClassesField,
      initField,
      staticGetField,
      staticSetField,
      staticHasField,
      staticHasFunc,
      staticCallField
    ];
  }

  /**
   * Goes over the function expressions and removes `inline` from them. This is because inlining a function call requires said function
   * to only have a single return, however due to how script extending works, this is no longer a guarantee.
   * @param fields  The fields whose function expressions to check and modify.
   */
  /**
   * The classes the host binary already carries, read from the `dll_import` file hxcpp is given.
   */
  static var hostClasses:Null<Map<String, Bool>> = null;

  /**
   * Whether this class lives in the host rather than in the module being compiled.
   */
  static function isHostClass(clsName:String):Bool
  {
    if (hostClasses == null)
    {
      hostClasses = new Map<String, Bool>();

      var path:Null<String> = Context.definedValue('dll_import');

      if (path != null && sys.FileSystem.exists(path))
      {
        for (line in sys.io.File.getContent(path).split('\n'))
        {
          var trimmed:String = StringTools.trim(line);
          if (StringTools.startsWith(trimmed, 'class ')) hostClasses.set(StringTools.trim(trimmed.substr(6)), true);
        }
      }
    }

    return hostClasses.exists(clsName);
  }

  static function removeInlinedFunctionCalls(fields:Array<Field>):Void
  {
    // This is a heavy operation and isn't needed to be done during code completion.
    if (Context.defined('display')) return;

    function removeInlines(expr:Expr):Expr
    {
      return switch (expr.expr)
      {
        case EMeta(s, e) if (s.name == ':inline'):
          e;
        default:
          expr.map(removeInlines);
      }
    }

    for (fld in fields)
    {
      switch (fld.kind)
      {
        case FFun(f) if (f.expr != null):
          f.expr = f.expr.map(removeInlines);
        default: // Do nothing.
      }
    }
  }

  /**
   * `TypeTools.toComplexType` doesn't properly convert parameters into their underlying types, which results in a compilation error.
   * We need the complex types as a return type for the `Class.scriptInit` function, and as such require underlying types.
   * @param cls   The class to get the ComplexType from.
   */
  static function getComplexTypeFromClass(cls:ClassType):ComplexType
  {
    var params:Array<Type> = [];

    function relocateParameters(type:Type)
    {
      if (type == null) return type;
      return switch (type)
      {
        case TInst(_.get() => classType, p):
          var paramIndex:Int = [for (p in cls.params) p.name].indexOf(classType.name);
          (paramIndex >= 0 ? params[paramIndex] : type.map(relocateParameters));

        default:
          type.map(relocateParameters);
      }
    }

    for (p in cls.params)
    {
      var type:Type = switch (p.t)
      {
        case(TInst(_.get() => classType, _)):
          switch (classType.kind)
          {
            case KTypeParameter(c):
              (c.length > 1 ? Type.TDynamic(null) : c[0]); // With multiple types, using only one results in a compilation error.
            default:
              p.t;
          }
        default:
          p.t;
      }

      params.push(type);
    }

    // If a parameter class points to the previous parameter, make it instead point to the underlying type.
    // See `FlxTypedPath` for an example of such.
    for (i in 0...params.length)
    {
      params[i] = params[i].map(relocateParameters);
    }

    return TPath(cls.toTypePath(params));
  }

  static function formatClassString(cls:ClassType):String
  {
    return cls.pack.copy().concat([cls.name]).join('.');
  }
}
#end
