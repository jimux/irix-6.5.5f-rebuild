#!/bin/sh
# Build the IRIX 6.5.5f IP22 (Indy) kernel from source.
#
# Run on an IRIX 6.5 system with MIPSpro 7.2.1 installed and the
# kernel build environment at /usr/cpu/sysgen/root.
#
# Usage:
#   sh scripts/build_kernel.sh           # full build: smake + lboot
#   sh scripts/build_kernel.sh compile   # compile only (smake)
#   sh scripts/build_kernel.sh link      # link only (lboot)
#
# Output: build/unix — a bootable IP22 Indy kernel binary.
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
cd "$PROJECT_DIR"

KERN_SRC="$PROJECT_DIR/src/kern"
BOOTAREA="$PROJECT_DIR/build/bootarea"
MASTERD="$PROJECT_DIR/build/master.d"
SYSTEM_FILE="$PROJECT_DIR/build/system.nolocks"
STUNE="$PROJECT_DIR/build/stune"
MTUNE="$PROJECT_DIR/build/mtune"
STAGING="$PROJECT_DIR/build/staging"
OUTPUT="$PROJECT_DIR/build/unix"

SMAKE=/usr/sbin/smake
LBOOT=/usr/sbin/lboot
CC=/usr/cpu/sysgen/root/usr/bin/cc

# ── Kernel compiler flags (from shipped .comment + kcommondefs) ──
# These are used for the C-only fallback path. The smake build
# picks up the same flags from kcommondefs automatically.
KCFLAGS="-n32 -mips3 -O3 -G 8 -non_shared -common"
KCFLAGS="$KCFLAGS -TENV:kernel -OPT:space -OPT:Olimit=0 -CG:unique_exit=on"
KCFLAGS="$KCFLAGS -LANG:=ansi_c -TARG:t5_ll_sc_bug=on -OPT:wrap_around_unsafe_opt=off"
KCFLAGS="$KCFLAGS -TENV:X=1 -OPT:IEEE_arithmetic=1 -OPT:roundoff=0"

KDEFS="-D_KERNEL -DSTATIC=static -DCELL_CAPABLE"
KDEFS="$KDEFS -D_PAGESZ=4096 -DMSIZE=256 -DMCLBYTES=2048 -DNBPG=4096"
KDEFS="$KDEFS -DSP -DIP22 -DR4000 -DMIPS3 -DR4000_DADDIU_WAR"
KDEFS="$KDEFS -DJUMP_WAR -DPROBE_WAR -DBADVA_WAR -D_MEM_PARITY_WAR"
KDEFS="$KDEFS -D_TLB_LOOP_LIMIT -DTLBMOD_BADVADDR_WAR"
KDEFS="$KDEFS -D_VCE_AVOIDANCE -D_R4600_CACHEOP_WAR -D_R4600_2_0_CACHEOP_WAR"
KDEFS="$KDEFS -D_IRIX5_MIPS3 -D_IRIX5_MIPS4 -D_R5000_BADVADDR_WAR"
KDEFS="$KDEFS -D_R5000_CVT_WAR=1 -D_MTEXT_VFS"

KINCLUDES="-I$KERN_SRC -I$KERN_SRC/sys -I$KERN_SRC/os -I$KERN_SRC/bsd"
KINCLUDES="$KINCLUDES -I$KERN_SRC/ml -I$KERN_SRC/fs -I$KERN_SRC/io"
KINCLUDES="$KINCLUDES -I$KERN_SRC/fs/xfs -I$KERN_SRC/fs/efs -I$KERN_SRC/fs/nfs"
KINCLUDES="$KINCLUDES -I$KERN_SRC/os/scheduler -I$KERN_SRC/os/proc -I$KERN_SRC/os/vm"
KINCLUDES="$KINCLUDES -I$KERN_SRC/os/as -I$KERN_SRC/os/file -I$KERN_SRC/os/host"
KINCLUDES="$KINCLUDES -I$KERN_SRC/os/shm -I$KERN_SRC/os/pagg -I$KERN_SRC/os/ksync"
KINCLUDES="$KINCLUDES -I$KERN_SRC/os/numa -I$KERN_SRC/os/cpr"
KINCLUDES="$KINCLUDES -I$KERN_SRC/../IP22bootarea"

