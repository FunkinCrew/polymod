package polymod.hscript._internal;

import haxe.macro.Context;
import haxe.macro.Expr;

using Lambda;
using haxe.macro.ComplexTypeTools;
using haxe.macro.ExprTools;
using haxe.macro.TypeTools;

class HScriptedClassMacro
{
	static var secondaryPassInitialized:Bool = false;

	/**
	 * The first step creates the interface functions.
	 * The second build step (called in an onAfterTyping callback) creates the rest of the functions,
	 *   which require initial typing to be completed before they can be created.
	 */
	public static macro function build():Array<Field>
	{
		var cls:haxe.macro.Type.ClassType = Context.getLocalClass().get();
		var initialFields:Array<Field> = Context.getBuildFields();
		var fields:Array<Field> = [].concat(initialFields);

		// If the class already has `@:hscriptClassPreProcessed` on it, we don't need to do anything.
		var alreadyProcessed_metadata = cls.meta.get().find(function(m) return m.name == ':hscriptClassPreProcessed');

		if (alreadyProcessed_metadata == null)
		{
			// Context.info('HScriptedClass: Class ' + cls.name + ' ready to pre-process...', Context.currentPos());

			var superCls:haxe.macro.Type.ClassType = cls.superClass.t.get();

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
	 * specifically the `init()` function and the override methods.
	 */
	public static function buildHScriptClass(cls:haxe.macro.Type.ClassType, fields:Array<Field>):Array<Field>
	{
		// var cls:haxe.macro.Type.ClassType = Context.getLocalClass().get();

		var script_class_meta = cls.meta.get().find(function(m) return m.name == ':hscriptClass');
		if (script_class_meta != null)
		{
			var superCls:haxe.macro.Type.ClassType = cls.superClass.t.get();

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
					var superClsConstType:haxe.macro.Type = superCls.constructor.get().type;
					// Context.follow(superCls.constructor.get().type);
					switch (superClsConstType)
					{
						case TFun(args, ret):
							// Build a new constructor, which has the same signature as the superclass constructor.
							var constArgs = [
								for (arg in args)
									{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
							];
							var initField:Field = buildScriptedClassInit(cls, superCls, constArgs);
							fields.push(initField);
							constructor = buildScriptedClassConstructor(constArgs);
						case TLazy(builder):
							var builtValue = builder();
							switch (builtValue)
							{
								case TFun(args, ret):
									// Build a new constructor, which has the same signature as the superclass constructor.
									var constArgs = [
										for (arg in args)
											{name: arg.name, opt: arg.opt, type: Context.toComplexType(arg.t)}
									];
									var initField:Field = buildScriptedClassInit(cls, superCls, constArgs);
									fields.push(initField);
									constructor = buildScriptedClassConstructor(constArgs);
								default:
									Context.error('Error: Lazy superclass constructor is not a function (got ${builtValue})', Context.currentPos());
							}
						default:
							Context.error('Error: super constructor is not a function (got ${superClsConstType})', Context.currentPos());
					}
				}
				else
				{
					constructor = buildEmptyScriptedClassConstructor();
					// Create scripted class utility functions.
					Context.info('  Creating scripted class utils...', Context.currentPos());
					var initField:Field = buildScriptedClassInit(cls, superCls, []);
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

	static function buildScriptedClassInit(cls:haxe.macro.Type.ClassType, superCls:haxe.macro.Type.ClassType, superConstArgs:Array<FunctionArg>):Field
	{
		// Context.info('  Building scripted class init() function', Context.currentPos());
		var clsTypeName:String = cls.pack.join('.') != '' ? '${cls.pack.join('.')}.${cls.name}' : cls.name;
		var superClsTypeName:String = superCls.pack.join('.') != '' ? '${superCls.pack.join('.')}.${superCls.name}' : superCls.name;

		var constArgs = [for (arg in superConstArgs) macro $i{arg.name}];
		var typePath:haxe.macro.TypePath = {
			pack: cls.pack,
			name: cls.name,
		};
		var function_init:Field = {
			name: 'init',
			doc: "Initializes a scripted class instance using the given scripted class name and constructor arguments.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [{name: 'clsName', type: macro :String},].concat(superConstArgs),
				params: null,
				ret: Context.toComplexType(Context.getType(clsTypeName)),
				expr: macro
				{
					var clsRef = polymod.hscript._internal.PolymodClassDeclEx.PolymodStaticClassReference.tryBuild(clsName);

					if (clsRef == null)
					{
						polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + ')\nUnknown error building class reference');
						return null;
					}

					try {
						var result = clsRef.instantiate([$a{constArgs}]);
						if (result == null)
						{
							polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + '):\nUnknown error instantiating class');
							return null;
						}

						return result;
					} catch (error) {
						polymod.Polymod.error(SCRIPT_RUNTIME_EXCEPTION, 'Could not construct instance of scripted class (${clsName} extends ' + $v{clsTypeName} + '):\n${error}');
						return null;
					}
				},
			}),
		};

		return function_init;
	}

	static function buildScriptedClassUtils(cls:haxe.macro.Type.ClassType, superCls:haxe.macro.Type.ClassType):Array<Field>
	{
		var clsTypeName:String = cls.pack.join('.') != '' ? '${cls.pack.join('.')}.${cls.name}' : cls.name;
		var superClsTypeName:String = superCls.pack.join('.') != '' ? '${superCls.pack.join('.')}.${superCls.name}' : superCls.name;

		var function_scriptGet:Field = {
			name: 'scriptGet',
			doc: 'Retrieves the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [{name: 'varName', type: macro :String}],
				params: null,
				ret: macro :Dynamic,
				expr: macro
				{
					return _asc.fieldRead(varName);
				},
			}),
		}

