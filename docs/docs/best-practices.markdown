---
title: Best Practices
---
{% include toc.html %}

# Best Practices

## For game developers

### 1. Use loose, flat files

Mods work best when modders can rely entirely on replace and append logic. The easiest way to facilitate this is to leave files separated out one by one rather than all glommed together. For instance, it's way easier to replace just one character sprite if each character sprite sheet is its own file, rather than all of them being packed together in one. Although a modder can easily copy and paste the packed file, make a change, and add it to their mod as a replacement, this becomes fragile in two ways:

1. If the base game updates that file (say parts other than what the modder changed), the mod will now have an old version of it, even though they only intended to modify one part of it.
2. If two modders want to change different in-game objects that reside in the same file, and they both use replace logic, their changes will override each other and only one will be resolved in the final asset set.

Of course, for performance reasons developers will often combine files, so there's some tension here. However keep in mind that the OpenFL Asset Library is a kind of *virtual file system*. The default asset library provides a nearly one-to-one mapping between asset names and actual files on disk, but there's no reason you couldn't override your default asset library with say, an asset library that stores everything on disk in one single binary (even encrypted!) PAK file or whatever, while still exposing a nice list of individual asset names. Polymod doesn't care how your actual assets are stored and loaded from disk.

### 2. Texture packs

Most texture packs will provide metadata that allows the original image frames/files to be extracted from a packed file, which in its own way is a tiny virtual file system. You might consider modifying your game/app code to first look for a given asset stored in its own loose file (in case a modder has provided one), before looking in your texture atlas cache.

### 3. Data tables

Data tables and other "flat" file formats can work very well with atomic modding, particularly with append logic. If adding new items or enemies is as simple as adding a new line to a spreadsheet, this is ideal for modders who want to create mix-and-matchable content.

### 4. Publish a modding API, adhere to Semantic Versioning

As soon as your game is ready for modding, you should publish documrentation for your modding API for your game that tells players what they can expect to modify and how, as well as an associated Mod API version. Don't forget to adhere to [Semantic Versioning 2.0](https://semver.org/), which is summarized thus:

    Given a version number MAJOR.MINOR.PATCH, increment the:

    MAJOR version when you make incompatible API changes,
    MINOR version when you add functionality in a backwards-compatible manner, and
    PATCH version when you make backwards-compatible bug fixes.

### 5. Use the error handler

You should pass in an error handler during initialization and then *use it*, ideally piping useful feedback to your players so that they can debug their mods and make sure they're properly formatted.

Keep in mind that the `PolymodError` object that the handler receives includes several useful attributes, including:

* `serverity`, which indicates if the message is merely a notice, or if it's a warning or error.
* `code`, which is one of the values of the `PolymodErrorCode` enumeration. This can be used with a switch/case block to provide different handling for different types of errors.
* `message`, which can be written to a log file or displayed to the user.

### 6. Data-driven design

A game that is mod friendly should be heavily data-driven. This means that, rather than hard-coding your list of enemy types, the game should draw from a text file or directory listing. This way players can define their own types by simply adding or appending files.

### 7. Support scripting

Certain parts of your code, such as basic game logic, AI routines, formula calculations, etc, can be exposed to modding via scripts -- human-readable code interpreted at runtime. Polymod can support any scripting language in theory, but we strongly recommend [hscript](https://github.com/HaxeFoundation/hscript) for Haxe games. See [Scripting](./scripting/) for more details.

If you do so, you should document a list of methods and properties exposed by your scripting system, and publish these along with your default asset manifest as your game's modding API.

The current version of Polymod does not support targeted merge logic for Haxe script files, so to best support modders, stick to simple isolated script files. Support for this may eventually be added in the future.

### 8. Encourage generic ids as merge keys

If you look at the sample mod represented by the GIF at the top of this page, you'll notice a slight "bug" of sorts. The base app has three images, a sun, a moon, and a star, and an XML file with tags like `<object value="sun"/>` to match. Notice that when activating mods 1-3, each one replaces one of the graphics with a different kind of flower, and updates the xml tags to match. The mods are using file replace logic for the images, and merge logic for the xml file.

But, notice what happens when mod 4 is activated. Mod 4 replaces the entire XML file so that the xml nodes have values "pineapple", "apple", and "bread". Notice that when Mod 4 is moved into load position 1 and the other mods are activated, the flowers replace the image assets, but they don't properly update the XML data. That's because the replace logic targets the same filenames ("a.png", "b.png", "c.png"), but the merge logic is keyed off of the specific value names ("sun", "moon", "stars"). So when the value names are changed, mods that depend on those specific values as merge keys will not act as intended.

If this file structure had been designed so that each `<object>` tag had a generic key like `<object id="0" value="sun"/>`, and the mods were written to replace based on the unchanging key (`id="0"` instead of `object="sun"`), then these mods would work as intended.

### 9. Think about security

Players modifying their games to accept random untrusted third party content are already exposing themselves in a fundamental way, but there's perhaps some things we can do to shave the attack surface area down a bit. For one, special care needs to be taken if some of the assets you're loading via Polymod are driving in-game scripts and have access to e.g. File read/write/delete API's (or even worse, invoking system commands and/or launching other executables). At the moment, Polymod does absolutely nothing to protect you from this, so you must make your own safeguards. In the future we might provide some basic sandboxing or safety checks.

## For modders

### 1. Start simple

Don't try to do too much too fast. Start with something basic, like replacing a single loose image, or adding a line of text somewhere. Don't try to change too much at once -- make one small edit, then test your mod to see how it's working. You can build up steady momentum this way as you build familiarity with both modding in general and the game's specific data set.

### 2. Include a license

If your mod doesn't include a license, it's in a legal gray area. By default, anything you create is automatically your copyright (in the USA at least), and in the absence of a license the assumption is that it's "all rights reserved" -- ie, nobody's allowed to use it any way you haven't specifically permitted.

It gets even worse if other people want to include your mod in theirs, or build off of it. To foster a collaborative modding community, I strongly recommend using open licenses such as these:

[Creative Commons Attribution 4.0](https://creativecommons.org/licenses/by/4.0/) -- for assets and data, etc.
[MIT License](https://opensource.org/licenses/MIT) -- for code/script files, etc.

### 3. It doesn't have to be big

Some of the best mods are simple ones that just do one thing. Since Polymod lets you combine multiple mods easily, it can be nice to just make a few small mods rather than one big one. You can always create a modpack to link multiple atomic mods together, after all.

### 4. Don't over-rely on merge logic

Merge logic is the most complicated, least flexible, and most error prone of the three supported operations. If the developer has structured their game well, you should be able to get most of your work done with just append and replace logic. You should save merge logic only for problems you can't solve any other way.
