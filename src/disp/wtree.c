/* wtree.c — IRIX 6.5.5f IP22 kernel, DISP weighted-tree scheduler
 * Reconstructed from shipped wtree.o via Ghidra + disassembly.
 * Uses offset-based access to avoid struct-layout conflicts with kernel headers.
 *
 * job_s offsets (verified from shipped disassembly):
 *   +0x00: j_queue.f   +0x04: j_queue.b   +0x08: j_queue.p   +0x0c: j_queue.fl
 *   +0x10: (pad)
 *   +0x14: j_flags     +0x18: j_state      +0x1c: w_sched0
 *   +0x20: w_sched1    +0x24: w_sched2     +0x28: w_sched3
 *   +0x38: j_u_area / runq pointer
 *   +0x40: w_credit    +0x50: w_runtime
 *
 * kthread_t offsets:
 *   +0x1fc: kt_uthread (ptr to uthread struct)
 *   +0x218: kt_job     (ptr to job_s)
 * uthread offsets:
 *   +0x134: priority byte
 */

typedef long long int64_t;
typedef unsigned int uint;
typedef unsigned short ushort;
typedef unsigned char uchar;

/* ---- Minimal types for our functions ---- */
struct q_elem_s { void *f; void *b; void *p; int fl; };

struct wtree_s {
    int wt_lock;               /* +0x00 */
    struct q_elem_s wt_ajobq;  /* +0x04 */
    int64_t wt_weights[81];    /* +0x18 */
};

/* Access macros — all offset-based to work with incomplete kernel types */
#define JOB_QUEUE_F(j)   (*(void **)((char *)(j) + 0x00))
#define JOB_QUEUE_P(j)   (*(void **)((char *)(j) + 0x08))
#define JOB_FLAGS(j)     (*(int *)((char *)(j) + 0x14))
#define JOB_STATE(j)     (*(int *)((char *)(j) + 0x18))
#define JOB_SCHED0(j)    (*(int *)((char *)(j) + 0x1c))
#define JOB_SCHED1(j)    (*(int *)((char *)(j) + 0x20))
#define JOB_SCHED2(j)    (*(int *)((char *)(j) + 0x24))
#define JOB_SCHED3(j)    (*(int *)((char *)(j) + 0x28))
#define JOB_RUNQ(j)      (*(void **)((char *)(j) + 0x38))
#define JOB_CREDIT(j)    (*(int64_t *)((char *)(j) + 0x40))
#define JOB_RUNTIME(j)   (*(int64_t *)((char *)(j) + 0x50))

#define KT_UTHREAD(kt)   (*(void **)((char *)(kt) + 0x1fc))
#define KT_JOB(kt)       (*(void **)((char *)(kt) + 0x218))
#define UT_PRIORITY(ut)  (*(uchar *)((char *)(ut) + 0x134))

/* ---- External symbols ---- */
extern struct wtree_s wtree;
extern struct wt_schedvec_s {
    char *sv_fmt;
    void (*sv_dbgp)(void *);
    void (*sv_run_time)(void *);
    void (*sv_detach)(void *);
} wt_schedvec;

extern void spinlock_init(void *, const char *);
extern void init_q_element(void *, void *);
extern int  nested_spintrylock(void *);
extern void nested_spinlock(void *);
extern void nested_spinunlock(void *);
extern void pushq(void *, void *);
extern void rmq(void *);
extern int  qprintf(const char *, ...);

void wt_dbgp(void *j);
void wt_run_time(void *kt);
void wt_detach(void *j);

/* ---- wt_get_priority ---- */
int wt_get_priority(void *kt)
{
    return UT_PRIORITY(KT_UTHREAD(kt));
}

/* ---- wt_set_weight ---- */
void wt_set_weight(void *kt, int w)
{
    void *j = KT_JOB(kt);
    if (j == (void *)0) return;
    if (JOB_STATE(j) != 1) return;
    JOB_CREDIT(j) = ((int64_t *)((char *)&wt_schedvec + 16))[w];
}

/* ---- wt_dbgp ---- */
void wt_dbgp(void *j)
{
    qprintf("            weight %lld acctime %lld\n",
            JOB_CREDIT(j), JOB_RUNTIME(j));
}

