#!/usr/bin/env python3
"""Generate 8-bit wasteland style background music as WAV."""

import struct, math, random, os

SAMPLE_RATE = 44100
DURATION = 90  # seconds
BPM = 90
BEAT = 60 / BPM
STEPS_PER_BEAT = 4

NOTES = {
    'C3': 130.81, 'D3': 146.83, 'Eb3': 155.56, 'F3': 174.61,
    'G3': 196.00, 'Ab3': 207.65, 'Bb3': 233.08,
    'C4': 261.63, 'D4': 293.66, 'Eb4': 311.13, 'F4': 349.23,
    'G4': 392.00, 'Ab4': 415.30, 'Bb4': 466.16,
    'C5': 523.25, 'D5': 587.33, 'Eb5': 622.25,
}

# 8-bit style: use square/triangle waves
def square_wave(freq, t, duty=0.5):
    phase = (t * freq) % 1.0
    return 1.0 if phase < duty else -1.0

def triangle_wave(freq, t):
    phase = (t * freq) % 1.0
    return 4.0 * abs(phase - 0.5) - 1.0

def noise(t, seed=0):
    random.seed(seed)
    return random.uniform(-1, 1)

# Song structure: (pattern, volume)
SONG = []

# Build 16-bar verse progression
verse = [
    ('C3', 'G3', 'Eb4'),   # I-V-III
    ('C3', 'G3', 'Eb4'),
    ('Ab3','G3', 'Eb4'),   # VI-V-III
    ('Ab3','G3', 'Eb4'),
    ('F3', 'G3', 'Eb4'),   # IV-V-III
    ('F3', 'G3', 'Eb4'),
    ('Bb3','G3', 'Eb4'),   # bVII-V-III
    ('Bb3','G3', 'Eb4'),
]

chorus = [
    ('C4', 'G4', 'Eb5'),
    ('C4', 'G4', 'Eb5'),
    ('Ab3','G3', 'Eb4'),
    ('Ab3','G3', 'Eb4'),
    ('F3', 'G3', 'C4'),
    ('F3', 'G3', 'C4'),
    ('Bb3','G3', 'F4'),
    ('C4', 'G3', 'F4'),
]

# Build full song (90s loop)
def build_song():
    song = []
    total_beats = 0
    bar_count = 0
    while total_beats < (BPM * DURATION / 60):
        section_start = total_beats
        if bar_count < 32:  # intro fade
            pattern = verse
            vol = min(0.9, 0.3 + (bar_count / 32) * 0.6)
        elif bar_count < 64:  # verse
            pattern = verse
            vol = 0.9
        elif bar_count < 80:  # chorus
            pattern = chorus
            vol = 1.0
        elif bar_count < 96:  # verse return
            pattern = verse
            vol = 0.85
        elif bar_count < 112:  # chorus final
            pattern = chorus
            vol = 1.0
        elif bar_count < 128:  # outro fade
            pattern = chorus
            vol = max(0.0, 1.0 - ((bar_count - 112) / 16))
        else:
            break

        for bar in pattern:
            chord = bar
            beats = 2
            song.append((total_beats, chord, vol, beats))
            total_beats += beats
        bar_count += 8

    return song

SONG = build_song()

def get_chord_at_beat(beat):
    for start, chord, vol, dur in SONG:
        if start <= beat < start + dur:
            return chord, vol
    return None, 0.0

print("Generating 8-bit wasteland BGM...")
print(f"Duration: {DURATION}s, BPM: {BPM}, Sample rate: {SAMPLE_RATE}")

samples = []
total_samples = int(SAMPLE_RATE * DURATION)

# Pre-compute LFO for filter sweep
def lfo(t, rate=0.5, depth=0.3):
    return 1.0 - depth + depth * (0.5 + 0.5 * math.sin(2 * math.pi * rate * t))

for i in range(total_samples):
    t = i / SAMPLE_RATE
    beat = t / BEAT
    step = beat / STEPS_PER_BEAT

    # Get current chord
    chord, vol = get_chord_at_beat(beat)
    if chord is None:
        samples.append(0)
        continue

    root, fifth, melody = chord
    root_freq = NOTES.get(root, 130.81)
    fifth_freq = NOTES.get(fifth, 196.00)
    melody_freq = NOTES.get(melody, 311.13)

    # Bass: triangle wave
    bass = triangle_wave(root_freq / 2, t) * 0.25

    # Harmony: square wave
    harm = square_wave(fifth_freq, t) * 0.18

    # Melody: square wave with arpeggio rhythm
    arp_step = int(step * 4) % 4
    if arp_step == 0:
        mel_freq = melody_freq
    elif arp_step == 2:
        mel_freq = melody_freq * 1.5  # fifth above
    else:
        mel_freq = melody_freq * 0.5  # octave below

    mel_vol = 0.15 if arp_step % 2 == 0 else 0.08
    mel = square_wave(mel_freq, t) * mel_vol

    # Percussion: noise bursts on beat
    perc = 0.0
    beat_sub = beat % 1.0
    if beat_sub < 0.05:
        perc += noise(t, int(beat)) * 0.3
    elif 0.25 < beat_sub < 0.3:
        perc += noise(t, int(beat * 4)) * 0.12

    # Wasteland ambient: low drone
    drone = math.sin(2 * math.pi * 55 * t) * 0.04
    drone += math.sin(2 * math.pi * 73.42 * t) * 0.03  # tritone

    # Filter sweep LFO
    filter_mod = lfo(t, rate=0.3, depth=0.5)

    # Mix and apply filter envelope
    raw = bass + harm + mel + perc + drone

    # Apply simple low-pass (approximate)
    raw = raw * filter_mod * 0.7

    # Apply overall volume with fade
    raw *= vol

    # Clamp
    raw = max(-1.0, min(1.0, raw))
    samples.append(raw)

    if i % (SAMPLE_RATE * 10) == 0:
        print(f"  Progress: {i // SAMPLE_RATE}s / {DURATION}s")

# Write WAV
output_path = os.path.join(os.path.dirname(__file__), 'bgm_wasteland.wav')
with open(output_path, 'wb') as f:
    # WAV header
    num_channels = 1
    bits_per_sample = 16
    byte_rate = SAMPLE_RATE * num_channels * bits_per_sample // 8
    data_size = len(samples) * bits_per_sample // 8

    f.write(b'RIFF')
    f.write(struct.pack('<I', 36 + data_size))
    f.write(b'WAVE')
    f.write(b'fmt ')
    f.write(struct.pack('<I', 16))           # subchunk1 size
    f.write(struct.pack('<H', 1))            # PCM
    f.write(struct.pack('<H', num_channels))
    f.write(struct.pack('<I', SAMPLE_RATE))
    f.write(struct.pack('<I', byte_rate))
    f.write(struct.pack('<H', num_channels * bits_per_sample // 8))  # block align
    f.write(struct.pack('<H', bits_per_sample))
    f.write(b'data')
    f.write(struct.pack('<I', data_size))

    # Write samples
    for s in samples:
        s_int = int(s * 32767 * 0.8)
        s_int = max(-32768, min(32767, s_int))
        f.write(struct.pack('<h', s_int))

print(f"\nDone! Saved to: {output_path}")
print(f"File size: {os.path.getsize(output_path) / 1024 / 1024:.1f} MB")