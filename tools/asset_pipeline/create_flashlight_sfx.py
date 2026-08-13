#!/usr/bin/env python3
"""Build deterministic 44.1 kHz flashlight SFX masters and mobile-safe OGGs."""

from __future__ import annotations

import math
import random
import struct
import subprocess
import wave
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "src/assets/audio/sfx"
RATE = 44_100
RNG = random.Random(0xF1A5)


def envelope(t: float, duration: float, attack: float = 0.015, release: float = 0.08) -> float:
    return min(1.0, t / attack) * min(1.0, max(0.0, duration - t) / release)


def softclip(value: float) -> float:
    return math.tanh(value * 1.25) / math.tanh(1.25)


def charge_up(t: float, duration: float) -> float:
    p = min(1.0, t / duration)
    freq = 105.0 + 930.0 * p * p
    phase = 2.0 * math.pi * (105.0 * t + 310.0 * t * t + 310.0 * t * t * t)
    coil = math.sin(phase) * 0.42 + math.sin(phase * 2.01) * 0.13
    shimmer = math.sin(2.0 * math.pi * (1450.0 + 680.0 * p) * t) * (0.04 + p * 0.10)
    relay = math.sin(2.0 * math.pi * 92.0 * t) * math.exp(-48.0 * t) * 0.32
    lock = math.sin(2.0 * math.pi * 1680.0 * (t - 0.78)) * math.exp(-28.0 * max(0.0, t - 0.78)) * (0.22 if t >= 0.78 else 0.0)
    return (coil + shimmer + relay + lock) * envelope(t, duration, 0.018, 0.10)


def low_battery(t: float, duration: float) -> float:
    signal = 0.0
    for start, pitch in ((0.035, 740.0), (0.315, 610.0)):
        local = t - start
        if 0.0 <= local <= 0.19:
            pulse_env = envelope(local, 0.19, 0.008, 0.055)
            signal += (math.sin(2.0 * math.pi * pitch * local) * 0.55 + math.sin(2.0 * math.pi * pitch * 2.0 * local) * 0.10) * pulse_env
    hum = math.sin(2.0 * math.pi * 82.0 * t) * 0.055 * envelope(t, duration, 0.02, 0.12)
    return signal + hum


def depleted(t: float, duration: float) -> float:
    p = min(1.0, t / duration)
    falling = 690.0 * (1.0 - p) ** 2 + 54.0
    phase = 2.0 * math.pi * (falling * t + 115.0 * math.sin(t * 2.4))
    power = math.sin(phase) * 0.44 + math.sin(phase * 0.51) * 0.15
    sputter = 1.0 if (int(t * 38.0) % 5) not in (0, 1) else 0.18
    noise = (RNG.random() * 2.0 - 1.0) * 0.045 * (1.0 - p)
    cutoff = math.exp(-2.4 * p) * envelope(t, duration, 0.01, 0.16)
    relay = math.sin(2.0 * math.pi * 76.0 * (t - 0.64)) * math.exp(-34.0 * max(0.0, t - 0.64)) * (0.28 if t >= 0.64 else 0.0)
    return (power * sputter + noise) * cutoff + relay


def build(name: str, duration: float, synth) -> None:
    frames = []
    for index in range(round(duration * RATE)):
        sample = softclip(synth(index / RATE, duration)) * 0.78
        frames.append(struct.pack("<h", max(-32767, min(32767, round(sample * 32767.0)))))
    wav_path = OUT / f"{name}.wav"
    ogg_path = OUT / f"{name}_v001.ogg"
    with wave.open(str(wav_path), "wb") as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b"".join(frames))
    subprocess.run(
        ["ffmpeg", "-hide_banner", "-loglevel", "error", "-y", "-i", str(wav_path), "-ac", "2", "-ar", str(RATE), "-c:a", "vorbis", "-strict", "-2", "-q:a", "5", str(ogg_path)],
        check=True,
    )


if __name__ == "__main__":
    OUT.mkdir(parents=True, exist_ok=True)
    build("flashlight_charge_up", 0.95, charge_up)
    build("flashlight_low_battery", 0.65, low_battery)
    build("flashlight_depleted", 0.85, depleted)
    print("FLASHLIGHT_SFX_BUILD_OK: 3 WAV masters + 3 stereo OGG runtime assets")
