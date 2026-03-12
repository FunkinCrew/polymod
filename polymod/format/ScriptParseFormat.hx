package polymod.format;

import polymod.format.ParseRules;
import polymod.hscript._internal.Expr;
import polymod.hscript._internal.Parser;
import polymod.hscript._internal.Printer;

using Lambda;

/**
 * A parse format for scripts. While Imports and Usings automatically get added and Packages get ignored,
 * the metadata is used to determine how Modules (Classes, Typedefs, etc.) are handled.
 * - `@:merge_add` - Directly add the Module, if one with the same name doesn't exist. Also works on Class Fields.
 * - `@:merge_override` - Override the Module, if one with the same name exists. Otherwise, add it normally. Also works on Class Fields
 * - `@:merge_combine` - Combine the fields of the two Modules, if the base one exists. Otherwise, add it normally. Only works on Classes.
 * - `@:merge_insert(index)` - Insert the expression into the base class at a specified index. Only works on Functions.
 * If a Module has more than one metadata, only the one with the highest priority is used, with the order being Combine > Insert > Add > Override.
 */
class ScriptParseFormat implements BaseParseFormat
{
  public static final ADD_METAS:Array<String> = [":merge_add", ":Unique", ":Add", ":add"];
  public static final COMBINE_METAS:Array<String> = [":merge_combine", ":Combine", ":combine"];
  public static final OVERRIDE_METAS:Array<String> = [":merge_override", ":Overwrite", ":override"];
  public static final INSERT_METAS:Array<String> = [":merge_insert", ":Inject", ":insert"];

  public var format(default, null):TextFileFormat;

  var parser:Parser = new Parser();
  var printer:Printer = new Printer();

  public function new()
  {
    format = SCRIPT;
  }

  public function parse(str:String):Array<ModuleDecl>
  {
    var output:Array<ModuleDecl> = [];
    try
    {
      output = parser.parseModule(str);
    }
    catch (e:Error)
    {
      Polymod.error(ASSET_MERGE_FAILED, 'Script merge error: ${e.toString()}');
      return [];
    }

    return output;
  }

  public function append(baseText:String, appendText:String, id:String):String
  {
    Polymod.warning(ASSET_MERGE_FAILED, '($id) Script files do not support append functionality!');
    return baseText;
  }

