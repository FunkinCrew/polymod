---
title: Scripted Classes
---
{% include toc.html %}

# Scripted Classes

See the `openfl_hscript_class` sample for an example of this in action.

Scripted classes are classes whose behavior is defined in a script, rather than in source code. They are parsed and registered at runtime, can be instantiated, and otherwise behave almost identically to normal classes.

This is an incredibly powerful feature for quickly prototyping and testing new features, as well as for providing robust and intuitive modding support to your application.

## Creating a Scripted Class

1. Create a class like this in your project. In our example, we will create a class called ScriptedStage which extends Stage; this will allow scripts to create classes which extend `Stage`.

```haxe
@:hscriptClass
class ScriptedStage extends Stage implements HScriptedClass {}
```

Note that the body of the class is COMPLETELY EMPTY. This is because the contents are populated at compile time using a macro.

2. Initialize Polymod as normal.
3. Call `ScriptedStage.listScriptClasses()` to get a list of all the classes that have been registered.
  - These include any classes defined in script files in your `assets` folder that have the correct file extension (defaulting to `.hxc`).
  - You can add additional classes or override existing classes by including them in Polymod mods.
4. Create a script that defines a class, and add it to the `assets` folder of your project (or to a mod folder to be loaded by Polymod).
5. Call `ScriptedStage.init(stageClassName, ...args)` to instantiate an object of the scripted class.
  - The `stageClassName` is the name of the class you want to instantiate. It should be one of the classes returned by `ScriptedStage.listScriptClasses()`.
  - The `init()` function will also require any constructor arguments that the superclass needs to be instantiated, so they can be passed to the scripted class.
  - The return value of `init()` will be of the type `ScriptedStage`. It has full support for compile completion and can be passed as an argument to functions which expect a `Stage` object.

## Example of a Scripted Class

Here is an example of what a user-provided scripted class may look like:

```haxe
// Make sure to import the target class...
import stage.Stage;
// ...and any modules you want to use.
import openfl.utils.Assets;
import openfl.display.Bitmap;

// Extend the Stage class, not the ScriptedStage class.
class BasicStage extends Stage {
  // You can define a constructor which utilizes the same arguments as the superclass,
  // or fewer arguments if you provide them yourself..
  public function new() {
    super('basic');
    // You can get and set fields of the stage and the program can access those properties.
    stageName = 'Basic Stage';
  }

  // You can define override functions which replace the superclass's behavior completely.
  public override function create():Void {
    // You can also call the superclass function.
    super.create();

    // You can call static functions of modules you import, or instantiate classes from those modules.
    var landscapeBg = new Bitmap(Assets.getBitmapData('img/stage/landscape.png'));
    // You have full access to any properties and methods of objects you instantiated,
    // as though you were writing source code directly!
    landscapeBg.x = 0;
    landscapeBg.y = 0;
    landscapeBg.width = 480;
    landscapeBg.height = 360;

    this.addChild(landscapeBg);
  }

  // You can also define new functions which can be called from within the script,
  // and variables which those functions can use.
  var abc:Int = 123;
  function coolStuff() {
    abc += 10;

    if (abc > 1000) {
      abc = 20;
    }

    trace('Value is: ' + abc);
  }
}
```

## Abilities and Limitations of Scripted Classes

There are many things which you can do within a scripted class, including but not limited to:

* Override the constructor (using `public function new() { ... }`)
* Define new fields and functions and call them from other functions.
* Modify public or private values of the superclass, and call superclass functions.
* Override existing functions of the class to replace (or extend) functionality.
* Import modules and call static functions or instantiate objects (like `import flixel.FlxG` or `import flixel.FlxSprite`)

There are some things to watch out for though:

* You can't override `static` functions from a script.
  - This is because the scripted class needs to be instantiated in order to have something to redirect function calls to.
* You can't override a function which uses a private class as an argument.
  - This cannot be done in Haxe either. This is because the private class cannot be accessed outside the module, even by macros.
* You can't override inline functions.
  - This cannot be done in Haxe either. This is because each call to the function is replaced with the function body at compile time.
  - Note that this may apply for functions which are not inline, if a child of the class that defines it overrides that function with an inline one.
* You can't override functions which use the `@:generic` annotation.
  - This cannot be done in Haxe either. This is because the `@:generic` annotation is actually syntax sugar that, at compile time, creates a
  separate function for each type it is used with.
* You can't override functions which use (as an argument or return value) a type parameter under more than one layer of nesting.
  - Example: `Foo<Bar<T>>`.
  - Doing so will throw an error while compiling, that looks like `Type not found: T`.
  - This issue exists because type parameters are not being parsed fully recursively right now. Make a GitHub issue explaining your use case if you need this fixed.
* You can't use string interpolation within a script.
  - For example, `trace('Value is ${abc}')` will literally print `Value is ${abc}` instead of `Value is 123`.
  - This is because implementing string interpolation would drastically complicate the script parser.
  - Thankfully, you can still use string concatenation, for example, `trace('Value is ' + abc)`.
* You can't define `final` variables within a script.
  - Just don't change the variable.