compile_cc() {
    local subdir="$1" extra_flags="$2"
    find "$KERN_SRC/$subdir" -maxdepth 1 -name '*.c' | while read -r src; do
        local obj="$STAGING/$(basename "$src" .c).o"
        $CC $KCFLAGS $KDEFS $KINCLUDES $extra_flags -c "$src" -o "$obj" && cp "$obj" "$BOOTAREA/"
    done
    find "$KERN_SRC/$subdir" -maxdepth 1 -name '*.s' | while read -r src; do
        local obj="$STAGING/$(basename "$src" .s).o"
        $CC $KCFLAGS $extra_flags -c "$src" -o "$obj" && cp "$obj" "$BOOTAREA/"
    done
}

# ── Prepare build directories ─────────────────────────────────
rm -rf "$STAGING"
mkdir -p "$BOOTAREA" "$STAGING" "$(dirname "$OUTPUT")"
touch "$STUNE"

echo "=== IRIX 6.5.5f IP22 Kernel Build ==="
echo "  Source:  $KERN_SRC"
echo "  Output:  $OUTPUT"
echo ""

# ── Step 1: Compile kernel objects ────────────────────────────
if [ "${1:-all}" = "all" ] || [ "${1:-all}" = "compile" ]; then
    echo "=== Step 1: Compiling kernel objects ==="

    # Try smake first (preferred — uses the exact SGI build system)
    if [ -x "$SMAKE" ] && [ -f "$PROJECT_DIR/build/Makefile" ]; then
        echo "  Using smake (SGI parallel make)..."
        cd "$PROJECT_DIR"
        SMAKE_JOBS="${SMAKE_JOBS:-$(sysconf NPROC_ONLN 2>/dev/null || echo 4)}"
        "$SMAKE" -J"$SMAKE_JOBS" -k 2>&1 || true
        echo "  smake done — $(ls "$BOOTAREA"/*.o 2>/dev/null | wc -l) objects"
    else
        echo "  smake not available, using cc directly..."
        compile_cc "bsd"          "-signed -common"
        compile_cc "bsd/misc"     "-signed -common"
        compile_cc "bsd/net"      "-signed -common"
        compile_cc "bsd/socket"   "-signed -common"
        compile_cc "fs/xfs"       ""
        compile_cc "fs/efs"       ""
        compile_cc "fs/nfs"       "-DNSD -D_IRIX5"
        compile_cc "io"           ""
        compile_cc "os"           ""
        compile_cc "os/scheduler" ""
        compile_cc "os/proc"      ""
        compile_cc "os/vm"        ""
        compile_cc "os/as"        ""
        compile_cc "os/file"      ""
        compile_cc "os/host"      ""
        echo "  cc done — $(ls "$BOOTAREA"/*.o 2>/dev/null | wc -l) objects"
    fi

    # ── Build our reconstructed DISP sources ───────────────────
    echo "  Building reconstructed DISP sources..."
    $CC $KCFLAGS $KDEFS $KINCLUDES -G 0 -c "$PROJECT_DIR/src/disp/wtree.c" -o "$BOOTAREA/wtree.o"
    $CC $KCFLAGS -c "$PROJECT_DIR/src/disp/wt_run_time.s" -o "$STAGING/wt_run_time.o"
    $CC $KCFLAGS -c "$PROJECT_DIR/src/disp/wtree_sched_tick_raw.s" -o "$STAGING/wtree_sched_tick.o"
    $CC $KCFLAGS -c "$PROJECT_DIR/src/disp/batch_raw.s" -o "$BOOTAREA/batch.o"
    echo "  DISP sources built"
fi

# ── Step 2: Link the kernel with lboot ────────────────────────
if [ "${1:-all}" = "all" ] || [ "${1:-all}" = "link" ]; then
    echo "=== Step 2: Linking kernel with lboot ==="
    echo "  Bootarea: $(ls "$BOOTAREA" | wc -l) files"

    "$LBOOT" -v \
        -m "$MASTERD" \
        -b "$BOOTAREA" \
        -u "$OUTPUT" \
        -s "$SYSTEM_FILE" \
        -c "$STUNE" \
        -n "$MTUNE"

    if [ -f "$OUTPUT" ]; then
        echo ""
        echo "=== Kernel built successfully ==="
        ls -la "$OUTPUT"
        file "$OUTPUT"
        echo ""
        echo "To install: cp $OUTPUT /unix && reboot"
    else
        echo "=== Kernel build FAILED ==="
        exit 1
    fi
fi
