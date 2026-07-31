#!/usr/bin/env python3
"""Generate the placeholder SFX in audio/sfx/.

BUILD-PLAN week 3 asks for "swing + impact as separate layers, pitch-randomised
+/-10%". The pitch randomisation lives in autoloads/sfx.gd; this just produces
eight short, ugly, distinguishable noises so that tuning happens with sound in
the loop rather than after it.

These are placeholders and are meant to be replaced (GDD section 9 budgets real
audio). Regenerate with:

    python3 tools/gen_placeholder_sfx.py
"""

from __future__ import annotations

import math
import os
import random
import struct
import wave

SAMPLE_RATE = 22050
OUT_DIR = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "audio", "sfx")

# Fixed seed: regenerating should not silently change how the prototype sounds.
random.seed(20250726)


def envelope(i: int, total: int, attack: float, decay_curve: float) -> float:
    """Fast attack, exponential decay. `attack` is a fraction of the length."""
    t = i / max(total - 1, 1)
    attack_gain = min(t / attack, 1.0) if attack > 0 else 1.0
    return attack_gain * math.exp(-decay_curve * t)


def noise_burst(duration, attack=0.01, decay=14.0, low_pass=0.0, gain=0.6):
    total = int(SAMPLE_RATE * duration)
    samples = []
    previous = 0.0
    for i in range(total):
        value = random.uniform(-1.0, 1.0)
        if low_pass > 0.0:
            # One-pole low pass; higher `low_pass` = duller.
            value = previous + (value - previous) / low_pass
            previous = value
        samples.append(value * envelope(i, total, attack, decay) * gain)
    return samples


def tone(duration, start_hz, end_hz, attack=0.01, decay=10.0, gain=0.6, square=False):
    total = int(SAMPLE_RATE * duration)
    samples = []
    phase = 0.0
    for i in range(total):
        t = i / max(total - 1, 1)
        # Exponential sweep reads as "pitch drop" rather than "slide".
        hz = start_hz * ((end_hz / start_hz) ** t)
        phase += 2.0 * math.pi * hz / SAMPLE_RATE
        raw = math.sin(phase)
        if square:
            raw = 1.0 if raw >= 0.0 else -1.0
        samples.append(raw * envelope(i, total, attack, decay) * gain)
    return samples


def mix(*layers):
    length = max(len(layer) for layer in layers)
    out = [0.0] * length
    for layer in layers:
        for i, value in enumerate(layer):
            out[i] += value
    peak = max(abs(v) for v in out) or 1.0
    if peak > 1.0:
        out = [v / peak for v in out]
    return out


def write_wav(name: str, samples) -> None:
    path = os.path.join(OUT_DIR, name)
    with wave.open(path, "wb") as handle:
        handle.setnchannels(1)
        handle.setsampwidth(2)
        handle.setframerate(SAMPLE_RATE)
        frames = b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, value)) * 32000)) for value in samples
        )
        handle.writeframes(frames)
    print(f"  {name}  ({len(samples) / SAMPLE_RATE * 1000:.0f}ms)")


