---
name: rainbow
description: Use Ledger Donjon's `rainbow` to emulate an embedded binary with Unicorn and (a) generate side-channel leakage traces for analysis with lascar, or (b) sweep instruction-skip / stuck-at fault models to find injection-bypass vulnerabilities — no hardware, scope, or glitcher needed. Trigger whenever the user mentions rainbow / "rainbow_flu" / Ledger Donjon's simulation tool, emulation-based side-channel analysis, fault-injection simulation, "is my code constant-time", testing FI hardening / glitch resistance of a firmware function, generating synthetic power traces from an ELF, or `start_and_fault` / `fault_skip` / `TraceConfig` / `HammingWeight`. Pairs with the `lascar` skill for the analysis half.
---

# rainbow — emulation-based side-channel & fault-injection simulation

[`Ledger-Donjon/rainbow`](https://github.com/Ledger-Donjon/rainbow) — "It makes unicorn traces." Loosely emulates an embedded binary under [Unicorn](https://www.unicorn-engine.org/) + [Capstone](https://www.capstone-engine.org/), records an *execution trace* (register / memory values under a leakage model), and can inject faults at chosen instruction indices. It's a pure-software first-pass evaluation of a code snippet's resistance to physical attacks — you find the bugs that are *your* fault (non-constant-time compares, secret-indexed table lookups, a guard that a single instruction-skip defeats) before paying for lab time. Trace *analysis* is deliberately left to [`lascar`](https://github.com/Ledger-Donjon/lascar) (see the `lascar` skill).

Two introductions worth a skim: the [launch post](https://medium.com/ledger-on-security-and-blockchain/introducing-rainbow-donjons-side-channel-analysis-simulation-tool-2f23fa1f11b3) and the [automatic FI test pipeline post](https://blog.ledger.com/fault-injection-simulation/) (+ its [Rust demo repo](https://github.com/Ledger-Donjon/fault_injection_checks_demo/)).

## What it is *not*

- **Not cycle-accurate, not a hardware model.** It emulates the *instruction stream*, with a Hamming-weight/-distance leakage model. It does **not** model the real chip's analog power, the on-die AES/SAES/SHA/PKA accelerators, the TRNG, MMIO peripheral behaviour, caches, or pipeline. Peripheral accesses must be stubbed (see Gotchas).
- **Not a substitute for a real SCA/FI bench.** It tests *algorithmic* leakage and *logical* fault-bypass of your code. Analog leakage and silicon countermeasure quality still need a scope + shunt / EM probe (e.g. ChipWhisperer, PicoScope) or a glitcher (ChipWhisperer, Scaffold, a crowbar rig).
- It traces with **no added noise** — that's intentional (worst-case attacker). You add noise in post-processing if you want a realistic SNR.

## Install

Python ≥ 3.7. Clone and install:

```bash
git clone https://github.com/Ledger-Donjon/rainbow.git
cd rainbow
pip install .              # core: unicorn + capstone + pyelftools
pip install .[examples]    # also pulls lascar + visplot/vispy/pyqt5 for the example scripts
```

If `unicorn` or `capstone` wheels fail, install them from the upstream projects (links above) then `pip install . --no-deps`-style. Verify:

```bash
python -c "from rainbow.devices import rainbow_stm32f215; print('ok')"
```

The `examples/` folder in the clone is the real documentation — `CortexM_AES/` (Thumb AES SCA), `HW_analysis/pin_compare.py` (NICV on a PIN compare), `HW_analysis/pin_fault.py` (instruction-skip sweep against a PIN check), `SecAESSTM32/go.py` (ANSSI secure-AES starting point), `OAES/`, `pimp_my_xor/`, `hacklu2009/`. **Read the closest example before writing a harness from scratch.**

## Core API

```python
from rainbow.devices import rainbow_stm32f215, rainbow_stm32l431   # SVD-backed STM32 devices
from rainbow.generics import rainbow_arm, rainbow_cortexm, rainbow_x86, rainbow_x64, rainbow_m68k

e = rainbow_stm32f215()                 # or rainbow_cortexm() for a generic Cortex-M target
e.load('firmware.elf')                  # type guessed from extension; .elf .hex .bin/PE supported
e.emu                                   # the underlying Unicorn instance — full access for custom hooks

# Memory & registers via subscript
e[0x2000_0000] = b'\x01\x02\x03\x04'    # write bytes to an address
data = e[0x2000_0000:0x2000_0010]       # read
e['r0'] = 0xdead_beef                   # set a register
e['lr'] = 0xaaaa_aaaa                   # common trick: a sentinel return address to detect "function returned"
e['pc'], e['sp'], e['cpsr'] = ...
print(e['r0'])

# Symbols (if the ELF has them)
addr = e.functions['my_crypto_fn'][0]   # (start, size)

# Run: like unicorn — begin, end, optional instruction budget
e.start(addr, 0xaaaa_aaaa, count=10_000)

e.reset()                               # reset emulator state between iterations (keep the loaded binary)
e.disassemble_single(pc, 4)             # -> (addr, size, mnemonic, op_str)
```

Verbose execution log:

```python
from rainbow import Print
import colorama; colorama.init()
e = rainbow_cortexm(print=Print.Code | Print.Functions | Print.Faults)
# Print.Code Print.Functions Print.Registers Print.Memory Print.Faults — OR them together
```

## Workflow A — generate leakage traces, analyse with lascar

```python
from rainbow import TraceConfig, HammingWeight
from rainbow.devices import rainbow_stm32f215
import numpy as np
from lascar import TraceBatchContainer, Session, CpaEngine, ConsoleOutputMethod
from lascar.tools.aes import sbox
from lascar import hamming

e = rainbow_stm32f215(trace_config=TraceConfig(register=HammingWeight(), instruction=True))
e.load('aes_target.elf')

N = 2000
traces, values = [], []
for _ in range(N):
    e.reset()
    pt = np.random.randint(0, 256, 16, dtype=np.uint8)
    e[0x2000_0100] = bytes(pt)            # plaintext buffer
    e[0x2000_0200] = bytes(KEY)           # key buffer (fixed)
    e['r0'] = 0x2000_0100
    e['r1'] = 0x2000_0200
    e['lr'] = 0xaaaa_aaaa
    e.start(e.functions['aes_encrypt'][0], 0xaaaa_aaaa, count=100_000)
    # Pull the leakage samples out of the trace dicts:
    traces.append(np.array([ev['register'] for ev in e.trace if 'register' in ev], dtype=np.uint8))
    values.append(pt)

# Traces from different runs may differ in length — truncate to the shortest (or align on a marker).
L = min(t.shape[0] for t in traces)
traces = np.array([t[:L] for t in traces])
values = np.array(values)

container = TraceBatchContainer(traces, values)
def sel(v, guess, byte=0):  return hamming(sbox[v[byte] ^ guess])
cpa = CpaEngine(lambda v, g: sel(v, g, 0), range(256))
Session(container, engine=cpa, output_method=ConsoleOutputMethod(cpa)).run(batch_size=200)
```

`TraceConfig` knobs: `register=<LeakageModel>` (per-instruction destination-register leakage), `mem_address=<LeakageModel>` (leak loaded/stored *addresses* — catches secret-indexed lookups), `mem_value=<LeakageModel>` (leak loaded/stored *values*), `instruction=True` (record the PC of each instruction so you can label your trace axis). Leakage models live in `rainbow.leakage_models` — `HammingWeight()`, plus identity/HD variants. Combine them; `e.trace` dicts then carry multiple keys (`register`, `address`, `value`).

For analysis details — engines, selection functions, TVLA, plotting — see the **`lascar` skill**.

## Workflow B — fault-injection sweep (instruction skip / stuck-at)

A fault model is a function `f(emu: Rainbow) -> None` that mutates emulator state. Built-ins in `rainbow.fault_models`: `fault_skip` (advance PC past the current instruction), `fault_stuck_at(value=0)` (force the destination register of the current instruction to `value`). `e.start_and_fault(fault_model, fault_index, begin, end, *args, count=N)` runs `fault_index` instructions, applies the fault, then continues — returning the PC at which the fault landed.

```python
from rainbow.devices import rainbow_stm32f215
from rainbow.fault_models import fault_skip   # or: fault_stuck_at

e = rainbow_stm32f215()
e.load('firmware.elf')

STORED_PIN, INPUT_PIN = "1874", "0000"
e[0x0800_8110 + 0x189] = bytes(STORED_PIN + "\0", "ascii")   # reference PIN in flash
e[0xcafe_cafe]         = bytes(INPUT_PIN  + "\0", "ascii")

def faulted(u):                                  # what does a *successful* bypass look like?
    return u['r0'] != 0 and u['pc'] == 0xaaaa_aaaa   # returned "PIN correct" despite wrong PIN

MAX_INSTR = 60
hits, crashes = [], []
for i in range(1, MAX_INSTR):
    e.reset()
    e['r0'] = 0xcafe_cafe                        # arg: input PIN ptr
    e['lr'] = 0xaaaa_aaaa                        # sentinel return
    try:
        pc = e.start_and_fault(fault_skip, i, e.functions['storage_containsPin'][0], 0xaaaa_aaaa, count=100)
    except RuntimeError:                          # fault produced an invalid instruction → "crash"
        crashes.append(i); continue
    except IndexError:                            # ran off the end before faulting / fault_index >= count
        pass
    if faulted(e):
        hits.append(i)
        print(f"  skip @ instr {i}: r0 = {hex(e['r0'])}  <-- BYPASS")

print(f"=== {len(hits)} exploitable skips, {len(crashes)} crashes ===")
```

Generalisations: sweep `fault_stuck_at(0)` / `fault_stuck_at(0xffffffff)` instead of `fault_skip`; sweep two faults; widen the window; write a `result()` predicate per target (a leaked secret in a register, a wrong branch taken, a counter not incremented). For a *guard* you want to prove robust (double-evaluated check, hamming-distant sentinels, redundant counter readback), the win condition is "**no** `fault_index` makes `result()` true" — and a few crashes are fine, a silent bypass is not. The [FI checks demo repo](https://github.com/Ledger-Donjon/fault_injection_checks_demo/) shows how to wrap this into a CI gate.

## Gotchas

- **ELF must have symbols** for `e.functions[...]` — build with debug info, don't strip. Or pass raw addresses.
- **Peripheral MMIO will trap or read garbage.** rainbow maps RAM/flash, not your chip's peripherals. Anything that touches a hardware HASH/AES/SAES/RNG/flash-controller/GPIO register needs a Unicorn hook stub: `e.emu.hook_add(uc.UC_HOOK_MEM_READ | uc.UC_HOOK_MEM_WRITE, cb, begin=PERIPH_BASE, end=PERIPH_END)` returning canned values (e.g. a fixed "random" word for the TRNG, a software-computed digest for the HASH block). The STM32 device classes (`rainbow_stm32f215`, `rainbow_stm32l431`) preload an SVD so the memory map is sane, but they still don't *implement* peripheral logic.
- **Best targets are pure-logic functions** — a constant-time compare, a KDF over a software hash, an ABI/calldata parser, an FI guard helper. If the code under test calls into a hardware accelerator, either stub the accelerator or test the *software reference* of the same algorithm.
- **Trace length varies per run** (data-dependent branches, loop counts). Truncate to the min length, or emit an in-firmware marker (a write to a known address) and align on it, before stacking into a numpy array for lascar.
- **`count=` is your safety net** — an unstubbed peripheral or a runaway loop will spin forever otherwise. Set a generous instruction budget.
- **No noise by design.** A CPA that resolves trivially in simulation can still be hard on silicon; a CPA that *fails* in simulation is a strong negative result. Add Gaussian noise to the trace array if you want a realistic-SNR study.
- It emulates **one architecture at a time** — `e.emu` is the unicorn handle if you need raw control (custom hooks, peeking memory mid-run, multi-stage execution).

## When the user says "test this function for leakage / glitch resistance"

1. Identify the function and its ABI (which registers/memory hold the secret, the inputs, the result).
2. Build the target ELF **with symbols**; if it pulls in hardware accelerators, decide: stub them, or point rainbow at the software reference implementation.
3. For SCA: `TraceConfig(register=HammingWeight(), mem_address=HammingWeight())`, loop N random inputs, stack traces, hand to lascar (CPA with a selection function over the sensitive value, or a fixed-vs-random TVLA — see the `lascar` skill).
4. For FI: write a `result()` predicate for "the guard was bypassed", sweep `fault_skip` (then `fault_stuck_at`) over the instruction window, report exploitable indices vs crashes. Robust guard ⇒ zero exploitable indices.
5. Save the harness as a script under `tools/sca/` (or wherever the project keeps tooling) so it's re-runnable and auditor-reviewable. Print the exact invocation.
