package polymod.hscript._internal;

import polymod.hscript._internal.Expr;

using Lambda;

typedef InterfaceFields = Map<String, Array<FieldDecl>>;

/**
 * Handles reference to an interface.
 */
class PolymodStaticInterfaceReference
{
  /**
   * Internal cache for all interface references to prevent needing to create a new instance.
   */
  static var _interfaceCache:Map<String, PolymodStaticInterfaceReference> = new Map<String, PolymodStaticInterfaceReference>();

  /**
   * The full path of this interface.
   */
  public var id:String;

  /**
   * The scripted class declaration of this interface.
   * `null` unless the id finds a scripted class.
   */
  public var interfaceDecl(get, never):InterfaceDecl;

  function get_interfaceDecl():InterfaceDecl
  {
    if (Interp.findScriptInterfaceDescriptor(id) != null)
    {
      return Interp.findScriptInterfaceDescriptor(id);
    }
    return null;
  }

  /**
   * The list of interfaces that are extended by this interface.
   */
  public var superInterfaces(get, never):Array<String>;

  function get_superInterfaces():Array<String>
  {
    var list:Array<String> = [];
    for (i in getFields().keys())
    {
      if (i == id)
        continue;

      list.push(i);
    }
    return list;
  }

  /**
   * The cached fields of this interface.
   * This is a map so we're easily able to track which field belongs to what interface in the case of error reporting.
   */
  var _fieldsDecl:InterfaceFields = null;

  /**
   * Instantiates instances of all scripted interfaces.
   */
  public static function cacheScriptedInterfaces():Void
  {
    @:privateAccess
    for (key in Interp._scriptInterfaceDescriptors.keys())
    {
      tryBuild(key);
    }
  }

  /**
   * Clear all scripted interfaces and remove them from the cache.
   * We don't remove any base interfaces as those were initalized on compilation and aren't going to change.
   */
  public static function clearScriptedInterfaces():Void
  {
    @:privateAccess
    for (key in Interp._scriptInterfaceDescriptors.keys())
    {
      var ref = _interfaceCache.get(key);
      if (ref != null)
      {
        // Just for good measure.
        ref._fieldsDecl.clear();
        ref._fieldsDecl = null;
      }
      _interfaceCache.remove(ref.id);
    }
  }

  /**
   * Retrieves a static interface reference through an id.
   * @param id The id (class path) of this interface.
   * @return PolymodStaticInterfaceReference
   */
  public static function tryBuild(id:String):PolymodStaticInterfaceReference
  {
    if (!PolymodScriptClass.baseInterfaceClasses.contains(id) && Interp.findScriptInterfaceDescriptor(id) == null)
    {
      return null;
    }
    else
    {
      if (_interfaceCache.exists(id)) return _interfaceCache.get(id);

      var ref:PolymodStaticInterfaceReference = new PolymodStaticInterfaceReference(id);
      _interfaceCache.set(id, ref);

      return ref;
    }
  }

  public function new(id:String)
  {
    this.id = id;
    getFields(); // Cache fields.
  }

