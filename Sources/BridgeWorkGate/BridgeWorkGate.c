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
