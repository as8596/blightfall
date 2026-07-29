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
    # syllable, so text has a voice without anybody recording one. Deeper than
    # Animal Crossing on purpose — theirs sits around 600Hz and reads as
    # cheerful chirping, which is exactly wrong for a town that has been losing.
    # These sit at 190-260Hz with a falling sweep, so they read as speech in a
    # low register.
    #
    # Three of them, cycled, because one blip repeated forty times is a machine
    # and three is a mouth. Playback pitch-varies them a further +/-8% and each
    # speaker carries their own pitch offset, so nobody sounds like anybody else.
    "voice_a.wav": lambda: mix(
        tone(0.055, 236, 198, attack=0.12, decay=17.0, gain=0.42),
        tone(0.045, 472, 396, attack=0.12, decay=22.0, gain=0.12),
    ),
    "voice_b.wav": lambda: mix(
        tone(0.06, 205, 179, attack=0.14, decay=16.0, gain=0.42),
        tone(0.05, 410, 358, attack=0.14, decay=21.0, gain=0.1),
    ),
    "voice_c.wav": lambda: mix(
        tone(0.05, 262, 214, attack=0.1, decay=19.0, gain=0.4),
        tone(0.042, 524, 428, attack=0.1, decay=24.0, gain=0.13),
    ),
    # Moving between replies, and choosing one. Quiet and short: this is a
    # sound the player will hear thousands of times.
    "ui_move.wav": lambda: tone(0.035, 520, 460, attack=0.1, decay=26.0, gain=0.22),
    "ui_select.wav": lambda: mix(
        tone(0.09, 380, 620, attack=0.08, decay=14.0, gain=0.3),
        noise_burst(0.04, decay=30.0, low_pass=2.0, gain=0.1),
    ),
}


def main() -> None:
    os.makedirs(OUT_DIR, exist_ok=True)
    print(f"Writing placeholder SFX to {OUT_DIR}")
    for name, build in SOUNDS.items():
        write_wav(name, build())


if __name__ == "__main__":
    main()
