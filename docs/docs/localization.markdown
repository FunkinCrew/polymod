---
title: Localization
---
{% include toc.html %}

# Localization

Polymod provides easy integration for localization in your app or game. Not only can you retrieve separate data files based on the current language, you can retrieve separate assets as well. Modders can even add support for their own languages with minimal intervention from the development team.

## NOTICE: Partial Support

This functionality is only implemented on the following frameworks:

- Lime
- OpenFL
- Flixel

Support for other frameworks is planned for the future.

## Setup

Polymod depends on the FireTongue library for localization support. You can install it using:

```
haxelib install firetongue
```

The FireTongue library is entirely optional if you are not utilizing the localization features of Polymod.

Before initializing Polymod, initialize a FireTongue instance for your locale:

```haxe
var tongue:FireTongue = new FireTongue();
tongue.init("en-US",onLoaded);
```

Then, once it loads, you can pass it to Polymod:

```haxe
Polymod.init({
    ...
    firetongue: tongue,
});
```

To change languages later, re-initialize FireTongue with the new locale, and Polymod will automatically update.

## Using Localization

When Polymod is used with FireTongue, the directory structure for asset files becomes more complicated.

Your asset folder should look like this (the same structure should be used by mods):

- assets/
    - locales/
        - _icons/
        - en-US/
            - menu.tsv
            - play.tsv
            - options.tsv
        - pt-BR/
            - assets/
              - music/
                  - song-with-lyrics.mp3
            - menu.tsv
            - play.tsv
            - options.tsv
        - index.xml
    - images/
        - billboard.png
    - music/
        - song-with-lyrics.mp3

There is no need to move the assets for your default locale into the `locale` folder, since the base directory will be used as a fallback anyway, and there is no need to copy assets to the other locales if you have not changed them.

Modded assets will take priority over unmodded assets, and localized assets take priority over unlocalized ones. For example, when checking which file to load, the following procedure is followed:

* Polymod will check if a mod contains the asset within the locale folder, and use that if it can.
* Otherwise, Polymod will check if the mod contains the asset within the base folder, and use that if it can.
* Otherwise, Polymod will check if the base files contain the asset within the locale folder, and use that if it can.
* Otherwise, Polymod will use the base asset from the base folder.

For example, if a mod replaces `assets/music/song-with-lyrics.mp3`, that new asset will be used, even if the user is playing in the Portuguese language and would normally load `assets/locales/pt-BR/assets/music/song-with-lyrics.mp3`.

Additionally, if a mod adds the file `assets/locales/pt-BR/assets/images/billboard.png`, that asset will be used, as long as the user is playing in the Portuguese language, *even if another mod has its own replacement for `assets/images/billboard.png`.*

## Switching Locales

To switch locales, call `tongue.init()`, providing the new locale to use. Polymod will automatically update and start loading assets from the newly selected locale.

Note that depending on your framework, you may have to call `Polymod.clearCache()`, and reload any localized assets that were loaded before the locale was changed.

## Adding New Locales

A mod can add a completely new locale to an existing application which utilizes FireTongue for its translation.

1. Add a new locale to the `locales` folder. Name it after the locale code, such as `en-US`, `pt-BR`, etc.
2. Add your new assets and translations to the new locale folder.
3. Create a file `_merge/assets/locales/index.xml` and add the new locale to it, like so:

### TODO: Validate this example

```xml
<?xml version="1.0" encoding="utf-8" ?>
<data>
    <data>
        <merge/>
        <locale id="en-US" is_default="true" sort="0">
	      	<contributors value="Lars Doucet, Level Up Labs"/>
	      	<ui language="Language" region="Region" accept="Okay" />
	      	<label id="en-US,en-GB,en-CA" language="English" region="United States"/>
	      	<label id="nb-NO" language="Engelsk" region="U.S.A."/>
	      </locale>
    </mode>
</data>
```

## Best Practices

When using Polymod with FireTongue, you should utilize FireTongue for user interface text whenever possible, and utilize Polymod's  localization integration only for things like graphics, audio, and script files.

FireTongue has many utilities to help you present localized text, and best practices on how to provide localization to users. Check out [FireTongue's documentation](https://github.com/larsiusprime/firetongue#advanced-use) for more information.
