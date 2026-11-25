"""Synthesizes the crossing's sounds: python3 src/sounds.py [out_dir]

For each theme (sunrise, sunset, night) it writes sounds/round-<theme>-0.m4a
to round-<theme>-6.m4a (the seven rounds of that theme's five-minute
programme: the bell, the train, what else happens that round, and a section
of that theme's quiet waltz) and sounds/air-<theme>.m4a (the air between:
birds at sunrise and sunset, crickets at night). Needs numpy, and macOS's
afconvert for the AAC files.

Each round's clip follows the round in src/live.wgsl second for second: it
starts when the lamps start to blink.
"""

import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

SAMPLE_RATE = 32000
SEED = 20261125

LAMP_BLINKS_PER_SECOND = 1.15
BELL_STRIKES_PER_SECOND = 2 * LAMP_BLINKS_PER_SECOND
BELL_ENDS = 13.6
TRAIN_ARRIVES = 4.6
TRAIN_LEAVES = 11.5
SHINKANSEN_ARRIVES = 6.0
SHINKANSEN_LEAVES = 9.65
THEMES = ("sunrise", "sunset", "night")
SECONDS_PER_CAR = 1.0
ROUND_CLIP_SECONDS = 46.5
MUSIC_LEVEL = 0.032
AIR_SECONDS = 12.0
AIR_FADE_SECONDS = 1.5

rng = np.random.default_rng(SEED)


def seconds(duration):
    return np.arange(int(duration * SAMPLE_RATE)) / SAMPLE_RATE


def smoothstep(low, high, value):
    x = np.clip((value - low) / (high - low), 0.0, 1.0)
    return x * x * (3.0 - 2.0 * x)


def shaped_noise(duration, gain_at_frequency):
    count = int(duration * SAMPLE_RATE)
    spectrum = np.fft.rfft(rng.standard_normal(count))
    frequencies = np.fft.rfftfreq(count, 1.0 / SAMPLE_RATE)
    shaped = np.fft.irfft(spectrum * gain_at_frequency(frequencies), count)
    return shaped / (np.max(np.abs(shaped)) + 1e-9)


def band(low, high, softness=0.35):
    def gain(frequencies):
        rise = smoothstep(low * (1.0 - softness), low, frequencies)
        fall = 1.0 - smoothstep(high, high * (1.0 + softness), frequencies)
        return rise * fall

    return gain


def add_at(track, start_second, clip):
    start = int(start_second * SAMPLE_RATE)
    if start >= len(track):
        return
    end = min(start + len(clip), len(track))
    track[start:end] += clip[: end - start]


def panned(mono, position):
    """position: -1 left to 1 right, a number or one value per sample."""
    angle = (np.asarray(position) + 1.0) * np.pi / 4.0
    return np.stack([mono * np.cos(angle), mono * np.sin(angle)], axis=1)


def bell_strike():
    t = seconds(0.42)
    partials = [(702.0, 1.0, 0.11), (748.0, 0.9, 0.11), (1405.0, 0.35, 0.06), (2110.0, 0.18, 0.04)]
    strike = sum(level * np.sin(2 * np.pi * pitch * t) * np.exp(-t / decay) for pitch, level, decay in partials)
    return strike * smoothstep(0.0, 0.002, t)


def bell():
    track = np.zeros(int(ROUND_CLIP_SECONDS * SAMPLE_RATE))
    strike = bell_strike()
    for index in range(int(BELL_ENDS * BELL_STRIKES_PER_SECOND) + 1):
        add_at(track, index / BELL_STRIKES_PER_SECOND, strike)
    return track * 0.16


def wheel_clack():
    t = seconds(0.09)
    click = shaped_noise(0.09, band(900.0, 3800.0)) * np.exp(-t / 0.012)
    thump = np.sin(2 * np.pi * 85.0 * t) * np.exp(-t / 0.035)
    return click * 0.5 + thump * 0.9


