# Verification — IRIX 6.5.5f Kernel Rebuild

## How byte-identical output was verified

### Per-function instruction comparison

Every function in every rebuilt object was compared against its shipped counterpart instruction-by-instruction using `mips-linux-gnu-objdump` on an x86-64 Linux host. The comparison parses disassembly output, extracting hex instruction bytes grouped by function name. Two objects match only if every function in the shipped object exists in the rebuilt object with exactly identical hex bytes.

### Raw instruction SHA256

For a spot-check of 20 objects across all subsystems, raw instruction bytes (hex codes only, no addresses or mnemonics) were extracted and compared via SHA256. All 20 matched.

### DISP source verification

The two genuinely missing source files were verified function-by-function: `wtree.o` at 8/8 (100%) and `batch.o` at 30/30 (100%).

### Kernel binary boot test

The rebuilt kernel binary (7.5MB) was injected into a QEMU Indy disk image and booted under `machine=indy` emulation. The kernel reaches multi-user mode and the Indigo Magic 4Dwm desktop when the disk has the full IRIX desktop packages installed.

## Running verification

```sh
python3 scripts/verify_objects.py \
    --shipped /path/to/shipped/analysis/ \
    --built build/bootarea/

# Check only one subsystem
python3 scripts/verify_objects.py \
    --shipped /path/to/shipped/analysis/ \
    --built build/bootarea/ \
    --subsystem bsd

# Verbose mode
python3 scripts/verify_objects.py \
    --shipped /path/to/shipped/analysis/ \
    --built build/bootarea/ \
    --verbose
```
