---
name: lascar
description: Use Ledger Donjon's `lascar` ("Ledger's Advanced Side-Channel Analysis Repository") to run side-channel analysis on power/EM traces — CPA, DPA, MIA, T-test/TVLA leakage assessment, SNR, NICV, profiled/template & ML attacks — over traces from any source (ChipWhisperer, PicoScope, a scope CSV/HDF5, or rainbow's emulated traces). Trigger whenever the user mentions lascar, CPA / DPA / CPA-on-AES, TVLA / Welch t-test leakage assessment, SNR or NICV on a trace set, recovering a key byte from traces, the Container / Session / Engine / OutputMethod model, selection functions / guess ranges / leakage models, or analysing the output of the `rainbow` emulator (see the `rainbow` skill for generating those traces).
---

# lascar — side-channel analysis library

[`Ledger-Donjon/lascar`](https://github.com/Ledger-Donjon/lascar) — a Python framework for side-channel analysis. Source-agnostic: it consumes a *trace set* (numpy arrays, HDF5, `.npy`, a CSV-loaded scope dump, ChipWhisperer projects, or [`rainbow`](https://github.com/Ledger-Donjon/rainbow)'s emulated traces) and runs the standard distinguishers and leakage-assessment tests over it. Streams data in batches so trace sets larger than RAM are fine.

The `tutorial/` and `examples/` directories of the cloned repo are the real docs — `examples/base/cpa.py`, `.../dpa.py`, `.../ttest.py`, `.../snr.py`, the `tutorial/` notebooks (containers, sessions, output methods), and the profiled/ML examples. **Read the closest example before composing an attack.**

## Install

```bash
pip3 install "git+https://github.com/Ledger-Donjon/lascar.git"
```

Pulls a heavy dependency set (numpy, scipy, scikit-learn, numba, h5py, matplotlib, PyQt5, vispy, progressbar2, click — and tensorflow/keras for the ML engines; if you don't need those and the install is painful, install lascar's non-ML deps and skip tensorflow). Verify:

```bash
python -c "from lascar import Session, CpaEngine, TraceBatchContainer; print('ok')"
```

## The four core classes

| Class | Role |
|---|---|
| **Container** | Source of `(leakage, value)` pairs — `leakage` = the trace samples (1-D array per trace), `value` = the associated metadata/plaintext/key/etc. used by selection functions. Batched iteration. |
| **Engine** | A computation accumulated over the trace set — `CpaEngine`, `DpaEngine`, `MiaEngine`, `TTestEngine` (Welch / TVLA), `SnrEngine`, `NicvEngine`, `Cpa`/profiled & ML engines, plus `MeanEngine`/`VarEngine`. |
| **Session** | Drives one or more engines over a container in batches; collects results. |
| **OutputMethod** | What to do with engine results — `ConsoleOutputMethod`, `MatPlotLibOutputMethod`, `ScoreProgressionOutputMethod`, `Hdf5OutputMethod`, `DictOutputMethod`, `NullOutputMethod`. |

```python
from lascar import *               # the package re-exports the common names
from lascar.tools.aes import sbox  # AES S-box for the textbook selection functions
# hamming(x), hamming_weight, etc. are also exported
```

## Recipe — CPA to recover an AES key byte

```python
from lascar import *
from lascar.tools.aes import sbox

# 1) a Container. Built-in simulator for a quick smoke test:
container = BasicAesSimulationContainer(2000, noise=2)        # 2000 sim traces, leak = HW(sbox out) + noise
# ...or your real traces (see "Loading real traces" below):
# container = TraceBatchContainer(traces_2d_array, values_array)

# 2) a selection function: "under the 'guess' hypothesis, model the sensitive value's leakage"
def selection(value, guess):
    return hamming(sbox[value["plaintext"][3] ^ guess])       # 4th byte; guess = key byte hypothesis

# 3) the engine
cpa = CpaEngine(selection, range(256))                        # guess_range = all 256 key-byte values

# 4) run it
Session(container, engine=cpa, output_method=MatPlotLibOutputMethod(cpa)).run(batch_size=200)
```

All 16 bytes in parallel, with a recovery-vs-#traces progression plot:

```python
def make_sel(byte):
    def sel(value, guess):  return hamming(sbox[value["plaintext"][byte] ^ guess])
    return sel

engines = [CpaEngine(make_sel(i), range(256), solution=container.key[i]) for i in range(16)]
Session(container, engines=engines, name="cpa 16 bytes",
        output_method=ScoreProgressionOutputMethod(*engines), output_steps=10).run(batch_size=50)
```

`solution=` (the known correct value, when you have it) lets the output methods plot rank/score of the true guess — essential for "how many traces did I need?" studies.

## Recipe — TVLA / Welch t-test (leakage assessment, no key model needed)

The fixed-vs-random test: does the device leak *at all*? Partition traces into a "fixed input" class and a "random input" class; `TTestEngine` flags samples where the two classes' means differ beyond ±4.5σ.

```python
from lascar import *
# value must carry the class label; here value[0] == 1 for the "fixed" set, 0 for "random"
ttest = TTestEngine(lambda value: value[0])
Session(container, engine=ttest, output_method=MatPlotLibOutputMethod(ttest)).run(batch_size=500)
# |t| crossing ~4.5 anywhere ⇒ first-order leakage present at that sample
```

Use this as the *first* thing on any new target/countermeasure: cheap, model-free, and a clean pass/fail. (For a masked design, also run the second-order variant on centred-product preprocessed traces.)

## Recipe — SNR / NICV (where is the leakage, and how strong)

```python
from lascar import *
snr  = SnrEngine(lambda v: v["plaintext"][0], range(256))      # partition by a byte value
nicv = NicvEngine(lambda v: v["plaintext"][0], range(256))     # normalised inter-class variance (∈[0,1])
Session(container, engines=[snr, nicv], output_method=MatPlotLibOutputMethod(snr, nicv)).run(batch_size=500)
```

Great for *trace alignment / point-of-interest selection* before a CPA, and for the kind of "which instruction leaks the PIN digit comparison" study in rainbow's `examples/HW_analysis/pin_compare.py`.

## Loading real traces

- **From numpy arrays** (e.g. produced by `rainbow`, or `np.load`-ed scope captures): `TraceBatchContainer(traces, values)` where `traces` is shape `(n_traces, n_samples)` and `values` is shape `(n_traces, ...)` (anything your selection functions index — a dict-array, a 2-D uint8 array of plaintexts, a structured array, …).
- **From HDF5**: `Hdf5Container(filename, leakages_dataset_name=..., values_dataset_name=...)` — and `Hdf5Container.export(...)` / `Hdf5OutputMethod` to persist.
- **From `.npy` on disk**: `NpyContainer(leakages_npy, values_npy)`.
- **ChipWhisperer projects / other formats**: check `lascar/container/` in the clone — there are loaders, and writing a custom `Container` subclass (implement `__init__` + `generate_trace_batch`) is straightforward.
- **Preprocessing**: containers accept a `leakage_processing=` callable (e.g. centring, standardisation, windowing, PCA, centred-product for 2nd-order) applied per batch — and `leakage_section=` to crop to a sample window.
- **Simulators for testing**: `BasicAesSimulationContainer(n, noise=σ)` and friends — verify your selection function / engine wiring before pointing it at real data.

## Output methods

- `ConsoleOutputMethod(*engines)` — text summary; good for scripts/CI.
- `MatPlotLibOutputMethod(*engines)` — plots (correlation traces, t-traces, SNR).
- `ScoreProgressionOutputMethod(*engines)` + `output_steps=` on the Session — rank/score vs #traces; the "how many traces to break it" curve.
- `Hdf5OutputMethod` / `DictOutputMethod` — persist results for later.
- `NullOutputMethod` — compute only; pull `session[engine]` / `engine.finalize()` yourself.

## Gotchas

- **Alignment is everything.** CPA/DPA assume sample *i* corresponds to the same operation across all traces. Misaligned traces (jitter, random delays, a moving trigger) tank the result — align first (cross-correlation, a sync pattern, or SNR-guided), or use the `leakage_processing` hook. (Emulated traces from `rainbow` are jitter-free but can differ in *length* per run — truncate to the min length.)
- **Selection-function signature is `(value, guess)`** for guess-based engines (CPA/DPA/MIA/SNR/NICV-with-guess) and `(value)` for partition engines (TTest, label-only SNR). Mismatch → cryptic errors. Capture loop variables with a default arg (`lambda v, g, z=i: ...`) when generating many engines, exactly as in the examples.
- **`value` is whatever you put in the container** — keep plaintext/ciphertext/key/labels in it; selection functions index it (`value["plaintext"][3]`, or `value[0]` for a flat array). Decide the layout up front.
- **Heavy deps.** If `tensorflow`/`keras` won't install and you don't need the ML/profiled-NN engines, you can run CPA/DPA/TVLA/SNR without them — just don't import the ML engines.
- **Batch size** trades memory for speed; it does not change results. Start ~200–1000.
- **A simulation pass ≠ a silicon result.** lascar happily breaks `BasicAesSimulationContainer` — that proves your *attack code* works, not that a real device leaks. Conversely a clean TVLA on real traces is a real (first-order) result.

## When the user says "analyse these traces" / "recover the key" / "is there leakage"

1. Get the traces into a `Container` — `TraceBatchContainer(traces, values)` from numpy is usually quickest; for big sets use `Hdf5Container`. Confirm shapes: `(n_traces, n_samples)` leakage, matching `values`.
2. If "is there leakage": run a **TVLA `TTestEngine`** (fixed-vs-random) and/or `SnrEngine` first — model-free pass/fail + point-of-interest.
3. If "recover the key": pick the sensitive intermediate (AES: `sbox[pt ^ k]` at round 1, or HD on the last-round output), write the `(value, guess)` selection function, `CpaEngine(sel, range(256), solution=known_key_byte)`, one engine per byte, `ScoreProgressionOutputMethod` to see the trace count needed.
4. Plot with `MatPlotLibOutputMethod` for a human; `ConsoleOutputMethod` for a script. Persist with `Hdf5OutputMethod` if it's part of a campaign.
5. Save the analysis as a re-runnable script (e.g. under `tools/sca/`) and print the exact invocation. Pair with the `rainbow` skill if the traces are emulator-generated.
