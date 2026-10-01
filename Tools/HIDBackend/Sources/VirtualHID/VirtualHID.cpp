#include "VirtualHID.h"
#include <IOKit/hid/IOHIDValue.h>
#include <pqrs/karabiner/driverkit/virtual_hid_device_service.hpp>
#include <algorithm>
#include <atomic>
#include <chrono>
#include <cstring>
#include <memory>
#include <mutex>
#include <thread>
#include <unistd.h>

namespace service = pqrs::karabiner::driverkit::virtual_hid_device_service;
namespace report = pqrs::karabiner::driverkit::virtual_hid_device_driver::hid_report;
namespace {
std::mutex lifecycle;
bool occupied = false;
int64_t now_ns() {
    return std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
}

report::keyboard_input keyboard(const WMBHIDState& state) {
    report::keyboard_input result;
    for (unsigned i = 0; i < 8; ++i) {
        if (state.modifiers & (1u << i)) result.modifiers.insert(static_cast<report::modifier>(1u << i));
    }
    for (size_t i = 0; i < state.key_count; ++i) result.keys.insert(state.keys[i]);
    return result;
}
report::apple_vendor_top_case_input fn(const WMBHIDState& state) {
    report::apple_vendor_top_case_input result;
    if (state.fn) result.keys.insert(type_safe::get(pqrs::hid::usage::apple_vendor_top_case::keyboard_fn));
    for (size_t i = 0; i < state.top_case_count; ++i) result.keys.insert(state.top_case_keys[i]);
    return result;
}
report::consumer_input consumer(const WMBHIDState& state) {
    report::consumer_input result;
    for (size_t i = 0; i < state.consumer_count; ++i) result.keys.insert(state.consumer_keys[i]);
    return result;
}
report::apple_vendor_keyboard_input vendor(const WMBHIDState& state) {
    report::apple_vendor_keyboard_input result;
    for (size_t i = 0; i < state.vendor_count; ++i) result.keys.insert(state.vendor_keys[i]);
    return result;
}
report::generic_desktop_input desktop(const WMBHIDState& state) {
    report::generic_desktop_input result;
    for (size_t i = 0; i < state.desktop_count; ++i) result.keys.insert(state.desktop_keys[i]);
    return result;
}
template <class Report> size_t encode(const Report& value, uint8_t* output, size_t capacity) {
    if (!output || capacity < sizeof(value)) return 0;
    std::memcpy(output, &value, sizeof(value));
    return sizeof(value);
}
}

struct WMBVirtualHID {
    std::atomic<uint32_t> status{0};
    std::atomic<bool> needs_full_report{true};
    std::atomic<unsigned> outstanding{0};
    std::atomic<int64_t> progress{0};
    std::unique_ptr<service::client> client;
    // Caller owns serialization; the official service callbacks only touch status.
    WMBHIDState last{};
    bool has_last = false;
};

