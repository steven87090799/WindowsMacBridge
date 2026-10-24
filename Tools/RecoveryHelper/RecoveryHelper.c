#include <CoreFoundation/CoreFoundation.h>
#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <spawn.h>
#include <stdbool.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/event.h>
#include <sys/file.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>

extern char **environ;
#ifndef WMB_RECOVERY_APP
#define WMB_RECOVERY_APP "/Applications/WindowsMacBridge.app"
#endif
#ifndef WMB_RECOVERY_LAUNCHER
#define WMB_RECOVERY_LAUNCHER "/usr/bin/open"
#endif
#ifdef WMB_RECOVERY_TESTING
#define WMB_DELAY_SCALE 0
#define WMB_ACK_TIMEOUT 1
#else
#define WMB_DELAY_SCALE 1
#define WMB_ACK_TIMEOUT 15
#endif

typedef struct { unsigned attempt, delay; uint64_t window; bool stop; } RecoveryPlan;

static uint64_t now_ms(void) {
    struct timeval value;
    gettimeofday(&value, NULL);
    return (uint64_t)value.tv_sec * 1000 + (uint64_t)value.tv_usec / 1000;
}

static RecoveryPlan next_plan(unsigned attempts, uint64_t window, uint64_t now) {
    if (now < window || now - window >= 300000) { attempts = 0; window = now; }
    static const unsigned delays[] = {1, 3, 10};
    RecoveryPlan result = {.attempt = attempts, .window = window, .stop = attempts >= 3};
    if (!result.stop) { result.delay = delays[attempts]; result.attempt++; }
    return result;
}

static bool number(const char *text, uint64_t *value) {
    if (!text || !*text) return false;
    for (const char *p = text; *p; p++) if (*p < '0' || *p > '9') return false;
    errno = 0;
    char *end = NULL;
    unsigned long long result = strtoull(text, &end, 10);
    if (errno || !end || *end) return false;
    *value = (uint64_t)result;
    return true;
}

static void record(int directory, const char *event, unsigned attempt) {
    int descriptor = openat(directory, "Recovery.log", O_WRONLY | O_CREAT | O_APPEND | O_CLOEXEC | O_NOFOLLOW, 0600);
    if (descriptor < 0) return;
    struct stat info;
    if (fstat(descriptor, &info) || !S_ISREG(info.st_mode) || info.st_uid != geteuid()) { close(descriptor); return; }
    if (info.st_size > 65536) (void)ftruncate(descriptor, 0);
    char message[256];
    int count = snprintf(message, sizeof(message), "%llu %s attempt=%u\n", (unsigned long long)now_ms(), event, attempt);
    if (count > 0 && (size_t)count < sizeof(message)) (void)write(descriptor, message, (size_t)count);
    close(descriptor);
}

static void notify_stopped(int directory, unsigned attempt) {
    record(directory, "recovery_stopped", attempt);
#ifndef WMB_RECOVERY_TESTING
    CFOptionFlags response = 0;
    (void)CFUserNotificationDisplayAlert(0, kCFUserNotificationStopAlertLevel, NULL, NULL, NULL,
        CFSTR("WindowsMacBridge 已停止自動恢復"),
        CFSTR("程式連續異常停止，或無法確認重新啟動成功。為避免反覆重開，已停止嘗試。請從「應用程式」手動開啟 WindowsMacBridge，並保留系統當機紀錄以供檢查。"),
        CFSTR("知道了"), NULL, NULL, &response);
#endif
}

static bool acknowledged(int directory, const char *name) {
    struct stat info;
    if (fstatat(directory, name, &info, AT_SYMLINK_NOFOLLOW) || !S_ISREG(info.st_mode) || info.st_uid != geteuid()) return false;
    (void)unlinkat(directory, name, 0);
    return true;
}

static bool await_relaunch(int directory, int queue, const char *name, pid_t child, bool *reaped) {
    struct timespec start;
    clock_gettime(CLOCK_MONOTONIC, &start);
    bool ready = false;
    int status = 0;
    while (true) {
        if (!*reaped) {
            pid_t result = waitpid(child, &status, WNOHANG);
            if (result == child) *reaped = true;
            else if (result < 0 && errno != EINTR) return false;
        }
        if (!ready) ready = acknowledged(directory, name);
        if (*reaped && (!WIFEXITED(status) || WEXITSTATUS(status) != 0)) return false;
        if (*reaped && ready) return true;
        struct timespec current;
        clock_gettime(CLOCK_MONOTONIC, &current);
        double remaining = WMB_ACK_TIMEOUT - (current.tv_sec - start.tv_sec) - (current.tv_nsec - start.tv_nsec) / 1e9;
        if (remaining <= 0) return false;
        struct timespec timeout = {.tv_sec = (time_t)remaining, .tv_nsec = (long)((remaining - (time_t)remaining) * 1e9)};
        struct kevent event;
        int result = kevent(queue, NULL, 0, &event, 1, &timeout);
        if (result == 0) return false;
        if (result < 0 && errno != EINTR) return false;
    }
}