/* ---- wt_init ---- */
void wt_init(void *j, void *kt)
{
    /* Direct global loads from wt_schedvec — shipped uses $a2,$a0,$v1,$v0 order */
    JOB_SCHED0(j) = *(int *)&wt_schedvec;
    JOB_SCHED1(j) = *((int *)&wt_schedvec + 1);
    JOB_SCHED2(j) = *((int *)&wt_schedvec + 2);
    JOB_SCHED3(j) = *((int *)&wt_schedvec + 3);
    JOB_RUNTIME(j) = 0;
    {
        int pri = UT_PRIORITY(KT_UTHREAD(kt));
        /* Shipped uses wtree base for credit lookup, not wt_schedvec */
        JOB_CREDIT(j) = ((int64_t *)((char *)&wtree + 16))[pri];
    }
    nested_spinlock(&wtree.wt_lock);
    pushq(&wtree.wt_ajobq, j);
    nested_spinunlock(&wtree.wt_lock);
}

/* ---- wt_run_time ---- */
void wt_run_time(void *kt)
{
    void *j = KT_JOB(kt);
    JOB_RUNTIME(j) = JOB_RUNTIME(j) - 10000;
    if (JOB_QUEUE_F(j) == j) {
        nested_spinlock(&wtree.wt_lock);
        if (JOB_QUEUE_F(j) == j) pushq(&wtree.wt_ajobq, j);
        nested_spinunlock(&wtree.wt_lock);
    }
}

/* ---- wt_detach ---- */
void wt_detach(void *j)
{
    if (JOB_QUEUE_F(j) != j) {
        nested_spinlock(&wtree.wt_lock);
        if (JOB_QUEUE_F(j) != j) rmq(j);
        nested_spinunlock(&wtree.wt_lock);
    }
}

/* ---- wtree_init ---- */
void wtree_init(void)
{
    int64_t *w = wtree.wt_weights; uint i;
    spinlock_init(&wtree.wt_lock, "wtree-lock");
    init_q_element(&wtree.wt_ajobq, &wtree);
    *(int64_t *)((char *)&wtree + 16) = 10;  /* divisor stored in wt_ajobq.fl */
    w[0] = 1000;                               /* must be AFTER divisor store */
    for (i = 1; i < 40; i++)
        w[i] = w[i - 1] + w[i - 1] / 10;
}

/* ---- wtree_sched_tick ---- */
/* ---- wtree_sched_tick ---- */
void wtree_sched_tick(void)
{
    void *j, *next, *endq = (void *)&wtree;
    int64_t tc = 0, tr = 0, rr, d;

    if (nested_spintrylock(&wtree.wt_lock) == 0) return;

    j = *(void **)((char *)&wtree + 12);
    while (j != endq) {
        tc += JOB_CREDIT(j); tr += JOB_RUNTIME(j);
        j = *(void **)((char *)JOB_QUEUE_F(j) + 8);
    }
    if (tc == 0) { nested_spinunlock(&wtree.wt_lock); return; }
    rr = (tr << 24) / tc;

    j = *(void **)((char *)&wtree + 12);
    while (j != endq) {
        next = *(void **)((char *)JOB_QUEUE_F(j) + 8);
        if (JOB_FLAGS(j) == 0) goto nx;
        d = (JOB_CREDIT(j) * rr) >> 24;
        JOB_RUNTIME(j) = JOB_RUNTIME(j) + d;
        if (JOB_RUNTIME(j) < 0) goto nx;
        {
            void *rp = JOB_RUNQ(j); int ok = 0; short sr = (short)rr;
            while (rp) {
                short f74 = *(short *)((char *)rp + 0x74);
                short f76 = *(short *)((char *)rp + 0x76);
                ok = (f74 >= 0) || (f76 < 0);
                if (*(short *)((char *)rp + 0xc6) == sr) {
                    if (ok) {
                        int64_t q = (int64_t)(uint)*(ushort *)((char *)rp + 0x21c) * JOB_FLAGS(j) * 20000;
                        if (q < d) JOB_RUNTIME(j) = q;
                    }
                    rmq(j); break;
                }
                rp = *(void **)((char *)rp + 0x154);
            }
            if (!rp) rmq(j);
        }
nx:     j = next;
    }
    nested_spinunlock(&wtree.wt_lock);
}
