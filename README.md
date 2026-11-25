# Tokyo Feel

A Zeron plugin: a pixel-art railway crossing in sakura season, behind a new chat and, faded, behind your chats.

You stand at the roadside of a level crossing in Tokyo. The lamps blink and the gates fall; a train passes, sweeping petals along with it; the gates rise and the people who waited cross. Sakura and green trees stand round the road, petals and a few leaves fall from them, and the street runs on between two rows of buildings to the horizon, where the Skytree stands.

There are three themes: **sunrise**, **sunset** and **night**. Each has its own sky and light, its own people and animals, its own sounds and its own waltz, and each is a programme five minutes long.

## The look

It follows [Deep Reef](https://github.com/wingleeio/pixel-reef) by Wing Lee, which follows the pixel-art gaussian splats at [splats.cobanov.dev](https://splats.cobanov.dev): forms sculpted in 3D, every surface point lit (a soft key light, occlusion, a grain per material, warm light pooling under lamps) and coloured through a ramp; the picture drawn small; translucent things (a lamp's glow, the land's far edge) cut to on/off pixels by a Bayer threshold; every pixel the nearest of a small palette. The scene, its models and its palette are this plugin's own.

## How it runs

Everything is on the GPU, in `tokyo_wgsl.luau`, at one texel per art pixel:

- **GROUND**: the still scenery, drawn once (and again when the window changes size) and kept.
- **LIVE**: what moves, drawn each frame over it: 24 frames a second behind a new chat, 15 behind chats.
- **SHOW**: scales the result up, nearest-neighbour.

The plugin keeps one clock, the computer's. Twelve times a second it tells the shaders which second of the programme to draw and starts the sounds that are due, so the picture and the sound keep together. One round of the crossing takes 44 seconds, and seven rounds make a theme's programme.

## The programmes

A round of the crossing takes 44 seconds, and seven rounds make a theme's programme. A commuter train and a Shinkansen take turns: the commuter trains (green, blue, orange) rattle by with the beat of their wheels; the Shinkansen is white with a blue line, more than twice as fast, and louder. Choosing a theme starts its programme from the beginning.

**Day cycle** follows the computer's clock: sunrise from 05:00, sunset from 12:00, night from 19:00. When the clock passes one of those hours, the programme you are watching plays to its end, and then the next theme's programme starts.

**Sunrise.** A pale blue sky, the sun climbing over the city through the five minutes, mist down the street. People on their way to work and school every round; the school run in most, the dog's walk in the others. Sparrows peck about on the road (rounds 1, 4 and 7) and fly off; a bush warbler calls; someone on a bicycle waits at the gate, rings and rides on (round 3); the cat in round 5; a school's chime far off in round 6. Many birds in the air, and two flocks crossing the sky.

**Sunset.** A sky from violet to gold, the sun sinking. People on their way home every round; a parent and child in most, the dog's walk in the others. Someone on a bicycle waits at the gate, rings and rides on (round 1); two cars wait, one on each side of the track, and pass each other when the gates rise (round 3); the black cat comes, sits and goes (rounds 2 and 5); crows (round 4); the child's red balloon gets away (round 6); a gust blows the falling petals down the street (round 7).

**Night.** A dark sky with a crescent moon, stars and a shooting star now and then; the street lamps and the windows lit, the Skytree lit blue and violet, moths about the near lamp. Few people: someone home late from the office, the dog's last walk twice, a student back from cram school once. The cat comes three times. In round 6 a motorcycle waits on this side and a car, its headlamps on, on the far side. Crickets, an owl, a dog barking far off, a can dropping in the vending machine.

## Sound

Four buttons sit at the bottom right of a chat and of a new chat: **Theme** (it steps through sunrise, sunset, night and day cycle), **Fade** (it steps through 100%, 50% and off; off shows the crossing behind a chat at full strength), **Restart** (the programme and its sounds start over) and **Turn sound on** / **Turn sound off**. With the sound on you hear the theme's air (birds at sunrise and sunset, crickets at night), each round's bell in time with its lamps, its train passing from the side it comes from, and that round's own sounds. Very low under it plays the theme's waltz for a soft piano and a music box: a bright one in C at sunrise, the one in F at sunset, a lullaby in A minor at night, with a round or two left silent.

Zeron lends plugins no audio, so the plugin plays the clips in `sounds/` with `player.js`, a short script for macOS's `osascript`. It joins each clip at the second the computer's clock says, so a sound you turn on part way through a round starts in step with the picture. The sound works on macOS only. The clips, the waltzes included, are synthesized by `python3 src/sounds.py`; no recording is used.

## Install

In Zeron: **Settings → Plugins → Install…**, then the repository `kevinfaveri/tokyo-feel`.

## Settings

**Settings → Plugins → Tokyo Feel**:

- **Use as wallpaper**: turns it on behind a new chat (only you can, there).
- **Pixel size**: Fine, Classic or Chunky.
- **Dither**: blends neighbouring palette colours with a checker pattern.
- **People**: the people and the dog who wait and cross.
- **Petals**: how many drift on the air.
- **Show behind chats** and **Strength**: the faded crossing behind a chat's messages.
- **Volume**: Quiet, Normal or Loud.

It asks for `ui.change` (to draw a new chat's background), `ui.add` (to place the crossing behind the transcript and the four buttons) and `commands` for three programs: `osascript` (runs `player.js`, which plays a clip), `pkill` (stops the plugin's own players, matched by the path of `player.js`) and `printenv` (reads `HOME` to find the clips). Zeron's consent sheet says of programs it does not know that they "can do anything you can"; `init.luau` shows the only calls made.

## Files

- `zeron-plugin.json`: the manifest, its settings, and Zeron's signature.
- `init.luau`: where the crossing is placed, its settings, the shaders' parameters.
- `tokyo_wgsl.luau`: the three shader sources, built by `python3 src/build.py`.
- `src/`: what that's built from. `build.py` lays out the crossing (trees, houses, poles and wires, the people's paths, the palette) as tables; `common.wgsl` is shared by `ground.wgsl` (the still scenery) and `live.wgsl` (what moves, and the sky); `show.wgsl` is the upscale.
- `sounds/`: the clips, built by `python3 src/sounds.py` (numpy, and macOS's `afconvert`).
- `zeron.luau`: Zeron's plugin SDK.

## Licence

MIT. See `LICENSE`.
