import flixel.FlxG;
import flixel.FlxSprite;
import flixel.FlxState;
import flixel.addons.ui.FlxInputText;
import flixel.graphics.frames.FlxAtlasFrames;
import flixel.text.FlxText;
import openfl.utils.AssetManifest;
import openfl.utils.AssetType;
import openfl.utils.Assets;
import polymod.Polymod.Framework;
import polymod.Polymod;

using StringTools;

class PlayState extends FlxState
{
	/**
	 * The mod widgets.
	 */
	private var widgets:Array<ModWidget> = [];

	/**
	 * Things that aren't the widgets (the images and texts).
	 * These get destroyed and reloaded when refreshing.
	 */
	private var stuff:Array<FlxSprite> = [];

	public override function create()
	{
		super.create();

		// Load with zero mods first?
		loadMods([]);

		this.bgColor = 0xFFFFFFFF;

		makeButtons();
		drawImages();
		drawText();
	}

	private function makeButtons()
	{
		var modDir:String = '../../../mods';
		#if mac
		// account for <APPLICATION>.app/Contents/Resources
		modDir = '../../../$modDir';
		#end

		var modList = Polymod.scan({
			modRoot: modDir,
		});

		var xx = 10;
		var yy = 400;
		for (modMeta in modList)
		{
			trace('Adding widget for mod ${modMeta.title}');
			var w = new ModWidget(modMeta.id, onWidgetMove);
			w.x = xx;
			w.y = yy;

			widgets.push(w);

			xx += Std.int(w.width) + 10;

			w.fixButtons();

			add(w);
		}

		updateWidgets();
	}

	public function refresh()
	{
		for (thing in stuff)
		{
			remove(thing);
		}
		stuff.splice(0, stuff.length);

		drawImages();
		drawText();
	}

	private function onWidgetMove(w:ModWidget, i:Int)
	{
		trace('onWidgetMove ${w.modId} : $i');
		if (i != 0)
		{
			var temp = widgets.indexOf(w);
			var newI = temp + i;
			if (newI < 0 || newI >= widgets.length)
			{
				return;
			}
			var other = widgets[newI];

			var oldX = w.x;
			var oldY = w.y;

			widgets[newI] = w;
			widgets[temp] = other;

			w.x = other.x;
			w.y = other.y;

			other.x = oldX;
			other.y = oldY;

			w.fixButtons();
			other.fixButtons();
		}

		reloadMods();
		updateWidgets();
	}

	private function updateWidgets()
	{
		if (widgets == null)
			return;
		for (i in 0...widgets.length)
		{
			var showLeft = i != 0;
			var showRight = i != widgets.length - 1;
			widgets[i].showButtons(showLeft, showRight);
		}
	}

	public override function update(elapsed:Float)
	{
		super.update(elapsed);
	}

	private function drawImages()
	{
		trace('Drawing images...');
		var xx = 10;
		var yy = 10;

		var images = Assets.list(AssetType.IMAGE).filter(function(item:String)
		{
			return item.startsWith('assets/img/') && item.endsWith('.png');
		});
		images.sort(function(a:String, b:String):Int
		{
			if (a < b)
				return -1;
			if (a > b)
				return 1;
			return 0;
		});

		trace('Drawing ${images.length} images...');
		for (image in images)
		{
			trace('Drawing image $image');
			var sprite = new FlxSprite(xx, yy);

			var atlasPath = image.replace('.png', '.xml');
			if (Assets.exists(atlasPath))
			{
				trace('Building animated image $image');
				sprite.frames = FlxAtlasFrames.fromSparrow(image, Assets.getText(atlasPath));
				sprite.animation.addByPrefix('idle', 'idle', 24, true);
				sprite.animation.play('idle');
			}
			else
			{
				trace('Building static image $image');
				sprite.loadGraphic(image);
			}

			sprite.setGraphicSize(72, 72);
			sprite.updateHitbox();
			sprite.antialiasing = true;

			var text = new FlxText(xx, sprite.y + sprite.height, sprite.width, image);
			text.setFormat("Arial", 12, 0xFF000000, FlxTextAlign.CENTER);

			add(sprite);
			add(text);
			stuff.push(text);
			stuff.push(sprite);

			xx += Std.int(sprite.width + 10);
		}
	}

	private function drawText()
	{
		var xx = FlxG.width - 250 - 10;
		var yy = 10;

		var texts = Assets.list(AssetType.TEXT).filter(function(item:String)
		{
			return item.startsWith('assets/data/');
		});

		texts.sort(function(a:String, b:String)
		{
			if (a < b)
				return -1;
			if (a > b)
				return 1;
			return 0;
		});

		trace('Drawing ${texts.length} texts...');

		for (t in texts)
		{
			trace('Drawing text $t');
			var isXML:Bool = false;
			if (t.indexOf('xml') != -1 || t.indexOf('json') != -1)
			{
				isXML = true;
			}

			var text = new FlxInputText(xx, yy, 250);
			text.setFormat("Arial", 12, 0xFF000000, FlxTextAlign.LEFT);
			text.height = 150;
			text.wordWrap = true;
			text.lines = 10;

			var str = Assets.getText(t);
			text.text = (str != null ? str : 'null');

			var caption = new FlxText(xx, text.y + text.height, text.width, "UNKNOWN");
			caption.setFormat("Arial", 12, 0xFF000000, FlxTextAlign.CENTER);
			caption.text = t;

			add(text);
			add(caption);
			stuff.push(text);
			stuff.push(caption);

			yy += Std.int(text.height + 35);
		}
	}

	private function reloadMods()
	{
		trace('Reloading mods...');
		var theMods = [];
		for (w in widgets)
		{
			if (w.isModActive)
			{
				theMods.push(w.modId);
			}
		}
		loadMods(theMods);
	}

	private function loadMods(dirs:Array<String>)
	{
		trace('Loading mods: ${dirs}');

		var modDir:String = '../../../mods';
		#if mac
		// account for <APPLICATION>.app/Contents/Resources
		modDir = '../../../$modDir';
		#end

		var results = Polymod.init({
			modRoot: modDir,
			dirs: dirs,
			errorCallback: onError,
			ignoredFiles: Polymod.getDefaultIgnoreList(),
			framework: Framework.FLIXEL
		});

		// Reload graphics before rendering again.
		var loadedMods = results.map(function(item:ModMetadata)
		{
			return item.id;
		});
		trace('Loaded mods: ${loadedMods}');
		refresh();
	}

	private function onError(error:PolymodError)
	{
		trace('[${error.severity}] (${Std.string(error.code).toUpperCase()}): ${error.message}');
	}
}