  /**
   * Iterates through each field of this interface to see whether this class meets all of the requirements.
   * If it doesn't, a list of errors will be thrown.
   * @param cls The class to check.
   * @param satisfied The list of interfaces that this class has already satisifed. Only really used to prevent redundant checks for interfaces we don't need to.
   * @return A list of errors needed to be resolved.
   */
  public function trySatisfy(cls:ClassDecl, ?satisfied:Array<PolymodStaticInterfaceReference>):Array<String>
  {
    satisfied ??= [];

    var errorList:Array<String> = [];
    for (interfaceId => interfaceFields in getFields())
    {
      // If this is an interface that the scripted class already satisfied, continue to the next one, no need to check again.
      if (satisfied.length > 0 && satisfied.findIndex((inter:PolymodStaticInterfaceReference) -> return [inter.id].concat(inter.superInterfaces).contains(interfaceId)) != -1)
      {
        continue;
      }

      for (field in interfaceFields)
      {
        var foundField:Null<FieldDecl> = cls.fields.find((clsField:FieldDecl) -> return clsField.name == field.name);
        if (foundField != null)
        {
          // Check to make sure the access is correct for the field.
          for (accessVal in field.access)
          {
            switch (accessVal)
            {
              case APrivate:
                if (!foundField.access.contains(APrivate) || foundField.access.contains(APublic))
                  errorList.push('Field "${foundField.name}" should be private as requested by "$interfaceId"');

              case APublic:
                if (!foundField.access.contains(APublic) || foundField.access.contains(APrivate))
                  errorList.push('Field "${foundField.name}" should be public as requested by "$interfaceId"');

              case AStatic:
                if (!foundField.access.contains(AStatic))
                  errorList.push('Field "${foundField.name}" should be static as requested by "$interfaceId"');
              default:
            }
          }

          // Check to make sure kind is the same.
          // When it is, we do checks to make sure it satisfies the declaration as well.
          switch (field.kind)
          {
            case KVar(v):
              switch (foundField.kind)
              {
                case KVar(v2):
                  // Throw an error if the property accessor is not the same.
                  if (v.get != null && v.set != null && !(v.set == v2.set && v.get == v2.get))
                  {
                    var clsFieldVarAccess:String = (v2.get == null && v2.set == null) ? 'var' : '(${v2.get}, ${v2.set})';
                    var interfaceFieldVarAccess:String = (v.get == null && v.set == null) ? 'var' : '(${v.get}, ${v.set})';

                    errorList.push('Field "${foundField.name}" has different property access than in "$interfaceId": $clsFieldVarAccess should be "$interfaceFieldVarAccess"');
                  }
                  if (v.isfinal != v2.isfinal)
                  {
                    errorList.push('Field "${foundField.name}" should be final as requested by "$interfaceId"');
                  }
                case KFunction(_):
                  // Field should be a var and not a function!
                  errorList.push('Field "${foundField.name}" should be "var" instead of "function" as requested by "$interfaceId"');
              }
            case KFunction(f):
              switch (foundField.kind)
              {
                case KFunction(f2):
                  if (f.args.length != f2.args.length)
                  {
                    errorList.push('"${foundField.name}" has different number of function arguments than in "${interfaceId}"');
                  }
                case KVar(_):
                  // Field should be a function and not a var!
                  errorList.push('Field "${foundField.name}" should be "function" instead of "var" as requested by "$interfaceId"');
              }
          }
        }
        else
        {
          // Field wasn't able to be found, the class needs to implement it.
          errorList.push('Field "${field.name}" needed by $interfaceId is missing.');
        }
      }
    }
    return errorList;
  }

  /**
   * Retrieves all fields of this interface.
   */
  public function getFields():InterfaceFields
  {
    if (_fieldsDecl != null) return _fieldsDecl;

    // `getBaseInterfaceField` is only called if the id isn't a scripted class, otherwise their caches are fetched instead.
    _fieldsDecl = interfaceDecl != null ? getScriptInterfaceFields(id) : getBaseInterfaceFields(id);
    return _fieldsDecl;
  }

  /**
   * Appends an interface to the given list.
   * @param list The list to append the fields to.
   * @param toAdd The interface fields to append.
   */
  public function appendInterfaceToList(currentFieldList:InterfaceFields, toAdd:InterfaceFields):Void
  {
    var errorFields:Array<String> = [];

    for (toAddInterfaceId => fields in toAdd)
    {
      // Make sure we only append fields of new interfaces to prevent redundency.
      if (!currentFieldList.exists(toAddInterfaceId))
      {
        var shouldAddToList:Bool = true;

        // Go through each field to make sure there's no duplicates, we throw an error otherwise.
        for (listId => val in currentFieldList)
        {
          for (toAddField in fields)
          {
            for (listField in val)
            {
              // Error reporting for fields with the same name.
              // Check to see if this field has the same name, but is a different kind of field.
              if (toAddField.name == listField.name)
              {
                if (Type.enumConstructor(toAddField.kind) != Type.enumConstructor(listField.kind))
                {
                  errorFields.push('Field "${toAddField.name}" of "$toAddInterfaceId" has different property access than in "$toAddInterfaceId"');
                }
                else
                {
                  errorFields.push('Field "${toAddField.name}" of $listId already exists in "$toAddInterfaceId"');
                }
                shouldAddToList = false;
              }
            }
          }
        }

        if (shouldAddToList)
        {
          currentFieldList.set(toAddInterfaceId, fields);
        }
      }
    }

    if (errorFields.length > 0)
    {
      throw errorFields.join('\n');
    }
  }

