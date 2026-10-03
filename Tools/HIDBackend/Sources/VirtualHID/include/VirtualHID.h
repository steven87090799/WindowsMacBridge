#ifndef WINDOWS_MAC_BRIDGE_VIRTUAL_HID_H
#define WINDOWS_MAC_BRIDGE_VIRTUAL_HID_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <IOKit/hid/IOHIDDevice.h>
#ifdef __cplusplus
extern "C" {
#endif

typedef struct WMBVirtualHID WMBVirtualHID;
// USB HID modifier bits: left Ctrl/Shift/Option/Command, right Ctrl/Shift/Option/Command.
// Fn has a separate Apple vendor top-case report, not a keyboard modifier bit.
typedef struct {
    uint8_t modifiers;
    bool fn;
    uint8_t key_count;
    uint8_t consumer_count;
    uint16_t keys[32];
    uint16_t consumer_keys[32];
    uint8_t top_case_count, vendor_count, desktop_count;
    uint16_t top_case_keys[32], vendor_keys[32], desktop_keys[32];
} WMBHIDState;
typedef struct { uint32_t buttons; int16_t x, y, wheel, pan; } WMBPointingState;

enum {
    WMB_DRIVER_CONNECTED = 1,
    WMB_KEYBOARD_READY = 2,
    WMB_DRIVER_MISMATCH = 4,
    WMB_CONNECTION_FAULT = 8,
    WMB_POINTING_READY = 16,
};
// Diagnostic/codec entry points never connect to the driver or emit input.
uint64_t wmb_driver_version(void);
uint16_t wmb_client_protocol_version(void);
bool wmb_hid_element_is_neutral(IOHIDDeviceRef device, IOHIDElementRef element);
bool wmb_validate_state(const WMBHIDState *state);
size_t wmb_plan_state_transition(const WMBHIDState *previous, const WMBHIDState *next, WMBHIDState *reports, size_t capacity);
size_t wmb_encode_keyboard(const WMBHIDState *state, uint8_t *buffer, size_t capacity);
size_t wmb_encode_fn(const WMBHIDState *state, uint8_t *buffer, size_t capacity);
size_t wmb_encode_consumer(const WMBHIDState *state, uint8_t *buffer, size_t capacity);
size_t wmb_encode_vendor(const WMBHIDState *state, uint8_t *buffer, size_t capacity);
size_t wmb_encode_desktop(const WMBHIDState *state, uint8_t *buffer, size_t capacity);
size_t wmb_plan_pointing_motion(uint32_t buttons, int16_t x, int16_t y, int16_t wheel, int16_t pan, WMBPointingState *reports, size_t capacity);
size_t wmb_encode_pointing(const WMBPointingState *state, uint8_t *buffer, size_t capacity);

// Exactly one client per helper process. Requires root; never prompts or escalates.
WMBVirtualHID *wmb_virtual_hid_create(void);
uint32_t wmb_virtual_hid_status(const WMBVirtualHID *client);
void wmb_virtual_hid_enable_pointing(WMBVirtualHID *client);
bool wmb_virtual_hid_post_pointing(WMBVirtualHID *client, uint32_t buttons, int16_t x, int16_t y, int16_t wheel, int16_t pan);
// Reports enqueued but not yet completed by the official service.
uint32_t wmb_virtual_hid_outstanding(const WMBVirtualHID *client);
// Posting is accepted only after the official service reports keyboard ready.
bool wmb_virtual_hid_post(WMBVirtualHID *client, const WMBHIDState *state);
void wmb_virtual_hid_reset(WMBVirtualHID *client);
typedef void (*WMBStatusCallback)(void *context);
void wmb_virtual_hid_set_status_callback(WMBVirtualHID *client, WMBStatusCallback callback, void *context);
void wmb_virtual_hid_destroy(WMBVirtualHID *client);
#ifdef __cplusplus
}
#endif
#endif
