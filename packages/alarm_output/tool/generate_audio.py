"""Generate original, seamless PCM alarm loops. No third-party recordings."""
import math
import struct
import wave
from pathlib import Path

DESTINATION = Path(__file__).resolve().parents[3] / 'assets' / 'audio'
DESTINATION.mkdir(parents=True, exist_ok=True)
RATE = 22050
DURATION = 4
MELODIES = {
    'gentle': [523.25, 659.25, 783.99, 659.25],
    'bell': [880, 0, 1174.66, 0],
    'chime': [659.25, 783.99, 1046.5, 0],
}

for name, melody in MELODIES.items():
    samples = []
    for index in range(RATE * DURATION):
        time = index / RATE
        beat = int(time)
        phase = time - beat
        frequency = melody[beat]
        envelope = min(1, phase / 0.025) * math.exp(-phase * 4) * min(1, (1 - phase) / 0.06)
        value = sum(math.sin(2 * math.pi * frequency * harmonic * phase) / harmonic**2
                    for harmonic in [1, 2, 3]) if frequency else 0
        samples.append(struct.pack('<h', round(value * envelope * 10000)))
    with wave.open(str(DESTINATION / f'{name}.wav'), 'wb') as output:
        output.setnchannels(1)
        output.setsampwidth(2)
        output.setframerate(RATE)
        output.writeframes(b''.join(samples))
    print(f'Generated {name}.wav: 4 seconds, original PCM melody')