def side_to_side(t, arrives, leaves, from_right):
    across = np.clip((t - arrives) / (leaves - arrives), -0.4, 1.4)
    position = np.clip((across - 0.5) * 1.1, -0.8, 0.8)
    return -position if from_right else position


def commuter_train(from_right, freight):
    t = seconds(ROUND_CLIP_SECONDS)
    near = smoothstep(TRAIN_ARRIVES - 2.2, TRAIN_ARRIVES + 0.5, t) * (1.0 - smoothstep(TRAIN_LEAVES - 0.3, TRAIN_LEAVES + 2.6, t))
    rumble_band = band(22.0, 120.0) if freight else band(28.0, 170.0)
    rumble = shaped_noise(ROUND_CLIP_SECONDS, rumble_band) * (0.75 if freight else 0.55)
    rush = shaped_noise(ROUND_CLIP_SECONDS, band(350.0, 2600.0)) * (0.13 if freight else 0.2)
    hum = np.sin(2 * np.pi * (62.0 if freight else 118.0) * t) * 0.05
    body = (rumble + rush + hum) * near**1.6

    clacks = np.zeros_like(t)
    clack = wheel_clack() * (1.3 if freight else 1.0)
    for car_start in np.arange(TRAIN_ARRIVES + 0.25, TRAIN_LEAVES - 0.2, SECONDS_PER_CAR):
        add_at(clacks, car_start, clack)
        add_at(clacks, car_start + 0.13, clack * 0.85)
    return panned(body + clacks * 0.28, side_to_side(t, TRAIN_ARRIVES, TRAIN_LEAVES, from_right))


def shinkansen(from_right):
    """Faster and louder: a wall of air that arrives at once, a falling whine, no wheel beat."""
    t = seconds(ROUND_CLIP_SECONDS)
    near = smoothstep(SHINKANSEN_ARRIVES - 1.1, SHINKANSEN_ARRIVES + 0.15, t) * (1.0 - smoothstep(SHINKANSEN_LEAVES - 0.1, SHINKANSEN_LEAVES + 2.2, t))
    air = shaped_noise(ROUND_CLIP_SECONDS, band(180.0, 5200.0)) * 0.5
    ground = shaped_noise(ROUND_CLIP_SECONDS, band(24.0, 150.0)) * 0.8
    passing = np.clip((t - SHINKANSEN_ARRIVES) / (SHINKANSEN_LEAVES - SHINKANSEN_ARRIVES), 0.0, 1.0)
    whine_pitch = 1150.0 - 420.0 * smoothstep(0.35, 0.65, passing)
    whine = np.sin(2 * np.pi * np.cumsum(whine_pitch) / SAMPLE_RATE) * 0.045
    thump = np.zeros_like(t)
    arrival = seconds(0.5)
    add_at(thump, SHINKANSEN_ARRIVES - 0.05, np.sin(2 * np.pi * 48.0 * arrival) * np.exp(-arrival / 0.12) * 0.7)
    body = (air + ground + whine) * near**1.3 + thump
    return panned(body, side_to_side(t, SHINKANSEN_ARRIVES, SHINKANSEN_LEAVES, from_right))


def horn(freight):
    t = seconds(1.4 if freight else 0.9)
    pitches = (185.0, 233.0) if freight else (349.0, 440.0)
    tone = sum(np.sin(2 * np.pi * pitch * t) + 0.4 * np.sin(4 * np.pi * pitch * t) for pitch in pitches)
    envelope = smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(len(t) / SAMPLE_RATE - 0.25, len(t) / SAMPLE_RATE, t))
    return tone * envelope * 0.035


def crossing(from_right, kind):
    """kind: "commuter", "freight" or "shinkansen"."""
    if kind == "shinkansen":
        return panned(bell(), 0.15) + shinkansen(from_right)
    freight = kind == "freight"
    mix = panned(bell(), 0.15) + commuter_train(from_right, freight)
    horn_track = np.zeros(len(mix))
    add_at(horn_track, TRAIN_ARRIVES - 1.6, horn(freight))
    return mix + panned(horn_track, 0.7 if from_right else -0.7)


