#pragma once
#include <stdbool.h>
#include <stdint.h>

typedef struct WMBWorkGate WMBWorkGate;
WMBWorkGate *WMBWorkGateCreate(void);
void WMBWorkGateDestroy(WMBWorkGate *gate);
bool WMBWorkGateIsCurrent(const WMBWorkGate *gate);
void WMBWorkGateInvalidate(WMBWorkGate *gate);

typedef struct WMBClipboardIntent WMBClipboardIntent;
WMBClipboardIntent *WMBClipboardIntentCreate(void);
void WMBClipboardIntentDestroy(WMBClipboardIntent *intent);
void WMBClipboardIntentCopy(WMBClipboardIntent *intent);
uint64_t WMBClipboardIntentCut(WMBClipboardIntent *intent);
bool WMBClipboardIntentIsCurrent(const WMBClipboardIntent *intent, uint64_t ticket);
uint64_t WMBClipboardIntentPending(const WMBClipboardIntent *intent);
void WMBClipboardIntentFinish(WMBClipboardIntent *intent, uint64_t ticket);
