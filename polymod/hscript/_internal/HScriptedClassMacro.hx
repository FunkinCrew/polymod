package polymod.hscript._internal;

#if macro
import haxe.macro.Context;
import haxe.macro.Expr;
import haxe.macro.Expr.ComplexType;
import haxe.macro.Expr.Field;
import haxe.macro.Type;

using Lambda;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

class HScriptedClassMacro
{
  /**
   * The first step creates the interface functions.
   * The second build step (called in an onAfterTyping callback) creates the rest of the functions,
   *   which require initial typing to be completed before they can be created.
   */
  public static macro function build():Array<Field>
  {
    var cls:ClassType = Context.getLocalClass().get();

    // If the class already has `@:hscriptClassPreProcessed` on it, we don't need to do anything.

    if (!cls.meta.has(':hscriptClassPreProcessed'))
    {
      // Context.info('HScriptedClass: Class ' + cls.name + ' ready to pre-process...', Context.currentPos());
      var fields:Array<Field> = Context.getBuildFields();
      var superCls:ClassType = cls.superClass.t.get();

      var newFields:Array<Field> = buildScriptedClassUtils(cls, superCls);
      fields = fields.concat(newFields);

      fields = buildHScriptClass(cls, fields);

      // Ensure unused scripted classes are still available to initialize in scripts.
      // SORRY, DCE gets run before this, so we can't use the @:keep metadata.
      cls.meta.add(":hscriptClassPreProcessed", [], cls.pos);
      return fields;
    }
    else
    {
      // Already processed.
    }

    // Returning null is equal to "don't do anything".
    return null;
  }

  /**
   * Parse `@:hscriptClass`.
   */
  static function parseHScriptClassParams(metaEntry:MetadataEntry):HScriptClassParams
  {
    var result:HScriptClassParams = {};

    switch (metaEntry.params[0].expr)
    {
      case EObjectDecl(paramFields):
        // paramFields
        for (paramField in paramFields)
        {
          switch (paramField.field)
          {
            case 'baseClass':
              switch (paramField.expr.expr)
              {
                case EConst(CIdent(baseClassName)):
                  result.baseClass = baseClassName;
                default:
                  Context.error("Error: @:hscriptClass baseClass must be a string", Context.currentPos());
              }
              break;
          }
        }
      default:
        Context.error("Error: @:hscriptClass({}) must contain an object", Context.currentPos());
    }

    return result;
  }

  /**
   * Create the complicated parts of the generated class,
   * specifically the `scriptInit()` function and the override methods.
   */
  public static function buildHScriptClass(cls:ClassType, fields:Array<Field>):Array<Field>
  {
    if (cls.meta.has(':hscriptClass'))
    {
      var superCls:ClassType = cls.superClass.t.get();

      // Create scripted class override for constructor.
      var constructor = fields.find(function(field) return field.name == 'new');

      if (constructor != null)
      {
        Context.error("Error: Constructor already defined for this class", Context.currentPos());
      }
      else
      {
        if (superCls.constructor != null)
        {
          var superClsConstType:Type = superCls.constructor.get().type;

          switch (superClsConstType)
          {
            case TFun(args, ret) | TLazy(_() => TFun(args, ret)):
              // Build a new constructor, which has the same signature as the superclass constructor.
              var constArgs = [
                for (arg in args)
                  {name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
              ];
              var initField:Field = buildScriptedClassInit(cls, superCls);
              fields.push(initField);
              constructor = buildScriptedClassConstructor(constArgs);
            default:
              Context.error('Error: super constructor is not a function (got ${superClsConstType})', Context.currentPos());
          }
        }
        else
        {
          constructor = buildEmptyScriptedClassConstructor();
          // Create scripted class utility functions.
          // Context.info('  Creating scripted class utils...', Context.currentPos());
          var initField:Field = buildScriptedClassInit(cls, superCls);
          fields.push(initField);
          fields.push(constructor);
        }
      }

      // Create scripted class overrides for all fields (except constructor).
      // Create scripted class overrides for non-constructor fields.
      fields = fields.concat(buildScriptedClassFieldOverrides(cls));
    }
    // Else, do nothing.

    return fields;
  }

  static function buildScriptedClassInit(cls:ClassType, superCls:ClassType):Field
  {
    // Context.info('  Building scripted class init() function', Context.currentPos());
    var clsTypeName:String = cls.pack.join('.') != '' ? '${cls.pack.join('.')}.${cls.name}' : cls.name;
    var function_init:Field =
      {
        name: 'scriptInit',
        doc: "Initializes a scripted class instance using the given scripted class name and constructor arguments.",
        access: [APublic, AStatic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'clsName', type: macro :String}, {name: 'args', type: macro :...Dynamic}],
            params: null,
            ret: Context.toComplexType(Context.getType(clsTypeName)),
            expr: macro
            {
              var clsRef = polymod.hscript._internal.PolymodStaticClassReference.tryBuild(clsName);

              if (clsRef == null)
              {
                polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
                  'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + ')\nUnknown error building class reference',
                  SCRIPT_RUNTIME);
                return null;
              }

              try
              {
                var result = clsRef.instantiate((cast args) ?? []);
                if (result == null)
                {
                  polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
                    'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + '):\nUnknown error instantiating class',
                    SCRIPT_RUNTIME);
                  return null;
                }

