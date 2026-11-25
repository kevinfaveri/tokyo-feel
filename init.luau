-- Tokyo Feel: a pixel-art railway crossing in sakura season, behind a new
-- chat and, faded, behind your chats.
--
-- The whole scene runs on the GPU (tokyo_wgsl.luau), at one texel per art
-- pixel. The still scenery (road, track, trees, houses) is a pass drawn once
-- and kept; what moves (the train, the gates, people, petals) is a pass drawn
-- each frame over it; a layer shader scales the result up nearest-neighbour.
-- The engine steps time on its own clock (`layer_clock`), so no script runs
-- per frame.
--
-- Three places:
--   #new-chat-background  the crossing, as a wallpaper
--   #transcript           the same crossing, faded, behind a chat
--   #chat-session, #chat-home   two buttons at the bottom right: the theme
--                         (sunrise, sunset or night) and the sound
--
-- A theme has its own sky and light, its own people and animals, its own
-- sounds and waltz: a programme of seven rounds, five minutes long, played
-- from its start whenever the theme is chosen.
--
-- Zeron lends plugins no audio, so the sound is macOS's afplay playing the
-- clips in sounds/ (made by src/sounds.py): the theme's air on a loop (birds
-- at sunrise and sunset, crickets at night), and one clip per round of the
-- crossing, started as the lamps start to blink: its train, what else
-- happens that round, a section of the theme's waltz.

local zeron = require("./zeron")("tokyo-feel")
local tokyo = require("./tokyo_wgsl")

local pixel_setting = zeron.setting("pixel")
local dither_setting = zeron.setting("dither")
local people_setting = zeron.setting("people")
local petals_setting = zeron.setting("petals")
local chats_setting = zeron.setting("chats")
local strength_setting = zeron.setting("strength")
local volume_setting = zeron.setting("volume")
local sound_on = zeron.store("sound", false)
local theme_choice = zeron.store("theme", "sunset")
local theme_of_the_hour = zeron.store("theme-of-the-hour", "sunset")

local DAY_CYCLE = "daycycle"
local CHOICES = { "sunrise", "sunset", "night", DAY_CYCLE }
local SUNRISE_FROM_HOUR = 5
local SUNSET_FROM_HOUR = 12
local NIGHT_FROM_HOUR = 19
local DAY_CYCLE_CHECK_MS = 60000
local THEME_NUMBER = { sunrise = 0, sunset = 1, night = 2 }
local THEME_LABEL = { sunrise = "Sunrise", sunset = "Sunset", night = "Night" }
local THEME_BACKDROP = { sunrise = "#c3d3e6", sunset = "#c47fa0", night = "#141733" }

local function known_theme(name: any): string
	return if THEME_NUMBER[name] ~= nil then name else "sunset"
end

local function theme(): string
	if theme_choice:get() == DAY_CYCLE then
		return known_theme(theme_of_the_hour:get())
	end
	return known_theme(theme_choice:get())
end

local function theme_now(): string
	if theme_choice:peek() == DAY_CYCLE then
		return known_theme(theme_of_the_hour:peek())
	end
	return known_theme(theme_choice:peek())
end

local function theme_for_hour(hour: number): string
	if hour >= NIGHT_FROM_HOUR or hour < SUNRISE_FROM_HOUR then
		return "night"
	elseif hour >= SUNSET_FROM_HOUR then
		return "sunset"
	end
	return "sunrise"
end

local function theme_for_the_computer_clock(): string
	local hour = tonumber(os.date("%H"))
	return if hour ~= nil then theme_for_hour(hour) else "sunset"
end

-- Screen pixels per art pixel (on a Retina screen, half as many points).
local SCREEN_PIXELS_PER_ART_PIXEL = { fine = 8, classic = 10, chunky = 14 }
local FRAMES_PER_SECOND = { wall = 24, chat = 15 }
local DITHER_STRENGTH = 0.9
local PETAL_COUNT = { few = 12, some = 26, many = 48 }
local CHAT_ALPHA = {
	dark = { subtle = 0.4, medium = 0.55, vivid = 0.75 },
	light = { subtle = 0.2, medium = 0.3, vivid = 0.45 },
}

