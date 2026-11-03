package mobile.backend;

import lime.system.System as LimeSystem;

#if android
import android.jni.JNICache;
import android.os.Build.VERSION as AndroidVersion;
import android.os.Build.VERSION_CODES as AndroidVersionCode;
#end

/**
 * A storage class for mobile.
 * @author Mihai Alexandru (M.A. Jigsaw) and Lily (mcagabe19)
 */
class SUtil
{
	public static inline var STORAGE_CONTAINER:String = 'D.C.Fantasy Land';
	public static inline var DEFAULT_STORAGE_FOLDER:String = 'Different Creatingness Engine';
	public static inline var VERSIONED_STORAGE_FOLDER:String = 'Different Creatingness Engine - 1.2';

	public static function normalizeStorageFolder(folder:String):String
	{
		return folder == VERSIONED_STORAGE_FOLDER ? VERSIONED_STORAGE_FOLDER : DEFAULT_STORAGE_FOLDER;
	}

	#if android
	public static function getStorageConfigPath():String
	{
		return AndroidEnvironment.getExternalStorageDirectory() + '/' + STORAGE_CONTAINER + '/.dce_storage_config';
	}
	#end

	#if sys
	public static function getStorageDirectory(type:StorageType = EXTERNAL, ?folderOverride:String = null):String
	{
		var daPath:String = '';
		#if android
			var folderName:String = normalizeStorageFolder(folderOverride);
		switch (type)
		{
			case EXTERNAL:
				daPath = AndroidEnvironment.getExternalStorageDirectory() + '/' + STORAGE_CONTAINER + '/' + folderName;
		}
		#elseif ios
		daPath = LimeSystem.documentsDirectory;
		#else
		daPath = Sys.getCwd();
		#end
		daPath = haxe.io.Path.addTrailingSlash(daPath);
		return daPath;
	}

	public static function mkDirs(directory:String):Void
	{
		var total:String = '';
		if (directory.substr(0, 1) == '/')
			total = '/';

		var parts:Array<String> = directory.split('/');
		if (parts.length > 0 && parts[0].indexOf(':') > -1)
			parts.shift();

		for (part in parts)
		{
			if (part != '.' && part != '')
			{
				if (total != '' && total != '/')
					total += '/';

				total += part;

				try
				{
					if (!FileSystem.exists(total))
						FileSystem.createDirectory(total);
				}
				catch (e:haxe.Exception)
					trace('Error while creating folder. (${e.message}');
			}
		}
	}

	public static function saveContent(fileName:String = 'file', fileExtension:String = '.json',
			fileData:String = 'You forgor to add somethin\' in yo code :3'):Void
	{
		try
		{
			if (!FileSystem.exists('saves'))
				FileSystem.createDirectory('saves');

			File.saveContent('saves/' + fileName + fileExtension, fileData);
			showPopUp(fileName + " file has been saved.", "Success!");
		}
		catch (e:haxe.Exception)
			trace('File couldn\'t be saved. (${e.message})');
	}

	#if android
	public static function hasStoragePermission():Bool
	{
		if (AndroidVersion.SDK_INT >= AndroidVersionCode.R)
			return AndroidEnvironment.isExternalStorageManager();
		var granted = AndroidPermissions.getGrantedPermissions();
		return granted.contains('android.permission.READ_EXTERNAL_STORAGE')
			&& granted.contains('android.permission.WRITE_EXTERNAL_STORAGE');
	}

	public static function doPermissionsShit():Void
	{
		// Settings and permission dialogs are asynchronous. Main waits for the
		// grant before touching external storage or constructing the game.
		if (hasStoragePermission()) return;
		if (AndroidVersion.SDK_INT >= AndroidVersionCode.R) // Android 11 (API 30) and above
		{
			if (!AndroidEnvironment.isExternalStorageManager())
				AndroidSettings.requestSetting('MANAGE_APP_ALL_FILES_ACCESS_PERMISSION');
		}
		else // Android 10 and below
		{
			if (!AndroidPermissions.getGrantedPermissions().contains('android.permission.READ_EXTERNAL_STORAGE')
				|| !AndroidPermissions.getGrantedPermissions().contains('android.permission.WRITE_EXTERNAL_STORAGE'))
			{
				AndroidPermissions.requestPermissions(['READ_EXTERNAL_STORAGE', 'WRITE_EXTERNAL_STORAGE']);
			}
		}

	}
	#end

	public static function showPopUp(message:String, title:String):Void
	{
		#if android
		// AndroidTools wraps even a null callback in a temporary HaxeObject.
		// The Java dialog can outlive that wrapper and call an invalid native
		// object when OK is pressed. Pass null callback objects to Java instead.
		JNICache.createStaticMethod('org/haxe/extension/Tools', 'showAlertDialog',
			'(Ljava/lang/String;Ljava/lang/String;Ljava/lang/String;Lorg/haxe/lime/HaxeObject;Ljava/lang/String;Lorg/haxe/lime/HaxeObject;)V')(title,
				message, 'OK', null, null, null);
		#else
		var application = lime.app.Application.current;
		if (application != null && application.window != null)
			application.window.alert(message, title);
		else
			Sys.println('$title\n$message');
		#end
	}
	#end
}

enum StorageType
{
	EXTERNAL;
}