def meow():
    t = seconds(0.62)
    glide = 520.0 + 380.0 * np.sin(np.pi * (t / 0.62) ** 0.7)
    phase = 2 * np.pi * np.cumsum(glide) / SAMPLE_RATE
    voice = np.sin(phase) + 0.5 * np.sin(2 * phase) + 0.3 * np.sin(3 * phase)
    return voice * np.sin(np.pi * t / 0.62) ** 1.5 * 0.035


def crow():
    t = seconds(0.34)
    rasp = shaped_noise(0.34, band(900.0, 2600.0))
    voice = np.sin(2 * np.pi * 620.0 * t * (1.0 - 0.25 * t / 0.34)) * (0.5 + 0.5 * np.sign(np.sin(2 * np.pi * 70.0 * t)))
    return (voice * 0.6 + rasp * 0.5) * np.sin(np.pi * t / 0.34) ** 0.7 * 0.03


def bicycle_bell():
    t = seconds(0.9)
    ring = sum(level * np.sin(2 * np.pi * pitch * t) for pitch, level in ((2090.0, 1.0), (3140.0, 0.5), (4730.0, 0.25)))
    return ring * np.exp(-t / 0.25) * smoothstep(0.0, 0.003, t) * 0.02


def gust():
    t = seconds(11.0)
    swell = np.sin(np.pi * t / 11.0) ** 2
    return shaped_noise(11.0, band(140.0, 900.0)) * swell * 0.16 + shaped_noise(11.0, band(2000.0, 6000.0)) * swell**2 * 0.04


def sparrows():
    track = np.zeros(int(14.0 * SAMPLE_RATE))
    for chirp_at in np.sort(rng.uniform(0.0, 13.5, 26)):
        add_at(track, chirp_at, bird_chirp(rng.uniform(3800.0, 5200.0), rng.uniform(-900.0, 600.0), rng.uniform(0.04, 0.07)) * 0.02)
    return track


def bush_warbler():
    """The uguisu's call: one long rising whistle, then three quick notes."""
    whistle = seconds(1.25)
    pitch = 1150.0 + 260.0 * (whistle / 1.25) ** 3
    call = np.sin(2 * np.pi * np.cumsum(pitch) / SAMPLE_RATE) * smoothstep(0.0, 0.5, whistle) * (1.0 - smoothstep(1.15, 1.25, whistle))
    track = np.zeros(int(2.2 * SAMPLE_RATE))
    add_at(track, 0.0, call)
    for note_at, note_pitch, sweep in ((1.3, 2500.0, 500.0), (1.46, 3300.0, -300.0), (1.62, 2300.0, 900.0)):
        add_at(track, note_at, bird_chirp(note_pitch, sweep, 0.14))
    return track * 0.03


def school_chime():
    """The Westminster quarters, as a school far off rings them."""
    phrases = (("G#4", "F#4", "E4", "B3"), ("E4", "F#4", "G#4", "E4"), ("G#4", "E4", "F#4", "B3"), ("B3", "F#4", "G#4", "E4"))
    track = np.zeros(int(17.0 * SAMPLE_RATE))
    strike = seconds(2.4)
    for phrase_index, phrase in enumerate(phrases):
        for note_index, note in enumerate(phrase):
            pitch = pitch_of(note)
            tone = (np.sin(2 * np.pi * pitch * strike) + 0.4 * np.sin(2 * np.pi * pitch * 2.76 * strike) * np.exp(-strike / 0.3)) * np.exp(-strike / 0.9)
            add_at(track, phrase_index * 4.0 + note_index * 0.8, tone * smoothstep(0.0, 0.01, strike))
    return track * 0.012


def dog_bark():
    t = seconds(0.16)
    voice = np.sin(2 * np.pi * (420.0 - 900.0 * t) * t) + 0.6 * shaped_noise(0.16, band(500.0, 1800.0))
    return voice * np.sin(np.pi * t / 0.16) * 0.014