static bool relaunch(int directory, const char *application, RecoveryPlan plan) {
    int queue = kqueue();
    if (queue < 0) return false;
    (void)fcntl(queue, F_SETFD, FD_CLOEXEC);
    struct kevent change;
    EV_SET(&change, directory, EVFILT_VNODE, EV_ADD | EV_CLEAR, NOTE_WRITE | NOTE_RENAME | NOTE_DELETE, 0, NULL);
    if (kevent(queue, &change, 1, NULL, 0, NULL) < 0) { close(queue); return false; }
    char token[33], ready[64], attempt[12], window[24];
    uint8_t random[16];
    arc4random_buf(random, sizeof(random));
    for (size_t index = 0; index < sizeof(random); index++) snprintf(token + index * 2, 3, "%02x", random[index]);
    snprintf(ready, sizeof(ready), "ready-%s", token);
    snprintf(attempt, sizeof(attempt), "%u", plan.attempt);
    snprintf(window, sizeof(window), "%llu", (unsigned long long)plan.window);
    char *arguments[] = {(char *)WMB_RECOVERY_LAUNCHER, "-g", (char *)application, "--args",
        "--bridge-recovery-attempt", attempt, "--bridge-recovery-window", window,
        "--bridge-recovery-token", token, NULL};
    pid_t child = 0;
    record(directory, "relaunch_requested", plan.attempt);
    int error = posix_spawn(&child, WMB_RECOVERY_LAUNCHER, NULL, NULL, arguments, environ);
    if (error) { close(queue); return false; }
    // Bound both LaunchServices and the new App's acknowledgment. The child
    // remains unreaped until checked, so its PID cannot be recycled here.
    EV_SET(&change, child, EVFILT_PROC, EV_ADD | EV_ONESHOT, NOTE_EXIT, 0, NULL);
    (void)kevent(queue, &change, 1, NULL, 0, NULL);
    bool reaped = false;
    bool success = await_relaunch(directory, queue, ready, child, &reaped);
    if (!reaped) {
        (void)kill(child, SIGKILL);
        while (waitpid(child, NULL, 0) < 0 && errno == EINTR) {}
    }
    close(queue);
    if (success) record(directory, "relaunch_acknowledged", plan.attempt);
    else record(directory, "relaunch_unconfirmed", plan.attempt);
    return success;
}

int main(int argc, char **argv) {
    if (argc == 2 && !strcmp(argv[1], "--self-check")) {
        RecoveryPlan a = next_plan(0, 1000, 1000), b = next_plan(2, 1000, 2000);
        RecoveryPlan c = next_plan(3, 1000, 2000), d = next_plan(3, 1000, 301000);
        if (a.attempt != 1 || a.delay != 1 || b.attempt != 3 || b.delay != 10 || !c.stop || d.stop || d.attempt != 1) return 1;
        puts("WindowsMacBridge recovery policy OK; no monitoring, relaunch or notification started.");
        return 0;
    }
#ifdef WMB_RECOVERY_TESTING
    if (argc == 5 && !strcmp(argv[1], "--plan")) {
        uint64_t attempts, window, now;
        if (!number(argv[2], &attempts) || attempts > UINT_MAX || !number(argv[3], &window) || !number(argv[4], &now)) return 64;
        RecoveryPlan plan = next_plan((unsigned)attempts, window, now);
        printf("%u %u %llu %u\n", plan.attempt, plan.delay, (unsigned long long)plan.window, plan.stop);
        return 0;
    }
#endif
    uint64_t attempts, window;
    if (argc != 5 || strcmp(argv[1], WMB_RECOVERY_APP) || !number(argv[3], &attempts) || attempts > 3 ||
        !number(argv[4], &window) || geteuid() == 0) return 64;
    int directory = open(argv[2], O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    struct stat info;
    if (directory < 0 || fstat(directory, &info) || info.st_uid != geteuid() || (info.st_mode & 0077)) return 77;
    record(directory, "monitoring", (unsigned)attempts);
    char buffer[32];
    ssize_t count;
    while ((count = read(STDIN_FILENO, buffer, sizeof(buffer))) != 0) {
        if (count < 0) { if (errno == EINTR) continue; close(directory); return 74; }
        if (memchr(buffer, 'Q', (size_t)count)) { record(directory, "normal_exit", (unsigned)attempts); close(directory); return 0; }
    }
    record(directory, "unexpected_exit", (unsigned)attempts);
    RecoveryPlan plan = next_plan((unsigned)attempts, window, now_ms());
    if (plan.stop) { notify_stopped(directory, plan.attempt); close(directory); return 75; }
    struct timespec delay = {.tv_sec = plan.delay * WMB_DELAY_SCALE, .tv_nsec = 0};
    while (nanosleep(&delay, &delay) < 0 && errno == EINTR) {}
    plan = next_plan((unsigned)attempts, window, now_ms());
    // A manual reopen during the delay wins. Never reopen a second instance.
    int parent = openat(directory, "..", O_RDONLY | O_DIRECTORY | O_CLOEXEC | O_NOFOLLOW);
    int lock = parent < 0 ? -1 : openat(parent, "instance.lock", O_RDWR | O_CLOEXEC | O_NOFOLLOW);
    if (parent >= 0) close(parent);
    if (lock < 0) { notify_stopped(directory, plan.attempt); close(directory); return 75; }
    if (flock(lock, LOCK_EX | LOCK_NB) < 0) {
        int error = errno;
        close(lock);
        if (error == EWOULDBLOCK) { record(directory, "existing_instance", plan.attempt); close(directory); return 0; }
        notify_stopped(directory, plan.attempt); close(directory); return 75;
    }
    (void)flock(lock, LOCK_UN);
    close(lock);
    bool success = relaunch(directory, argv[1], plan);
    if (!success) notify_stopped(directory, plan.attempt);
    close(directory);
    return success ? 0 : 75;
}
