# Changelog
All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

# [2.0.0] - 2026-??-??
## Added
- You can now declare and access static variables and functions of scripted classes, even from other scripts.
- You can directly instantiate a scripted class by name from another script (`new TestClass()` instead of `ScriptedBar.init('TestClass', [])`).
- Scripted classes can now extend an aliased class.
  - For example, if you `import foo.Bar as Baz;`, you can do `class TestClass extends Baz`.
- You can now use the `package` keyword in a scripted class to specify a package name for a scripted class, preventing the `SCRIPTED_CLASS_ALREADY_REGISTERED` warning.
- Added the new function `Polymod.clearAllScriptClasses()` to clear all registered scripted class descriptors.
- Added new generated function to classes implementing `HScriptedClass`:
  - `scriptStaticCall` to invoke a static function on a scripted class.
  - `scriptStaticGet` to retrieve a static variable on a scripted class.
  - `scriptStaticSet` to assign a static variable on a scripted class.
- Added the ability to import and access static fields and methods of `abstract`s.
- Added the ability to import and access values of `enum abstract`s.
- Added the ability to import and access `typedef`s (they will be aliased to the appropriate type).
- Added the new `scriptHas` function to scripted class implementations to check for field existance.
- Added support for import renaming using the `as` keyword. () - by @KoloInDaCrib in [#190]
- Added support for properties, with getters and setters. () - by @KoloInDaCrib in [#191]
  - When using `var myValue(get, set):Int;`, accessing and assigning `myValue` will instead call `get_myValue` and `set_myValue` respectively.
- Added support for scripted `enum` values, accessible from other scripts. () - by @lemz1 in [#192]
- Added support for the `final` keyword. () - by @KoloInDaCrib in [#193]
- Added support for scripted classes to import other scripted classes that are in a different package. Scripted classes with the same package will be automatically imported. () - by @lemz1 in [#194]
- Added the ability to blacklist static or instance fields or methods. () - by @KoloInDaCrib in [#216]
  - Use `Polymod.blacklistStaticFields(Class, Array<String>)` to blacklist static variables or functions from being accessed by scripts.
  - Use `Polymod.blacklistInstanceFields(Class, Array<String>)` to blacklist instance variables or functions from being accessed by scripts.
  - When using `final myValue = 12;`, attempting to reassign the value throws an error.
- Added support for static extensions via the `using` keyword. () - by @KoloInDaCrib in [#218]
- Added support for scripted classes to extend other scripted classes. () - by @NotHyper-474 in [#285]
- Added support for typedef extensions, and optional fields in typedefs. () - by @Starexify in [#290]
- Added support for string interpolation (i.e. you can now use `'${value}'` instead of string concatenation). () - by @NotHyper-474 in [#292]
## Changed
- Polymod's scripting systems now utilize an internal, built-in fork of HScript, rather than a separate repository. This allows for new features and support to be added (such as new keywords and syntax) without having to require a specific non-standard version of the Haxelib.
- Added improved error messages for the following cases:
  - Attempting to access `this` from a scripted static function.
  - Attempting to access a blacklisted static or instance field.
  - Attempting to declare a field with a duplicate name (previously, this silently replaced the field, leading to weird bugs!). () - by @KoloInDaCrib in [#261]
- Cleaned up a lot of existing error messages to be more clear what they're doing.
- Added a new CheckStyle config, and performed a lot of code cleanup across the project.
- If a mod is skipped because its API version is invalid, it will now output a `MOD_API_VERSION_MISMATCH` warning.
- File accesses are now case insensitive by default, to create similar behavior between Linux and Windows. Use `PolymodConfig.caseInsensitiveZipLoading` to configure. () - by @mikolka9144 in [#212]
  - Functionality also implemented for the ZIPFileSystem. () - by @NotHyper-474 in [#204]
- Polymod will automatically clear any cached scripts before loading them again. () - by @KoloInDaCrib in [#247]
- Function calls now support an arbitrary number of arguments, up from eight. () - by @NotHyper-474 in [#278]
- Scripted classes no longer have to extend anything (a scripted class that has no superclass can only be instantiated from other scripts). () - by @NotHyper-474 in [#280]
- `interface`s and uses of `implements` now get properly parsed instead of throwing an error (they aren't enforced right now, though) () - by @Starexify in [#284]
- The `init` function of scripted class implementations has been renamed to `scriptInit`; this is a breaking change but should be an easy rename. () - by @NotHyper-474 in [#286]
  - This PR also fixes an issue where constructor arguments wouldn't be parsed correctly.
## Fixed
- Fixed a Null Object Reference error that could occur if a scripted class attempts to extend a superclass which hasn't been imported.
- Optimized the `HScriptedClass` macro to no longer require reflection when the script does not override the function being called.
- When instantiating a `Map` or `Array`, the type of the variable will sometimes be parsed to ensure the correct underlying type is created.
  - For example, `var myValue:Map<String, Dynamic> = [];` used to sometimes instantiate an Array value, causing errors.
- Refactored and cleaned up asset exclusion.
- Fixed issues with asset retrieval through Lime on HTML5.
- Fixed the `list()` function implementation to make it more consistent with Lime's behavior.
- Fixed an issue where attempting to list assets from a specific library would display all assets from all libraries instead.
- Resolve a build error `Type not found: T` caused by not properly deparameterizing scripted class types. () - by @Geokureli in [#178]
- Fixed an issue where try/catch blocks would prevent the rest of the function from being called properly. () - by @NotHyper-474 in [#199]
- `PolymodScriptClass.className` now returns a properly formatted value. () - by @cyn0x8 in [#202]
- Fix an issue where `DefineUtil.getDefineBool` would always return false, even if a different default value was provided. () - by @NotHyper-474 in [#208]
- Fixed an issue where some expressions would be evaluated twice, causing a deranged context loss error. () - by @NotHyper-474 in [#234]
- Fixed an issue where static variables with no expression would throw a Null Object Reference. () - by @NotHyper-474 in [#239]
- Fixed an issue where `Array.remove()` could not be called on HTML5. () - by @KoloInDaCrib in [#251]
- Fixed an issue where local variables would still be in scope in static functions. () - by @NotHyper-474 in [#281]
- Fixed an issue where static extensions couldn't be used in static functions. () - by @NotHyper-474 in [#282]
- Fixed an issue where the `is` keyword had the wrong operator priority. () - by @Starexify in [#290]
- Fixed an issue where enum constructors couldn't be called with multiple arguments. () - by @Starexify in [#296]

# [1.8.0] - 2024-07-26
The version is the result of resolving practical needs that arose from using Polymod with [Friday Night Funkin'](https://github.com/FunkinCrew/Funkin) over the past year and a half!
## Added
- Added the config option `frameworkParams.coreAssetRedirect` which lets you use another directory as your primary `assets/` folder.
  - This is useful if you are hot reloading scripts or other data files!
- Added the `loadScriptsAsync` parameter to `Polymod.init()` to load scripted classes asynchronously.
- Reworked `_append` and `_merge` functionality for JSON.
  - `_append` now adds the keys of the provided JSON to the target JSON.
  - `_merge` now utilizes a [JSONPatch](https://jsonpatch.com/) file to modify the target JSON with operations.
    - This implementation of JSONPatch has been modified to allow for [JSONPath](https://goessner.net/articles/JsonPath/) strings in the `path` argument.
## Changed
- Replaced several instances of the deprecated `@:enum` syntax (via @MAJigsaw77)
- Improved image caching on HTML5 builds.
- Reimplement the `loadBytes` function so that it properly loads the files's contents asynchronously.
  - Also reimplemented `loadImage` and `loadText` to be properly asynchronous.
- Made improvements to error handling for script parsing.
- Greatly improved the speed of Lime's `Assets.list()` function.
- Added proper handling for calls to `throw` in scripts.
- Fixed an issue when using HScript 2.5.0.
- Improve parsing of scripted superclass types.
- Improve error handling when a function called by a script throws an uncaught exception.
## Fixed
- Fix an issue where variables may not resolve properly when assigned to `null`.
- Fixed an issue where scripts could not access or import enums.
- Fixed a build issue with the HashLink library.
- Fixed an issue where Polymod's Lime backend would destroy the underlying library's cached assets.
- Fixed an issue where invalid `coreAssetRedirect` paths would crash the game.
- Fixed an issue where `coreAssetRedirect` wouldn't allow accessing files from the default library.
- Fixed an issue where Polymod would fail to build if HScript wasn't installed (via @MAJigsaw77)
- Fixed an issue with a null object reference in the script parser (via @AltronMaxX)
- Fixed an issue with loading custom fonts (via @gamerbross)

## [1.7.0] - 2023-01-16
This version has been postposed a while, but adds several powerful features. A dependency system, support for zipped mods (on both desktop and HTML5!), reworks to versioning functions, and more.
## Added
- Added the `dependencies` key to the ModMetadata format.
  - Example: `{"modA": "1.0.0", "modB": "3.*", "modC": "1.9.0 - 2.3.0"}`
    - Add an object of key/value pairs to your `_polymod_meta.json` file, where the key is the mod ID and the value is the version rule.
    - Version rules can match any of those seen in [node-semver](https://github.com/npm/node-semver).
  - Mods provided in the dependency list must be loaded in order for this mod to be loaded.
    - The provided mod list will be reordered to account for dependencies, as needed, and maintaining order otherwise.
    - Missing dependencies, mismatched dependency versions, or cyclical dependencies will result in an error. See `skipDependencyErrors` for more info.
- Added the `optionalDependencies` key to the ModMetadata format.
  - Mods provided in the optional dependencies list will reorder the dependency list, but will not cause dependency errors if absent.
- Added the `skipDependencyChecks` parameter to `Polymod.init()`.
  - Defaults to `false`.
  - Setting this option to `true` will skip checks for the presence of mandatory dependencies, and prevent reordering the mod load list.
  - Enabling this option is NOT recommended, since it may break mods which rely on their dependencies.
- Added the new `ZipFileSystem`.
  - Enable it with `Polymod.init({customFilesystem: polymod.fs.ZipFileSystem})`.
  - On desktop platforms, ZipFileSystem automatically behaves like SysFileSystem with the additional capability of loading mods from ZIP files (compressed or uncompressed) as though they were folders instead.
  - On HTML5 builds, ZipFileSystem will instead act like a MemoryFileSystem which can load a mod when provided the byte data of a ZIP file.
    - After loading mods, you may need to wait a short time before reloading any images. This is because the browser must asynchronously preload the image data before it can be provided to Haxe.
- Added a convenience functions to handle loading and unloading of mods at runtime.
  - `loadOnlyMods()` loads a given set of mods, by re-initializing the framework with the appropriate mods enabled.
    - This is as opposed to `loadMods()`, which appends to the mod list rather than setting it.
  - Note you may need to call `clearCache()` depending on your framework and your app's current state.
- Added import aliasing and blacklist system for scripted classes.
  - Call `Polymod.addImportAlias('full.class.Path', TargetClass)` to replace any instances of that import with the target class.
  - Call `Polymod.removeImportAlias('full.class.Path')` to remove a previously assigned import alias.
  - Call `Polymod.blacklistImport('full.class.Path')` to throw an error whenever a scripted class attempts to import the chosen module.
- `loadMod()`, `unloadMod()`, `loadMods()`, and `unloadMods()` now return an array of ModMetadata for each of the mods that are loaded after the operation.
- Added the `skipDependencyErrors` parameter to `Polymod.init()`.
  - Defaults to `false`.
  - While this option is `true`, any dependency issues will cause a warning to be reported, and Polymod will skip the problematic mods and load the rest.
  - While this option is `false`, any dependency issues (missing dependencies, mismatched versions, or cyclical dependencies) will cause an error to be reported, and Polymod will initialize with NO mods loaded.
## Changed
- `thx.semver` has been added as a mandatory dependency Haxelib, replacing the existing Semantic Version code.
  - This provides full support for the features of [node-semver](https://github.com/npm/node-semver) when specifying version rules.
- Updated `openfl` sample to showcase dependency features.
  - `mod2` now has a mandatory dependency on `mod1`.
  - Added a button to showcase the difference when `skipDependencyErrors` changes.
- `Polymod.scan()` has been refactored.
  - `scan()` now has two modes; the first, used when a parameter object is provided, uses the modRoot and fileSystem given.
    - This will supercede the modRoot and fileSystem that was used for `Polymod.init()`.
  - The second mode, used when a parameter object is not provided, utilizes the filesystem created in `Polymod.init()`.
    - If you want to scan the modlist before loading mods, you can initialize Polymod with an empty modlist before scanning, then use `loadMods()` to reinitialize with additional mods.
    - If no parameters are provided but `init()` has not been called yet, an error will be thrown.
- Updated samples to use the `hmm` dependency management tool.
  - Install `hmm` via Haxelib, then run `hmm install` in a sample project to install project-local copies of all necessary dependencies with the correct version.
- `IFileSystem.scanMods()` has been refactored.
  - `scanMods` now takes an optional `apiVersionRule` parameter, and returns `Array<ModMetadata>`.
  - `scanMods` will now parse and return the mod metadata, rather than returning an array of mod IDs.
  - `scanMods` will now optionally filter to only mods which match the provided `apiVersionRule` (pass `null` to skip this).
- Reworked error codes for script-related exceptions and warnings.
## Removed
- Several deprecated and obsolete options and variables related to this update's changes have been removed.
  - Removed the `SemanticVersion` utility class.
  - Removed the `apiVersionMatch` option from PolymodConfig.
  - Removed the `POLYMOD_API_VERSION_MATCH` define.
  - Removed the `modVersion` parameter of `Polymod.init`
## Fixed
- Fixed several compilation issues with `hscriptPos` disabled.


## [1.6.0] - 2022-07-28
Not much in the way of new features for end users here, but some refactors resulted in breaking changes so this is labelled as a minor version rather than a bugfix version.
## Added
- Scripted classes now allow functions with up to 8 arguments, up from 4.
- Added the new `ErrorEx` and `PolymodPrinterEx` classes for more detailed and extensible error handling.
  - Added new error message when attempting to call a custom function on a scripted class improperly.
  - Added new error message when attempting to retrieve a custom variable on a scripted class improperly.
  - Added new error message when attempting to assign a custom variable on a scripted class improperly.
- New static function `Polymod.clearScripts()` clears all scripted classes and scripted functions. Useful for cleaning up before a script reload.
## Changed
- HScriptable has been split into two interfaces: HScriptable and HScriptedClass.
  - HScriptable is now used only for `@:hscript` annotations on scripted functions, and HScriptedClass is used for `@:hscriptClass` annotations to generate scripted classes.
  - These two interfaces are considered mutually exclusive, and only one should be used on a given class.
- Moved internal HScript classes to an `_internal` package.
## Fixed
- Refactored HScript-related macros for improved maintainability.
- Cached `Reflect.fields()` queries on PolymodScriptedClass proxies to improve performance.
- Fixed an issue where attempting to annotate `@:hscriptClass` on a class which utilized variables whose type is a function.
  - This now allows for FlxUIState to be scripted.
- Fixed an issue where the right-hand side of a variable assignment was being executed twice.
- Cleanup extraneous compile-time logging.


## [1.5.4] - 2022-07-16
This patch includes several major bug fixes and convenience improvements.
## Added
- Added a new error message which occurs when a script cannot locate a module you try to import.
  - If you encounter this message, make sure you typed the package name correctly, and make sure the module is exempt from Haxe's [Dead Code Elimination](https://haxe.org/manual/cr-dce.html) process.
## Fixed
- Fixed an issue where attempting to annotate `@:hscriptClass` on a class which utilized nested type parameters would fail to compile.
  - This now allows for FlxState and FlxSubState to be scripted, among other things.
- Fixed an issue where, if a function in a scripted class calls another function within that class, the local variable scope is destroyed.
- Fixed a compilation issue which occurs when `hscriptPos` is not enabled (`hscript.Error has no field line`)
  - Line numbers will now display as `#???` by default. To enable line numbers on script errors (highly recommended), add `<haxedef name="hscriptPos" value="true" />` to your `project.xml` file.
## Known Issues
- A build error `hscript.Interp has no field setVar` may occur. If this happens, make sure you are using the latest version of HScript, version 2.5.0.


## [1.5.3] - 2022-05-18
Lots of tiny bug fixes and several new utilities. Overall a better experience if you're debugging a tricky script.
## Added
- Added the following utility functions to scripted classes.
  - `scriptCall(methodName, [...args])`: Calls a given function from a scripted class with the given arguments.
  - `scriptGet(fieldName)`: Gets the value of a given field from a scripted class.
  - `scriptSet(fieldName, value)`: Sets the value of a given field in a scripted class.
  - Note that these functions are only necessary when the field is defined on the scripted class itself. Functions and fields defined on the superclass will be accessible automatically.
- Added the `Polymod.reload()` function.
  - This function will reload Polymod, with the same modlist and parameters as the last time you initialized.
- Added the `iconPath` attribute to the ModMetadata class.
  - This provides the full path of the mod's icon, if available.
- Added a stub backend for the Ceramic framework.
## Changed
- Drastically improved error logging for scripted classes, with the new `SCRIPT_PARSE_ERROR` and `SCRIPT_EXCEPTION` error codes.
- Scripted functions now use the scripted class interpreter; this provides improved error logging in some cases.
## Fixed
- Improved error handling for certain scripts.
- Fixed a bug where Polymod would mutate the mod directory list (fixes a bug with `loadMod()` and `unloadMod()`).
- Improved compatibility with build macros, especially when building for HTML5.
- Fixed a compatibility issue with older versions of Haxe (syntax error in PolymodFileSystem).
# Known Issues
- Passing a function of a scripted class as an argument (for example, when used as a sort function) clears all the variables in the local scope.
  - As a workaround, define and use an anonymous function instead.


## [1.5.2] - 2022-03-01
A small bug fix update.
### Fixed
- Fixed a bug where scripted classes would fail while attempting to import and use an enum.
- Standardized code style across several files.


## [1.5.1] - 2022-02-25
A large number of bug fixes for scripted classes.
### Changed
- The `dirs` parameter of Polymod is now optional. This is useful if Polymod is only used for localization.
- Reduced the amount of compile-time logging created by scripted classes.
### Removed
- Removed an unused PolymodErrorCode.
### Fixed
- Fixed a bug where scripted classes would fail to build when encountering fields marked with `@:generic`.
  - These fields are now skipped completely (and cannot be overridden by scripted classes).
- Fixed a bug where scripted classes would fail to build when encountering arguments or return types using a type parameter.
- Fixed a bug where scripted classes would override functions with the return type `Void` with a function that attempts to return `null`.
- Fixed a bug where scripted classes did not properly support overriding functions with optional arguments.
- Fixed a bug related to using macros while using the FlixelBackend.
- Fixed a bug where the library would not build without the `hscript-ex` library installed (the library is no longer required).


## [1.5.0] - 2022-02-22
### Added
- Added new functionality which allows for parsing and instantiation of classes defined in scripts.
  - These scripted classes can extend existing classes or even other scripted classes.
  - See [Scripted Classes](https://polymod.io/docs/scripted-classes) for more information.
- Incorporated the functionality of `hscript-ex` into Polymod.
### Removed
- The `POLYMOD_USE_HSCRIPTEX` flag has been made redundant. A fork of `hscript-ex` is now bundled into Polymod.


## [1.4.3] - 2022-02-18
### Fixed
- OpenFLBackend no longer breaks when you are using the main version of OpenFL.


## [1.4.2] - 2022-02-06
Version 1.4.2 includes a large number of bug fixes and tweaks to improve reliability.
### Added
- Added the optional `assetsPrefix` option to the `frameworkParams`.
  - Use this if your project's `assets/` folder uses a different name.
- Added a new Flixel sample project which ensures cache clearing when reloading mods.
- Added several convenience functions to handle loading and unloading of mods at runtime.
  - These convenience functions perform the proper steps to reload Polymod. Note you may need to call `clearCache()` depending on your framework and your app's current state.
  - `loadMod()` and `loadMods()` enables an individual (or multiple) mods, by re-initializing the framework with the appropriate mods enabled.
  - `unloadMod()` and `unloadMods()` disables an individual (or multiple) mods, by re-initializing the framework with the appropriate mods disabled.
  - `unloadAllMods()` disables all mods, by re-initializing the framework with no mods enabled.
    - Localized asset replacements will still work, but no user-defined mods will be loaded.
  - `disable()` fully disables Polymod, destroying the asset handler.
    - Neither user-defined mods nor localized asset replacements will work until you call `init()` again.
### Changed
- Added additional testing to the `openfl_firetongue` sample.
  - `mod5` now loads a different image depending on the selected locale.
- Performed many internal code style improvements (please use template strings)
- Improvements to documentation
  - Renamed and cleaned up the `Localization` page (formerly known as `Translation`)
  - Added a section to the `Localization` page describing its partial support (only available in Lime/OpenFL/Flixel as of this update).
### Fixed
- Fixed several issues that stopped the Flixel backend from working. It's finally actually working I swear check the sample.
- Fixed several bugs related to asset retrieval.
- Fixed a bug where debug printing would sometimes not enable.
- Fixed a bug where the project would not build if Firetongue was not installed.
- Fixed several issues with the HEAPS sample (seriously was it ever working?).
### Removed
- Temporarily disabled the `HScript-EX` feature.
  - Additional work to implement the scripted class functionality is required.
- REMOVED the existing modpack functionality (based on the `_polymod_pack.txt` file).
  - This will be replaced with a revamped system for modpacks in the future.
- REMOVED the documentation associated with modpacks.
### Known Issues
- The `openfl_firetongue` sample mod which implements an additional language is currently broken.


## [1.4.1] - 2022-01-20
### Changed
- Added additional codedocs for each error code.
### Fixed
- Fixed a compile bug for Flixel backends.
- Fixed a bug where embedded default assets would not load properly.


## [1.4.0] - 2022-01-17
This release marks the migration of the project documentation to [polymod.io](https://polymod.io), a new website for the project hosted by Github Pages.
### Added
- Added a new Github Pages site for documentation.
  - This page is automatically generated using the `master` branch, with the Jekyll project located at `/docs/`.
- Added a new logo for the library.
- Added FireTongue integration for asset localization.
  - This incredibly powerful feature allows you to pass a FireTongue instance to Polymod, which will allow loading assets from the locale folder. This allows for locales to override not just strings, but also data files and even audio/visual assets, just by using your framework's asset management system.
  - For example, when the locale is set to `en-US`, `openfl.Assets.getImage("images/billboard.png")` can return a default image, or a custom image when the locale is `pt-BR`.
  - This not only allows developers to translate audio or graphics with almost no effort, but also allows mods to translate audio and graphics of the base game, or EVEN OTHER MODS.
  - With the existing features of Polymod, mods should also be able to reasonably append new locales to the manifest, without requiring the developers to modify the base game.
- Added a new compile definition: `POLYMOD_API_VERSION_MATCH`
  - This allows you to define how strictly mods must match when loading.
  - `NONE` matches any version, `MATCH_MAJOR` requires the major version to match, `MATCH_MINOR` requires the minor version to match, and `MATCH_PATCH` requires the patch version to match.
  - This defaults to `MATCH_PATCH` to prevent breaking changes, but you should probably update this to at least `MATCH_MINOR` to reduce strain on your mod developers.
- Added a new compile definition: `POLYMOD_USE_HSCRIPTEX`
  - This *EXPERIMENTAL* option allows you to replace the default hscript parser with [hscript-ex](https://github.com/ianharrigan/hscript-ex), which provides support for classes.
- Added the new `FlixelBackend` backend.
  - This backend provides additional HaxeFlixel-specific fixes to the OpenFLBackend.
  - Added `FLIXEL` as a Framework value to manually select this backend.
  - Updated the framework detector to use the `FlixelBackend` over the `OpenFLBackend` when HaxeFlixel is being used.
- Added a new function, `Polymod.clearCache()`, which triggers the backend to clear any cached assets from memory.
  - This is useful if you want to ensure assets reload after a modlist or locale change.
- Improved the Mod Metadata format with new and useful attributes.
  - These changes are backwards compatible; new fields are optional, and changed fields still support the existing format.
  - Added the `homepage` attribute to allow mods to provide a URL.
  - Added the `contributors` attribute to provide a list of contributors.
    - Each contributor is an object with the following keys: `name`, `role`, `email`, `url`.
    - New applications are encouraged to use this attribute over the `author` attribute where possible.
- Added a new sample demonstrating usage with FireTongue.
### Changed
- Deprecated the `author` attribute in favor of the `contributors` attribute.
  - The `author` attribute is still supported for backwards compatibility.
  - Retrieving `author` when `contributors` is defined will return the name of the first contributor.
- Improved compile-time error output for when `@:hscript({context})` receives an invalid value.
- Changed the `openfl_hscript` sample to demonstrate retrieving and calling one or more functions from a single script file.
- Cleaned up samples by removing unnecessary project configuration.
### Fixed
- Fixed a crash bug which occured when LimeBackend was used without a `frameworkParams` argument.
- Fixed a bug where `MOD_LOAD_PREPARE` and `MOD_LOAD_DONE` were showing as errors rather than notices.


## [1.3.1] - 2021-12-05
### New Contributors
- @Cheemsandfriends made their first contribution in https://github.com/larsiusprime/polymod/pull/75
### Added
- All compile defines can now also be edited at runtime.
  - For example, you can enable Debug logging in code by using `PolymodConfig.debug = true;`
  - If you use these to set asset library locations, etc., be sure to set them before instantiating any classes which utilize script files.
- Added a config option to customize the mod append folder.
  - Modify this option by adding `POLYMOD_APPEND_FOLDER` as a compile define, or by setting `PolymodConfig.appendFolder` in your code.
  - Defaults to `_append` for backwards compatibility.
- Added a config option to customize the mod merge folder.
  - Modify this option by adding `POLYMOD_MERGE_FOLDER` as a compile define, or by setting `PolymodConfig.mergeFolder` in your code.
  - Defaults to `_merge` for backwards compatibility.
- Added a config option to customize the mod metadata file.
  - Modify this option by adding `POLYMOD_MOD_METADATA_FILE` as a compile define, or by setting `PolymodConfig.modMetadataFile` in your code.
  - Defaults to `_polymod_meta.json` for backwards compatibility.
- Added a config option to customize the mod icon file.
  - Modify this option by adding `POLYMOD_MOD_ICON_FILE` as a compile define, or by setting `PolymodConfig.modIconFile` in your code.
  - Defaults to `_polymod_icon.png` for backwards compatibility.
- Added a config option to customize the mod pack definition file.
  - Modify this option by adding `POLYMOD_MOD_PACK_FILE` as a compile define, or by setting `PolymodConfig.modPackFile` in your code.
  - Defaults to `_polymod_pack.txt` for backwards compatibility.
- Added a config option to customize the ignore list for Polymod mod files.
  - Modify this option by adding `POLYMOD_MOD_IGNORE` as a compile define (use a comma separated list), or by setting `PolymodConfig.modIgnoreFiles` in your code (use an `Array<String>`).
  - Defaults to `LICENSE.txt,ASSET_LICENSE.txt,CODE_LICENSE.txt` for backwards compatibility.
- Added `optional` as an `@:hscript` parameter.
  - This suppresses the error thrown when a script file is missing.
### Changed
- Missing scripts are now handled gracefully rather than throwing an unhandled missing asset exception.
  - Added a debug print call when the script is missing but `optional` is set to `true`.
### Fixed
- Fixed a bug where scripted function that define a `pathName` function fail to retrieve the script.
- Fixed compilation errors when using the HEAPS backend.
  - The HEAPS sample now compiles and runs without errors.
- Fixed a deprecation warning in the CSV.hx file.


## [1.3.0] - 2021-11-18
This release marks the transition to [Eric Myllyoja](https://github.com/MasterEric) as the lead maintainer for the repository.
This release is backwards compatible with 1.0.0 as no breaking changes have been made.
### Added
- Added the `NodeFileSystem` class and `OpenFLWithNodeBackend`, for use with projects built in HTML5 for use with Electron.
  - Provided by [TamarCurry](https://github.com/MasterEric/polymod/pull/35).
- The `@:hscript` annotation can now be defined on classes and interfaces.
  - Defining a `@:hscript` annotation on a class or interface will add the constants provided to them to the context of any script functions of any of that class's children.
    - For example, `@:hscript(Std, Math)` on a class will allow any of that class's script functions to access `Std` and `Math` from the context as though they had defined them, without having to manually define these values for each individual function.
  - These values are parsed recursively, so any superclass, supersuperclass, interfaces of those classes, etc. will also be added to the context.
  - Updated the `openfl_hscript` sample to demonstrate this new syntax.
- The `@:hscript` annotation can now be defined as a parameter object.
  - This allows for additional types of configuration to be passed, aside from the script context.
  - Parameter objects can now be passed when using `@:hscript` on a class or interface.
    - Parameters are defined recursively, and values defined on a superclass or interface will be overridden by child classes.
    - The exception is the `context` parameter, which merges the provided contexts together.
  - If an identifier is provided in the annotation on a parent class or interface, the identifier need not necessarily be defined in the upper context.
      - For example, an interface can require that the variable `scriptPath` be included in the context or used as the script path name, without defining that variable itself, as long as any implementing classes that include a script function define that variable.
  - Updated the `openfl_hscript` sample to demonstrate this new syntax.
- Added `context` as an `@:hscript` parameter.
  - This achieves the existing functionality of providing constants to the script context.
  - Example: `@:hscript({context: [Std, Math]})`
- Added `cancellable` as an `@:hscript` parameter.
  - This allows for a script to be cancelled by the user. Defaults to `false`.
    - A new function `cancel()` is added to the context, which can be used to cancel the execution of the rest of the provided script body.
    - For example, you can add `@:hscript({cancellable: true})` to allow users to cancel an event before you perform an action.
  - Example: `@:hscript({context: [Std, Math], cancellable: true})`
- Added `pathName` as an `@:hscript` parameter.
  - This allows for a script to specify the specific pathname to access.
    - This ignores the `POLYMOD_ROOT_PATH` and `POLYMOD_USE_NAMESPACE` settings.
    - The value of `POLYMOD_SCRIPT_EXT` is still appended to the final path.
  - Example: `@:hscript({context: [Std, Math], pathName: "assets/scripts/initBee"})`
- The `pathName` parameter can now use an identifier. This allows for the pathname to be defined dynamically by the object.
  - If a constant is provided, the value is used as the pathname.
    - Example: `@:hscript({context: [Std, Math], pathName: "assets/scripts/initBee"})`
  - If an identifier is provided, the value of that identifier is accessed at the time the function is called.
    - Example: `@:hscript({context: [Std, Math], pathName: getScriptName})`
    - If the resulting value is a string constant, that value is used as the path.
    - If the resulting value is a Function, it will be called and the return value will be used as the path.
- Added `runBefore` as an `@:hscript` parameter.
  - This allows for a script's function body to be called before the script, rather than after. Defaults to `false`.
  - Incompatible with the `cancellable` parameter.
  - Example: `@:hscript({context: [Std, Math], runBefore: true})`
### Fixed
- Fixed a bug where defining `@:hscript` annotations on a parent class or interface would not pass the values down to the child function.


## [1.2.0] - 2021-11-04
### Added
- Added several new compile defines to change the behavior of Polymod
  - `POLYMOD_ROOT_PATH`: Defines the base path from which scripts should be accessed.
  - `POLYMOD_USE_NAMESPACE`: If true, scripts are located in a folder based on the classpath.
    - For example, the script `com.polymod.test#init` will be located at `/data/com/polymod/test/init.txt`.
  - `POLYMOD_SCRIPT_EXT`: Defines the file extension used by all Polymod scripts.
    - This defaults to `.txt` for backwards compatibility, but should be changed to `.hscript` to improve integration with IDEs.
  - `POLYMOD_SCRIPT_LIBRARY`: Defines the asset library used by all Polymod scripts.
    - This defaults to `default`, which should be fine for Lime projects which only utilize the default asset library.
  - Set these values using either of the following methods:
    - For Haxe projects, add something like `-D POLYMOD_SCRIPT_EXT=.hscript` to your Haxe compiler arguments or `hxml`.
    - For Lime projects, add something like `<haxedef name="POLYMOD_SCRIPT_EXT" value=".hscript" />` to your `project.xml`.
- Added the new variable `script_variables`, accessible after the execution of a scripted function.
  - Similar to `script_result`, which provides the return value of the script, and `script_error`, which outputs the error provided by the script, `script_variables` provides access to the named variables created by the script's local scope.
  - One use case for this is to allow a single script to define several named functions, which can be retrieved and stored to use later.


## [1.1.0] - 2021-09-25
### New Contributors
* @MasterEric made their first contribution in https://github.com/larsiusprime/polymod/pull/34
### Added
- Added several new informational error codes to `onError`:
  - `MOD_LOAD_PREPARE`: Called when Polymod is about to load a given mod.
  - `MOD_LOAD_DONE`: Called when Polymod has successfully finished loading a given mod. Useful for logging.
  - `MOD_LOAD_FAIL`: Called when Polymod has failed to load a given mod.
- Fully abstracted the file system and made it a parameter, similar to `IBackend`.
  - This allows users to implement and utilize their own custom file system class.
  - Example: `Polymod.init({customFileSystem: CustomFileSystem})` given a class `CustomFileSystem` which implements `IFileSystem`.
- Added several video file types to the list of default file extensions.
  - Added `.mov`, `.mp4`, `.avi`, `.mkv`, and `.webm`.
### Fixed
- Performed HaxeFormatter cleanup on all source files.
- Fixed a crash when old projects which used multiple asset libraries were not specifying `frameworkParams`.
  - This fix is required for users attempting to build [Friday Night Funkin'](https://github.com/ninjamuffin99/Funkin/) or derivatives.


## [1.0.0] - 2021-09-15
The repository as it existed on 2020-09-15.
### Added
- All basic functionality.
### Changed
- Fixed support for Lime projects utilizing multiple asset libraries.
### Known Issues
- A crash may occur when old projects (which do not specify `frameworkParams.assetLibraryPaths`) are run in this version.
