"""Ambient score + sound design for the 84 s Lanserhof Tegernsee spot.
Soft pads (D major colour), sparse felt-piano motif, wind/water beds,
gentle whooshes on scene changes, reverb tail, fade out. Writes music.wav."""
import sys, wave
import numpy as np

SR, DUR = 48000, 84.0
N = int(SR * DUR)
t = np.arange(N) / SR
rng = np.random.default_rng(7)
L = np.zeros(N); R = np.zeros(N)

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def fft_filter(x, lo=None, hi=None):
    X = np.fft.rfft(x); f = np.fft.rfftfreq(len(x), 1 / SR); g = np.ones_like(f)
    if hi: g *= 1 / np.sqrt(1 + (f / hi) ** 4)
    if lo: g *= 1 / np.sqrt(1 + (lo / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(X * g, len(x))

def env(n, a, r):
    e = np.ones(n); na, nr = int(a * SR), int(r * SR)
    e[:na] = np.sin(np.linspace(0, np.pi / 2, na)) ** 2
    e[-nr:] *= np.cos(np.linspace(0, np.pi / 2, nr)) ** 2
    return e

# --- pads: chord changes roughly with scenes
chords = [  # (start, end, midi notes)
    (0, 10.6, [50, 57, 62, 66, 69, 76]),      # Dmaj9 colour
    (10, 20.6, [47, 54, 62, 66, 69, 73]),     # Bm11
    (20, 32.6, [43, 55, 59, 62, 66, 69]),     # Gmaj9
    (32, 44.6, [45, 52, 57, 61, 64, 71]),     # A6/9
    (44, 58.6, [50, 57, 62, 64, 66, 69]),     # Dadd9
    (58, 74.6, [47, 54, 59, 62, 66, 71]),     # Bm9
    (74, 84.0, [43, 50, 55, 62, 66, 69, 74]), # Gmaj7 -> resolve feel
]
for (a, b, notes) in chords:
    i0, i1 = int(a * SR), int(min(b + 2.5, DUR) * SR); n = i1 - i0; tt = np.arange(n) / SR
    e = env(n, 2.2, 3.0)
    for k, m in enumerate(notes):
        f = hz(m); amp = (0.05 if m < 52 else 0.032) * (0.9 + 0.2 * rng.random())
        voice = np.zeros(n)
        for det in (-0.12, 0.0, 0.13):  # gentle chorus
            ff = f * 2 ** (det / 12 / 8)
            voice += np.sin(2 * np.pi * ff * tt + rng.random() * 6) + 0.18 * np.sin(4 * np.pi * ff * tt) + 0.06 * np.sin(6 * np.pi * ff * tt)
        voice *= amp / 3 * e * (1 + 0.15 * np.sin(2 * np.pi * (0.07 + 0.03 * k) * tt))
        pan = 0.5 + 0.35 * np.sin(k * 1.7)
        L[i0:i1] += voice * (1 - pan); R[i0:i1] += voice * pan

# --- felt piano motif (pentatonic, sparse, deterministic)
scale = [62, 64, 66, 69, 71, 74, 76, 78, 81]
def piano(at, m, vel=0.12):
    i0 = int(at * SR); n = min(int(4.5 * SR), N - i0)
    if n <= 0: return
    tt = np.arange(n) / SR; f = hz(m); s = np.zeros(n)
    for h, a in ((1, 1), (2, .42), (3, .18), (4, .09), (5, .04)):
        s += a * np.sin(2 * np.pi * f * h * (1 + 0.0004 * h * h) * tt) * np.exp(-tt * (1.1 + 0.9 * h))
    s *= vel * (1 - np.exp(-tt * 400)); pan = 0.3 + 0.4 * ((m * 7) % 10) / 10
    L[i0:i0 + n] += s * (1 - pan); R[i0:i0 + n] += s * pan
motif = [0, 3, 2, 4, 3, 1]
tm, k = 3.0, 0
while tm < DUR - 6:
    piano(tm, scale[(motif[k % 6] + (k // 6) % 3) % len(scale)], 0.10 + 0.04 * ((k % 4) == 0))
    if k % 5 == 2: piano(tm + 0.55, scale[(motif[k % 6] + 2) % len(scale)], 0.06)
    tm += [1.6, 2.1, 1.3, 2.4][k % 4]; k += 1
# final chord bell on the slogan
for m in (62, 66, 69, 74, 78): piano(75.2, m, 0.09)

# --- nature beds: wind (opening/ending), water (wellness scene)
noise = rng.standard_normal(N)
wind = fft_filter(noise, lo=180, hi=900) * (0.5 + 0.5 * np.sin(2 * np.pi * 0.09 * t) ** 2)
wmask = np.clip(1 - np.abs(t - 5) / 7, 0, 1) + np.clip(1 - np.abs(t - 80) / 7, 0, 1)
water = fft_filter(rng.standard_normal(N), lo=1200, hi=5500) * (0.6 + 0.4 * np.abs(np.sin(2 * np.pi * 1.3 * t)))
water_mask = np.clip((t - 32) / 1.0, 0, 1) * np.clip((36 - t) / 1.0, 0, 1)
L += 0.018 * wind * wmask + 0.006 * water * water_mask
R += 0.018 * np.roll(wind, 900) * wmask + 0.006 * np.roll(water, 700) * water_mask

# --- whooshes on scene transitions
for c in (10, 20, 32, 44, 58, 74):
    i0 = int((c - 1.4) * SR); n = int(2.2 * SR); tt = np.arange(n) / SR
    sw = fft_filter(rng.standard_normal(n), lo=300, hi=4000) * np.sin(np.pi * tt / tt[-1]) ** 3 * 0.035
    L[i0:i0 + n] += sw; R[i0:i0 + n] += np.roll(sw, 300)
# soft sub swell under the final slogan
i0 = int(73 * SR); n = int(8 * SR); tt = np.arange(n) / SR
sub = np.sin(2 * np.pi * hz(38) * tt) * np.sin(np.pi * tt / tt[-1]) ** 2 * 0.05
L[i0:i0 + n] += sub; R[i0:i0 + n] += sub

# --- reverb (exponential noise tail, FFT convolution)
def reverb(x, sec=3.2, seed=1):
    n = int(sec * SR); ir = np.random.default_rng(seed).standard_normal(n) * np.exp(-np.arange(n) / SR * 2.1)
    ir = fft_filter(ir, hi=6000); ir /= np.sqrt(np.sum(ir ** 2))
    m = len(x) + n; F = 1 << (m - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, F) * np.fft.rfft(ir, F), F)[:len(x)]
Lw, Rw = reverb(L, seed=1), reverb(R, seed=2)
L, R = 0.72 * L + 0.42 * Lw, 0.72 * R + 0.42 * Rw

# --- master: fade in/out, normalise
fade = np.clip(t / 1.2, 0, 1) * np.clip((DUR - t) / 4.0, 0, 1) ** 1.5
L *= fade; R *= fade
peak = max(np.abs(L).max(), np.abs(R).max()); g = 0.70 / peak
st = np.stack([L * g, R * g], 1)
out = sys.argv[1] if len(sys.argv) > 1 else 'music.wav'
with wave.open(out, 'wb') as w:
    w.setnchannels(2); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((np.clip(st, -1, 1) * 32767).astype('<i2').tobytes())
print('wrote', out, f'{DUR}s')
