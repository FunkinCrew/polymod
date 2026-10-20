import haxe.io.Bytes;
<<<<<<< Updated upstream
import polymod.hscript.ScriptRunner;
import polymod.hscript.ScriptRunner.Script;
import polymod.hscript._internal.Expr.Error;
import polymod.Polymod;
import polymod.fs.MemoryFileSystem;
=======
import polymod.Polymod;
import polymod.fs.MemoryFileSystem;
import polymod.hscript._internal.PolymodScriptClass;
import polymod.hscript.ScriptRunner;
import polymod.hscript.ScriptRunner.Script;
import polymod.hscript._internal.Expr.Error;
>>>>>>> Stashed changes
import tests.ScriptedStage;

class TestMain
{
  static var passed:Int = 0;
  static var failed:Array<String> = [];

  static function main():Void
  {
    run("expression precedence", testExpressionPrecedence);
    run("host context variables", testHostContextVariables);
    run("script functions", testScriptFunctions);
    run("closures", testClosures);
    run("control flow", testControlFlow);
    run("array indexing", testArrayIndexing);
    run("invalid syntax", testInvalidSyntax);
    run("script asset loading and cache", testScriptAssetLoading);
    run("HScriptedClass integration", testScriptedClass);

    Sys.println('$passed/${passed + failed.length} tests passed');

    if (failed.length > 0)
    {
      for (failure in failed)
      {
        Sys.println('FAIL: $failure');
      }
      Sys.exit(1);
    }
  }

  static function run(name:String, test:Void->Void):Void
  {
    try
    {
      test();
      passed++;
      Sys.println('PASS: $name');
    }
    catch (error:Dynamic)
    {
      var stack = haxe.CallStack.toString(haxe.CallStack.exceptionStack());
      failed.push('$name: ${Std.string(error)}\n$stack');
    }
  }

  static function testExpressionPrecedence():Void
  {
    assertEquals(7, executeFixture("precedence.hxs"));
  }

  static function testHostContextVariables():Void
  {
    var script = new Script("score * multiplier");
    script.set("score", 6);
    script.set("multiplier", 7);
<<<<<<< Updated upstream

=======
>>>>>>> Stashed changes
    assertEquals(42, script.execute().script_result);
  }

  static function testScriptFunctions():Void
  {
    var script = new Script(readFixture("functions.hxs"));
    script.set("input", 6);
    assertEquals(720, script.execute().script_result);
  }

  static function testClosures():Void
  {
    assertEquals(12, executeFixture("closures.hxs"));
  }

  static function testControlFlow():Void
  {
<<<<<<< Updated upstream
    assertEquals(18, executeFixture("control_flow.hxs"));
=======
    var scriptErrors:Array<String> = [];
    var previousErrorCallback = Polymod.onError;
    Polymod.onError = function(error) scriptErrors.push(error.message);
    var script = new Script(readFixture("control_flow.hxs"));
    var output:Dynamic = null;
    try
    {
      output = script.execute();
    }
    catch (error:Dynamic)
    {
      Polymod.onError = previousErrorCallback;
      throw error;
    }
    Polymod.onError = previousErrorCallback;
    assertEquals(18, output.script_result, scriptErrors.join("\n"));
>>>>>>> Stashed changes
  }

  static function testArrayIndexing():Void
  {
    assertEquals(7, executeFixture("array_indexing.hxs"));
  }

  static function testInvalidSyntax():Void
  {
    var threw = false;
    try
    {
      executeFixture("invalid_syntax.hxs");
    }
    catch (error:Error)
    {
      threw = true;
    }
<<<<<<< Updated upstream

=======
>>>>>>> Stashed changes
    assertTrue(threw, "Invalid script syntax should throw during parsing");
  }