  public function getScriptInterfaceFields(key:String):InterfaceFields
  {
    var fieldsDecl = new InterfaceFields();
    var scriptDecl = Interp.findScriptInterfaceDescriptor(key);

    fieldsDecl.set(key, scriptDecl.fields);

    for (e in scriptDecl.extend)
    {
      switch (e)
      {
        case CTPath(path, _):
          var baseInterfaceName:String = path[path.length - 1];
          var fullName:String = scriptDecl.imports?.get(baseInterfaceName)?.fullPath ?? path.join('.');

          var extendFieldsList:InterfaceFields = new InterfaceFields();
          if (PolymodScriptClass.baseInterfaceClasses.contains(fullName))
          {
            // Fetch the base internal interface and retrieve its fields.
            // These fields should be cached by now so we can just easily retrieve them.
            var baseInterface = PolymodScriptClass.interfaceImpls.get(fullName);
            extendFieldsList = baseInterface.getFields();
          }
          else
          {
            extendFieldsList = getScriptInterfaceFields(fullName);
          }
          appendInterfaceToList(fieldsDecl, extendFieldsList);
        default:
      }
    }
    return fieldsDecl;
  }

  public function getBaseInterfaceFields(key:String):InterfaceFields
  {
    var fields:InterfaceFields = new InterfaceFields();

    var interfaceData:Array<Dynamic> = PolymodScriptClassMacro.listInterfaceImpls().get(key);
    var fieldsList:Array<Dynamic> = interfaceData[0];
    var extendList:Array<String> = interfaceData[1];

    // Base fields for this interface.
    fields.set(key, convertInterfaceFields(fieldsList));

    for (extend in extendList)
    {
      var extendFieldsList:InterfaceFields = getBaseInterfaceFields(extend);

      appendInterfaceToList(fields, extendFieldsList);
    }
    return fields;
  }

  public function toString():String
  {
    return 'PolymodStaticInterfaceReference($id)';
  }

  /**
   * Converts a list of fields constructed from `PolymodScriptClassMacro` into regular field decls.
   * Used to convert interfaces implemented in source code into runtime interfaces we're able to use.
   * @param fields The list of fields to convert.
   * @return Array<FieldDecl>
   */
  static function convertInterfaceFields(fields:Array<Dynamic>):Array<FieldDecl>
  {
    var fieldDecls:Array<FieldDecl> = [];
    for (field in fields)
    {
      var accessList:Array<String> = field.access;
      var kind:String = field.kind;
      var kindParams:Dynamic = field.kindParams;

      var fieldAccess:Array<FieldAccess> = [];
      for (access in accessList)
      {
        switch (access)
        {
          case 'public':
            fieldAccess.push(APublic);
          case 'private':
            fieldAccess.push(APrivate);
          case 'static':
            fieldAccess.push(AStatic);
        }
      }

      var fieldKind:FieldKind = switch (kind)
      {
        case 'var':
          KVar({
            get: kindParams.get,
            set: kindParams.set,
            expr: null, // Shouldn't be defined in the interface,
            type: null,
            isfinal: kindParams.isFinal
          });
        case 'method':
          var functionArgs:Array<String> = kindParams.args;
          KFunction({
            args: [for (arg in functionArgs) {
              name: arg,
              t: null,
              opt: null,
              value: null
            }],
            expr: null,
            ret: null,
          });
        default:
          null;
      }

      var fieldDecl:FieldDecl = {
        name: field.name,
        meta: null,
        kind: fieldKind,
        access: fieldAccess
      }
      fieldDecls.push(fieldDecl);
    }
    return fieldDecls;
  }
}
