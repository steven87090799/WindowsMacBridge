// Read-only endpoint counters. No task suspension, screen, input or clipboard.
// Compile: clang -O2 -Wall -Wextra -Werror process-resource-snapshot.c -o snapshot
// Run: snapshot <pid> <exact-executable-path>
#include <libproc.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <time.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <limits.h>
#include <errno.h>
#include <mach/mach_time.h>

int main(int argc, char **argv) {
    if (argc != 3) return 64;
    char *end = NULL;
    errno = 0;
    long parsed = strtol(argv[1], &end, 10);
    if (errno || !end || *end || parsed <= 0 || parsed > INT_MAX) return 64;
    int pid = (int)parsed;
    char path[PROC_PIDPATHINFO_MAXSIZE] = {0};
    struct rusage_info_v4 before = {0}, after = {0};
    struct proc_taskinfo task = {0};
    if (proc_pidpath(pid, path, sizeof(path)) <= 0 || strcmp(path, argv[2])) return 65;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&before)) return 66;
    if (proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &task, sizeof(task)) != sizeof(task)) return 66;
    if (proc_pid_rusage(pid, RUSAGE_INFO_V4, (rusage_info_t *)&after)) return 66;
    if (before.ri_proc_start_abstime != after.ri_proc_start_abstime ||
        proc_pidpath(pid, path, sizeof(path)) <= 0 || strcmp(path, argv[2])) return 65;
    struct timespec now;
    if (clock_gettime(CLOCK_MONOTONIC_RAW, &now)) return 66;
    mach_timebase_info_data_t timebase;
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || !timebase.denom) return 66;
    // rusage CPU counters use Mach ticks. Convert explicitly on Apple silicon.
    long double cpu_seconds = ((long double)after.ri_user_time + after.ri_system_time) *
        timebase.numer / timebase.denom / 1000000000.0L;
    printf("{\"pid\":%d,\"start_abstime\":%llu,\"monotonic_ns\":%llu,"
           "\"cpu_seconds\":%.9Lf,\"timebase_numer\":%u,\"timebase_denom\":%u,"
           "\"physical_footprint_bytes\":%llu,\"resident_bytes\":%llu,"
           "\"lifetime_peak_footprint_bytes\":%llu,\"interrupt_wakeups\":%llu,\"package_idle_wakeups\":%llu,"
           "\"disk_read_bytes\":%llu,\"disk_written_bytes\":%llu,\"threads\":%d}\n",
           pid, (unsigned long long)after.ri_proc_start_abstime,
           (unsigned long long)now.tv_sec * 1000000000ULL + (unsigned long long)now.tv_nsec,
           cpu_seconds, timebase.numer, timebase.denom,
           (unsigned long long)after.ri_phys_footprint, (unsigned long long)after.ri_resident_size,
           (unsigned long long)after.ri_lifetime_max_phys_footprint,
           (unsigned long long)after.ri_interrupt_wkups, (unsigned long long)after.ri_pkg_idle_wkups,
           (unsigned long long)after.ri_diskio_bytesread, (unsigned long long)after.ri_diskio_byteswritten,
           task.pti_threadnum);
    return 0;
}