  static function testScriptAssetLoading():Void
  {
    ScriptRunner.clearScripts();
<<<<<<< Updated upstream
    var loadCount:Int = 0;
    var assetExists:Bool = true;
=======
    var loadCount = 0;
    var assetExists = true;
>>>>>>> Stashed changes
    var assetHandler =
    {
      exists: function(path:String, library:Dynamic):Bool {
        return assetExists;
      },
      getText: function(path:String):String {
        loadCount++;
        return "40 + 2";
      }
    };

    var firstRunner = new ScriptRunner();
    var script = firstRunner.get("cached-test", assetHandler);
    assertTrue(script != null, "Existing script asset should load");
    if (script != null) assertEquals(42, script.execute().script_result);
    assertEquals(1, loadCount);

    var secondRunner = new ScriptRunner();
<<<<<<< Updated upstream
    var cachedScript = secondRunner.get("cached-test", null);
=======
    var cachedScript = secondRunner.get("cached-test");
>>>>>>> Stashed changes
    assertTrue(cachedScript != null, "Loaded scripts should be shared across runners");
    if (cachedScript != null) assertEquals(42, cachedScript.execute().script_result);
    assertEquals(1, loadCount);

    ScriptRunner.clearScripts();
    var reloadedScript = secondRunner.get("cached-test", assetHandler);
    assertTrue(reloadedScript != null, "Cleared scripts should load again");
    assertEquals(2, loadCount);

    ScriptRunner.clearScripts();
    assetExists = false;
    assertEquals(null, secondRunner.get("missing-test", assetHandler));
    assertEquals(2, loadCount);
    ScriptRunner.clearScripts();
  }

  static function testScriptedClass():Void
  {
    var fileSystem = new MemoryFileSystem({modRoot: "mods"});
    addModFile(fileSystem, "mods/script-tests/_polymod_meta.json",
<<<<<<< Updated upstream
      '{"title":"Script tests","description":"HScriptedClass test fixtures","author":"Polymod","api_version":"0.1.0","mod_version":"1.0.0"}');
    addModFile(fileSystem, "mods/script-tests/_polymod_icon.png", "");
    addFixture(fileSystem, "mods/script-tests/data/BasicStage.hxc", "BasicStage.hxc");
    addFixture(fileSystem, "mods/script-tests/data/AdvancedStage.hxc", "AdvancedStage.hxc");
    addFixture(fileSystem, "mods/script-tests/data/InvalidStage.hxc", "InvalidStage.hxc");

    var polymodErrors:Array<String> = [];
=======
      '{"title":"Script tests","description":"HScriptedClass regression fixtures","author":"Polymod","api_version":"0.1.0","mod_version":"1.0.0"}');
    addModFile(fileSystem, "mods/script-tests/_polymod_icon.png", "");
    addFixture(fileSystem, "mods/script-tests/data/scripts/BasicStage.hxc", "BasicStage.hxc");
    addFixture(fileSystem, "mods/script-tests/data/scripts/AdvancedStage.hxc", "AdvancedStage.hxc");
    addFixture(fileSystem, "mods/script-tests/data/scripts/InvalidStage.hxc", "InvalidStage.hxc");

    var errors:Array<String> = [];
>>>>>>> Stashed changes
    var previousErrorCallback = Polymod.onError;
    Polymod.init({
      modRoot: "mods",
      dirs: ["script-tests"],
      framework: CUSTOM,
      customBackend: tests.TestBackend,
      customFilesystem: fileSystem,
<<<<<<< Updated upstream
      useScriptedClasses: false,
      skipDependencyChecks: true,
      errorCallback: function(error) {
        if (error.severity == ERROR) polymodErrors.push(error.message);
      }
=======
      skipDependencyChecks: true,
      errorCallback: function(error) errors.push(error.message)
>>>>>>> Stashed changes
    });

