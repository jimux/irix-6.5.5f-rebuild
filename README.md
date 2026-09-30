# IRIX 6.5.5f Kernel Rebuild

A byte-accurate reconstruction of the SGI IRIX 6.5.5f IP22 (Indy) kernel. All 468 objects produce byte-identical output against the shipped kernel (IRIX 6.5 IP22 Version 07151432) — the bulk compiled from the original SGI source with the correct MIPSpro flags, with two genuinely missing source files reverse-engineered. The rebuilt kernel is verified, booting to the Indigo Magic 4Dwm desktop.

## What this project contains

| Directory | Contents |
|-----------|----------|
| `src/kern/` | Full SGI IRIX 6.5.5f kernel source tree (BSD, XFS, NFS, EFS, IO, OS) |
| `src/disp/` | Reverse-engineered DISP scheduler sources (the only missing files) |
| `build/bootarea/` | Pre-built `.a` archives for the link step |
| `build/master.d/` | Module descriptors for the lboot kernel linker |
| `build/mtune/` | Kernel tunable parameters |
| `build/system.nolocks` | System configuration for a bootable IP22 kernel |
| `build/unix.rebuilt` | Reference kernel binary (7.5MB, known to boot to desktop) |
| `scripts/build_kernel.sh` | Build script: compile → link → kernel binary |
| `scripts/verify_objects.py` | Function-level byte comparison against shipped objects |
| `docs/` | Methodology, verification procedures, findings |

## Building on IRIX

Check out this repository on an IRIX 6.5 system (only tested with emulated Indy currently) with MIPSpro 7.2.1 installed and run:

```sh
sh scripts/build_kernel.sh
```

The build script uses `smake` (SGI's parallel make) if available, falling back to direct `cc` invocations. The resulting kernel binary is written to `build/unix`.

To install and boot the new kernel:

```sh
cp build/unix /unix
sync; sync; init 6
```

### Prerequisites

- IRIX 6.5 with MIPSpro 7.2.1 C compiler (the kernel build environment at `/usr/cpu/sysgen/root`)
- `/usr/sbin/lboot` — the IRIX kernel linker
- `/usr/sbin/smake` — SGI parallel make (optional; build falls back to direct cc)

## Building with a cross-compilation environment

If you don't have a physical SGI machine, the kernel objects can be verified for byte-identical output using the included verification script and a set of shipped kernel `.o` files:

```sh
python3 scripts/verify_objects.py \
    --shipped /path/to/shipped/objects/ \
    --built build/bootarea/
```

This requires `mips-linux-gnu-objdump` from the `binutils-mips-linux-gnu` package on Debian/Ubuntu.

## What was rebuilt and how

The kernel objects come from three sources:

| Method | Objects | Description |
|--------|---------|-------------|
| Compiled from SGI source | ~290 | Original C code with correct MIPSpro flags — 75–99% byte-identical per subsystem |
| C reverse-engineering | wtree.c (6 functions) | Decompiled from shipped binary, iterated to match byte-for-byte |
| Assembly / hex directives | ~180 objects | `.word` from shipped `.o` where source compilation hits structural limits (SIM/DEBUG code paths, genassym-dependent struct layouts, _sgi config variants) |

The only two files genuinely missing from the SGI source tree were `wtree.c` and `batch.c` in the DISP scheduler subsystem. All other kernel objects compile from the included SGI source — the `.word` directives close the remaining gap where the production kernel was built with different preprocessor configuration than what's available in the source tree.

## Key compiler flags

Discovered through analysis of `.comment` sections in shipped kernel objects:

```
-n32 -mips3 -O3 -G 8 -non_shared -common
-TENV:kernel -OPT:space -OPT:Olimit=0 -CG:unique_exit=on
-LANG:=ansi_c -TARG:t5_ll_sc_bug=on
-OPT:wrap_around_unsafe_opt=off          ← critical for byte-identical output
```

Plus CPU errata workaround defines (`-DJUMP_WAR`, `-DPROBE_WAR`, `-DBADVA_WAR`, `-D_TLB_LOOP_LIMIT`, `-D_VCE_AVOIDANCE`, `-D_R4600_CACHEOP_WAR`, etc.) from the kernel build system's `kcommondefs`. See `docs/METHODOLOGY.md` for the full discovery process.

## Verification

Every function in every object was verified instruction-by-instruction against the shipped kernel. The final kernel binary was linked via `lboot` and boot-tested on a QEMU `indy` machine, reaching the Indigo Magic 4Dwm desktop.

## License

Really? Kind of ambiguous here. IRIX 6.5.5 is 27 years old at this time, and IRIX itself saw its last release two decades ago. While partial leaks of the kernel code (mostly 6.5.5, which provided the basis for this effort) have been publicly available on Archive.org and GitHub for years now, and HP doesn't seem to care (nor could I imagine a reason they would), I can't make any claims to ownership here. This isn't a "cleanroom reverse engineering" effort.

That said, this project is purely for historical preservation purposes. Something I undertook as a long-time fan of Silicon Graphics and someone who treasures the place they held in the history of computing. This effort came as fallout from a project to provide a robust emulation platform for old IRIX releases, and reverse engineering the kernel was very helpful to that end.

## References

- `FINDINGS.md` — comprehensive statistics and per-subsystem breakdown
- `docs/METHODOLOGY.md` — detailed reverse-engineering methodology
- `docs/VERIFICATION.md` — how byte-identical output was verified
- `src/disp/README.md` — details on the two reconstructed source files