extern "C" uint64_t wmb_driver_version() {
    return type_safe::get(pqrs::karabiner::driverkit::driver_version::embedded_driver_version);
}
extern "C" bool wmb_hid_element_is_neutral(IOHIDDeviceRef device, IOHIDElementRef element) {
    IOHIDValueRef value = nullptr;
    return IOHIDDeviceGetValueWithOptions(device, element, &value, kIOHIDDeviceGetValueWithoutUpdate) == kIOReturnSuccess &&
           value && IOHIDValueGetIntegerValue(value) == 0;
}
extern "C" uint16_t wmb_client_protocol_version() {
    return type_safe::get(pqrs::karabiner::driverkit::client_protocol_version::embedded_client_protocol_version);
}
extern "C" bool wmb_validate_state(const WMBHIDState* state) {
    if (!state || state->key_count > 32 || state->consumer_count > 32 || state->top_case_count > 32 || state->vendor_count > 32 || state->desktop_count > 32) return false;
    for (size_t i = 0; i < state->key_count; ++i) {
        // Modifier usages belong exclusively in the modifier byte.
        if (state->keys[i] < 4 || state->keys[i] >= 0xe0) return false;
        for (size_t j = 0; j < i; ++j) if (state->keys[j] == state->keys[i]) return false;
    }
    for (size_t i = 0; i < state->consumer_count; ++i) {
        if (state->consumer_keys[i] == 0) return false;
        for (size_t j = 0; j < i; ++j) if (state->consumer_keys[j] == state->consumer_keys[i]) return false;
    }
    const auto valid = [](const uint16_t* keys, unsigned count) {
        for (unsigned i = 0; i < count; ++i) {
            if (!keys[i]) return false;
            for (unsigned j = 0; j < i; ++j) if (keys[i] == keys[j]) return false;
        }
        return true;
    };
    if (!valid(state->top_case_keys, state->top_case_count) || !valid(state->vendor_keys, state->vendor_count) ||
        !valid(state->desktop_keys, state->desktop_count)) return false;
    if (state->fn) for (unsigned i = 0; i < state->top_case_count; ++i) if (state->top_case_keys[i] == 3) return false;
    return true;
}
extern "C" size_t wmb_encode_keyboard(const WMBHIDState* state, uint8_t* buffer, size_t capacity) {
    return wmb_validate_state(state) ? encode(keyboard(*state), buffer, capacity) : 0;
}
extern "C" size_t wmb_encode_fn(const WMBHIDState* state, uint8_t* buffer, size_t capacity) {
    return wmb_validate_state(state) ? encode(fn(*state), buffer, capacity) : 0;
}
extern "C" size_t wmb_encode_consumer(const WMBHIDState* state, uint8_t* buffer, size_t capacity) {
    return wmb_validate_state(state) ? encode(consumer(*state), buffer, capacity) : 0;
}
extern "C" size_t wmb_encode_vendor(const WMBHIDState* state, uint8_t* buffer, size_t capacity) {
    return wmb_validate_state(state) ? encode(vendor(*state), buffer, capacity) : 0;
}
extern "C" size_t wmb_encode_desktop(const WMBHIDState* state, uint8_t* buffer, size_t capacity) {
    return wmb_validate_state(state) ? encode(desktop(*state), buffer, capacity) : 0;
}
extern "C" size_t wmb_plan_state_transition(const WMBHIDState* previous, const WMBHIDState* next, WMBHIDState* reports, size_t capacity) {
    if (!reports || !wmb_validate_state(next) || (previous && !wmb_validate_state(previous))) return 0;
    const bool rollover = previous && (previous->modifiers != next->modifiers || previous->fn != next->fn) &&
        (previous->key_count || previous->consumer_count || previous->top_case_count || previous->vendor_count || previous->desktop_count);
    const size_t count = rollover ? 3 : 1;
    if (capacity < count) return 0;
    if (rollover) {
        reports[0] = {}; reports[0].modifiers = previous->modifiers; reports[0].fn = previous->fn;
        reports[1] = {};
    }
    reports[count - 1] = *next;
    return count;
}
extern "C" WMBVirtualHID* wmb_virtual_hid_create() {
    if (geteuid() != 0) return nullptr;
    std::lock_guard<std::mutex> guard(lifecycle);
    if (occupied) return nullptr;
    occupied = true;
    std::unique_ptr<WMBVirtualHID> result;
    try {
        pqrs::dispatcher::extra::initialize_shared_dispatcher();
        result = std::make_unique<WMBVirtualHID>();
        auto* state = result.get();
        state->client = std::make_unique<service::client>();
        state->client->output_request_completed.connect([state] {
            state->outstanding.fetch_sub(1);
            state->progress.store(now_ns());
        });
        state->client->connected.connect([state] {
            state->needs_full_report.store(true);
            state->status.fetch_and(~WMB_CONNECTION_FAULT);
            service::virtual_hid_keyboard_parameters parameters;
            parameters.set_country_code(pqrs::hid::country_code::us);
            state->client->async_virtual_hid_keyboard_initialize(parameters);
        });
        state->client->driver_connected.connect([state](bool ready) {
            if (ready) state->status.fetch_or(WMB_DRIVER_CONNECTED);
            else state->status.fetch_and(~(WMB_DRIVER_CONNECTED | WMB_KEYBOARD_READY));
        });
        state->client->virtual_hid_keyboard_ready.connect([state](bool ready) {
            if (ready) state->status.fetch_or(WMB_KEYBOARD_READY);
            else {
                state->status.fetch_and(~WMB_KEYBOARD_READY);
                state->needs_full_report.store(true);
            }
        });
        state->client->driver_version_mismatched.connect([state](bool mismatch) {
            if (mismatch) state->status.fetch_or(WMB_DRIVER_MISMATCH);
            else state->status.fetch_and(~WMB_DRIVER_MISMATCH);
        });
        auto fault = [state] {
            state->status.store(WMB_CONNECTION_FAULT);
            state->needs_full_report.store(true);
        };
        state->client->closed.connect(fault);
        state->client->connect_failed.connect([fault](auto&&) { fault(); });
        state->client->error_occurred.connect([fault](auto&&) { fault(); });
        state->client->warning_reported.connect([fault](auto&&) { fault(); });
        state->client->async_start();
        return result.release();
    } catch (...) {
        result.reset();
        pqrs::dispatcher::extra::terminate_shared_dispatcher();
        occupied = false;
        return nullptr;
    }
}
extern "C" uint32_t wmb_virtual_hid_status(const WMBVirtualHID* client) {
    if (!client) return WMB_CONNECTION_FAULT;
    // Never keep a physical keyboard seized while output service replies are stalled.
    if (client->outstanding.load() > 0 && now_ns() - client->progress.load() > 500000000) return WMB_CONNECTION_FAULT;
    return client->status.load();
}
extern "C" bool wmb_virtual_hid_post(WMBVirtualHID* client, const WMBHIDState* state) {
    if (!client || !wmb_validate_state(state)) return false;
    const auto status = wmb_virtual_hid_status(client);
    if (!(status & WMB_KEYBOARD_READY) || (status & (WMB_DRIVER_MISMATCH | WMB_CONNECTION_FAULT))) return false;
    try {
        if (client->needs_full_report.exchange(false)) client->has_last = false;
        // One reservation per changed report, decremented only on an official service reply.
        auto post = [client](const auto& report) {
            if (client->outstanding.load() >= 256) throw std::runtime_error("output backlog");
            if (client->outstanding.fetch_add(1) == 0) client->progress.store(now_ns());
            client->client->async_post_report(report);
        };
        WMBHIDState sequence[3];
        const size_t count = wmb_plan_state_transition(client->has_last ? &client->last : nullptr, state, sequence, 3);
        if (!count) return false;
        for (size_t index = 0; index < count; ++index) {
            const auto& next = sequence[index];
            if (!client->has_last || fn(client->last) != fn(next)) post(fn(next));
            if (!client->has_last || keyboard(client->last) != keyboard(next)) post(keyboard(next));
            if (!client->has_last || consumer(client->last) != consumer(next)) post(consumer(next));
            if (!client->has_last || vendor(client->last) != vendor(next)) post(vendor(next));
            if (!client->has_last || desktop(client->last) != desktop(next)) post(desktop(next));
            client->last = next; client->has_last = true;
        }
        return true; // Enqueued, not a driver delivery acknowledgement.
    } catch (...) { client->status.store(WMB_CONNECTION_FAULT); return false; }
}
extern "C" void wmb_virtual_hid_reset(WMBVirtualHID* client) {
    if (!client) return;
    try {
        client->client->async_virtual_hid_keyboard_reset();
        client->has_last = false;
    } catch (...) { client->status.store(WMB_CONNECTION_FAULT); }
}
extern "C" void wmb_virtual_hid_destroy(WMBVirtualHID* client) {
    if (!client) return;
    std::lock_guard<std::mutex> guard(lifecycle);
    wmb_virtual_hid_reset(client);
    // Give the asynchronous reset a bounded shutdown window; not an acknowledgement.
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    delete client;
    pqrs::dispatcher::extra::terminate_shared_dispatcher();
    occupied = false;
}