SOUNDS = {
    # Swings are air, not impact: filtered noise with no low end.
    "swing_light.wav": lambda: noise_burst(0.09, attack=0.25, decay=18.0, low_pass=1.6, gain=0.35),
    "swing_heavy.wav": lambda: noise_burst(0.16, attack=0.3, decay=11.0, low_pass=2.6, gain=0.5),
    # Impacts get a body (the tone) under the crack (the noise).
    "impact_light.wav": lambda: mix(
        noise_burst(0.08, decay=26.0, low_pass=2.0, gain=0.5),
        tone(0.08, 320, 140, decay=24.0, gain=0.45),
    ),
    "impact_heavy.wav": lambda: mix(
        noise_burst(0.16, decay=16.0, low_pass=3.2, gain=0.55),
        tone(0.18, 200, 60, decay=13.0, gain=0.7),
    ),
    "dodge.wav": lambda: noise_burst(0.14, attack=0.35, decay=13.0, low_pass=3.0, gain=0.3),
    "player_hurt.wav": lambda: mix(
        tone(0.22, 420, 110, decay=11.0, gain=0.55, square=True),
        noise_burst(0.1, decay=20.0, low_pass=2.0, gain=0.3),
    ),
    # The telegraph cue has to be audible without being a jump-scare: a rising
    # tone, so it reads as "about to" rather than "just did".
    "enemy_telegraph.wav": lambda: tone(0.3, 180, 340, attack=0.2, decay=3.5, gain=0.32),
    "enemy_death.wav": lambda: mix(
        tone(0.32, 260, 45, decay=8.0, gain=0.55, square=True),
        noise_burst(0.26, decay=9.0, low_pass=3.6, gain=0.4),
    ),
    # ---- voice blips, one per few revealed characters (ui/dialogue_box.gd)
    #
    # The Animal Crossing trick: no words, just a short pitched blip per
    # syllable, so text has a voice without anybody recording one.
    #
    # **Deeper than Animal Crossing, but not by as much as the first attempt.**
    # Theirs sits around 600Hz and reads as cheerful chirping, which is wrong for
    # a town that has been losing. The first version went to 190-260Hz and was
    # inaudible: 60% of its energy sat below 300Hz, playback pitched it *down*
    # again by each speaker's offset — the guard is 0.78, so his fundamental
    # landed near 150Hz — and small speakers roll off hard down there. Measured,
    # they were 10dB quieter than every other sound in the game.
    #
    # These sit at 330-430Hz with a strong second harmonic, which is the part
    # that actually carries on a laptop. Still unmistakably low, and audible.
    "voice_a.wav": lambda: mix(
        tone(0.055, 372, 318, attack=0.12, decay=15.0, gain=0.55),
        tone(0.05, 744, 636, attack=0.12, decay=18.0, gain=0.3),
    ),
    "voice_b.wav": lambda: mix(
        tone(0.06, 336, 292, attack=0.14, decay=14.0, gain=0.55),
        tone(0.052, 672, 584, attack=0.14, decay=17.0, gain=0.28),
    ),
    "voice_c.wav": lambda: mix(
        tone(0.05, 424, 352, attack=0.1, decay=17.0, gain=0.52),
        tone(0.044, 848, 704, attack=0.1, decay=20.0, gain=0.3),
    ),
    "ui_move.wav": lambda: tone(0.035, 520, 460, attack=0.1, decay=26.0, gain=0.22),
    "ui_select.wav": lambda: mix(
        tone(0.09, 380, 620, attack=0.08, decay=14.0, gain=0.3),
        noise_burst(0.04, decay=30.0, low_pass=2.0, gain=0.1),
    ),
    # Refusal. A short fall, where `ui_select` is a short rise — the pair has to
    # be tellable apart with the music up and without looking, because "that did
    # not work" is the whole message.
    "ui_deny.wav": lambda: tone(0.11, 300, 170, attack=0.06, decay=13.0, gain=0.28),
    # ---- the bow
    #
    # The draw is the sound that has to carry information: it plays at full
    # draw, and it is how the player knows the shot is ready without watching a
    # meter. So it rises and it is nearly clean — everything else in this bank
    # is noise, and a tone cuts through a fight.
    "bow_draw.wav": lambda: mix(
        tone(0.13, 240, 430, attack=0.18, decay=7.0, gain=0.26),
        noise_burst(0.1, attack=0.4, decay=16.0, low_pass=4.0, gain=0.09),
    ),
    # The loose is the opposite: mostly air, over in a blink, and pitched well
    # above the sword's swing so a bow never sounds like a blade.
    "bow_loose.wav": lambda: mix(
        noise_burst(0.07, attack=0.05, decay=30.0, low_pass=1.25, gain=0.34),
        tone(0.05, 900, 380, decay=28.0, gain=0.16),
    ),
    # An arrow into a wall or into the dirt: dry, wooden, no body under it. The
    # sound of a shot that missed, which the player should be able to hear.
    "arrow_miss.wav": lambda: mix(
        noise_burst(0.05, decay=34.0, low_pass=1.8, gain=0.24),
        tone(0.045, 520, 260, decay=30.0, gain=0.14),
    ),
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing placeholder SFX to {OUT_DIR}")
    for name, build in SOUNDS.items():
        write_wav(name, build())


if __name__ == "__main__":
    main()
