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
-- Two places:
--   #new-chat-background  the crossing, as a wallpaper
--   #transcript           the same crossing, slower and faded, behind a chat

local zeron = require("./zeron")("tokyo-feel")
local tokyo = require("./tokyo_wgsl")

local pixel_setting = zeron.setting("pixel")
local dither_setting = zeron.setting("dither")
local people_setting = zeron.setting("people")
local petals_setting = zeron.setting("petals")
local chats_setting = zeron.setting("chats")
local strength_setting = zeron.setting("strength")

-- Screen pixels per art pixel (on a Retina screen, half as many points).
local SCREEN_PIXELS_PER_ART_PIXEL = { fine = 8, classic = 10, chunky = 14 }
local FRAMES_PER_SECOND = { wall = 24, chat = 15 }
local DITHER_STRENGTH = 0.9
local PETAL_COUNT = { few = 40, some = 90, many = 150 }
local CHAT_ALPHA = {
	dark = { subtle = 0.4, medium = 0.55, vivid = 0.75 },
	light = { subtle = 0.2, medium = 0.3, vivid = 0.45 },
}

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
	return `{pixel_setting:get() or "classic"}|{dither}|{people}|{petals_setting:get() or "some"}`
end

type Look = { art_pixel: number, dither: number, people: number, petals: number }

local function look_from(key: string): Look
	local pixel, dither, people, petals = string.match(key, "^(.-)|(.-)|(.-)|(.*)$")
	return {
		art_pixel = SCREEN_PIXELS_PER_ART_PIXEL[pixel or "classic"] or SCREEN_PIXELS_PER_ART_PIXEL.classic,
		dither = if dither == "1" then DITHER_STRENGTH else 0,
		people = if people == "0" then 0 else 1,
		petals = PETAL_COUNT[petals or "some"] or PETAL_COUNT.some,
	}
end

-- The shaders' parameters are listed at the top of tokyo_wgsl.luau.
local function Scene(mode: string, look: Look, speed: number, alpha: number, muted: number): Node
	return ui.div {
		w_full = true,
		h_full = true,
		-- (Shown while the shaders compile. A layer shader filters what its box
		-- paints, so behind a chat it gets a fill too, one nobody can see.)
		bg = if mode == "wall" then "#141733" else "#14173301",
		layer_shader = shader_for(look.art_pixel, mode),
		layer_clock = true,
		layer_params = {
			{ 0, look.people, look.dither, speed },
			{ alpha, 1, 1, 0 },
			{ 1, muted, 0, 0 },
			{ look.petals, 0, 0, 0 },
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
				return Scene("chat", look_from(look or ""), 0.8, levels[strength or "subtle"] or levels.subtle, 0)
			end, { w_full = true, h_full = true }),
		}
	end,
}
