#include "BridgeWorkGate.h"
#include <stdatomic.h>
#include <stdlib.h>

_Static_assert(ATOMIC_BOOL_LOCK_FREE == 2, "Work validity must be lock-free on supported targets");
struct WMBWorkGate { atomic_bool valid; };
WMBWorkGate *WMBWorkGateCreate(void) {
    WMBWorkGate *gate = malloc(sizeof(*gate));
    if (gate) { atomic_init(&gate->valid, true); }
    return gate;
}
void WMBWorkGateDestroy(WMBWorkGate *gate) { free(gate); }
bool WMBWorkGateIsCurrent(const WMBWorkGate *gate) {
    return atomic_load_explicit(&gate->valid, memory_order_acquire);
}
void WMBWorkGateInvalidate(WMBWorkGate *gate) {
    atomic_store_explicit(&gate->valid, false, memory_order_release);
}

_Static_assert(ATOMIC_LLONG_LOCK_FREE == 2, "Clipboard intent must be lock-free");
struct WMBClipboardIntent { atomic_ullong revision; atomic_ullong cut; };
WMBClipboardIntent *WMBClipboardIntentCreate(void) {
    WMBClipboardIntent *intent = malloc(sizeof(*intent));
    if (intent) { atomic_init(&intent->revision, 0); atomic_init(&intent->cut, 0); }
    return intent;
}
void WMBClipboardIntentDestroy(WMBClipboardIntent *intent) { free(intent); }
void WMBClipboardIntentCopy(WMBClipboardIntent *intent) {
    atomic_fetch_add_explicit(&intent->revision, 1, memory_order_acq_rel);
    atomic_store_explicit(&intent->cut, 0, memory_order_release);
}
uint64_t WMBClipboardIntentCut(WMBClipboardIntent *intent) {
    uint64_t ticket = atomic_fetch_add_explicit(&intent->revision, 1, memory_order_acq_rel) + 1;
    atomic_store_explicit(&intent->cut, ticket, memory_order_release);
    return ticket;
}
bool WMBClipboardIntentIsCurrent(const WMBClipboardIntent *intent, uint64_t ticket) {
    return ticket != 0 && atomic_load_explicit(&intent->revision, memory_order_acquire) == ticket &&
        atomic_load_explicit(&intent->cut, memory_order_acquire) == ticket;
}
uint64_t WMBClipboardIntentPending(const WMBClipboardIntent *intent) {
    uint64_t ticket = atomic_load_explicit(&intent->cut, memory_order_acquire);
    return WMBClipboardIntentIsCurrent(intent, ticket) ? ticket : 0;
}
void WMBClipboardIntentFinish(WMBClipboardIntent *intent, uint64_t ticket) {
    unsigned long long expected = ticket;
    atomic_compare_exchange_strong_explicit(&intent->cut, &expected, 0, memory_order_acq_rel, memory_order_acquire);
}