def can_drop():
    t = seconds(0.35)
    clunk = np.sin(2 * np.pi * 140.0 * t) * np.exp(-t / 0.05) + 0.5 * shaped_noise(0.35, band(1200.0, 4000.0)) * np.exp(-t / 0.03)
    track = np.zeros(int(0.8 * SAMPLE_RATE))
    add_at(track, 0.0, clunk)
    add_at(track, 0.28, clunk * 0.5)
    return track * 0.03


def owl():
    track = np.zeros(int(2.0 * SAMPLE_RATE))
    for hoot_at, length in ((0.0, 0.45), (0.7, 0.22), (1.0, 0.6)):
        t = seconds(length)
        add_at(track, hoot_at, np.sin(2 * np.pi * 330.0 * t) * np.sin(np.pi * t / length) ** 2)
    return track * 0.02


# ---- the waltz: in F, three beats to a bar, sixteen bars to a round ----------

BARS_PER_ROUND = 16
BEATS_PER_BAR = 3
ROUND_SECONDS = 44.0
BEAT_SECONDS = ROUND_SECONDS / (BARS_PER_ROUND * BEATS_PER_BAR)

NOTE_NUMBERS = {"C": 0, "C#": 1, "D": 2, "E": 4, "F": 5, "F#": 6, "G": 7, "G#": 8, "A": 9, "Bb": 10, "B": 11}


def pitch_of(name):
    return 440.0 * 2.0 ** ((NOTE_NUMBERS[name[:-1]] + 12 * (int(name[-1]) + 1) - 69) / 12.0)


CHORDS = {
    "Bbmaj7": ("Bb2", ("D4", "F4", "A4")), "C": ("C3", ("E4", "G4", "C4")), "Am7": ("A2", ("C4", "E4", "G4")),
    "Dm": ("D3", ("D4", "F4", "A4")), "F": ("F2", ("C4", "F4", "A4")), "Gm7": ("G2", ("Bb3", "D4", "F4")),
    "C7": ("C3", ("E4", "G4", "Bb4")), "Bb": ("Bb2", ("D4", "F4", "Bb4")), "A": ("A2", ("C#4", "E4", "A4")),
    "A7": ("A2", ("C#4", "E4", "G4")), "G": ("G2", ("B3", "D4", "G4")), "Am": ("A2", ("C4", "E4", "A4")),
    "Em": ("E2", ("B3", "E4", "G4")), "E": ("E2", ("G#3", "B3", "E4")),
}

# Each bar: its chord, then its melody as (note, beats).
THEME = [
    ("Bbmaj7", [("D5", 2), ("F5", 1)]), ("C", [("E5", 2), ("G5", 1)]), ("Am7", [("E5", 1), ("C5", 1), ("A4", 1)]), ("Dm", [("D5", 3)]),
    ("Bbmaj7", [("D5", 1), ("F5", 1), ("A5", 1)]), ("C", [("G5", 2), ("E5", 1)]), ("F", [("F5", 3)]), ("F", [(None, 2), ("C5", 1)]),
    ("Bbmaj7", [("D5", 2), ("F5", 1)]), ("C", [("E5", 2), ("G5", 1)]), ("Am7", [("A5", 1), ("G5", 1), ("E5", 1)]), ("Dm", [("F5", 2), ("D5", 1)]),
    ("Gm7", [("Bb4", 1), ("D5", 1), ("G5", 1)]), ("C7", [("E5", 2), ("D5", 1)]), ("F", [("C5", 1), ("F5", 2)]), ("F", [("F5", 3)]),
]
ANSWER = [
    ("Dm", [("A4", 1), ("D5", 1), ("F5", 1)]), ("Bb", [("F5", 2), ("D5", 1)]), ("C", [("E5", 1), ("G5", 1), ("C6", 1)]), ("F", [("A5", 3)]),
    ("Dm", [("A5", 1), ("F5", 1), ("D5", 1)]), ("Bb", [("D5", 2), ("Bb4", 1)]), ("C", [("C5", 1), ("E5", 1), ("G5", 1)]), ("A", [("E5", 3)]),
    ("Dm", [("F5", 1), ("A5", 1), ("D6", 1)]), ("Bb", [("D6", 2), ("Bb5", 1)]), ("C", [("C6", 1), ("G5", 1), ("E5", 1)]), ("F", [("F5", 2), ("A5", 1)]),
    ("Gm7", [("G5", 1), ("Bb5", 1), ("D6", 1)]), ("A7", [("C#6", 2), ("A5", 1)]), ("Dm", [("D6", 3)]), ("Dm", [("D5", 3)]),
]