                return result;
              }
              catch (error)
              {
                polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION,
                  'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + '):\n${error}', SCRIPT_RUNTIME);
                return null;
              }
            },
          }),
      };

    return function_init;
  }

  static function buildScriptedClassUtils(cls:ClassType, superCls:ClassType):Array<Field>
  {
    var superClsTypeName:String = superCls.pack.join('.') != '' ? '${superCls.pack.join('.')}.${superCls.name}' : superCls.name;

    var function_scriptGet:Field =
      {
        name: 'scriptGet',
        doc: 'Retrieves the value of a local variable of a scripted class.',
        access: [APublic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'varName', type: macro :String}],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return _asc.fieldRead(varName);
            },
          }),
      }

    var function_scriptSet:Field =
      {
        name: 'scriptSet',
        doc: 'Directly modifies the value of a local variable of a scripted class.',
        access: [APublic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'varName', type: macro :String},
              {
                name: 'varValue',
                type: macro :Dynamic,
                value: macro null,
              }
            ],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return _asc.fieldWrite(varName, varValue);
            },
          }),
      }

    var function_scriptHas:Field =
      {
        name: 'scriptHas',
        doc: 'Determines if a field of a scripted class exists or not.',
        access: [APublic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'fieldName', type: macro :String}],
            params: null,
            ret: macro :Bool,
            expr: macro
            {
              return _asc.fieldExists(fieldName);
            },
          }),
      }

    var function_scriptCall:Field =
      {
        name: 'scriptCall',
        doc: 'Calls a function of the scripted class with the given name and arguments.',
        access: [APublic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'funcName', type: macro :String},
              {
                name: 'funcArgs',
                type: macro :Array<Dynamic>,
                value: macro null,
              }
            ],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return _asc.callFunction(funcName, funcArgs == null ? [] : funcArgs);
            },
          }),
      };

    var var__asc:Field =
      {
        name: '_asc',
        doc: "The AbstractScriptClass instance which any variable or function calls are redirected to internally.",
        access: [APrivate], // Private instance variable
        kind: FVar(macro :polymod.hscript._internal.PolymodAbstractScriptClass),
        pos: cls.pos,
      };

    var var__isHScriptedClass:Field =
      {
        name: '_isHScriptedClass',
        doc: 'Field used to identify a HScriptedClass.',
        access: [APrivate, AStatic],
        meta: [
          {name: ':noCompletion', pos: cls.pos}],
        pos: cls.pos,
        kind: FVar(macro :Bool, macro true)
      };

    var function_listScriptClasses:Field =
      {
        name: 'listScriptClasses',
        doc: "Returns a list of all the scripted classes which extend this class.",
        access: [APublic, AStatic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [],
            params: null,
            ret: macro :Array<String>,
            expr: macro
            {
              return polymod.hscript._internal.PolymodScriptClass.listScriptClassesExtending($v{superClsTypeName});
            },
          }),
      };

    var function_scriptStaticCall:Field =
      {
        name: 'scriptStaticCall',
        doc: "Call a custom static function on a scripted class, by the given name, with the given arguments.",
        access: [APublic, AStatic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'clsName', type: macro :String}, {name: 'funcName', type: macro :String},],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return polymod.hscript._internal.PolymodScriptClass.callScriptClassStaticFunction(clsName, funcName);
            }
          })
      };

    var function_scriptStaticGet:Field =
      {
        name: 'scriptStaticGet',
        doc: "Retrieves a custom static variable on a scripted class, by the given name.",
        access: [APublic, AStatic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'clsName', type: macro :String},
              {name: 'fieldName', type: macro :String},
            ],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return polymod.hscript._internal.PolymodScriptClass.getScriptClassStaticField(clsName, fieldName);
            }
          })
      };

    var function_scriptStaticSet:Field =
      {
        name: 'scriptStaticSet',
        doc: "Sets the value of a custom static variable on a scripted class, by the given name.",
        access: [APublic, AStatic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'clsName', type: macro :String},
              {name: 'fieldName', type: macro :String},
              {
                name: 'fieldValue',
                type: macro :Dynamic,
                value: macro null,
              },
            ],
            params: null,
            ret: macro :Dynamic,
            expr: macro
            {
              return polymod.hscript._internal.PolymodScriptClass.setScriptClassStaticField(clsName, fieldName, fieldValue);
            }
          })
      };

    var function_scriptStaticHas:Field =
      {
        name: 'scriptStaticHas',
        doc: 'Determines if a static field of a scripted class exists or not.',
        access: [APublic],
        meta: null,
        pos: cls.pos,
        kind: FFun(
          {
            args: [
              {name: 'fieldName', type: macro :String}],
            params: null,
            ret: macro :Bool,
            expr: macro
            {
              @:privateAccess
              return _asc._interp.getScriptClassStaticFieldDecl(_asc.fullyQualifiedName, fieldName) != null;
            },
          }),
      };

    return [
      var__asc,
      var__isHScriptedClass,
      function_listScriptClasses,
      function_scriptCall,
      function_scriptGet,
      function_scriptSet,
      function_scriptHas,
      function_scriptStaticCall,
      function_scriptStaticGet,
      function_scriptStaticSet,
      function_scriptStaticHas
    ];
  }

  /**
   * For each function in the superclass, create a function in the subclass
       * that redirects to the internal abstract script class.
   */
  static function buildScriptedClassFieldOverrides(cls:ClassType):Array<Field>
  {
    var fieldDone:Array<String> = [];
    var fieldArray:Array<Field> = [];

    var targetClass:ClassType = cls;
    var mappedParams:Map<String, Type> = new Map<String, Type>();

    // Start with a custom implementation of .toString()
    var func_toString:Field = buildScriptedClass_toString(targetClass);
    fieldArray.push(func_toString);
    fieldDone.push('toString');

    // Skip overriding other fields during `display` mode. This avoids issues with code completion.
    // We cannot check using an #if conditional because those are evaluated at parse time.
    if (Context.defined('display'))
    {
      targetClass = null;
    }

    while (targetClass != null)
    {
      // Context.info('Processing overrides for class: ${targetClass.name}<${mappedParams}>', Context.currentPos());
      var newFields:Map<String, {f:Null<Field>}> = buildScriptedClassFieldOverrides_inner(targetClass, mappedParams);
      for (newFieldName => newField in newFields)
      {
        if (newField.f == null)
        {
          // Sometimes a child version needs to be skipped but the parent version doesn't.
          // In this case, the parent needs to be skipped also.
          // Example: A child function override can be inline when the parent isn't.
          fieldDone.push(newFieldName);
        }
        else
        {
          if (!fieldDone.contains(newFieldName))
          {
            fieldArray.push(newField.f);
            fieldDone.push(newFieldName);
          }
          else
          {
            // Context.info('  Redundant: ${newField.name}', Context.currentPos());
          }
        }
      }
      if (targetClass.superClass != null)
      {
        var targetParams:Array<Type> = targetClass.superClass.params;
        targetClass = targetClass.superClass.t.get();
        for (paramIndex in 0...targetClass.params.length)
        {
          var paramType = targetParams[paramIndex];
          var paramName = targetClass.params[paramIndex].name;
          var paramFullName = '${targetClass.pack.join('.')}.${targetClass.name}.${paramName}';
          mappedParams.set(paramFullName, paramType);
        }
      }
      else
      {
        targetClass = null;
      }
    }

    return fieldArray;
  }

  static function buildScriptedClass_toString(cls:ClassType):Field
  {
    return {
      name: 'toString',
      doc: null,
      access: [APublic, AOverride],
      meta: null,
      pos: cls.pos,
      kind: FFun(
        {
          args: [],
          params: null,
          ret: macro :String,
          expr: macro
          {
            if (_asc == null)
            {
              return $v{'PolymodScriptedClass<${cls.name} extends ${cls.superClass.t.get().name}>(NO ASC)'};
            }
            else
            {
              return _asc.callFunction('toString', []);
            }
          },
        }),
    };
  }

  static function buildScriptedClassFieldOverrides_inner(cls:ClassType, targetParams:Map<String, Type>):Map<String, {f:Null<Field>}>
  {
    var fields:Map<String, {f:Field}> = [];

    for (field in cls.fields.get())
    {
      if (field.name == 'new')
      {
        // Do nothing
      }
      else
      {
        var results:Array<Field> = overrideField(field, false, targetParams);
        if (results.length == 0)
        {
          fields.set(field.name, {f: null});
        }
        else
        {
          for (result in results)
          {
            fields.set(result.name, {f: result});
          }
        }
      }
    }
    return fields;
  }

  static function getBaseParamsOfType(parentType:Type, paramTypes:Array<Type>):Array<TypeParameter>
  {
    var parentParams:Array<TypeParameter> = [];
    parentType = Context.follow(parentType, true);

    switch (parentType)
    {
      case TInst(_.get() => t, _):
        // Continue
        parentParams = t.params;

      case TType(_.get().type => ty, params):
        // Recurse
        return getBaseParamsOfType(ty, paramTypes);

      case TDynamic(t):
        // Recurse
        return getBaseParamsOfType(t, paramTypes);

      case TAbstract(_.get() => t, _):
        // Continue
        parentParams = t.params;

      // case TEnum(t:Ref<EnumType>, params:Array<Type>):
      // case TFun(args:Array<{name:String, opt:Bool, t:Type}>, ret:Type):
      // case TAnonymous(a:Ref<AnonType>):
      default:
        Context.error('Unsupported type: ${parentType}', Context.currentPos());
    }

    var result:Array<TypeParameter> = [];
    for (i => parentParam in parentParams)
    {
      var newParam:TypeParameter =
        {
          name: parentParam.name,
          t: paramTypes[i],
        };
      result.push(newParam);
    }

    return result;
  }

  static function scanBaseTypes(targetType:Type):Array<Type>
  {
    switch (targetType)
    {
      case TFun(args, ret):
        var results:Array<Type> = [];

        for (result in scanBaseTypes(ret))
        {
          results.push(result);
        }
        for (arg in args)
        {
          for (result in scanBaseTypes(arg.t))
          {
            results.push(result);
          }
        }
        return results;
      case TAbstract(ty, params):
        if (params.length == 0)
        {
          return [targetType];
        }
        else
        {
          var results:Array<Type> = [];
          for (param in params)
          {
            for (result in scanBaseTypes(param))
            {
              results.push(result);
            }
          }
          return results;
        }
      default:
        return [targetType];
    }
  }

  /**
   * Insert real types into a parameterized type.
   * For example, `TypeA<TypeB<TypeC<T>>>` becomes `TypeA<TypeB<TypeC<int>>>` if T is `int`.
   *
   * Note, function runs recursively.
   */
  static function deparameterizeType(targetType:Type, targetParams:Map<String, Type>):Type
  {
    var resultType:Type = Context.follow(targetType, true);

    switch (resultType)
    {
      case TFun(args, ret):
        // Function type.
        // This is not referring to functions of a class, but rather a function taken as a parameter (like a callback).

        // Deparameterize the return type.
        var retType:Type = deparameterizeType(ret, targetParams);
        // Deparameterize the argument types.
        var argTypes:Array<{name:String, opt:Bool, t:Type}> = args.map((arg) -> {
          return {
            name: arg.name,
            opt: arg.opt,
            t: deparameterizeType(arg.t, targetParams),
          };
        });

        // Construct the new type.
        resultType = TFun(argTypes, retType);

      case TAbstract(_.toString() => name, params) | TInst(_.toString() => name, params):
        // Check if the type is a parameter we recognize and can replace.
        if (targetParams.exists(name))
        {
          // If so, replace it with the real type.
          resultType = targetParams.get(name);
          // recursive call in case result is a parameter
          resultType = deparameterizeType(resultType, targetParams);
        }
        else if (params.length != 0)
        {
          var oldParams:Array<Type> = [];
          var newParams:Array<Type> = [];
          for (param in params)
          {
            var baseTypes = scanBaseTypes(param);

            for (baseType in baseTypes)
            {
              var newParam = deparameterizeType(baseType, targetParams);
              if (newParam.toString() == "Void")
              {
                // Skipping Void...
              }
              else
              {
                oldParams.push(baseType);
                newParams.push(newParam);
              }
            }
          }
          var baseParams = getBaseParamsOfType(resultType, oldParams);
          newParams = newParams.slice(0, baseParams.length);

          if (newParams.length > 0)
          {
            // Context.info('Building new ${targetType.match(TAbstract(_)) ? 'abstract' : 'class'} (${baseParams} + ${newParams})...', Context.currentPos());
            resultType = resultType.applyTypeParameters(baseParams, newParams);
            // Context.info('Deparameterized ${targetType.match(TAbstract(_)) ? 'abstract' : 'class'} type: ${resultType.toString()}', Context.currentPos());
          }
          else
          {
            // Leave the type as is.
          }
        }
        else
        {
          // Else, there are no parameters related this type and we don't need to mutate it.
        }

      default:
        // Do nothing.
        // Muted because I haven't actually seen any issues caused by this. Maybe investigate in the future.
        // Context.warning('You failed to handle this! ${targetType}', Context.currentPos());
    }

    return resultType;
  }

  /**
   * Given a ClassField from the target class, create one or more Fields that override the target field,
   * redirecting any calls to the internal AbstractScriptedClass.
   */
  static function overrideField(field:ClassField, isStatic:Bool, targetParams:Map<String, Type>, ?type:Type):Array<Field>
  {
    if (type == null)
    {
      type = field.type;
    }

    switch (Context.follow(type))
    {
      case TFun(args, ret):
        // This field is a function of the class.
        // We need to redirect to the scripted class in case our scripted class overrides it.
        // If it isn't overridden, the AbstractScriptClass will call the original function.

        // We need to skip overriding functions which meet have a private type as an argument.
        // Normal Haxe classes can't override these functions anyway, so we can skip them.
        for (arg in args)
        {
          switch (arg.t)
          {
            case TInst(_.get() => cls, _) if (cls.isPrivate):
              // Context.info('  Skipping: "${field.name}" contains private type ${typ.module}.${typ.name}', Context.currentPos());
              return [];
            default: // Do nothing.
          }
        }

        // We need to skip overriding functions which are inline.
        // Normal Haxe classes can't override these functions anyway, so we can skip them.
        switch (field.kind)
        {
          case FMethod(MethInline):
            // Context.info('  Skipping: "${field.name}" is inline function', Context.currentPos());
            return [];
          default: // Do nothing.
        }

        // Skip overriding functions which are Generics.
        // This is because this actually creates several different functions at compile time.
        // TODO: Can we somehow override these functions?
        if (field.meta.has(':generic'))
        {
          // Context.info('  Skipping: "${field.name}" is marked with @:generic', Context.currentPos());
          return [];
        }

        var func_inputArgs:Array<FunctionArg> = [];

        // We only get limited information about the args from Type, we need to use TypedExprDef.
        var fieldExpr:Null<TypedExpr> = field?.expr();
        if (fieldExpr == null)
        {
          // Context.info('  Skipping: "${field.name}" is not an expression', Context.currentPos());
          return [];
        }

        var func_access = [field.isPublic ? APublic : APrivate];
        if (field.isFinal) func_access.push(AFinal);
        if (isStatic)
        {
          func_access.push(AStatic);
        }
        else
        {
          func_access.push(AOverride);
        }

        switch (fieldExpr.expr)
        {
          case TFunction(tfunc):
            // Create an array of FunctionArg from the TFunction's argument objects.
            // Context.info('  Processing args of function "${field.name}"', Context.currentPos());
            for (arg in tfunc.args)
            {
              // Whether the argument is optional.
              // var isOptional = (arg.value != null);
              // The argument's metadata (if any).
              var tfuncMeta:Metadata = arg.v.meta.get();
              // The argument's expression/default value (if any).
              var tfuncExpr:Expr = arg.value == null ? null : Context.getTypedExpr(arg.value);
              // The argument type. We have to handle any type parameters, and deparameterizeType does so recursively.
              var tfuncType:ComplexType = Context.toComplexType(deparameterizeType(arg.v.t, targetParams));

              var tfuncArg:FunctionArg =
                {
                  name: arg.v.name,
                  type: tfuncType,
                  // opt: isOptional,
                  meta: tfuncMeta,
                  value: tfuncExpr,
                };
              func_inputArgs.push(tfuncArg);
            }
          case TConst(tcon):
            // Okay, so uh, this is actually a VARIABLE storing a function.
            // Don't attempt to re-define it.

            return [];
          default:
            Context.warning('Expected a function and got ${field.expr().expr}', Context.currentPos());
        }

        // Is there a better way to do this?
        var doesReturnVoid:Bool = ret.toString() == "Void";

        // Generate the list of call arguments for the function.
        // Context.info('${args}', Context.currentPos());
        var func_callArgs:Array<Expr> = [for (arg in args) macro $i{arg.name}];

        var func_params = [for (param in field.params) {name: param.name}];

        // Context.info('  Processing return of function "${field.name}"', Context.currentPos());
        var func_ret = doesReturnVoid ? null : Context.toComplexType(deparameterizeType(ret, targetParams));

        var funcName:String = field.name;
        var func_over:Field =
          {
            name: funcName,
            doc: field.doc == null ? 'Polymod HScriptedClass override of ${field.name}.' : 'Polymod HScriptedClass override of ${field.name}.\n${field.doc}',
            access: func_access,
            meta: field.meta.get(),
            pos: field.pos,
            kind: FFun(
              {
                args: func_inputArgs,
                params: func_params,
                ret: func_ret,
                expr: macro
                {
                  if (_asc != null)
                  {
                    if (_asc.hasScriptFunction($v{funcName}))
                    {
                      $
                      {
                        doesReturnVoid ? (macro
                          {_asc.callFunction($v{funcName}, [$a{func_callArgs}]); return;}) : (macro return _asc.callFunction($v{funcName}, [$a{func_callArgs}]))
                      }
                    }
                    else
                    {
                      // If another scripted class is being extended, call if the function exists there
                      var _super = _asc.superClass;
                      while (_super is polymod.hscript._internal.PolymodScriptClass)
                      {
                        var _scriptSuper = (_super : polymod.hscript._internal.PolymodScriptClass);
                        if (_scriptSuper.hasScriptFunction($v{funcName}))
                        {
                          $
                          {
                            doesReturnVoid ? (macro
                              {
                                _scriptSuper.callFunction($v{funcName}, [$a{func_callArgs}]);
                                return;
                              }) : (macro return _scriptSuper.callFunction($v{funcName}, [$a{func_callArgs}]))
                          }
                        }

                        _super = _scriptSuper.superClass;
                      }
                    }
                  }
                  // Fallback, call the original function.
                  $
                  {
                    doesReturnVoid ? (macro super.$funcName($a{func_callArgs})) : (macro return super.$funcName($a{func_callArgs}))
                  }
                },
              }),
          };
        var func_superCall:Field =
          {
            name: '__super_' + funcName,
            doc: 'Calls the original ${field.name} function while ignoring the ScriptedClass override.',
            access: [APrivate],
            meta: field.meta.get(),
            pos: field.pos,
            kind: FFun(
              {
                args: func_inputArgs,
                params: func_params,
                ret: func_ret,
                expr: macro
                {
                  // Fallback, call the original function.
                  $
                  {
                    doesReturnVoid ? (macro super.$funcName($a{func_callArgs})) : (macro return super.$funcName($a{func_callArgs}))
                  }
                },
              }),
          }

        return [func_over, func_superCall];
      case TInst(_t, _params):
        // This field is an instance of a class.
        // Example: var test:TestClass = new TestClass();

        // Originally, I planned to replace all variables on the class with properties,
        // however this is not possible because properties are merely a compile-time feature.

        // However, since scripted classes correctly access the superclass variables anyway,
        // there is no need to override the value.
        // Context.info('Field: Instance variable "${field.name}"', Context.currentPos());
        return [];
      case TEnum(_t, _params):
        // Enum instance
        // Context.info('Field: Enum variable "${field.name}"', Context.currentPos());
        return [];
      case TMono(_t):
        // Monomorph instance
        // https://haxe.org/manual/types-monomorph.html
        // Context.info('Field: Monomorph variable "${field.name}"', Context.currentPos());
        return [];
      case TAnonymous(_t):
        // Context.info('Field: Anonymous variable "${field.name}"', Context.currentPos());
        return [];
      case TDynamic(_t):
        // Context.info('Field: Dynamic variable "${field.name}"', Context.currentPos());
        return [];
      case TAbstract(_t, _params):
        // Context.info('Field: Abstract variable "${field.name}"', Context.currentPos());
        return [];
      default:
        // Context.info('Unknown field type: ${field}', Context.currentPos());
        return [];
    }
  }

  static function buildScriptedClassConstructor(superConstArgs:Array<FunctionArg>):Field
  {
    var superCallArgs:Array<Expr> = [for (arg in superConstArgs) macro $i{arg.name}];

    // Context.info('  Generating constructor for scripted class with super(${superCallArgs})', Context.currentPos());

    return {
      name: 'new',
      access: [APrivate],
      pos: Context.currentPos(),
      kind: FFun(
        {
          args: superConstArgs,
          expr: macro
          {
            // Call the super constructor with appropriate args
            super($a{superCallArgs});
          },
        }),
    };
  }

  /**
   * Create the type corresponding to an array of the given type.
   * For example, toComplexTypeArray(String) will return Array<String>.
   */
  static function toComplexTypeArray(inputType:ComplexType):ComplexType
  {
    var typeParams = (inputType != null) ? [TPType(inputType)] : [
      TPType(TPath(
        {
          pack: [],
          name: 'Dynamic',
          sub: null,
          params: []
        }))
    ];

    var result:ComplexType = TPath(
      {
        pack: [],
        name: 'Array',
        sub: null,
        params: typeParams,
      });

    return result;
  }

  static function buildEmptyScriptedClassConstructor():Field
  {
    return (
      {
        name: "new",
        access: [APrivate],
        pos: Context.currentPos(),
        kind: FFun(
          {
            args: [],
            expr: macro {}
          })
      });
  }
}
#end

typedef HScriptClassParams =
{
  ?baseClass:String,
}
