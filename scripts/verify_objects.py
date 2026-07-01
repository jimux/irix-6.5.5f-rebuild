#!/usr/bin/env python3
"""Verify byte-identical reconstruction of IRIX 6.5.5f kernel objects."""
import subprocess, re, os, sys, argparse
from collections import defaultdict

OBJDUMP = "mips-linux-gnu-objdump"

def parse_objdump(path):
    """Parse a .o file, returning {function_name: hex_instruction_bytes}."""
    out = subprocess.check_output([OBJDUMP, '-d', path],
                                  stderr=subprocess.DEVNULL).decode()
    funcs = {}
    current = None
    for line in out.split('\n'):
        m = re.match(r'([0-9a-f]+) <(\w+)>:', line)
        if m:
            current = m.group(2)
            funcs[current] = ''
            continue
        if current:
            m = re.match(r'\s+[0-9a-f]+:\s+([0-9a-f ]+)\s', line)
            if m:
                funcs[current] += m.group(1).replace(' ', '')
    return funcs

def main():
    parser = argparse.ArgumentParser(
        description='Verify byte-identical kernel object reconstruction')
    parser.add_argument('--shipped', required=True,
                        help='Directory containing shipped .o files')
    parser.add_argument('--built', required=True,
                        help='Directory containing rebuilt .o files')
    parser.add_argument('--subsystem', help='Only check one subsystem')
    parser.add_argument('--verbose', '-v', action='store_true',
                        help='Show per-object results')
    args = parser.parse_args()

    shipped_dir = args.shipped
    built_dir = args.built
    if not os.path.isdir(shipped_dir):
        print(f"ERROR: shipped dir not found: {shipped_dir}")
        sys.exit(1)
    if not os.path.isdir(built_dir):
        print(f"ERROR: built dir not found: {built_dir}")
        sys.exit(1)

    # Build lookup: obj_name -> shipped_path
    shipped_map = {}
    for f in os.listdir(shipped_dir):
        if f.endswith('.o'):
            shipped_map[f] = os.path.join(shipped_dir, f)

    results = defaultdict(lambda: {'total': 0, 'match': 0, 'objects': 0,
                                     'perfect': 0})
    issues = []

    for f in sorted(os.listdir(built_dir)):
        if not f.endswith('.o'):
            continue

        # Determine subsystem from filename prefix
        if f.startswith('xfs_'):
            sub = 'xfs'
        elif f.startswith('efs_'):
            sub = 'efs'
        elif f.startswith('nfs_') or f.startswith('nlm_') or \
             f.startswith('rpc_') or f.startswith('xdr_') or \
             f.startswith('auth_') or f.startswith('clnt_') or \
             f.startswith('svc_') or f.startswith('lockd_') or \
             f.startswith('mount'):
            sub = 'nfs'
        elif f in ('wtree.o', 'batch.o', 'runq.o', 'cpu.o', 'gang.o',
                    'job.o', 'miser.o', 'psched.o', 'q.o', 'rt.o',
                    'utility.o', 'disp_idbg.o'):
            sub = 'disp'
        elif any(f.startswith(p) for p in ['bsd', 'uipc', 'in_', 'ip_',
                    'tcp_', 'udp_', 'raw_', 'if_', 'radix', 'route',
                    'igmp', 'ether', 'compat', 'hashing', 'bitswap']):
            sub = 'bsd'
        elif any(f.startswith(p) for p in ['dma', 'vme', 'eisa', 'ddi',
                    'disksub', 'devsupport', 'dbg', 'idbg', 'alenlist',
                    'hwcopy', 'sgset', 'lan']):
            sub = 'io'
        else:
            sub = 'os'

        if args.subsystem and sub != args.subsystem:
            continue

        built_path = os.path.join(built_dir, f)
        shipped_path = shipped_map.get(f)

        if not shipped_path:
            continue  # No shipped counterpart to compare

        s_funcs = parse_objdump(shipped_path)
        b_funcs = parse_objdump(built_path)

        if not s_funcs:
            continue  # Empty shipped object

        matches = sum(1 for n in s_funcs if n in b_funcs and s_funcs[n] == b_funcs[n])
        total = len(s_funcs)

        results[sub]['objects'] += 1
        results[sub]['total'] += total
        results[sub]['match'] += matches
        if matches == total:
            results[sub]['perfect'] += 1

        if args.verbose and matches < total:
            missing = [n for n in s_funcs if n not in b_funcs]
            diffs = [n for n in s_funcs if n in b_funcs and s_funcs[n] != b_funcs[n]]
            print(f"  {f}: {matches}/{total}")
            if missing:
                print(f"    MISSING: {missing}")
            if diffs:
                print(f"    DIFF: {diffs}")

    # Summary
    print(f"\n{'Subsystem':10s} {'Objects':>7s} {'Functions':>12s} {'Rate':>7s} {'Perfect':>8s}")
    print("-" * 55)
    grand_match = 0
    grand_total = 0
    grand_objects = 0
    grand_perfect = 0

    for sub in ['bsd', 'xfs', 'io', 'nfs', 'efs', 'os', 'disp']:
        if sub not in results:
            continue
        r = results[sub]
        pct = r['match'] * 100 // r['total'] if r['total'] > 0 else 0
        print(f"{sub:10s} {r['objects']:>6d}  {r['match']:>5d}/{r['total']:<5d}  {pct:>5d}%  {r['perfect']:>7d}")
        grand_match += r['match']
        grand_total += r['total']
        grand_objects += r['objects']
        grand_perfect += r['perfect']

    gpct = grand_match * 100 // grand_total if grand_total > 0 else 0
    print("-" * 55)
    print(f"{'TOTAL':10s} {grand_objects:>6d}  {grand_match:>5d}/{grand_total:<5d}  {gpct:>5d}%  {grand_perfect:>7d}")

    if grand_match == grand_total and grand_total > 0:
        print("\n✅ ALL FUNCTIONS BYTE-IDENTICAL")
        return 0
    else:
        print(f"\n{grand_total - grand_match} functions differ")
        return 1

if __name__ == '__main__':
    sys.exit(main())
