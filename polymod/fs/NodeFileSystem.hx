package polymod.fs;

import polymod.Polymod.PolymodErrorOrigin;
import haxe.io.Bytes;
import haxe.io.UInt8Array;
import js.Browser;
import js.html.ScriptElement;
import js.Lib;
import polymod.Polymod.ModMetadata;
import polymod.PolymodConfig;
import polymod.fs.PolymodFileSystem.IFileSystem;
import polymod.util.Util;
import polymod.util.VersionUtil;
import thx.semver.Version;
import thx.semver.VersionRule;

/**
 * An implementation of IFileSystem which accesses files from the local directory,
 * when running in Node.js via Electron.
 */
class NodeFileSystem implements IFileSystem
{
  // hack to make sure NodeUtils.injectJSCode is called
  private static var _jsCodeInjected:Bool = injectJSCode();

  public var modRoot(default, null):String;

  public function new(params:polymod.fs.PolymodFileSystem.PolymodFileSystemParams)
  {
    this.modRoot = params.modRoot;
  }

  // -----------------------------------------------------------------------------------------------
  // -----------------------------------------------------------------------------------------------

  /**
   * Injects JS code needed to interact with Node's file system into the head element of the HTML document.
   * @return
   */
  private static function injectJSCode():Bool
  {
    // array for adding JS text
    var jsCode:Array<String> = [];

    // get the node file system
    jsCode.push("let _nodefs = require('fs')");

    // utility function for getting directory contents
    jsCode.push("function getDirectoryContents(path, recursive, dirContents=null)");
    jsCode.push('{');
    jsCode.push("	if ( dirContents == null ) {");
    jsCode.push("		dirContents = [];");
    jsCode.push("	}");
    jsCode.push("	if ( isDirectory(path) ) {");
    jsCode.push("		if ( path.charAt(path.length - 1) != '/' ) {");
    jsCode.push("			path += '/';");
    jsCode.push("		}");
    jsCode.push("		var entries = _nodefs.readdirSync(path, { withFileTypes:true } );");
    jsCode.push("		for ( var i = 0; i < entries.length; ++i ) {");
    jsCode.push("			var entryPath = path + entries[i].name;");
    jsCode.push("			if ( entries[i].isDirectory() && recursive ) {");
    jsCode.push("				getDirectoryContents( entryPath, true, dirContents );");
    jsCode.push("			}");
    jsCode.push("			else {");
    jsCode.push("				dirContents.push( entryPath );");
    jsCode.push("			}");
    jsCode.push("		}");
    jsCode.push("	}");
    jsCode.push("	return dirContents;");
    jsCode.push('}');

    // functions needed by Polymod
    jsCode.push("function exists(path) { return _nodefs.existsSync(path); }");
    jsCode.push("function getStats(path) { return exists(path) ? _nodefs.statSync(path) : null; }");
    jsCode.push("function isDirectory(path) { var stats = getStats(path); return stats != null && stats.isDirectory(); }");
    jsCode.push("function getFileContent(path) { return exists(path) ? _nodefs.readFileSync(path, {encoding:'utf8', flag:'r'}) : ''; }");
    jsCode.push("function getFileBytes(path) { return exists(path) ? Uint8Array.from( _nodefs.readFileSync(path) ) : null; }");
    jsCode.push("function readDirectory(path) { return getDirectoryContents(path, false, []) }");
    jsCode.push("function readDirectoryRecursive(path) { return getDirectoryContents(path, true, []) }");

    // create the script element
    var scriptElement:ScriptElement = Browser.document.createScriptElement();
    scriptElement.type = 'text/javascript';
    scriptElement.text = jsCode.join("\n");

    // inject into the head tag
    Browser.document.head.appendChild(scriptElement);

    return true;
  }

  // -----------------------------------------------------------------------------------------------