-- The round in src/live.wgsl: 44 seconds, the first one 2.5 seconds after
-- the scene's clock starts.
local ROUND_SECONDS = 44
local SECONDS_BEFORE_FIRST_ROUND = 2.5
local ROUNDS_IN_PROGRAMME = 7
local AIR_CLIP_SECONDS = 12
local AIR_OVERLAP_SECONDS = 1.5
-- (About how long afplay takes to make its first sound.)
local PLAYER_START_MS = 120
local LONGEST_CLIP_SECONDS = 70
local VOLUME = { quiet = 0.3, normal = 0.6, loud = 1 }
local OWN_CLIPS = "tokyo-feel/sounds/"
local SCENE_CHECK_MS = 1000
local CHECKS_BEFORE_SILENCE = 3
local PROGRAMMES_BEFORE_CLOCK_WRAPS = 12

type ShownScene = { speed: number }
type Programme = { started_ms: number, speed: number }

local sounds_folder: string? = nil
local shown_scenes: { ShownScene } = {}
local programme: Programme? = nil
local playing = false
local checks_without_a_scene = 0
local cancel_next_round: (() -> ())? = nil
local cancel_next_air: (() -> ())? = nil
local cancel_next_check: (() -> ())? = nil
local start_sounds: () -> ()

local function motion_is_reduced(): boolean
	local prefers = (ui :: any).prefers
	return prefers ~= nil and prefers.reduced_motion ~= nil and prefers.reduced_motion:peek() == true
end

local function stop_clips(named: string)
	zeron.run("pkill", { "-f", OWN_CLIPS .. named })
end

local function cancel_timer(cancel: (() -> ())?)
	if cancel then
		cancel()
	end
end

local function silence()
	if not playing then
		return
	end
	playing = false
	cancel_timer(cancel_next_round)
	cancel_timer(cancel_next_air)
	cancel_timer(cancel_next_check)
	cancel_next_round, cancel_next_air, cancel_next_check = nil, nil, nil
	stop_clips("")
end

local function sound_failed()
	if not playing then
		return
	end
	silence()
	sound_on:set(false)
	zeron.toast("Tokyo Feel's sound needs macOS (it plays with afplay)")
end

local function play(clip: string, rate: number)
	local volume = VOLUME[volume_setting:peek() or "normal"] or VOLUME.normal
	local file = `{sounds_folder}/{clip}.m4a`
	zeron.run("afplay", { "-v", tostring(volume), "-r", tostring(rate), file }, { timeout = LONGEST_CLIP_SECONDS }):after(nil, sound_failed)
end

local function programme_seconds(running: Programme): number
	return (ui.now() - running.started_ms) / 1000 * running.speed
end