# Sunrise's, in C: brighter and higher.
MORNING = [
    ("C", [("E5", 1), ("G5", 1), ("C6", 1)]), ("F", [("A5", 2), ("G5", 1)]), ("C", [("E5", 2), ("G5", 1)]), ("G", [("D5", 3)]),
    ("Am", [("C5", 1), ("E5", 1), ("A5", 1)]), ("F", [("G5", 2), ("F5", 1)]), ("C", [("E5", 2), ("D5", 1)]), ("G", [("D5", 2), ("G5", 1)]),
    ("C", [("E5", 1), ("G5", 1), ("C6", 1)]), ("F", [("A5", 2), ("C6", 1)]), ("Em", [("B5", 2), ("G5", 1)]), ("Am", [("A5", 3)]),
    ("F", [("F5", 1), ("A5", 1), ("C6", 1)]), ("G", [("B5", 2), ("D6", 1)]), ("C", [("C6", 3)]), ("C", [("G5", 1), ("E5", 1), ("C5", 1)]),
]
MORNING_ANSWER = [
    ("Am", [("A5", 2), ("E5", 1)]), ("F", [("F5", 2), ("A5", 1)]), ("C", [("G5", 2), ("E5", 1)]), ("G", [("D5", 2), ("B4", 1)]),
    ("Am", [("C5", 1), ("E5", 1), ("A5", 1)]), ("F", [("C6", 2), ("A5", 1)]), ("G", [("B5", 2), ("G5", 1)]), ("G", [("D5", 3)]),
    ("F", [("A5", 1), ("C6", 1), ("F5", 1)]), ("C", [("G5", 2), ("E5", 1)]), ("Dm", [("F5", 2), ("D5", 1)]), ("G", [("G5", 3)]),
    ("F", [("A5", 1), ("G5", 1), ("F5", 1)]), ("G", [("D5", 1), ("G5", 1), ("B5", 1)]), ("C", [("C6", 3)]), ("C", [("C5", 3)]),
]
# Night's, in A minor: a lullaby, low and slow.
LULLABY = [
    ("Am", [("E4", 2), ("A4", 1)]), ("Am", [("C5", 3)]), ("F", [("A4", 2), ("C5", 1)]), ("F", [("F4", 3)]),
    ("Dm", [("D4", 2), ("F4", 1)]), ("Dm", [("A4", 3)]), ("E", [("G#4", 2), ("B4", 1)]), ("E", [("E4", 3)]),
    ("Am", [("E4", 2), ("A4", 1)]), ("Am", [("C5", 2), ("E5", 1)]), ("F", [("D5", 2), ("C5", 1)]), ("F", [("A4", 3)]),
    ("Dm", [("F4", 2), ("A4", 1)]), ("E", [("G#4", 2), ("B4", 1)]), ("Am", [("A4", 3)]), ("Am", [(None, 3)]),
]
LULLABY_ANSWER = [
    ("F", [("C5", 2), ("A4", 1)]), ("G", [("B4", 2), ("D5", 1)]), ("Em", [("G4", 2), ("B4", 1)]), ("Am", [("A4", 3)]),
    ("F", [("A4", 1), ("C5", 1), ("F5", 1)]), ("G", [("D5", 2), ("B4", 1)]), ("C", [("E5", 3)]), ("E", [("G#4", 3)]),
    ("F", [("C5", 2), ("A4", 1)]), ("G", [("B4", 2), ("G4", 1)]), ("Em", [("E4", 2), ("G4", 1)]), ("Am", [("C5", 3)]),
    ("Dm", [("D5", 2), ("A4", 1)]), ("E", [("B4", 2), ("G#4", 1)]), ("Am", [("A4", 3)]), ("Am", [("E4", 3)]),
]