  /**
   * Pulled and modified from OpenFL's ExternalInterface implementation
   * @param	functionName
   * @param	arg
   * @return
   */
  private function callFunc(functionName:String, arg:Dynamic = null):Dynamic
  {
    if (!~/^\(.+\)$/.match(functionName))
    {
      var thisArg = functionName.split('.').slice(0, -1).join('.');
      if (thisArg.length > 0)
      {
        functionName += '.bind(${thisArg})';
      }
    }

    var fn:Dynamic = Lib.eval(functionName);

    return fn(arg);
  }

  // -----------------------------------------------------------------------------------------------
  public function santizePaths(path:String, directories:Array<String>):Void
  {
    for (i in 0...directories.length)
    {
      directories[i] = StringTools.replace(directories[i], path, '');
      if (directories[i].charAt(0) == '/')
      {
        directories[i] = directories[i].substr(1);
      }
    }
  }

  // -----------------------------------------------------------------------------------------------
  public inline function exists(path:String):Bool
  {
    return callFunc('exists', path);
  }

  // -----------------------------------------------------------------------------------------------
  public inline function isDirectory(path:String):Bool
  {
    return callFunc('isDirectory', path);
  }

  // -----------------------------------------------------------------------------------------------
  public inline function readDirectory(path:String):Array<String>
  {
    var arr:Array<String> = callFunc('readDirectory', path);
    santizePaths(path, arr);
    return arr;
  }

  // -----------------------------------------------------------------------------------------------
  public inline function getFileContent(path:String):String
  {
    return callFunc('getFileContent', path);
  }

  // -----------------------------------------------------------------------------------------------
  public inline function getFileBytes(path:String):Bytes
  {
    var intArr:UInt8Array = callFunc('getFileBytes', path);
    return intArr != null ? intArr.view.buffer : null;
  }

  // -----------------------------------------------------------------------------------------------
  public inline function readDirectoryRecursive(path:String):Array<String>
  {
    var arr:Array<String> = callFunc('readDirectoryRecursive', path);
    santizePaths(path, arr);
    return arr;
  }

  // -----------------------------------------------------------------------------------------------
  public function getMetadata(modId:String, ?origin:PolymodErrorOrigin):Void
  {
    if (exists(modId))
    {
      var meta:ModMetadata = null;

      var metaFile = Util.pathJoin(modId, PolymodConfig.modMetadataFile);
      var iconFile = Util.pathJoin(modId, PolymodConfig.modIconFile);

      if (!exists(metaFile))
      {
        Polymod.warning(MOD_MISSING_METADATA, 'Could not find mod metadata file: $metaFile', origin);
      }
      else
      {
        var metaText = getFileContent(metaFile);
        meta = ModMetadata.fromJsonStr(metaText, origin);
      }
      if (!exists(iconFile))
      {
        Polymod.warning(MOD_MISSING_ICON, 'Could not find mod icon file: $iconFile', origin);
      }
      else
      {
        var iconBytes = getFileBytes(iconFile);
        meta.icon = iconBytes;
        meta.iconPath = iconFile;
      }
      return meta;
    }
    else
    {
      Polymod.error(MOD_MISSING_DIRECTORY, 'Could not find mod directory: "$modId"', origin);
    }
    return null;
  }

  // -----------------------------------------------------------------------------------------------
  public function scanMods(?apiVersionRule:VersionRule):Array<ModMetadata>
  {
    if (apiVersionRule == null) apiVersionRule = VersionUtil.DEFAULT_VERSION_RULE;

    var dirs = readDirectory(modRoot);
    var result:Array<ModMetadata> = [];
    for (dir in dirs)
    {
      var testDir = Util.pathJoin(modRoot, dir);

      if (!exists(testDir)) continue;

      if (!isDirectory(testDir)) continue;

      var meta:ModMetadata = this.getMetadata(dir, PolymodErrorOrigin.SCAN);

      if (meta == null) continue;

      if (!VersionUtil.match(meta.apiVersion, apiVersionRule)) continue;

      result.push(meta);
    }

    return result;
  }
}