-- (A scene's own clock starts at zero when it is built. Every scene adds the
-- programme's seconds to it, so all chats show the same moment.)
local function seconds_into_programme(): number
	local running = programme
	if running == nil then
		return 0
	end
	return programme_seconds(running) % (ROUND_SECONDS * ROUNDS_IN_PROGRAMME * PROGRAMMES_BEFORE_CLOCK_WRAPS)
end

local function ms_until_next_round(running: Programme): number
	local into_round = (programme_seconds(running) - SECONDS_BEFORE_FIRST_ROUND) % ROUND_SECONDS
	return (ROUND_SECONDS - into_round) / running.speed * 1000
end

-- (The programme's first round starts 2.5 seconds after the scene's clock.)
local function next_round(running: Programme): number
	local rounds_begun = math.ceil((programme_seconds(running) - SECONDS_BEFORE_FIRST_ROUND) / ROUND_SECONDS)
	return math.max(rounds_begun, 0) % ROUNDS_IN_PROGRAMME
end

local function schedule_round()
	local running = programme
	if not playing or running == nil or motion_is_reduced() then
		return
	end
	local wait = math.max(ms_until_next_round(running) - PLAYER_START_MS, 0)
	local round = next_round(running)
	cancel_next_round = ui.after(wait, function()
		play(`round-{theme_now()}-{round}`, running.speed)
		cancel_next_round = ui.after(1000, schedule_round)
	end)
end

local function play_air()
	if not playing then
		return
	end
	play(`air-{theme_now()}`, 1)
	cancel_next_air = ui.after((AIR_CLIP_SECONDS - AIR_OVERLAP_SECONDS) * 1000, play_air)
end

-- (Going from one chat to another leaves no scene for a moment. The sound
-- plays on through that, and stops only when no scene comes back.)
local function stop_when_no_scene_is_left()
	if not playing then
		return
	end
	checks_without_a_scene = if #shown_scenes == 0 then checks_without_a_scene + 1 else 0
	if checks_without_a_scene >= CHECKS_BEFORE_SILENCE then
		silence()
		return
	end
	cancel_next_check = ui.after(SCENE_CHECK_MS, stop_when_no_scene_is_left)
end

function start_sounds()
	if playing or sounds_folder == nil or programme == nil or #shown_scenes == 0 then
		return
	end
	playing = true
	checks_without_a_scene = 0
	play_air()
	schedule_round()
	stop_when_no_scene_is_left()
end

-- (A theme's scene is built anew, so its programme and its sounds start over.)
local function start_programme_over()
	silence()
	programme = nil
end

local function follow_the_computer_clock()
	local due = theme_for_the_computer_clock()
	if theme_of_the_hour:peek() == due then
		return
	end
	if theme_choice:peek() == DAY_CYCLE then
		start_programme_over()
	end
	theme_of_the_hour:set(due)
end

local function scene_shows(scene: ShownScene)
	follow_the_computer_clock()
	table.insert(shown_scenes, scene)
	if programme == nil then
		programme = { started_ms = ui.now(), speed = scene.speed }
	end
	if not playing and sound_on:peek() == true then
		start_sounds()
	end
end

local function scene_went_away(scene: ShownScene)
	local index = table.find(shown_scenes, scene)
	if index ~= nil then
		table.remove(shown_scenes, index)
	end
end

local function keep_following_the_computer_clock()
	follow_the_computer_clock()
	ui.after(DAY_CYCLE_CHECK_MS, keep_following_the_computer_clock)
end

local function choose_next_theme()
	local current = table.find(CHOICES, theme_choice:peek()) or 2
	follow_the_computer_clock()
	start_programme_over()
	theme_choice:set(CHOICES[current % #CHOICES + 1])
end

local function toggle_sound()
	local turn_on = sound_on:peek() ~= true
	sound_on:set(turn_on)
	if turn_on then
		start_sounds()
	else
		silence()
	end
end

keep_following_the_computer_clock()

zeron.run("printenv", { "HOME" }):after(function(answer: any)
	local home = string.match(answer.stdout or "", "^%s*(.-)%s*$")
	if home == nil or home == "" then
		return
	end
	sounds_folder = `{home}/.zeron/plugins/tokyo-feel/sounds`
	-- (Clips left playing by a window that closed.)
	stop_clips("")
	if sound_on:peek() == true then
		start_sounds()
	end
end)

local compiled_shaders: { [string]: any } = {}

local function shader_for(art_pixel: number, mode: string): any
	local key = `{art_pixel}:{mode}`
	local compiled = compiled_shaders[key]
	if compiled == nil then
		compiled = ui.layer_shader(tokyo.SHOW, {
			fps = FRAMES_PER_SECOND[mode],
			passes = {
				-- (Light, material, depth and warm light go past 0 to 1, so floats.)
				{ name = "ground", shader = tokyo.GROUND, scale = 1 / art_pixel, format = "rgba16float", once = true },
				{ name = "scene", shader = tokyo.LIVE, scale = 1 / art_pixel },
			},
		})
		compiled_shaders[key] = compiled
	end
	return compiled
end

-- (Compiled off the frame from here, so the default is ready when it shows.)
shader_for(SCREEN_PIXELS_PER_ART_PIXEL.classic, "wall")
shader_for(SCREEN_PIXELS_PER_ART_PIXEL.classic, "chat")

local function look_key(): string
	local dither = if dither_setting:get() == true then "1" else "0"
	local people = if people_setting:get() == false then "0" else "1"
	return `{pixel_setting:get() or "classic"}|{dither}|{people}|{petals_setting:get() or "some"}|{theme()}`
end

type Look = { art_pixel: number, dither: number, people: number, petals: number, theme: string }

local function look_from(key: string): Look
	local pixel, dither, people, petals, chosen = string.match(key, "^(.-)|(.-)|(.-)|(.-)|(.*)$")
	return {
		art_pixel = SCREEN_PIXELS_PER_ART_PIXEL[pixel or "classic"] or SCREEN_PIXELS_PER_ART_PIXEL.classic,
		dither = if dither == "1" then DITHER_STRENGTH else 0,
		people = if people == "0" then 0 else 1,
		petals = PETAL_COUNT[petals or "some"] or PETAL_COUNT.some,
		theme = if THEME_NUMBER[chosen] ~= nil then chosen else "sunset",
	}
end

-- The shaders' parameters are listed at the top of tokyo_wgsl.luau.
local function Scene(mode: string, look: Look, speed: number, alpha: number, muted: number): Node
	local this_scene: ShownScene = { speed = speed }
	ui.on_cleanup(function()
		scene_went_away(this_scene)
	end)
	return ui.div {
		on_mount = function()
			scene_shows(this_scene)
		end,
		w_full = true,
		h_full = true,
		-- (Shown while the shaders compile. A layer shader filters what its box
		-- paints, so behind a chat it gets a fill too, one nobody can see.)
		bg = THEME_BACKDROP[look.theme] .. (if mode == "wall" then "" else "01"),
		layer_shader = shader_for(look.art_pixel, mode),
		layer_clock = true,
		layer_params = {
			{ 0, look.people, look.dither, speed },
			{ alpha, 1, 1, 0 },
			{ 1, muted, THEME_NUMBER[look.theme], 0 },
			{ look.petals, seconds_into_programme(), 0, 0 },
		},
		pointer_events = "none",
		aria_hidden = true,
	}
end

zeron.place {
	at = "#new-chat-background",
	fill = true,
	replace = function(): Node
		return ui.presence(look_key, function(key: string): Node
			return Scene("wall", look_from(key), 1, 1, 0.12)
		end, { w_full = true, h_full = true })
	end,
}

-- Behind a chat it's placed by the transcript: the column holding it is a
-- positioned box (the area messages scroll in).
zeron.place {
	at = "#transcript",
	before = function(): Node
		local appearance = zeron.live("appearance")
		return ui.div {
			absolute = true,
			left = 0,
			right = 0,
			top = 0,
			-- (The transcript's column stops at the composer's footer line,
			-- 40 points over the page's foot: Zeron's chat/dock page_pad.
			-- The crossing runs on to the foot.)
			bottom = -40,
			pointer_events = "none",
			ui.presence(function(): string
				if chats_setting:get() == false then
					return "off"
				end
				local scheme = if appearance and appearance() == "light" then "light" else "dark"
				return `{scheme}|{strength_setting:get() or "subtle"}|{look_key()}`
			end, function(key: string): Node
				if key == "off" then
					return ui.div {}
				end
				local scheme, strength, look = string.match(key, "^(.-)|(.-)|(.*)$")
				local levels = CHAT_ALPHA[scheme or "dark"] or CHAT_ALPHA.dark
				return Scene("chat", look_from(look or ""), 1, levels[strength or "subtle"] or levels.subtle, 0)
			end, { w_full = true, h_full = true }),
		}
	end,
}

local function CornerButton(props: { id: string, label: string, pressed: () -> boolean, words: () -> string, on_click: () -> () }): Node
	return ui.button {
		id = props.id,
		label = props.label,
		h = "$zeron.island.control",
		px = "$space.2",
		rounded = "$radius.full",
		cursor = "pointer",
		bg = function(): string
			return if props.pressed() then "$hover" else "#00000000"
		end,
		color = function(): string
			return if props.pressed() then "$text.primary" else "$text.secondary"
		end,
		hover = { bg = "$hover", color = "$text.primary" },
		active = { bg = "$pressed" },
		on_click = props.on_click,
		ui.presence(props.words, function(words: string): Node
			return ui.text { words, text_size = "$font.size.sm", weight = "$font.weight.medium" }
		end),
	}
end

local function never(): boolean
	return false
end

local function Corner(): Node
	-- (A box of no height at the page's foot, for the buttons to stand on.)
	return ui.div {
		relative = true,
		w_full = true,
		h = 0,
		ui.div {
			absolute = true,
			right = 12,
			bottom = 10,
			direction = "row",
			gap = "$space.1",
			CornerButton {
				id = "tokyo-feel-theme",
				label = "Tokyo Feel theme",
				pressed = never,
				words = function(): string
					if theme_choice:get() == DAY_CYCLE then
						return `Theme: Day cycle ({THEME_LABEL[theme()]})`
					end
					return `Theme: {THEME_LABEL[theme()]}`
				end,
				on_click = choose_next_theme,
			},
			CornerButton {
				id = "tokyo-feel-sound",
				label = "Crossing sound",
				pressed = function(): boolean
					return sound_on:get() == true
				end,
				words = function(): string
					return if sound_on:get() == true then "Turn sound off" else "Turn sound on"
				end,
				on_click = toggle_sound,
			},
		},
	}
end

-- (Beside a chat's page and a new chat's: both fill the window's main area,
-- so the buttons sit at its bottom right in either.)
for _, page in { "#chat-session", "#chat-home" } do
	zeron.place { at = page, after = Corner }
end
