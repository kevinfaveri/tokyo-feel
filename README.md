# Tokyo Feel

A Zeron plugin: a pixel-art railway crossing in sakura season, behind a new chat and, faded, behind your chats.

You stand at the roadside in the evening. The crossing's lamps blink and its gates fall; a commuter train passes, its windows lit, sweeping the petals along with it; the gates rise and the people who waited cross: a parent and a child in a yellow hat, someone with a dog, an office worker and a student coming the other way. Sakura and green trees stand round the road, petals drift down and lie on the asphalt, a street lamp and a vending machine glow, and a far city with its tower is lit under a crescent moon.

Trains alternate: one from the left with a green stripe, the next from the right with a blue one.

## The look

It follows [Deep Reef](https://github.com/wingleeio/pixel-reef) by Wing Lee, which follows the pixel-art gaussian splats at [splats.cobanov.dev](https://splats.cobanov.dev): forms sculpted in 3D, every surface point lit (a soft key light, occlusion, a grain per material, warm light pooling under lamps) and coloured through a ramp; the picture drawn small; translucent things (a lamp's glow, the land's far edge) cut to on/off pixels by a Bayer threshold; every pixel the nearest of a small palette. The scene, its models and its palette are this plugin's own.

## How it runs

Everything is on the GPU, in `tokyo_wgsl.luau`, at one texel per art pixel:

- **GROUND**: the still scenery, drawn once (and again when the window changes size) and kept.
- **LIVE**: what moves, drawn each frame over it: 24 frames a second behind a new chat, 15 behind chats.
- **SHOW**: scales the result up, nearest-neighbour.

Zeron's compositor steps the clock, so no script runs per frame. One round of the crossing takes 44 seconds.

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

It asks for `ui.change` (to draw a new chat's background) and `ui.add` (to place the crossing behind the transcript), nothing else.

## Files

- `zeron-plugin.json`: the manifest, its settings, and Zeron's signature.
- `init.luau`: where the crossing is placed, its settings, the shaders' parameters.
- `tokyo_wgsl.luau`: the three shader sources, built by `python3 src/build.py`.
- `src/`: what that's built from. `build.py` lays out the crossing (trees, houses, poles and wires, the people's paths, the palette) as tables; `common.wgsl` is shared by `ground.wgsl` (the still scenery) and `live.wgsl` (what moves, and the sky); `show.wgsl` is the upscale.
- `zeron.luau`: Zeron's plugin SDK.
