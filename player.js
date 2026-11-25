// Plays one clip in step with the computer's clock:
//   osascript -l JavaScript player.js <file> <when the clip's start falls, in epoch ms> <volume 0 to 1>
// A clip whose start is already past is joined part way in; one whose start
// is still to come waits for it. So the sound keeps to the picture however
// long this program took to start.
ObjC.import("AVFoundation");
ObjC.import("unistd");

function run(argv) {
	const file = argv[0];
	const clipStartsAtMs = Number(argv[1]);
	const volume = Number(argv[2]);
	const player = $.AVAudioPlayer.alloc.initWithContentsOfURLError($.NSURL.fileURLWithPath(file), null);
	player.volume = volume;
	player.prepareToPlay;

	const secondsUntilStart = (clipStartsAtMs - Date.now()) / 1000;
	if (secondsUntilStart > 0) {
		delay(secondsUntilStart);
	}
	const secondsIntoClip = Math.max((Date.now() - clipStartsAtMs) / 1000, 0);
	if (secondsIntoClip >= player.duration) {
		return;
	}
	player.currentTime = secondsIntoClip;
	player.play;
	playWhileThePluginRuns(player, file);
}

// (Zeron does not stop the programs a plugin started, not when it quits and
// not when the plugin is turned off or removed. A program whose parent has
// gone is handed to another, so its parent's id changes. Whether a plugin
// is on is in .state.json, beside the plugins' folders.)
function playWhileThePluginRuns(player, file) {
	const zeron = $.getppid();
	const pluginFolder = file.split("/").slice(0, -2);
	const stateFile = pluginFolder.slice(0, -1).concat(".state.json").join("/");
	const pluginId = pluginFolder[pluginFolder.length - 1];
	while (player.playing && $.getppid() === zeron && pluginIsOn(stateFile, pluginId, file)) {
		delay(0.25);
	}
	player.stop;
}

function pluginIsOn(stateFile, pluginId, file) {
	if (!$.NSFileManager.defaultManager.fileExistsAtPath(file)) {
		return false;
	}
	const text = $.NSString.stringWithContentsOfFileEncodingError(stateFile, $.NSUTF8StringEncoding, null);
	if (text.isNil()) {
		return true;
	}
	try {
		const decision = JSON.parse(text.js).decisions[pluginId];
		return decision !== undefined && decision.off !== true;
	} catch (halfWrittenFile) {
		return true;
	}
}