		var function_scriptSet:Field = {
			name: 'scriptSet',
			doc: 'Directly modifies the value of a local variable of a scripted class.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
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

		var function_scriptCall:Field = {
			name: 'scriptCall',
			doc: 'Calls a function of the scripted class with the given name and arguments.',
			access: [APublic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
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

		var var__asc:Field = {
			name: '_asc',
			doc: "The AbstractScriptClass instance which any variable or function calls are redirected to internally.",
			access: [APrivate], // Private instance variable
			kind: FVar(macro :polymod.hscript._internal.PolymodAbstractScriptClass),
			pos: cls.pos,
		};

		var function_listScriptClasses:Field = {
			name: 'listScriptClasses',
			doc: "Returns a list of all the scripted classes which extend this class.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [],
				params: null,
				ret: macro :Array<String>,
				expr: macro
				{
					return polymod.hscript._internal.PolymodScriptClass.listScriptClassesExtending($v{superClsTypeName});
				},
			}),
		};

		var function_scriptStaticCall:Field = {
			name: 'scriptStaticCall',
			doc: "Call a custom static function on a scripted class, by the given name, with the given arguments.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [
					{name: 'clsName', type: macro :String},
					{name: 'funcName', type: macro :String},
				],
				params: null,
				ret: macro :Dynamic,
				expr: macro
				{
					return polymod.hscript._internal.PolymodScriptClass.callScriptClassStaticFunction(clsName, funcName);
				}
			})
		};

		var function_scriptStaticGet:Field = {
			name: 'scriptStaticGet',
			doc: "Retrieves a custom static variable on a scripted class, by the given name.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
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

		var function_scriptStaticSet:Field = {
			name: 'scriptStaticSet',
			doc: "Sets the value of a custom static variable on a scripted class, by the given name.",
			access: [APublic, AStatic],
			meta: null,
			pos: cls.pos,
			kind: FFun({
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

		return [
			var__asc,
			function_listScriptClasses,
			function_scriptCall,
			function_scriptGet,
			function_scriptSet,
			function_scriptStaticCall,
			function_scriptStaticGet,
			function_scriptStaticSet
		];
	}

	/**
	 * For each function in the superclass, create a function in the subclass
	 		* that redirects to the internal abstract script class.
	 */
	static function buildScriptedClassFieldOverrides(cls:haxe.macro.Type.ClassType):Array<Field>
	{
		var fieldDone:Array<String> = [];
		var fieldArray:Array<Field> = [];

		var targetClass:haxe.macro.Type.ClassType = cls;
		var mappedParams:Map<String, haxe.macro.Type> = new Map<String, haxe.macro.Type>();
		var tType = Context.getType(cls.name);
		var tClass = Context.toComplexType(tType);

		// Start with a custom implementation of .toString()
		var func_toString:haxe.macro.Expr.Field = buildScriptedClass_toString(targetClass);
		fieldArray.push(func_toString);
		fieldDone.push('toString');

		while (targetClass != null)
		{
			// Context.info('Processing overrides for class: ${targetClass.name}<${mappedParams}>', Context.currentPos());
			// Values will be either of type haxe.macro.Expr.Field or Bool. This is because setting a Map value to null removes the key.
			var newFields:Map<String, Dynamic> = buildScriptedClassFieldOverrides_inner(targetClass, mappedParams);
			for (newFieldName => newField in newFields)
			{
				if (Std.isOfType(newField, Bool))
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
						fieldArray.push(newField);
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
				var targetParams:Array<haxe.macro.Type> = targetClass.superClass.params;
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

	static function buildScriptedClass_toString(cls:haxe.macro.Type.ClassType):Field
	{
		return {
			name: 'toString',
			doc: null,
			access: [APublic, AOverride],
			meta: null,
			pos: cls.pos,
			kind: FFun({
				args: [],
				params: null,
				ret: macro :String,
				expr: macro
				{
					if (_asc == null)
					{
						var clsName = $v{cls.name};
						var superName = $v{cls.superClass.t.get().name};
						return 'PolymodScriptedClass<${clsName} extends ${superName}>(NO ASC)';
					}
					else
					{
						return _asc.callFunction('toString', []);
					}
				},
			}),
		};
	}

	static function buildScriptedClassFieldOverrides_inner(cls:haxe.macro.Type.ClassType, targetParams:Map<String, haxe.macro.Type>):Map<String, Dynamic>
	{
		// Values will be either of type haxe.macro.Expr.Field or Bool. This is because setting a Map value to null removes the key.
		var fields:Map<String, Dynamic> = new Map<String, Dynamic>();

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
					fields.set(field.name, false);
				}
				else
				{
					for (result in results)
					{
						fields.set(result.name, result);
					}
				}
			}
		}
		for (field in cls.statics.get())
		{
			// Context.info('  Skipping: ${field.name} is static', Context.currentPos());
		}
		return fields;
	}

	static function getBaseParamsOfType(parentType:haxe.macro.Type, paramTypes:Array<haxe.macro.Type>):Array<haxe.macro.Type.TypeParameter>
	{
		var parentParams:Array<haxe.macro.Type.TypeParameter> = [];

		switch (parentType)
		{
			case TMono(t):
				var ty = t.get();
				return getBaseParamsOfType(ty, paramTypes);

			case TInst(t, params):
				// Continue
				parentParams = t.get().params;

			case TType(t, params):
				// Recurse
				var ty:haxe.macro.Type = t.get().type;
				return getBaseParamsOfType(ty, paramTypes);

			case TDynamic(t):
				// Recurse
				return getBaseParamsOfType(t, paramTypes);

			case TLazy(f):
				// Recurse
				var ty:haxe.macro.Type = f();
				return getBaseParamsOfType(ty, paramTypes);

			case TAbstract(t, _params):
				// Continue
				parentParams = t.get().params;

			// case TEnum(t:Ref<EnumType>, params:Array<Type>):
			// case TFun(args:Array<{name:String, opt:Bool, t:Type}>, ret:Type):
			// case TAnonymous(a:Ref<AnonType>):
			default:
				Context.error('Unsupported type: ${parentType}', Context.currentPos());
		}

		var result:Array<haxe.macro.Type.TypeParameter> = [];

		for (i => parentParam in parentParams)
		{
			var newParam:haxe.macro.Type.TypeParameter = {
				name: parentParam.name,
				t: paramTypes[i],
			};
			result.push(newParam);
		}

		return result;
	}

	static function scanBaseTypes(targetType:haxe.macro.Type):Array<haxe.macro.Type>
	{
		switch (targetType)
		{
			case TFun(args, ret):
				var results:Array<haxe.macro.Type> = [];

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
					var results:Array<haxe.macro.Type> = [];
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
	static function deparameterizeType(targetType:haxe.macro.Type, targetParams:Map<String, haxe.macro.Type>):haxe.macro.Type
	{
		var resultType:haxe.macro.Type = targetType;

		switch (targetType)
		{
			case TFun(args, ret):
				// Function type.
				// This is not referring to functions of a class, but rather a function taken as a parameter (like a callback).

				// Deparameterize the return type.
				var retType:haxe.macro.Type = deparameterizeType(ret, targetParams);
				// Deparameterize the argument types.
				var argTypes:Array<{name:String, opt:Bool, t:haxe.macro.Type}> = args.map(function(arg)
				{
					return {
						name: arg.name,
						opt: arg.opt,
						t: deparameterizeType(arg.t, targetParams),
					};
				});

				// Construct the new type.
				resultType = TFun(argTypes, retType);

			case TAbstract(ty, params):
				// Abstract type. Sometimes used by types like Null<T>.

				var name = ty.toString();
				var typ = ty.get();

				// Check if the Abstract type is a parameter we recognize and can replace.
				if (targetParams.exists(ty.toString()))
				{
					// If so, replace it with the real type.
					resultType = targetParams.get(ty.toString());
					// recursive call in case result is a parameter
					resultType = deparameterizeType(resultType, targetParams);
				}
				else if (params.length != 0)
				{
					var oldParams:Array<haxe.macro.Type> = [];
					var newParams:Array<haxe.macro.Type> = [];
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
						// Context.info('Building new abstract (${baseParams} + ${newParams})...', Context.currentPos());
						resultType = resultType.applyTypeParameters(baseParams, newParams);
						// Context.info('Deparameterized abstract type: ${resultType.toString()}', Context.currentPos());
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
			case TInst(ty, params):
				// Instance type. Used by most variables.

				// Check if the Instance type is a parameter we recognize and can replace.
				if (targetParams.exists(ty.toString()))
				{
					// If so, replace it with the real type.
					resultType = targetParams.get(ty.toString());
					// recursive call in case result is a parameter
					resultType = deparameterizeType(resultType, targetParams);
				}
				else if (params.length != 0)
				{
					var oldParams:Array<haxe.macro.Type> = [];
					var newParams:Array<haxe.macro.Type> = [];
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
						// Context.info('Building new abstract (${baseParams} + ${newParams})...', Context.currentPos());
						resultType = resultType.applyTypeParameters(baseParams, newParams);
						// Context.info('Deparameterized abstract type: ${resultType.toString()}', Context.currentPos());
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
	static function overrideField(field:haxe.macro.Type.ClassField, isStatic:Bool, targetParams:Map<String, haxe.macro.Type>,
			?type:haxe.macro.Type = null):Array<Field>
	{
		if (type == null)
		{
			type = field.type;
		}

		switch (type)
		{
			case TLazy(lt):
				// A lazy wrapper for another field.
				// We have to call the function to get the true value.
				var ltv:haxe.macro.Type = lt();
				return overrideField(field, isStatic, targetParams, ltv);
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
						case TInst(ty, pa):
							var typ = ty.get();
							if (typ != null && typ.isPrivate)
							{
								// Context.info('  Skipping: "${field.name}" contains private type ${typ.module}.${typ.name}', Context.currentPos());
								return [];
							}
						default: // Do nothing.
					}
				}

				// We need to skip overriding functions which are inline.
				// Normal Haxe classes can't override these functions anyway, so we can skip them.
				switch (field.kind)
				{
					case FMethod(k):
						switch (k)
						{
							case MethInline:
								// Context.info('  Skipping: "${field.name}" is inline function', Context.currentPos());
								return [];
							default: // Do nothing.
						}
					default: // Do nothing.
				}

				// Skip overriding functions which are Generics.
				// This is because this actually creates several different functions at compile time.
				// TODO: Can we somehow override these functions?
				for (fieldMeta in field.meta.get())
				{
					if (fieldMeta.name == ':generic')
					{
						// Context.info('  Skipping: "${field.name}" is marked with @:generic', Context.currentPos());
						return [];
					}
				}

				var func_inputArgs:Array<FunctionArg> = [];

				// We only get limited information about the args from Type, we need to use TypedExprDef.

				if (field == null || field.expr() == null)
				{
					// Context.info('  Skipping: "${field.name}" is not an expression', Context.currentPos());
					return [];
				}

				var func_access = [field.isPublic ? APublic : APrivate];
				if (field.isFinal)
					func_access.push(AFinal);
				if (isStatic)
				{
					func_access.push(AStatic);
				}
				else
				{
					func_access.push(AOverride);
				}

				switch (field.expr().expr)
				{
					case TFunction(tfunc):
						// Create an array of FunctionArg from the TFunction's argument objects.
						// Context.info('  Processing args of function "${field.name}"', Context.currentPos());
						for (arg in tfunc.args)
						{
							// Whether the argument is optional.
							var isOptional = (arg.value != null);
							// The argument's metadata (if any).
							var tfuncMeta:haxe.macro.Metadata = arg.v.meta.get();
							// The argument's expression/default value (if any).
							var tfuncExpr:haxe.macro.Expr = arg.value == null ? null : Context.getTypedExpr(arg.value);
							// The argument type. We have to handle any type parameters, and deparameterizeType does so recursively.
							var tfuncType:haxe.macro.ComplexType = Context.toComplexType(deparameterizeType(arg.v.t, targetParams));

							var tfuncArg:FunctionArg = {
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
				var func_over:Field = {
					name: funcName,
					doc: field.doc == null ? 'Polymod HScriptedClass override of ${field.name}.' : 'Polymod HScriptedClass override of ${field.name}.\n${field.doc}',
					access: func_access,
					meta: field.meta.get(),
					pos: field.pos,
					kind: FFun({
						args: func_inputArgs,
						params: func_params,
						ret: func_ret,
						expr: macro
						{
							if (_asc != null && _asc.hasScriptFunction($v{funcName}))
							{
								// trace('ASC: Calling $fieldName() in macro-generated function...');
								$
								{
									doesReturnVoid
										? (macro _asc.callFunction($v{funcName}, [$a{func_callArgs}]))
										: (macro return _asc.callFunction($v{funcName}, [$a{func_callArgs}]))
								}
							}
							else
							{
								// Fallback, call the original function.
								// trace('ASC: Fallback to original ${fieldName}');
								$
								{
									doesReturnVoid
										? (macro super.$funcName($a{func_callArgs}))
										: (macro return super.$funcName($a{func_callArgs}))
								}
							}
						},
					}),
				};
				var func_superCall:Field = {
					name: '__super_' + funcName,
					doc: 'Calls the original ${field.name} function while ignoring the ScriptedClass override.',
					access: [APrivate],
					meta: field.meta.get(),
					pos: field.pos,
					kind: FFun({
						args: func_inputArgs,
						params: func_params,
						ret: func_ret,
						expr: macro
						{
							var fieldName:String = $v{funcName};
							// Fallback, call the original function.
							// trace('ASC: Force call to super ${fieldName}');
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
		var constArgs:Array<FunctionArg> = superConstArgs;
		var superCallArgs:Array<Expr> = [for (arg in superConstArgs) macro $i{arg.name}];

		// Context.info('  Generating constructor for scripted class with super(${superCallArgs})', Context.currentPos());

		return {
			name: 'new',
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
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
	static function toComplexTypeArray(inputType:ComplexType):haxe.macro.ComplexType
	{
		var typeParams = (inputType != null) ? [TPType(inputType)] : [
			TPType(TPath({
				pack: [],
				name: 'Dynamic',
				sub: null,
				params: []
			}))
		];

		var result:ComplexType = TPath({
			pack: [],
			name: 'Array',
			sub: null,
			params: typeParams,
		});

		return result;
	}

	static function buildEmptyScriptedClassConstructor():Field
	{
		return ({
			name: "new",
			access: [APrivate],
			pos: Context.currentPos(),
			kind: FFun({
				args: [],
				expr: macro
				{
				}
			})
		});
	}
}

typedef HScriptClassParams =
{
	?baseClass:String,
}
