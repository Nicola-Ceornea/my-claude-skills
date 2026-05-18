---
name: scared
description: Use eShard's `scared` (Side-Channel Analysis Reduced) framework — a higher-level CPA / DPA / ANOVA / NICV / SNR / MIA / TVLA / template-attack library built on `estraces` (ETS, Riscure TRS, raw-bin glob, sqlite, in-RAM numpy formats). Trigger whenever the user mentions scared, eShard's SCA framework, `CPAAttack` / `DPAAttack` / `ANOVAAttack` / `NICVAttack` / `SNRAttack` / `MIAAttack` / `TemplateAttack` / `TTestAnalysis`, `@scared.attack_selection_function` (or `@selection_function` / `@reverse_selection_function`), `scared.HammingWeight()` / `Monobit` / `Value` models, `scared.maxabs` / `nanmax` / `nansum` discriminants, an `.ets` or `.trs` trace file or `TraceHeaderSet` / `read_ths_from_ets_file` / `read_ths_from_trs_file` / `read_ths_from_bin_filenames_pattern` / `read_ths_from_ram`, the `Synchronizer` resync API, `convergence_step=` (rank-vs-#traces), the DPA Contest V2 dataset, scared's built-in AES selection functions (`scared.aes.selection_functions.encrypt.{FirstAddRoundKey, LastAddRoundKey, FirstSubBytes, LastSubBytes, DeltaRLastRounds}` + decrypt mirrors), or `set_batch_size`. Pair with the `rainbow` skill when traces come from rainbow's Unicorn emulator; cross-reference the `lascar` skill — they overlap (both do CPA/DPA/TVLA) and the choice between them is workflow-driven (see "scared vs lascar" below).
---

# scared — eShard's side-channel analysis framework

[`eshard/scared`](https://github.com/eshard/scared) · [docs](https://eshard.gitlab.io/scared/) · LGPLv3 (commercial license available from eShard). A Python framework where you assemble an `Attack` from four pieces:

```
Attack = selection_function  +  model  +  discriminant  +  distinguisher
```

…then `.run()` it over a **`Container`** wrapping a `TraceHeaderSet` from [`estraces`](https://pypi.org/project/estraces/). estraces is the trace I/O layer — it speaks ETS (eShard's native), Riscure TRS (`.trs` — the lingua franca for SCA exchange, and what most scopes / ChipWhisperer Capture can export to), raw `.bin` glob patterns, SQLite, and in-RAM numpy arrays.

## Setup & how to run things — the `scared-sca` CLI

scared is installed and driven through the **`scared-sca`** CLI (from the [`my-claude-skills`](https://github.com/Nicola-Ceornea/my-claude-skills) repo — on PATH if that repo's `setup.sh` was run). It owns a dedicated venv (separate from `donjon-sca`'s — scared needs `numpy ≥ 2` and Python ≥ 3.11, which collides with parts of the lascar/rainbow stack).

```bash
scared-sca doctor                 # check the install
scared-sca setup                  # bootstrap/update (venv at ~/.local/share/scared-sca/venv, pip install scared)
scared-sca run analysis.py        # run a scared analysis script inside the venv
scared-sca python -c 'import scared; print(scared.__version__)'
scared-sca repl                   # interactive python with scared + numpy pre-imported
```

If `scared-sca` isn't found: `git clone https://github.com/Nicola-Ceornea/my-claude-skills.git ~/repos/my-claude-skills && ~/repos/my-claude-skills/setup.sh`. (Manual fallback: `python3.11 -m venv ~/.venvs/scared && ~/.venvs/scared/bin/pip install scared` — wheels exist on PyPI for Linux x86_64 / macOS x86_64 on 3.11/3.12/3.13.)

## The four building blocks

| Piece | Role |
|---|---|
| **selection function** | Maps `(plaintext_batch, guesses)` → intermediate values `(n_traces, n_guesses, n_bytes)` ndarray. Decorate with `@scared.attack_selection_function` (you know the key, want success metrics) or `@scared.reverse_selection_function` (key unknown). **Vectorised** — unlike lascar's per-trace `(value, guess) → scalar`. |
| **model** | Maps intermediate values to expected leakage: `scared.HammingWeight()` (HW), `scared.Monobit(bit)` (DPA-style single-bit), `scared.Value()` (identity / Hamming distance), or subclass `scared.Model`. |
| **discriminant** | Reduces the per-time-sample distinguisher output to a per-guess score: `scared.maxabs` (CPA classic — max absolute correlation), `nanmax`, `nansum`, `abssum`, `opposite_min`, or write your own with `@scared.discriminant`. |
| **container** | `scared.Container(ths, frame=slice(a, b), preprocesses=[...])` — wraps a `TraceHeaderSet`, crops to a sample frame, applies per-batch preprocessing (centring, FFT, high-order combination). `scared.set_batch_size(...)` to tune memory/speed. |

The high-level `…Attack` classes (`CPAAttack`, `DPAAttack`, `ANOVAAttack`, `NICVAttack`, `SNRAttack`, `MIAAttack`, `TemplateAttack`, `TemplateDPAAttack`) bundle distinguisher + model + selection function + discriminant. The `…Reverse` mirrors are the same thing when you don't have a known key — fewer success-metric attributes, otherwise identical.

```python
import scared
import numpy as np
```

## Recipe — CPA on AES with a built-in selection function

scared ships AES round selection functions, so you usually do **not** need to write one. Recover the last-round key on a DPA Contest V2 trace set:

```python
from scared import aes, traces

ths = traces.read_ths_from_ets_file('dpa_v2_sub.ets')      # estraces TraceHeaderSet
sf  = aes.selection_functions.encrypt.DeltaRLastRounds()    # target Δ between last two rounds

container = scared.Container(ths[:15_000], frame=slice(2340, 2395))   # crop to last-round window

cpa = scared.CPAAttack(
    selection_function = sf,
    model              = scared.HammingWeight(),
    discriminant       = scared.maxabs,
    convergence_step   = 1000,             # log scores every 1000 traces (rank-vs-#traces curve)
)
cpa.run(container)

recovered = np.argmax(cpa.scores, axis=0)
expected  = aes.key_schedule(key=ths[0].key)[-1]
print("match:", np.array_equal(expected, recovered))
print("correlation traces, byte 15:", cpa.results[:, 15, :].shape)   # (n_guesses, n_samples_in_frame)
print("convergence, byte 15:",       cpa.convergence_traces[:, 15, :].shape)  # (n_guesses, n_steps)
```

Built-ins under `scared.aes.selection_functions`:

| Target | Class |
|---|---|
| First round, after AddRoundKey | `encrypt.FirstAddRoundKey` |
| First round, SBox output | `encrypt.FirstSubBytes` |
| Last round, after AddRoundKey | `encrypt.LastAddRoundKey` |
| Last round, SBox output | `encrypt.LastSubBytes` |
| Δ between last two rounds (HD) | `encrypt.DeltaRLastRounds` |
| Same five mirrored for decrypt | `decrypt.…` (last round of decrypt = first round of encrypt, etc.) |

DES selection functions sit under `scared.des.selection_functions`. AES helpers: `aes.key_schedule`, `aes.sub_bytes`, `aes.inv_sub_bytes`, `aes.shift_rows` (and inverses) — useful when writing custom selection functions.

## Recipe — custom selection function (vectorised, not per-trace)

```python
@scared.attack_selection_function
def first_add_key(plaintext, guesses):
    # plaintext: (n_traces, 16) uint8
    # guesses:   array-like of guess bytes, len = n_guesses
    # return:    (n_traces, n_guesses, 16) uint8
    out = np.empty((plaintext.shape[0], len(guesses), plaintext.shape[1]), dtype='uint8')
    for i, g in enumerate(guesses):
        out[:, i, :] = np.bitwise_xor(plaintext, g)
    return out

scared.CPAAttack(selection_function=first_add_key, model=scared.HammingWeight(), discriminant=scared.maxabs).run(container)
```

The metadata field name (`plaintext` here) MUST match the field on the `TraceHeaderSet` — `ths[0].plaintext`, `ths[0].cipher`, etc. (estraces autoloads metadata from `.ets` files; for raw `.bin` you pass a `metadatas_parsers={...}` dict — see "Loading real traces").

## Recipe — TVLA / Welch t-test (leakage assessment)

Fixed-vs-random first-order leakage. Need **two** trace sets: one with a fixed input, one with random inputs.

```python
from scared import traces
ths_fix = traces.read_ths_from_ets_file('fixed.ets')
ths_rnd = traces.read_ths_from_ets_file('random.ets')

container = scared.TTestContainer(ths_fix, ths_rnd, frame=None, preprocesses=[])
ttest     = scared.TTestAnalysis(precision='float32')
ttest.run(container)

t = ttest.result                                # (n_samples,) Welch t-statistic
leak_samples = np.where(np.abs(t) > 4.5)[0]     # ~4.5σ TVLA threshold
print(f"{len(leak_samples)} samples cross |t|>4.5 — first-order leakage" if leak_samples.size else "no first-order leakage at this threshold")
```

For masked targets: stack a high-order preprocess (e.g. centred product) in `preprocesses=` to lift the analysis to second order.

## Recipe — SNR / NICV (point-of-interest selection before CPA)

`SNRAttack` / `NICVAttack` use a partition by intermediate value and tell you *which samples carry the leakage*. They consume the same `selection_function + model + discriminant` triple. NICV ∈ [0, 1] is easier to compare across campaigns; SNR has the cleaner "signal vs noise" interpretation.

```python
sf = scared.aes.selection_functions.encrypt.FirstSubBytes()
nicv = scared.NICVAttack(selection_function=sf, model=scared.HammingWeight(), discriminant=scared.maxabs)
nicv.run(container)
poi = np.argmax(nicv.results.max(axis=0), axis=-1)   # best sample per byte — feed to a windowed CPA next
```

Same recipe with `scared.ANOVAAttack` / `scared.MIAAttack` (the latter takes `bins_number=` / `bin_edges=`).

## Loading real traces (the estraces layer)

`scared.traces` is `estraces` re-exported. The readers shipped in estraces 1.10:

| Source | Reader |
|---|---|
| `.ets` (eShard native, self-describing) | `traces.read_ths_from_ets_file('foo.ets')` |
| `.trs` (Riscure Inspector — common SCA exchange format; ChipWhisperer Capture can export to it via Riscure tooling, most commercial scopes export here too) | `traces.read_ths_from_trs_file('foo.trs')` |
| Glob of raw `.bin` files | `traces.read_ths_from_bin_filenames_pattern('caps/*.bin', dtype='int16', metadatas_parsers={...})` |
| Explicit list of raw `.bin` files | `traces.read_ths_from_bin_filenames_list([...], dtype='int16', metadatas_parsers={...})` |
| In-memory numpy arrays | `traces.read_ths_from_ram(samples=..., **metadata_arrays)` — `samples` shape `(n_traces, n_samples)`, metadata kwargs become `ths[i].key`, `ths[i].plaintext`, etc. |
| SQLite | `traces.read_ths_from_sqlite(...)` |
| Concatenate multiple `ths` into one | `traces.read_ths_from_multiple_ths([ths_a, ths_b, ...])` |

> **No native ChipWhisperer / HDF5 reader.** Older scared docs mention them, but estraces 1.10 doesn't ship those readers. Bridge with `read_ths_from_ram(samples=cw_project.waves, plaintext=cw_project.textins, ...)` from a ChipWhisperer project, or `h5py.File(...)` → `np.array` → `read_ths_from_ram` from HDF5. The `Synchronizer` API also writes ETS via `BufferedETSWriter`, so a one-time conversion-to-`.ets` pass is often easiest for repeated re-analysis.

For the bin-glob case, metadata is parsed via `bin_extractor`:

```python
metadata = {
    'key':    traces.bin_extractor.PatternExtractor(r"([A-Fa-f0-9]{32})", num=0),
    'plain':  traces.bin_extractor.PatternExtractor(r"([A-Fa-f0-9]{32})", num=1),
    'cipher': traces.bin_extractor.PatternExtractor(r"([A-Fa-f0-9]{32})", num=2),
}
ths = traces.read_ths_from_bin_filenames_pattern('dpa_v2_files/*.bin', dtype='int16', metadatas_parsers=metadata)
```

Slice a `TraceHeaderSet` (`ths[:10_000]`, `ths[mask]`) before wrapping in a `Container` — slicing is lazy.

## Recipe — Synchronizer (trace resync, writing back an ETS)

The killer feature of scared on real silicon. `Synchronizer` aligns jittered/misaligned traces and writes the realigned set to a new ETS file you can re-open and analyse:

```python
from scared import Synchronizer
import estraces

def my_resync(trace, pattern):
    # trace: 1-D ndarray, one trace
    # return: aligned 1-D ndarray, or raise scared.ResynchroError to reject this trace
    shift = int(np.argmax(np.correlate(trace, pattern, mode='valid')))
    return trace[shift : shift + 5000]

pattern = ths.samples[0, 100:200]   # reference snippet from a known-good trace
sync = Synchronizer('aligned.ets', input_ths=ths, function=my_resync, function_kwargs={'pattern': pattern})
sync.run()
ths_aligned = estraces.read_ths_from_ets_file('aligned.ets')
```

lascar has nothing equivalent — for a jittered campaign, prefer scared just for this.

## Preprocesses & signal processing

Per-batch transforms applied inside the container, before the distinguisher sees them:

```python
from scared import preprocesses as pp
container = scared.Container(ths, frame=slice(450, 650),
                             preprocesses=[pp.center, pp.standardize])   # zero-mean, unit-σ
```

Built-ins: `pp.center`, `pp.square`, `pp.fft_modulus`, `pp.standardize`, `pp.serialize_bit`, `pp.ToPower(p)`, `pp.CenterOn(ref)`, `pp.StandardizeOn(ref)`, plus `pp.high_order.*` (centred products and friends for masked targets). Custom: decorate with `@scared.preprocess`.

Signal-processing utilities (filters, FFT helpers, moving operators, pattern/peak detection) live under `scared.signal_processing.*` — use them when building POI windows or before `Synchronizer`.

## scared vs lascar — when to pick which

The two libraries overlap heavily; pick on workflow, not on which-one-is-better.

- **Pick scared when:** you have `.ets` files (or want them); want built-in AES/DES round selection functions and `aes.key_schedule`; have jittered traces and want `Synchronizer` to bake out a realigned ETS; want `convergence_step=` built into every Attack for rank-vs-#traces curves; prefer batch-vectorised selection functions returning ndarrays.
- **Pick lascar when:** you want the lower-level `Engine` / `Session` / `OutputMethod` toolkit, `ScoreProgressionOutputMethod` / `MatPlotLibOutputMethod` plotting pipeline, or the profiled-NN / ML engines (TF/Keras); you're consuming `rainbow` emulator output (where you already wrote a `(value, guess)→scalar` selection function); you're running CPA/DPA from a one-shot numpy buffer with no file-format concerns.
- **Use both:** quick TVLA + Synchronizer in scared, then heavy attack scripting in lascar (or vice versa). Their venvs are isolated (`scared-sca` vs `donjon-sca`) so they don't fight over numpy versions.

## Gotchas

- **`numpy >= 2` + Python ≥ 3.11** is hard-required by scared. `scared-sca`'s venv is separate from the lascar/rainbow one (`donjon-sca`) for exactly this reason — don't try to merge them.
- **Selection-function output shape** must be `(n_traces, n_guesses, n_bytes)` even for a single-byte attack (`n_bytes = 1`). Wrong shape → cryptic broadcasting errors deep in the distinguisher.
- **`@attack_selection_function` vs `@reverse_selection_function`** — Attack needs the true key (in metadata or passed) to compute success metrics; Reverse runs the same distinguisher with no key-aware outputs. Mismatch → `SelectionFunctionError`.
- **DPA needs `Monobit`** — `DPAAttack` enforces `model=scared.Monobit(bit)`; passing `HammingWeight()` raises `DistinguisherError`.
- **Metadata field name** in your selection function (`plain`, `plaintext`, `cipher`, …) MUST match what the `TraceHeaderSet` carries. Print `ths` to confirm.
- **`frame=slice(a, b)`** crops *time samples*, not traces. Slice the ths itself (`ths[:N]`) to limit trace count.
- **Trace alignment is everything** for CPA/DPA. Jitter tanks correlation. Run a `Synchronizer` (or `signal_processing.pattern_detection`) before attacking real silicon traces.
- **Batch size** trades RAM for speed; defaults adapt to trace length. Override with `scared.set_batch_size(5000)` (count), `scared.set_batch_size(64.0)` (MB), or a piecewise list `[(0, 25_000), (1001, 5000), ...]`.
- **`scared.maxabs` is the CPA default**, not `nanmax`. They differ when negative correlations are physically meaningful (often: yes).
- **Convergence traces** (`attack.convergence_traces`) only exist when `convergence_step=` is set on the Attack constructor. Without it, you only get the final `.scores` / `.results`.
- **Commercial use needs an eShard license.** scared is LGPLv3 + "intended for non-commercial use" per the README.

## When the user says "analyse these traces" / "recover the key" / "is there leakage"

1. **Get the traces into a `TraceHeaderSet`.** `.ets` → `traces.read_ths_from_ets_file(path)`. numpy → `traces.read_ths_from_ram(samples=arr, plaintext=pt_arr, key=k_arr, ...)`. Confirm `print(ths)` shows the metadata fields your selection function will reference.
2. **Align if needed.** Eyeball `ths.samples[:5]` overlapped — if peaks drift, run a `Synchronizer` and re-open the realigned ETS before going further.
3. **"Is there leakage" → `TTestAnalysis`** on a fixed-vs-random split (`TTestContainer(ths_fix, ths_rnd)`), threshold `|t| > 4.5`. Cheap, model-free pass/fail.
4. **"Where does it leak" → `SNRAttack` / `NICVAttack`** with a one-byte selection function — peaks in `.results` are your CPA window.
5. **"Recover the key" → `CPAAttack`** with `aes.selection_functions.encrypt.DeltaRLastRounds()` (HD on the cipher) or `.FirstSubBytes()` (HW on round-1 S-box), `model=HammingWeight()`, `discriminant=maxabs`, `convergence_step=` to see how many traces you needed. `np.argmax(att.scores, axis=0)` is your candidate key.
6. **Save the analysis as a re-runnable script** (e.g. under `tools/sca/`) and print the exact invocation: `scared-sca run tools/sca/cpa_lastround.py`.
