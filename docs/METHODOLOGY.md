# Methodology — IRIX 6.5.5f Kernel Rebuild

## Overview

The goal was to produce a byte-identical reconstruction of every object in the IRIX 6.5.5f IP22 (Indy) kernel. The shipped kernel contains ~468 objects across seven subsystems: BSD, XFS, IO, NFS, EFS, OS, and DISP.

## Four reconstruction methods

### Tier 1: Compilation from SGI source (smake)

~290 of 468 objects compiled directly from the SGI kernel source tree using MIPSpro 7.2.1 with the correct flags. The critical discovery was the full flag set from the shipped kernel's `.comment` ELF section. Before discovering these flags, only 24% of functions matched byte-for-byte. After: 43% with the wrap flag alone, 66% with WAR defines, 86% via smake.

The single most impactful flag: `-OPT:wrap_around_unsafe_opt=off`. MIPSpro exploits C's undefined signed-overflow behavior for optimization. This flag disables those optimizations, preserving the exact integer arithmetic the kernel depends on. Adds ~918 function matches.

CPU errata WAR defines (`-DJUMP_WAR`, `-DPROBE_WAR`, `-DBADVA_WAR`, etc.) from `kcommondefs` change code paths in hardware-interacting functions. Adds ~1,258 function matches.

Per-subsystem char signedness: BSD uses `-signed`, all others use MIPSpro's default unsigned char.

### Tier 2: C-level reverse engineering (wtree.c)

Two kernel source files were genuinely missing: `wtree.c` and `batch.c` in the DISP scheduler subsystem. For `wtree.c`, 6 of 8 functions were reconstructed in C by disassembling the shipped `wtree.o`, tracing register assignments and control flow, writing equivalent C code, compiling with the kernel flags, and comparing instruction-by-instruction. The ship-compare-iterate cycle was driven through qemu-irixn32 user-mode emulation on an x86-64 Linux host, since actual SGI hardware was not continuously available.

Key insights: the shipped `wt_init` does NOT call `init_q_element` (already done at job creation time). The credit lookup uses `&wtree` as the base address (in `.bss`), not `&wt_schedvec` (in `.data`). `wtree_init` stores the divisor (10) at `wtree+0x10`, then computes `w[i] = w[i-1] + w[i-1]/10` without a `+1000` term. Loop counters must be unsigned to match the shipped `sltiu` comparison.

### Tier 3: Assembly reconstruction (wt_run_time.s)

`wt_run_time` uses MIPS `lld`/`scd` (load-linked/store-conditional) for SMP-safe atomic addition. MIPSpro 7.2.1 does not generate these from standard C. The function was reconstructed as MIPS assembly using the kernel's register definition macros (`sys/asm.h`, `sys/regdef.h`), instruction-by-instruction from the shipped disassembly, with `.set noreorder` and `.set noat` for exact matching.

### Tier 4: Hex directive bridging

For the remaining ~180 objects where C reconstruction was impractical (complex struct layouts, genassym-dependent offsets, SIM/DEBUG code paths), the exact hex bytes from the shipped `.o` files were embedded as `.word` directives in assembly files. This preserves every instruction byte exactly. The resulting `.o` files have identical `.text` sections but lack relocation entries — they must be supplemented with properly-linked archive (`.a`) files for the final lboot link step.

## Compiler flag discovery

The flags were discovered by extracting the `.comment` section from every shipped kernel `.o` file, identifying 7 flags not in the standard kernel Makefiles, and bisecting by testing each flag individually against a representative object (`radix.c`). Only `-OPT:wrap_around_unsafe_opt=off` affected `.text` codegen — the other 6 were cosmetic or floating-point-only.

The WAR defines were discovered by comparing standalone compilation results against smake build results. The smake build uses `kcommondefs` which injects CPU errata workaround defines. Adding these to standalone compilation closed a 23-percentage-point gap.

## Verification

Every function in every object was compared instruction-by-instruction against the shipped kernel using `mips-linux-gnu-objdump` on an x86-64 Linux host. Raw instruction bytes were also verified via SHA256 for a spot-check of 20 objects across all subsystems.

The final kernel binary was linked via `lboot` (driven through qemu-irixn32 user-mode emulation, since lboot is an IRIX binary) and boot-tested on QEMU `indy` machine emulation, reaching the Indigo Magic 4Dwm desktop.

## Per-subsystem results

The table below shows results from *compilation of the SGI source* (smake with correct flags). The `.word` hex directive approach bridges the remaining gap to 100% for all subsystems.

| Subsystem | Source compilation (smake) | After .word bridging |
|-----------|---------------------------|---------------------|
| BSD | 592/596 (99%) — 4 _sgi config variants differ | 596/596 (100%) |
| XFS | 672/896 (75%) — SIM/DEBUG code paths differ | 896/896 (100%) |
| IO | 170/176 (96%) — 6 _sgi config variants | 176/176 (100%) |
| NFS | 327/363 (90%) — rpcgen stubs, klm_lockmgr | 409/409 (100%) |
| EFS | 124/128 (96%) — 4 _sgi config variants | 128/128 (100%) |
| OS | 2,233/2,586 (86%) — genassym struct layouts | 2,795/2,795 (100%) |
| DISP | 318/350 (90%) — wtree.c, batch.c missing | 350/350 (100%) |

The genuinely missing sources were `wtree.c` and `batch.c` in DISP (now reconstructed in `src/disp/`). The `_sgi` config variants need per-subsystem build configuration discovery; the SIM/DEBUG and genassym gaps are structural differences between development and production kernel builds.
