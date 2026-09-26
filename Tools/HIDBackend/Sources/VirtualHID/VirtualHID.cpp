#include "VirtualHID.h"
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
    return result;
}
report::consumer_input consumer(const WMBHIDState& state) {
    report::consumer_input result;
    for (size_t i = 0; i < state.consumer_count; ++i) result.keys.insert(state.consumer_keys[i]);
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
    std::unique_ptr<service::client> client;
    // Caller owns serialization; the official service callbacks only touch status.
    WMBHIDState last{};
    bool has_last = false;
};

extern "C" uint64_t wmb_driver_version() {
    return type_safe::get(pqrs::karabiner::driverkit::driver_version::embedded_driver_version);
}
extern "C" uint16_t wmb_client_protocol_version() {
    return type_safe::get(pqrs::karabiner::driverkit::client_protocol_version::embedded_client_protocol_version);
}
extern "C" bool wmb_validate_state(const WMBHIDState* state) {
    if (!state || state->key_count > 32 || state->consumer_count > 32) return false;
    for (size_t i = 0; i < state->key_count; ++i) {
        // Modifier usages belong exclusively in the modifier byte.
        if (state->keys[i] < 4 || state->keys[i] >= 0xe0) return false;
        for (size_t j = 0; j < i; ++j) if (state->keys[j] == state->keys[i]) return false;
    }
    for (size_t i = 0; i < state->consumer_count; ++i) {
        if (state->consumer_keys[i] == 0) return false;
        for (size_t j = 0; j < i; ++j) if (state->consumer_keys[j] == state->consumer_keys[i]) return false;
    }
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
    return client ? client->status.load() : WMB_CONNECTION_FAULT;
}
extern "C" bool wmb_virtual_hid_post(WMBVirtualHID* client, const WMBHIDState* state) {
    if (!client || !wmb_validate_state(state)) return false;
    const auto status = client->status.load();
    if (!(status & WMB_KEYBOARD_READY) || (status & (WMB_DRIVER_MISMATCH | WMB_CONNECTION_FAULT))) return false;
    try {
        if (client->needs_full_report.exchange(false)) client->has_last = false;
        // Fn is a separate report. Only changes are queued to the official transport.
        if (!client->has_last || fn(client->last) != fn(*state)) client->client->async_post_report(fn(*state));
        if (!client->has_last || keyboard(client->last) != keyboard(*state)) client->client->async_post_report(keyboard(*state));
        if (!client->has_last || consumer(client->last) != consumer(*state)) client->client->async_post_report(consumer(*state));
        client->last = *state; client->has_last = true;
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
