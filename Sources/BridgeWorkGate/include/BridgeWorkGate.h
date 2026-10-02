#pragma once
#include <stdbool.h>

typedef struct WMBWorkGate WMBWorkGate;
WMBWorkGate *WMBWorkGateCreate(void);
void WMBWorkGateDestroy(WMBWorkGate *gate);
bool WMBWorkGateIsCurrent(const WMBWorkGate *gate);
void WMBWorkGateInvalidate(WMBWorkGate *gate);