    try
    {
      var registrations = Polymod.registerAllScriptClasses();
      var failedRegistrations = [for (path => success in registrations) if (!success) path];
      assertEquals(1, failedRegistrations.length);
<<<<<<< Updated upstream
      assertTrue(failedRegistrations[0].indexOf("InvalidStage.hxc") != -1, "Invalid class fixture should be reported as a failed registration");
      assertTrue(contains(polymodErrors, "InvalidStage.hxc"), "Parse errors should be reported to the Polymod callback");

      var scriptClasses = ScriptedStage.listScriptClasses();
      assertEquals(2, scriptClasses.length);
      assertTrue(scriptClasses.indexOf("tests.BasicStage") != -1, "Script class should be registered");
      assertTrue(scriptClasses.indexOf("tests.AdvancedStage") != -1, "Derived script class should be registered");

      var stage = ScriptedStage.scriptInit("tests.BasicStage", "test-stage");
      assertTrue(stage != null, "Script class should instantiate");
=======
      assertTrue(failedRegistrations[0].indexOf("InvalidStage.hxc") != -1, "Invalid fixture should fail registration");
      assertTrue(contains(errors, "InvalidStage.hxc"), "Parse errors should be reported");

      var classes = PolymodScriptClass.listScriptClasses();
      assertEquals(2, classes.length);
      assertTrue(classes.indexOf("tests.BasicStage") != -1, "Base scripted class should register");
      assertTrue(classes.indexOf("tests.AdvancedStage") != -1, "Derived scripted class should register");

      var stage = ScriptedStage.scriptInit("tests.BasicStage", "test-stage");
      assertTrue(stage != null, 'Script class should instantiate: ${errors.join("\n")}');
>>>>>>> Stashed changes
      if (stage == null) throw "Script class instantiation unexpectedly returned null";

      assertEquals("test-stage", stage.stageId);
      assertEquals("scripted", stage.name);
      assertEquals(6, stage.update(3));
      assertEquals(3, stage.count);
      assertEquals("tests.BasicStage", Reflect.callMethod(stage, Reflect.field(stage, "getScriptClassName"), []));

      var scriptCall = Reflect.field(stage, "scriptCall");
<<<<<<< Updated upstream
      assertTrue(Reflect.isFunction(scriptCall), "Generated scriptCall bridge should exist");
=======
      assertTrue(Reflect.isFunction(scriptCall), "scriptCall bridge should exist");
>>>>>>> Stashed changes
      assertEquals(7, Reflect.callMethod(stage, scriptCall, ["addScriptOnly", [2]]));

      var scriptGet = Reflect.field(stage, "scriptGet");
      var scriptSet = Reflect.field(stage, "scriptSet");
      var scriptHas = Reflect.field(stage, "scriptHas");
<<<<<<< Updated upstream
      assertTrue(Reflect.isFunction(scriptGet), "Generated scriptGet bridge should exist");
      assertTrue(Reflect.isFunction(scriptSet), "Generated scriptSet bridge should exist");
      assertTrue(Reflect.isFunction(scriptHas), "Generated scriptHas bridge should exist");
      assertEquals(true, Reflect.callMethod(stage, scriptHas, ["scriptValue"]));
      assertEquals(false, Reflect.callMethod(stage, scriptHas, ["missingField"]));
      assertEquals(7, Reflect.callMethod(stage, scriptGet, ["scriptValue"]));
=======
      assertTrue(Reflect.isFunction(scriptGet), "scriptGet bridge should exist");
      assertTrue(Reflect.isFunction(scriptSet), "scriptSet bridge should exist");
      assertTrue(Reflect.isFunction(scriptHas), "scriptHas bridge should exist");
      assertEquals(true, Reflect.callMethod(stage, scriptHas, ["scriptValue"]));
      assertEquals(false, Reflect.callMethod(stage, scriptHas, ["missingField"]));
      assertEquals(5, Reflect.callMethod(stage, scriptGet, ["scriptValue"]));
>>>>>>> Stashed changes
      Reflect.callMethod(stage, scriptSet, ["scriptValue", 20]);
      assertEquals(22, Reflect.callMethod(stage, scriptCall, ["addScriptOnly", [2]]));

      assertEquals(10, ScriptedStage.scriptStaticGet("tests.BasicStage", "staticValue"));
      assertEquals(true, ScriptedStage.scriptStaticHas("tests.BasicStage", "staticValue"));
      assertEquals(true, ScriptedStage.scriptStaticHasFunc("tests.BasicStage", "addStatic"));
      assertEquals(42, ScriptedStage.scriptStaticCall("tests.BasicStage", "addStatic", [2]));
      ScriptedStage.scriptStaticSet("tests.BasicStage", "staticValue", 20);
      assertEquals(20, ScriptedStage.scriptStaticGet("tests.BasicStage", "staticValue"));

      var advancedStage = ScriptedStage.scriptInit("tests.AdvancedStage", "advanced-stage");
<<<<<<< Updated upstream
      assertTrue(advancedStage != null, "Derived script class should instantiate");
      if (advancedStage != null)
      {
        assertEquals("advanced-stage", advancedStage.stageId);
        assertEquals("scripted", advancedStage.name);
        assertEquals(7, advancedStage.update(3));
        assertEquals(3, advancedStage.count);
        var inheritedScriptCall = Reflect.field(advancedStage, "scriptCall");
        assertEquals(7, Reflect.callMethod(advancedStage, inheritedScriptCall, ["addScriptOnly", [2]]));
=======
      assertTrue(advancedStage != null, "Derived scripted class should instantiate");
      if (advancedStage != null)
      {
        assertEquals("advanced-stage", advancedStage.stageId);
        assertEquals("advanced", advancedStage.name);
        assertEquals(7, advancedStage.update(3));
        assertEquals(3, advancedStage.count);
>>>>>>> Stashed changes
      }

      var missingStage = ScriptedStage.scriptInit("tests.DoesNotExist", "missing-stage");
      assertEquals(null, missingStage);
<<<<<<< Updated upstream
      assertTrue(contains(polymodErrors, "tests.DoesNotExist"), "Failed instantiation should be reported to the Polymod callback");
      assertEquals(2, polymodErrors.length);

      Polymod.clearScripts();
      assertEquals(0, ScriptedStage.listScriptClasses().length);
      Polymod.registerAllScriptClasses();
      assertTrue(ScriptedStage.listScriptClasses().indexOf("tests.BasicStage") != -1, "Script classes should register again after clearing");
      Polymod.clearScripts();
      Polymod.onError = previousErrorCallback;
=======
      assertTrue(contains(errors, "tests.DoesNotExist"), "Failed instantiation should be reported");

      Polymod.clearScripts();
      assertEquals(0, PolymodScriptClass.listScriptClasses().length);
      Polymod.registerAllScriptClasses();
      assertTrue(PolymodScriptClass.listScriptClasses().indexOf("tests.BasicStage") != -1, "Scripts should register after clearing");
>>>>>>> Stashed changes
    }
    catch (error:Dynamic)
    {
      Polymod.clearScripts();
      Polymod.onError = previousErrorCallback;
      throw error;
    }
<<<<<<< Updated upstream
=======

    Polymod.clearScripts();
    Polymod.onError = previousErrorCallback;
>>>>>>> Stashed changes
  }

