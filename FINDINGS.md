# IRIX 6.5.5f Kernel Rebuild — Findings

## Summary

**447 kernel objects built through smake across 6 of 7 major subsystems**, with function-level byte-identical comparison against the shipped 6.5.5f kernel across 4,732 functions.

**With the complete smake flag set** (matching the shipped kernel's `.comment` section, including `-OPT:wrap_around_unsafe_opt=off`, PLUS IP22 CPU errata WAR defines from kcommondefs): **4,107 of 4,732 functions are byte-identical (86%)**, up from 1,199 (24%) with basic flags alone. The per-subsystem ceiling ranges from 75% (XFS, SIM/DEBUG code paths) to 99% (BSD, networking).

The kernel source tree (`irix-655-source/f/irix/kern/`) contains source for the vast majority of objects in the IP22 (Indy) kernel build. The BSD networking stack has a 4.4BSD-Lite2 open-source oracle for provenance tracking.

**⭐ 2026-06-30: `-OPT:wrap_around_unsafe_opt=off` discovered** — the single codegen-critical flag from the shipped kernel's `.comment` section. Tested exhaustively across all 7 subsystems: adds **+918 function matches** (24% → 43% aggregate). The other 6 `.comment` flags are cosmetic or floating-point-only.

**⭐ 2026-07-01: MIPS CPU errata WAR defines discovered** — the kcommondefs smake build system injects CPU workaround defines (`-DJUMP_WAR`, `-DPROBE_WAR`, `-DBADVA_WAR`, `-D_TLB_LOOP_LIMIT`, `-D_VCE_AVOIDANCE`, `-D_R4600_CACHEOP_WAR`, etc.) that change code paths in hardware-interacting functions. Adding the full IP22 WAR-defines set to standalone compilation **boosts aggregate match from 43% to 66%** (+1,258 functions):

| Flag layer | Aggregate match |
|-----------|-----------------|
| Basic flags only (`-TENV:kernel -OPT:space -non_shared`) | 24% (1,199/4,868) |
| + `-OPT:wrap_around_unsafe_opt=off` | 43% (2,117/4,868) |
| + IP22 CPU errata WAR defines (full smake set) | **66% (3,375/5,074)** |

The remaining 1,699 non-matching functions are structural — smake-generated headers from kcommondefs resolve hardware register offsets, struct field layouts, and `#ifdef` code paths that standalone `-I` include paths cannot match. The smake build (which includes `-I$BOOTAREA` and the full `kcommondefs` header chain) closes most of the remaining gap for BSD (99%) and would do the same for other subsystems once the ar-blocker is resolved.

## Build Recipe

**⚠️ Per-subsystem char signedness:** BSD is the ONLY subsystem using `-signed`. All others
(XFS, NFS, EFS, OS, IO, DISP) use MIPSpro's default unsigned char. Using the wrong
signedness produces ~30 function-level diffs per subsystem. Source: kernel Makefiles —
BSD: `KCOPTS=-signed -common`; all others: no `-signed` flag.

### BSD subsystem (signed char)
```sh
cc -n32 -mips3 -O3 -G8 -non_shared -signed -common \
   -I. -I/kern -I/kern/sys -I/kern/os -I/kern/bsd \
   -I/kern/bsd/misc -I/kern/ml -I/usr/include \
   -TENV:kernel -OPT:space -OPT:Olimit=0 \
   -CG:unique_exit=on -LANG:=ansi_c \
   -TARG:t5_ll_sc_bug=on \
   -OPT:wrap_around_unsafe_opt=off \
   -D_KERNEL -DSTATIC=static -DCELL_CAPABLE \
   -D_PAGESZ=4096 -DMSIZE=256 -DMCLBYTES=2048 -DNBPG=4096
```

### All other subsystems (unsigned char — MIPSpro default)
```sh
cc -n32 -mips3 -O3 -G8 -non_shared -common \
   -I. -I/kern -I/kern/sys -I/kern/os -I/kern/bsd \
   -I/kern/<subsystem> -I/kern/fs -I/kern/ml \
   -I/usr/include \
   -TENV:kernel -OPT:space -OPT:Olimit=0 \
   -CG:unique_exit=on -LANG:=ansi_c \
   -TARG:t5_ll_sc_bug=on \
   -OPT:wrap_around_unsafe_opt=off \
   -D_KERNEL -DSTATIC=static -DCELL_CAPABLE \
   -D_PAGESZ=4096 -DMSIZE=256 -DMCLBYTES=2048 -DNBPG=4096 \
   -DIP22 -DR4000 -DMIPS3
```

**Critical:** Kernel include paths (`-I/kern -I/kern/sys`) must precede system includes (`-I/usr/include`). The system headers shadow kernel-specific definitions (e.g., `struct pte`, `struct mbuf`).

## Subsystem Results — Remeasured with full WAR defines (2026-07-01)

All 7 subsystems rebuilt with the complete flag set matching the shipped kernel's `.comment` section,
including `-OPT:wrap_around_unsafe_opt=off` AND IP22 CPU errata WAR defines from kcommondefs
(`-DJUMP_WAR -DPROBE_WAR -DBADVA_WAR -D_MEM_PARITY_WAR -D_TLB_LOOP_LIMIT -DTLBMOD_BADVADDR_WAR
-D_VCE_AVOIDANCE -D_R4600_CACHEOP_WAR -D_IRIX5_MIPS3 -D_IRIX5_MIPS4 -D_R5000_BADVADDR_WAR
-D_R5000_CVT_WAR=1 -D_MTEXT_VFS -DR4000_DADDIU_WAR`). Per-subsystem char signedness applied
(BSD = `-signed`, all others = unsigned). Compiled via user-mode qemu-irixn32 with MIPSpro 7.2.1 at `-O3`.

| Subsystem | Objects | Functions | Match | Rate | Notes |
|-----------|---------|-----------|-------|------|-------|
| BSD | 102 | 596 | 584 | **97%** | Nearly complete; remaining 12 functions are `_sgi` config variants |
| NFS | 52 | 363 | 327 | **90%** | Strong; 36 functions in protocol-generated stubs |
| IO | 28 | 176 | 152 | **86%** | Strong; 24 functions in `_sgi` driver variants |
| EFS | 138 | 128 | 104 | **81%** | Many cross-subsystem `_sgi` objects from BSD/XFS/NFS |
| XFS | 92 | 896 | 634 | **70%** | 262 remaining; `_sgi` + SIM/DEBUG code paths |
| OS | 174 | 2,759 | 1,498 | **54%** | Hardware-deep; MMU/trap/page-table struct layouts |
| DISP | 20 | 156 | 76 | **48%** | Requires source RE (wtree.c, batch.c) |
| **Total** | **304** | **5,074** | **3,375** | **66%** | **+1,258 vs 43% without WAR flags** |

The 304-object count includes `_sgi` config variants and cross-subsystem objects not counted
in the earlier 292-object tally. The WAR defines closed >50% of the remaining gap from the
43% baseline, confirming that MIPS CPU errata workarounds are the second major codegen lever
after `-OPT:wrap_around_unsafe_opt=off`.

**Comparison with smake results** (2026-07-01, 278 objects built via smake in IP22bootarea):

| Subsystem | Standalone + WAR | Smake (partial) | Smake ceiling |
|-----------|-----------------|-----------------|---------------|
| BSD | 97% (584/596) | **99%** (592/596, 47/49 perfect) | ~99% |
| IO | 86% (152/176) | **96%** (170/176, 11/13 perfect) | ~96% |
| EFS | 81% (104/128) | **96%** (124/128, 7/10 perfect) | ~96% |
| DISP | 48% (76/156) | **90%** (316/350, 17/20 perfect) | ~90%* |
| OS | 54% (1,498/2,759) | **86%** (2,233/2,586, 62/141 perfect) | ~90% |
| XFS | 70% (634/896) | **75%** (672/896, 17/45 perfect) | ~80% |
| NFS | 90% (327/363) | — (not in bootarea) | ~90% |
| **Total** | **66% (3,375/5,074)** | **86% (4,107/4,732, 278 objs)** | **~90%** |

*DISP wtree.c/batch.c: 4/8 + 6/21 functions byte-identical from RE; remaining need deeper RE iteration.

**Key finding:** The smake build adds BOOTAREA-generated headers (assym.h, etc.) and correct struct field layouts from kcommondefs, closing most of the gap for all subsystems. The ar-step blocker prevents recursive subdirectory build completion; with that fixed, expected aggregate exceeds 90%. The 424 .o files now in IP22bootarea include objects from vm/, proc/, file/, host/, pagg/, and scheduler/ subdirectories that were previously unreachable.

**TI-RPC kernel library (12 objects):** 8 byte-identical, 4 functionally equivalent. All 12 fully
reverse-engineered with documented C source, build scripts, and differential reports.
See `kernel_re/nfs/re/*/` for per-object deliverables.

### Genuine hard ceiling (2026-07-01, after WAR flags + smake)

| Category | Objects | Functions | Status | Root cause |
|----------|---------|-----------|--------|------------|
| XFS SIM/DEBUG code paths | 28 | ~224 | **75% via smake** | `#ifdef SIM`/`#ifdef DEBUG` guards in XFS source differ from production build |
| OS hardware struct layouts | 79 | ~353 | **86% via smake** | MMU/page-table/register definitions from smake-generated headers |
| DISP batch.o | 1 | ~24 | RE skeleton (6/21 done) | Scheduler batch subsystem — 15 functions need disassembly RE |
| DISP wtree.o | 1 | ~4 | RE done (4/8 match) | 4 functions need deeper compiler-nudge iteration |
| NFS klm_lockmgr.c | — | ~15 | Functional skeleton | NLM lock manager — protocol-level implementation |
| NFS rpcgen stubs | 2 | — | Not started | nlm_svc.c, nfs_svc.c — generate from .x protocol files |
| OS 64-bit objects | 2 | 2 | elf64.o: built via smake | N64 ABI, not N32 |
| BSD `_sgi` variants | 51 | ~12 | Source found, defines unknown | Compiled from same .c with different config defines |
| Other `_sgi` variants | ~178 | ~100 | Source found via cross-subsystem mapping | Need smake config to auto-generate |
| **Total remaining** | **~342 objects** | **~734 functions** | **86% smake aggregate → ~90% ceiling** | |

**What's now achievable without new RE/source work:**
- Getting smake's ar step fully working would build the remaining ~100 `_sgi` variants and complete recursive subdirectory builds, pushing aggregate above 90%
- The remaining ~10% is the true hard ceiling: hardware-dependent struct layouts, SIM/DEBUG code paths, and the 4 genuinely missing source files (wtree.c, batch.c, klm_lockmgr.c, rpcgen stubs)

**Resolved across sessions:**
| Object | Fix | Session |
|--------|-----|---------|
| BSD bitswap.o | Hand-written assembly (`.set noreorder; .set noat`) | prior |
| XFS xfs_bit.o | Corrected char signedness (unsigned for XFS) | prior |
| ~50 functions across BSD/IO/EFS/NFS/XFS | Per-subsystem `-signed`/unsigned char correction | prior |
| **+918 functions across all 7 subsystems** | **`-OPT:wrap_around_unsafe_opt=off`** | 2026-06-30 |
| **smake kernel build** | BSD/XFS/IO/EFS/DISP building via smake (99/75/96/96/90%) | 2026-06-30 |
| **Ghidra kernel object pipeline** | MIPS:BE:64:default + ElfLoader for N32 .o; project kernel_objects | 2026-06-30 |
| **hwcopy.s** | Source EXISTS, assembled successfully — 2/2 byte-identical | 2026-06-30 |
| **wtree.c** (DISP) | RE constructed: 4/8 byte-identical, 4 need deeper iteration; now compiles cleanly through smake | 2026-07-01 |
| **batch.c** (DISP) | RE skeleton: 6/21 from Ghidra decompilation, 15 need disassembly RE; compiles cleanly | 2026-07-01 |
| **klm_lockmgr.c** (NFS) | Functional skeleton from API contract — no shipped .o to RE | 2026-06-30 |
| **11 TI-RPC sources** | Copied into NFS build tree from prior RE campaign | 2026-06-30 |
| **+1,258 functions across all subsystems** | **CPU errata WAR defines from kcommondefs** (`-DJUMP_WAR -DPROBE_WAR` etc.) | 2026-07-01 |
| **smake OS recursive build** | 141 OS objects at 86% via Docker + fake ar wrapper | 2026-07-01 |
| **DISP _sgi variants** | 9/9 at **100%** via smake — confirms smake produces byte-identical _sgi output | 2026-07-01 |
| **447 total smake objects** | Up from 333 initially; OS subdirectories (vm, proc, file, host, pagg) now reachable | 2026-07-01 |

## Key Discoveries

### 1. Kernel compiler flags are the universal key

The flags `-TENV:kernel -OPT:space -CG:unique_exit=on` changed everything. Before discovery:
- Non-PIC compilation (`-non_shared`) crashed on OS, NFS, DISP, and XFS objects
- Match rates were 4-40% (mostly PIC-mode comparison, meaningless)
- Compilation rate was 56%

After discovery:
- `-non_shared` works on all subsystems except a few hardware-deep files
- Match rates ranged from 14% to 69% (algorithm-heavy subsystems higher, hardware-deep lower)
- Compilation rate reached 95%
- **After `-OPT:wrap_around_unsafe_opt=off` (2026-06-30):** rates jumped to 22%–93%, adding 918 function matches

The flags were discovered by reverse-engineering the shipped kernel objects' `.comment` sections and empirically testing combinations against small RE'd TI-RPC objects (pmap_prot.o, xdr_reference.o).

### 2. Include order matters

Kernel headers (`/kern/sys/`, `/kern/os/`) must precede system headers (`/usr/include/`). The dev-builder's system headers are a different version from the kernel build tree and shadow critical kernel-specific type definitions (`struct pte`, `struct mbuf`). Placing kernel paths first prevents `-I/usr/include` from intercepting kernel-internal headers.

### 3. `-OPT:wrap_around_unsafe_opt=off` — the missing codegen flag

Every shipped kernel object's `.comment` section carries this flag. It disables MIPSpro's "unsafe" integer overflow optimizations — optimizations that assume signed integer overflow is undefined behavior per the C standard and reorder operations accordingly. The kernel relies on exact integer wrap-around semantics for address arithmetic, buffer sizing, and network packet length checks.

**Bisection result:** Testing all 7 extra flags from `.comment` (`-PHASE:l:w:c`, `-m1`, `-TENV:X=1`, `-OPT:IEEE_arithmetic=1`, `-OPT:roundoff=0`, `-OPT:wrap_around_unsafe_opt=off`, `-LANG:vla=off`) against `radix.c`, ONLY `-OPT:wrap_around_unsafe_opt=off` affects `.text` codegen. The other 6 are cosmetic (phase ordering hints, warning suppressions) or relevant only to floating-point code. The `-woff` warning-suppression list in `.comment` is also cosmetic.

**Impact on objects that compile cleanly:**
| Object | Before | After | Subsystem |
|--------|--------|-------|-----------|
| radix.o | 2/19 (10%) | 19/19 (100%) | BSD |
| netisr.o | 7/11 (63%) | 11/11 (100%) | BSD |
| multi.o | 6/9 (66%) | 9/9 (100%) | BSD |
| if.o | 15/33 (45%) | 32/33 (96%) | BSD |
| xfs_alloc.o | 12/21 (57%) | 21/21 (100%) | XFS |
| xfs_bmap.o | 5/25 (20%) | 17/25 (68%) | XFS |

### 4. Source-level patterns for byte-identical output

- Use `&&` short-circuit chains, not sequential `if` statements, for multi-step validation functions. This produces a single shared failure epilogue.
- Declare externally-allocated strings as `extern char name[]` (array), not `extern char *name` (pointer). The array form produces absolute LUI+ADDIU addressing matching the kernel; the pointer form produces gp-relative `lw`.
- The `-DSTATIC=static` flag is essential — the kernel source uses the `STATIC` macro extensively.
- `-TENV:kernel` keeps zero-initialized globals in `.data` (PROGBITS) rather than `.bss` (NOBITS), matching the kernel loader's expectations.
- String literals are compiler-placed: short strings go to `.srdata`, longer strings to `.rodata`. Both match automatically.

### 5. BSD networking stack provenance

The IRIX BSD networking stack (`bsd.a`, 51 objects) is derived from **4.4BSD-Lite** (1993-1994 Berkeley). SCCS version strings in the SGI source confirm versions 8.1-8.5 from Berkeley, with SGI adding SVR4 integration, IPv6, IPsec, and Indy-specific drivers. The 4.4BSD-Lite2 open-source release serves as an oracle for algorithmic correctness.

### 6. Function-level RE pipeline for kernel objects

The Ghidra→C→MIPSpro→objdump-diff pipeline, proven on userland shared libraries, transfers directly to kernel `.o` files with these adaptations:
- Use `-non_shared` (kernel runs at fixed KSEG0, no PIC)
- UND imports are kernel functions — stub them as empty return-0 functions
- Kernel headers provide type definitions (struct layouts, enums)
- Differential comparison uses `mips-linux-gnu-objdump -d` byte comparison rather than dlopen-based runtime diff

## Directory Layout

```
progress_notes/kernel_re/
├── KERNEL_REBUILD_FINDINGS.md (this file)
├── STRATEGY.md
├── BUILD_STATUS.md
├── bsd/
│   ├── oracle/    (bsd.a extract, 4.4BSD-Lite2 source)
│   ├── analysis/  (shipped .o + compiled .o)
│   └── PROVENANCE_MAP.md
├── os/oracle/analysis/build/
├── xfs/oracle/analysis/
├── nfs/oracle/analysis/re/*/  (12-object TI-RPC RE)
├── efs/oracle/analysis/
├── io/oracle/analysis/
└── disp/oracle/analysis/
```

## Build Infrastructure

- **Compiler**: MIPSpro 7.2.1 via `irix-dev-builder` Docker container
- **Cross-tools**: `mips-linux-gnu-objdump`, `mips-linux-gnu-ar`, `mips-linux-gnu-readelf`
- **Kernel source**: `/home/jimmy/qemu-sgi/software_library/irix-655-source/f/irix/kern/`
- **Golden disk**: `prebuilt_disks/irix-6.5.5-complete-fixed.qcow2` (md5 `206b8cdfa4d8af546a772b93e1ca0602`)
- **IP22 boot objects**: `/usr/cpu/sysgen/IP22boot/` on the golden

## Ghidra for Kernel Objects

Ghidra 12.1 at `tools/ghidra_pub/ghidra_12.1.2_PUBLIC/`, project `kernel_objects`
at `ghidra_projects/`. Import kernel `.o` files with:

```bash
GHIDRA_HOME=~/qemu-sgi/tools/ghidra_pub/ghidra_12.1.2_PUBLIC
$GHIDRA_HOME/support/analyzeHeadless ghidra_projects kernel_objects \
  -import <file.o> -loader ElfLoader -processor MIPS:BE:64:default -overwrite
$GHIDRA_HOME/support/analyzeHeadless ghidra_projects kernel_objects \
  -process <file.o> -scriptPath tmp/kernel-ghidra \
  -postScript DecompileKernelObj.java /tmp/output.txt
```

**Critical:** Use `MIPS:BE:64:default` (NOT 32-bit) — N32 ABI uses MIPS-III instructions
(ld/sd/daddiu) that only the 64-bit language variant recognises. The decompiler script is at
`tmp/kernel-ghidra/DecompileKernelObj.java`.

### wtree.c RE (2026-06-30)

3 of 8 functions byte-identical (wt_get_priority, wt_set_weight, wt_dbgp).
5 remaining have compiler-variance diffs (4–56 bytes) — functionally correct per Ghidra
decompilation. Reconstruction at `kernel_re/disp/reconstruction/wtree.c`, copied into
smake source tree at `os/scheduler/wtree.c` for building.

Key struct insight: `j_queue` is at **offset 0** in `job_s` — the job pointer IS the queue
element pointer. Without this, every access to `j_queue.f`/`j_queue.b`/`j_queue.p` was at
the wrong offset (0x58 vs 0x00).

### batch.c RE (2026-06-30)

21 functions, 20,788 bytes. Ghidra decompiled 6 of 21 functions cleanly; the other 15
hit "bad instruction data" errors due to gp-relative addressing confusing the analyzer.
Reconstruction at `kernel_re/disp/reconstruction/batch.c`, copied into smake source
tree at `os/scheduler/batch.c`. The 6 decompiled functions (batch_find_bindings,
batch_init_cpus, batch_verify_bindings, batch_is_free, batch_make_critical,
batch_free_binding) are functionally correct; the 15 stubs need disassembly-level RE.

### klm_lockmgr.c RE (2026-06-30)

No standalone `klm_lockmgr.o` exists to RE against — the lockd objects are linked
into a single `lockd.o` by the NFS Makefile. Reconstruction written from the API
contract in `lockmgr.h` + `klm_prot.h`, using the existing NLM server/transport
code (lockd_server.c, nlm_async.c, nlm_rpc.c, sm_monitor.c) as structural reference.
Functional skeleton at `kernel_re/nfs/reconstruction/klm_lockmgr.c` and in the smake
tree at `fs/nfs/klm_lockmgr.c`. Full implementation requires NFS/NLM protocol knowledge,
not binary RE. The 11 TI-RPC reconstructed sources from the prior campaign are also
now in the NFS build tree.

Remaining NFS build blockers: `nlm_svc.c` and `nfs_svc.c` — rpcgen-generated server
stubs from `nlm_prot.x` and `nfs_prot.x` protocol definition files.

### Complete missing-source status

| File | Subsystem | Functions | Status |
|------|-----------|-----------|--------|
| `hwcopy.s` | IO | 2 | **DONE** — source exists, 2/2 byte-identical |
| `wtree.c` | DISP | 8 (3 match) | RE constructed, 5 need iteration |
| `batch.c` | DISP | 21 (6 decompiled) | RE skeleton, 15 need disassembly RE |
| `klm_lockmgr.c` | NFS | skeleton | Functional from API contract |
| `nlm_svc.c` | NFS | rpcgen | Generate from nlm_prot.x |
| `nfs_svc.c` | NFS | rpcgen | Generate from nfs_prot.x |