  public function merge(baseText:String, mergeText:String, id:String):String
  {
    var baseDecls:Array<ModuleDecl> = parse(baseText);
    var mergeDecls:Array<ModuleDecl> = parse(mergeText);
    var output:String = baseText;

    if (baseDecls.length == 0 || mergeDecls.length == 0)
    {
      return baseText;
    }

    for (decl in mergeDecls)
    {
      switch (decl)
      {
        case DPackage(path):
          // Never merge the packages with the base class, since that can make the base class unavailable to some scripts.
          Polymod.warning(ASSET_MERGE_FAILED, 'Skipping package merge; if other scripts import the base script they would otherwise break!');

        case DImport(path, star, name):
          // Simply push the import, duplicates are handled later.
          baseDecls.push(decl);

        case DUsing(path):
          // Simply push the using, duplicates are handled later.
          baseDecls.push(decl);

        case DClass(c1):
          // See the comment for ScriptParseFormat for how Classes are handled.
          var metaNames:Array<String> = [for (m in c1.meta) m.name];
          var metaName:Null<String> = metaNames.find((n) -> COMBINE_METAS.contains(n) || ADD_METAS.contains(n) || OVERRIDE_METAS.contains(n));

          if (metaName == null)
          {
            Polymod.warning(ASSET_MERGE_FAILED, 'Merge class ${c1.name} has no recognized metadata. Skipping.');
            continue;
          }

          var baseDecl:Null<ModuleDecl> = null;
          var baseClass:Null<ClassDecl> = null;
          for (decl2 in baseDecls)
          {
            switch (decl2)
            {
              case DClass(c2):
                if (c2.name != c1.name) continue;

                baseDecl = decl2;
                baseClass = c2;
                break;

              default:
            }
          }

          // Check for Class Metadata
          c1.meta.remove(c1.meta[metaNames.indexOf(metaName)]);

          if (COMBINE_METAS.contains(metaName))
          {
            // Add the class normally if it doesn't exist.
            if (baseDecl == null)
            {
              baseDecls.push(decl);
              continue;
            }

            // Handle class Field merging
            for (fld in c1.fields)
            {
              var fldMetaNames:Array<String> = [for (m in fld.meta) m.name];
              var fldMetaName:Null<String> = fldMetaNames.find(n -> INSERT_METAS.contains(n) || OVERRIDE_METAS.contains(n) || ADD_METAS.contains(n));

              var baseFieldNames:Array<String> = [for (fld in baseClass.fields) fld.name];
              var baseFieldIndex:Int = baseFieldNames.indexOf(fld.name);

              // If the field has no metadata, do nothing.
              if (fldMetaName == null)
              {
                Polymod.warning(ASSET_MERGE_FAILED, 'Field ${fld.name} from the merge class ${c1.name} has no recognized metadata. Skipping.');
                continue;
              }

              var meta = fld.meta[fldMetaNames.indexOf(fldMetaName)];
              fld.meta.remove(meta);

              if (INSERT_METAS.contains(fldMetaName))
              {
                // If the insert field doesn't have the index field, do nothing.
                if ((meta.params?.length ?? 0) == 0)
                {
                  Polymod.warning(ASSET_MERGE_FAILED,
                  'The insert metadata from the field ${fld.name} of the merge class ${c1.name} has no parameters. Skipping.');
                  continue;
                }

                var insertIndex:Int = switch (meta.params[0]#if hscriptPos .e #end)
                {
                  case EConst(c):
                    switch (c)
                    {
                      case CInt(v): v;
                      default: 0;
                    }
                  default: 0;
                }

                switch (fld.kind)
                {
                  case KFunction(f1):
                    switch (baseClass.fields[baseFieldIndex].kind)
                    {
                      case KFunction(f2):
                        var funcExpr = #if hscriptPos f2.expr.e; #else f2.expr; #end

                        // If the function isn't in a block, turn it into a block.
                        switch (funcExpr)
                        {
                          case EBlock(b):
                            b.insert(insertIndex, f1.expr);

                          default:
                            var exprArray:Array<Expr> = [f2.expr];
                            exprArray.insert(insertIndex, f1.expr);
                            funcExpr = EBlock(exprArray);
                        }

                      default:
                        Polymod.warning(ASSET_MERGE_FAILED, 'Field ${fld.name} from the base class ${baseClass.name} is not a function. Skipping.');
                    }

                  default:
                    Polymod.warning(ASSET_MERGE_FAILED, 'Field ${fld.name} from the merge class ${c1.name} is not a function. Skipping.');
                }

                continue;
              }
              else if (OVERRIDE_METAS.contains(fldMetaName))
              {
                baseClass.fields.remove(baseClass.fields[baseFieldIndex]);
                baseClass.fields.push(fld);
                continue;
              }
              else if (ADD_METAS.contains(fldMetaName))
              {
                if (baseFieldIndex != -1)
                {
                  Polymod.warning(ASSET_MERGE_FAILED, 'Field ${fld.name} from the merge class ${c1.name} already exists in the base class. Skipping.');
                }
                else
                {
                  baseClass.fields.push(fld);
                }

                continue;
              }

              Polymod.warning(ASSET_MERGE_FAILED, 'Field ${fld.name} from the merge class ${c1.name} doesn\'t have any merge metadata. Skipping.');
            }
          }
          else if (ADD_METAS.contains(metaName))
          {
            if (baseDecl != null)
            {
              Polymod.warning(ASSET_MERGE_FAILED, 'A class with the name ${c1.name} already exists. Skipping.');
            }
            else
            {
              baseDecls.push(decl);
            }
          }
          else if (OVERRIDE_METAS.contains(metaName))
          {
            baseDecls.remove(baseDecl);
            baseDecls.push(decl);
            continue;
          }

          Polymod.warning(ASSET_MERGE_FAILED, 'Merge class ${c1.name} doesn\'t have any merge metadata. Skipping.');

        case DTypedef(t1):
          // See the comment for ScriptParseFormat for how Typedefs are handled.
          var metaNames:Array<String> = [for (m in t1.meta) m.name];
          var metaName:Null<String> = metaNames.find((n) -> COMBINE_METAS.contains(n) || ADD_METAS.contains(n) || OVERRIDE_METAS.contains(n));

          if (metaName == null)
          {
            Polymod.warning(ASSET_MERGE_FAILED, 'Merge typedef ${t1.name} has no recognized metadata. Skipping.');
            continue;
          }

          var baseDecl:Null<ModuleDecl> = null;
          for (decl2 in baseDecls)
          {
            switch (decl2)
            {
              case DTypedef(t2):
                if (t2.name != t1.name) continue;

                baseDecl = decl2;
                break;

              default:
            }
          }

          t1.meta.remove(t1.meta[metaNames.indexOf(metaName)]);

          if (ADD_METAS.contains(metaName))
          {
            if (baseDecl != null)
            {
              Polymod.warning(ASSET_MERGE_FAILED, 'A typedef with the name ${t1.name} already exists. Skipping.');
            }
            else
            {
              baseDecls.push(decl);
            }

            continue;
          }
          else if (OVERRIDE_METAS.contains(metaName))
          {
            baseDecls.remove(baseDecl);
            baseDecls.push(decl);
            continue;
          }

          Polymod.warning(ASSET_MERGE_FAILED, 'Merge typedef ${t1.name} doesn\'t have any merge metadata. Skipping.');

        case DEnum(e1):
          // See the comment for ScriptParseFormat for how Enums are handled.
          var metaNames:Array<String> = [for (m in e1.meta) m.name];
          var metaName:Null<String> = metaNames.find((n) -> COMBINE_METAS.contains(n) || ADD_METAS.contains(n) || OVERRIDE_METAS.contains(n));
          if (metaName == null)
          {
            Polymod.warning(ASSET_MERGE_FAILED, 'Merge enum ${e1.name} has no recognized metadata. Skipping.');
            continue;
          }

          var baseDecl:Null<ModuleDecl> = null;
          for (decl2 in baseDecls)
          {
            switch (decl2)
            {
              case DEnum(e2):
                if (e2.name != e1.name) continue;

                baseDecl = decl2;
                break;

              default:
            }
          }

          e1.meta.remove(e1.meta[metaNames.indexOf(metaName)]);

          if (ADD_METAS.contains(metaName))
          {
            if (baseDecl != null)
            {
              Polymod.warning(ASSET_MERGE_FAILED, 'A typedef with the name ${e1.name} already exists. Skipping.');
            }
            else
            {
              baseDecls.push(decl);
            }

            continue;
          }
          else if (OVERRIDE_METAS.contains(metaName))
          {
            baseDecls.remove(baseDecl);
            baseDecls.push(decl);
            continue;
          }

          Polymod.warning(ASSET_MERGE_FAILED, 'Merge enum ${e1.name} doesn\'t have any merge metadata. Skipping.');

        case DInterface(i1):
          // See the comment for ScriptParseFormat for how Interfaces are handled.
          var metaNames:Array<String> = [for (m in i1.meta) m.name];
          var metaName:Null<String> = metaNames.find((n) -> COMBINE_METAS.contains(n) || ADD_METAS.contains(n) || OVERRIDE_METAS.contains(n));
          if (metaName == null)
          {
            Polymod.warning(ASSET_MERGE_FAILED, 'Merge interface ${i1.name} has no recognized metadata. Skipping.');
            continue;
          }

          var baseDecl:Null<ModuleDecl> = null;
          for (decl2 in baseDecls)
          {
            switch (decl2)
            {
              case DInterface(i2):
                if (i2.name != i1.name) continue;

                baseDecl = decl2;
                break;

              default:
            }
          }

          i1.meta.remove(i1.meta[metaNames.indexOf(metaName)]);

          if (ADD_METAS.contains(metaName))
          {
            if (baseDecl != null)
            {
              Polymod.warning(ASSET_MERGE_FAILED, 'An interface with the name ${i1.name} already exists. Skipping.');
            }
            else
            {
              baseDecls.push(decl);
            }

            continue;
          }
          else if (OVERRIDE_METAS.contains(metaName))
          {
            baseDecls.remove(baseDecl);
            baseDecls.push(decl);
            continue;
          }

          Polymod.warning(ASSET_MERGE_FAILED, 'Merge interface ${i1.name} doesn\'t have any merge metadata. Skipping.');

        default:
      }
    }

    var realOutput:String = printer.modulesToString(baseDecls);
    if (realOutput.length > 0) return realOutput;

    // Failsafe in case the printing didn't work.
    return output;
  }
}

