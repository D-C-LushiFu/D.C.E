package states.freeplayState;

import flash.net.FileFilter;
import flixel.FlxG;
import flixel.FlxSprite;
import flixel.addons.ui.FlxInputText;
import flixel.text.FlxText;
import flixel.ui.FlxButton;
import flixel.util.FlxColor;
import general.backend.CoolUtil;
import openfl.events.Event;
import openfl.events.IOErrorEvent;
import openfl.net.FileReference;
import sys.FileSystem;
import sys.io.File;

/** Local-only profile editor opened from the Freeplay profile card. */
class FreeplayProfileSubState extends MusicBeatSubstate
{
	var owner:FreeplayState;
	var nameInput:FlxInputText;
	var status:FlxText;
	var avatarFile:FileReference;

	public function new(owner:FreeplayState)
	{
		super();
		this.owner = owner;
	}

	override public function create():Void
	{
		super.create();
		var dim = new FlxSprite().makeGraphic(FlxG.width, FlxG.height, 0xB8000000);
		add(dim);
		var panelWidth = Std.int(Math.min(600, FlxG.width - 40));
		var panelHeight = 330;
		var left = (FlxG.width - panelWidth) / 2;
		var top = (FlxG.height - panelHeight) / 2;
		var panel = new FlxSprite(left, top).makeGraphic(panelWidth, panelHeight, 0xFF171E29);
		add(panel);
		add(new FlxText(left + 28, top + 24, panelWidth - 56, 'Freeplay 用户资料', 26));
		add(new FlxText(left + 30, top + 88, panelWidth - 60, '显示名称', 16));
		var currentName = 'Ruckus';
		if (FlxG.save != null && FlxG.save.data != null)
		{
			var stored:Dynamic = Reflect.field(FlxG.save.data, 'dceFreeplayProfileName');
			if (stored != null && StringTools.trim(Std.string(stored)) != '') currentName = Std.string(stored);
		}
		nameInput = new FlxInputText(left + 30, top + 116, panelWidth - 60, currentName, 20);
		nameInput.maxLength = 24;
		add(nameInput);
		var imageHelp = new FlxText(left + 30, top + 166, panelWidth - 60, '头像图片会复制到 D.C.E. 本地存档目录。', 14);
		imageHelp.color = FlxColor.CYAN;
		add(imageHelp);
		status = new FlxText(left + 30, top + 198, panelWidth - 60, '', 14);
		status.color = FlxColor.YELLOW;
		add(status);
		add(new FlxButton(left + 30, top + 242, '选择头像图片', chooseAvatar));
		add(new FlxButton(left + panelWidth - 230, top + 242, '保存', saveProfile));
		add(new FlxButton(left + panelWidth - 125, top + 242, '取消', close));
	}

	function chooseAvatar():Void
	{
		#if desktop
		if (avatarFile != null) return;
		avatarFile = new FileReference();
		avatarFile.addEventListener(Event.SELECT, onAvatarSelected);
		avatarFile.addEventListener(Event.COMPLETE, onAvatarLoaded);
		avatarFile.addEventListener(Event.CANCEL, onAvatarCancelled);
		avatarFile.addEventListener(IOErrorEvent.IO_ERROR, onAvatarError);
		if (!avatarFile.browse([new FileFilter('Image files', '*.png;*.jpg;*.jpeg')])) clearAvatarFile();
		#else
		status.text = '移动版暂不支持系统文件选择；可将头像放入本地存档的 freeplay-profile 文件夹并命名为 avatar.png。';
		#end
	}

	function onAvatarSelected(_:Event):Void
	{
		try avatarFile.load() catch (e:Dynamic) status.text = '读取图片失败：' + Std.string(e);
	}

	function onAvatarLoaded(_:Event):Void
	{
		try
		{
			var ext = haxe.io.Path.extension(avatarFile.name).toLowerCase();
			if (['png', 'jpg', 'jpeg'].indexOf(ext) < 0) throw '不支持的图片格式';
			if (avatarFile.data == null || avatarFile.data.length > 5 * 1024 * 1024) throw '图片不能超过 5 MB';
			var directory = CoolUtil.getSavePath() + '/freeplay-profile';
			if (!FileSystem.exists(directory)) FileSystem.createDirectory(directory);
			var filename = 'avatar.' + ext;
			File.saveBytes(directory + '/' + filename, avatarFile.data);
			Reflect.setField(FlxG.save.data, 'dceFreeplayAvatarFile', filename);
			FlxG.save.flush();
			status.text = '头像已保存到本地。';
			owner.onPhiProfileUpdated();
		}
		catch (e:Dynamic) status.text = '读取图片失败：' + Std.string(e);
		clearAvatarFile();
	}

	function onAvatarCancelled(_:Event):Void clearAvatarFile();
	function onAvatarError(_:Event):Void
	{
		status.text = '读取图片失败。';
		clearAvatarFile();
	}

	function clearAvatarFile():Void
	{
		if (avatarFile == null) return;
		avatarFile.removeEventListener(Event.SELECT, onAvatarSelected);
		avatarFile.removeEventListener(Event.COMPLETE, onAvatarLoaded);
		avatarFile.removeEventListener(Event.CANCEL, onAvatarCancelled);
		avatarFile.removeEventListener(IOErrorEvent.IO_ERROR, onAvatarError);
		avatarFile = null;
	}

	function saveProfile():Void
	{
		if (FlxG.save == null || FlxG.save.data == null)
		{
			status.text = '本地存档暂不可用，请稍后重试。';
			return;
		}
		var value = StringTools.trim(nameInput.text);
		if (value == '') value = 'Ruckus';
		if (value.length > 24) value = value.substr(0, 24);
		Reflect.setField(FlxG.save.data, 'dceFreeplayProfileName', value);
		FlxG.save.flush();
		owner.onPhiProfileUpdated();
		close();
	}

	override public function destroy():Void
	{
		clearAvatarFile();
		nameInput = null;
		status = null;
		owner = null;
		super.destroy();
	}
}
