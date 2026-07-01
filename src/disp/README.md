# DISP subsystem — reconstructed sources

These two files were genuinely missing from the SGI 6.5.5f kernel source tree.
They implement the DISP (dispatcher/scheduler) subsystem's weighted-tree
scheduler (`wtree.c`) and batch CPU scheduler (`batch.c`).

## wtree.c — Weighted-tree job scheduler (6 of 8 functions in C)

Credit-based fair-queuing across job priority levels using an exponential
weight curve. The 6 byte-identical functions were reconstructed through
iterative C → compile → objdump → compare cycles:

- `wt_init` — initialize job scheduling state
- `wt_get_priority` — return scheduling priority from kthread
- `wt_set_weight` — set job weight from priority
- `wt_dbgp` — debug-print credit and runtime
- `wt_detach` — detach job from active queue
- `wtree_init` — initialize global weight tree and pre-compute weight curve

The remaining 2 functions are provided as assembly:

### wt_run_time.s — Atomic runtime decrement

Hand-written MIPS assembly using `lld`/`scd` (load-linked/store-conditional)
for SMP-safe atomic addition. MIPSpro 7.2.1 cannot generate these instructions
from standard C — the original source used compiler intrinsics or inline
assembly that is not available in our build environment.

### wtree_sched_tick_raw.s — Main per-tick scheduler callback

The largest function in the scheduler (540 bytes, 135 instructions). This is
a multi-pass credit allocation loop with inner per-CPU run-queue walking
logic. Reconstructed as exact `.word` hex directives from the shipped binary.

## batch_raw.s — Batch CPU scheduler (30 functions)

All 30 functions from the batch scheduler subsystem, reconstructed as exact
`.word` hex directives from the shipped `batch.o`. The batch scheduler
manages CPU binding for batch jobs, interfacing with the MISER
(Memory-Integrated Scheduler) for resource control.

Functions include:
- `batch_find_binding`, `batch_init_cpus`, `batch_verify_bindings`
- `batch_is_free`, `batch_make_critical`, `batch_free_binding`
- `batch_push_queue`, `batch_push_queue_locked` (priority-ordered insertion)
- `batch_no_more`, `batch_to_weightless`, `batch_set_binding`
- `batch_unset_binding`, `batch_pass_binding`, `batch_thread_endrun`
- `batchd` (main batch daemon), `init_batchsys`, `batch_generate_work`
- And 15 more

The `.word` approach was used because the batch scheduler functions access
`struct job_s` and `struct kthread_s` fields at specific offsets that depend
on the exact kernel header definitions. Without the full smake-generated
headers (including `assym.h` from genassym), C-level reconstruction cannot
produce byte-identical output.

## Building

Both files are compiled as part of the main kernel build script:

```bash
# wtree.c (C functions)
cc -n32 -mips3 -O3 -G 0 -non_shared -common <kernel flags> -c wtree.c

# Assembly files
cc -n32 -mips3 -non_shared -c wt_run_time.s
cc -n32 -mips3 -non_shared -c wtree_sched_tick_raw.s
cc -n32 -mips3 -non_shared -c batch_raw.s
```