  static function addModFile(fileSystem:MemoryFileSystem, path:String, content:String):Void
  {
    fileSystem.addFileBytes(path, Bytes.ofString(content));
  }

  static function execute(code:String):Dynamic
  {
    return new Script(code).execute().script_result;
  }

  static function executeFixture(name:String):Dynamic
  {
    return execute(readFixture(name));
  }

  static function readFixture(name:String):String
  {
<<<<<<< Updated upstream
    return sys.io.File.getContent('../tests/fixtures/hscript/$name');
=======
    return sys.io.File.getContent('fixtures/hscript/$name');
>>>>>>> Stashed changes
  }

  static function addFixture(fileSystem:MemoryFileSystem, path:String, fixtureName:String):Void
  {
    addModFile(fileSystem, path, readFixture(fixtureName));
  }

  static function contains(values:Array<String>, text:String):Bool
  {
    for (value in values)
    {
      if (value.indexOf(text) != -1) return true;
    }
    return false;
  }

<<<<<<< Updated upstream
  static function assertEquals(expected:Dynamic, actual:Dynamic):Void
  {
    if (expected != actual)
    {
      throw 'Expected ${Std.string(expected)}, got ${Std.string(actual)}';
=======
  static function assertEquals(expected:Dynamic, actual:Dynamic, ?message:String):Void
  {
    if (expected != actual)
    {
      var detail = (message == null || message.length == 0) ? "" : '\n$message';
      throw 'Expected ${Std.string(expected)}, got ${Std.string(actual)}$detail';
>>>>>>> Stashed changes
    }
  }

  static function assertTrue(value:Bool, message:String):Void
  {
<<<<<<< Updated upstream
    if (!value)
    {
      throw message;
    }
=======
    if (!value) throw message;
>>>>>>> Stashed changes
  }
}