def sparse(bars):
    return [(chord, [(melody[0][0], 3)] if index % 2 == 0 else [(None, 3)]) for index, (chord, melody) in enumerate(bars)]


def soft_key(pitch, beats, level):
    t = seconds(beats * BEAT_SECONDS + 2.2)
    tone = sum(strength * np.sin(2 * np.pi * pitch * harmonic * t) * np.exp(-t * harmonic / 1.5)
               for harmonic, strength in ((1, 1.0), (2, 0.42), (3, 0.18), (4, 0.07)))
    return tone * smoothstep(0.0, 0.012, t) * level


def music_box(pitch, level):
    t = seconds(1.6)
    tone = np.sin(2 * np.pi * pitch * t) + 0.3 * np.sin(2 * np.pi * pitch * 3.01 * t) * np.exp(-t / 0.15)
    return tone * np.exp(-t / 0.45) * smoothstep(0.0, 0.004, t) * level


def room(stereo):
    count = int(1.4 * SAMPLE_RATE)
    tail = rng.standard_normal((count, 2)) * np.exp(-np.arange(count) / (0.38 * SAMPLE_RATE))[:, None]
    wet = np.stack([np.convolve(stereo[:, side], tail[:, side])[: len(stereo)] for side in (0, 1)], axis=1)
    return stereo + wet * 0.012


def waltz(bars, with_music_box=False, with_left_hand=True):
    melody = np.zeros(int(ROUND_CLIP_SECONDS * SAMPLE_RATE))
    left_hand = np.zeros_like(melody)
    chimes = np.zeros_like(melody)
    for bar_index, (chord, notes) in enumerate(bars):
        bar_start = bar_index * BEATS_PER_BAR * BEAT_SECONDS
        beat = 0
        for note, beats in notes:
            if note is not None:
                add_at(melody, bar_start + beat * BEAT_SECONDS, soft_key(pitch_of(note), beats, 1.0))
                if with_music_box:
                    add_at(chimes, bar_start + beat * BEAT_SECONDS, music_box(pitch_of(note) * 2.0, 0.5))
            beat += beats
        if with_left_hand:
            bass, upper = CHORDS[chord]
            add_at(left_hand, bar_start, soft_key(pitch_of(bass), 3, 0.7))
            for beat in (1, 2):
                for upper_note in upper[:2] if beat == 1 else upper[1:]:
                    add_at(left_hand, bar_start + beat * BEAT_SECONDS, soft_key(pitch_of(upper_note), 1, 0.28))
    return room(panned(melody, 0.1) + panned(left_hand, -0.2) + panned(chimes, 0.4)) * MUSIC_LEVEL


# ---- the programmes: seven rounds a theme, as src/live.wgsl has them ---------

def train_of(theme, index):
    if index % 2 == 1:
        return "shinkansen"
    if theme == "night" and index == 4:
        return "freight"
    return "commuter"


def comes_from_right(index):
    return ((index + 1) // 2) % 2 == 1


# Each round: the waltz it carries (bars, with a music box, with a left hand)
# or None, then what else sounds, as (second, sound, level, left to right).
SCREENPLAYS = {
    "sunrise": [
        ((MORNING, True, True), [(20.0, sparrows, 1.0, 0.0)]),
        ((MORNING_ANSWER, False, True), [(22.0, bush_warbler, 1.0, -0.6)]),
        ((MORNING, False, True), [(18.0, bush_warbler, 1.0, 0.5), (30.0, bicycle_bell, 1.0, 0.6), (30.5, bicycle_bell, 1.0, 0.6)]),
        (None, [(20.0, sparrows, 1.0, 0.0), (36.0, bush_warbler, 0.7, -0.4)]),
        ((MORNING_ANSWER, True, True), [(24.6, meow, 1.0, -0.2)]),
        (("sparse", MORNING, False, False), [(17.0, school_chime, 1.0, 0.3)]),
        ((MORNING, True, True), [(20.0, sparrows, 1.0, 0.0)]),
    ],
    "sunset": [
        ((THEME, False, True), [(29.0, bicycle_bell, 1.0, 0.5), (29.5, bicycle_bell, 1.0, 0.5)]),
        ((ANSWER, False, True), [(24.6, meow, 1.0, -0.2)]),
        ((THEME, True, True), []),
        (None, [(20.0, crow, 1.0, -0.6), (20.5, crow, 1.0, -0.6), (21.3, crow, 1.0, -0.6), (30.0, crow, 0.8, 0.4), (30.5, crow, 0.8, 0.4)]),
        (("sparse", THEME, False, False), [(24.6, meow, 1.0, -0.2), (26.4, meow, 0.7, -0.2)]),
        ((ANSWER, True, True), []),
        (("sparse", ANSWER, False, True), [(22.5, gust, 1.0, 0.0)]),
    ],
    "night": [
        ((LULLABY, False, True), [(24.6, meow, 1.0, -0.2)]),
        (None, [(22.0, owl, 1.0, -0.7), (33.0, dog_bark, 1.0, 0.6), (33.4, dog_bark, 1.0, 0.6)]),
        ((LULLABY_ANSWER, False, True), [(30.0, can_drop, 1.0, 0.7)]),
        (("sparse", LULLABY, False, False), [(24.6, meow, 1.0, -0.2), (36.0, owl, 0.8, 0.5)]),
        (None, [(26.0, dog_bark, 0.8, -0.5), (26.5, dog_bark, 0.8, -0.5), (27.4, dog_bark, 0.6, -0.5)]),
        ((LULLABY, True, True), [(28.0, owl, 1.0, -0.7)]),
        (("sparse", LULLABY_ANSWER, False, True), [(24.6, meow, 1.0, -0.2)]),
    ],
}


def round_clip(theme, index):
    music, sounds = SCREENPLAYS[theme][index]
    mix = crossing(comes_from_right(index), train_of(theme, index))
    if music is not None:
        thin = music[0] == "sparse"
        bars, with_music_box, with_left_hand = music[1:] if thin else music
        mix += waltz(sparse(bars) if thin else bars, with_music_box, with_left_hand)
    for start, sound, level, position in sounds:
        track = np.zeros(len(mix))
        add_at(track, start, sound() * level)
        mix += panned(track, position)
    t = seconds(ROUND_CLIP_SECONDS)
    return mix * (1.0 - smoothstep(ROUND_CLIP_SECONDS - 1.5, ROUND_CLIP_SECONDS, t))[:, None]


def bird_chirp(pitch, sweep, length):
    t = seconds(length)
    glide = pitch + sweep * (t / length) ** 2
    phase = 2 * np.pi * np.cumsum(glide) / SAMPLE_RATE
    envelope = np.sin(np.pi * t / length) ** 2
    return np.sin(phase) * envelope


def birds(phrase_starts):
    track = np.zeros((int(AIR_SECONDS * SAMPLE_RATE), 2))
    for phrase_start in phrase_starts:
        position = rng.uniform(-0.8, 0.8)
        pitch = rng.uniform(2600.0, 3600.0)
        notes = rng.integers(2, 5)
        for note in range(notes):
            chirp = bird_chirp(pitch + note * rng.uniform(-150.0, 220.0), rng.uniform(300.0, 900.0), rng.uniform(0.07, 0.13))
            start = int((phrase_start + note * 0.17) * SAMPLE_RATE)
            track[start : start + len(chirp)] += panned(chirp, position) * 0.017
    return track


def cricket_chirp(pitch, pulses):
    """One chirp: a few short pulses of the wing, each falling a little in pitch."""
    pulse_seconds, gap_seconds = 0.017, 0.015
    t = seconds(pulse_seconds)
    swell = np.sin(np.pi * t / pulse_seconds) ** 2
    pulse = np.sin(2 * np.pi * (pitch - 900.0 * t) * t) * swell
    gap = np.zeros(int(gap_seconds * SAMPLE_RATE))
    return np.concatenate([np.concatenate([pulse * (0.7 + 0.3 * index / pulses), gap]) for index in range(pulses)])


def crickets():
    """A few crickets far off in the grass. Each chirps for a while, then rests."""
    track = np.zeros((int(AIR_SECONDS * SAMPLE_RATE), 2))
    for pitch, pulses, chirp_every, sings, rests, level, position in (
        (4350.0, 3, 0.62, 4.5, 2.5, 0.011, -0.65),
        (4800.0, 4, 0.81, 3.2, 4.1, 0.007, 0.55),
        (3950.0, 3, 0.70, 2.4, 5.3, 0.005, 0.15),
    ):
        chirp_start = rng.uniform(0.0, rests)
        song_ends = chirp_start + sings
        while chirp_start < AIR_SECONDS - 0.3:
            chirp = cricket_chirp(pitch * rng.uniform(0.99, 1.01), pulses) * rng.uniform(0.75, 1.0)
            start = int(chirp_start * SAMPLE_RATE)
            track[start : start + len(chirp)] += panned(chirp * level, position)
            chirp_start += chirp_every * rng.uniform(0.94, 1.06)
            if chirp_start > song_ends:
                chirp_start += rests * rng.uniform(0.7, 1.3)
                song_ends = chirp_start + sings
    return track


def air(theme):
    t = seconds(AIR_SECONDS)
    swell = 0.6 + 0.4 * np.sin(2 * np.pi * t / AIR_SECONDS - 1.0)
    wind_level = {"sunrise": 0.07, "sunset": 0.11, "night": 0.06}[theme]
    wind = shaped_noise(AIR_SECONDS, band(90.0, 520.0)) * swell * wind_level
    leaves = shaped_noise(AIR_SECONDS, band(2400.0, 7000.0)) * swell**2 * wind_level * 0.25
    city = shaped_noise(AIR_SECONDS, band(40.0, 110.0)) * (0.05 if theme == "night" else 0.09)
    drift = 0.25 * np.sin(2 * np.pi * t / AIR_SECONDS)
    mix = panned(wind + leaves, drift) + panned(city, 0.0)
    if theme == "sunrise":
        mix += birds([0.6, 2.1, 3.3, 4.9, 6.2, 7.4, 8.8, 9.9])
    elif theme == "sunset":
        mix += birds([1.4, 5.2, 8.9])
    else:
        mix += crickets()
    edge = smoothstep(0.0, AIR_FADE_SECONDS, t) * (1.0 - smoothstep(AIR_SECONDS - AIR_FADE_SECONDS, AIR_SECONDS, t))
    return mix * edge[:, None]


def write_aac(stereo, path):
    samples = (np.clip(stereo, -1.0, 1.0) * 32767.0).astype("<i2")
    wav_path = path.with_suffix(".wav")
    with wave.open(str(wav_path), "wb") as wav:
        wav.setnchannels(2)
        wav.setsampwidth(2)
        wav.setframerate(SAMPLE_RATE)
        wav.writeframes(samples.tobytes())
    subprocess.run(["afconvert", "-f", "m4af", "-d", "aac", "-b", "64000", str(wav_path), str(path)], check=True)
    wav_path.unlink()
    print(f"{path}  {path.stat().st_size // 1024} KB  peak {np.max(np.abs(stereo)):.2f}")


def main():
    out_dir = Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent / "sounds"
    out_dir.mkdir(parents=True, exist_ok=True)
    for theme in THEMES:
        for index in range(7):
            write_aac(round_clip(theme, index), out_dir / f"round-{theme}-{index}.m4a")
        write_aac(air(theme), out_dir / f"air-{theme}.m4a")


if __name__ == "__main__":
    main()
