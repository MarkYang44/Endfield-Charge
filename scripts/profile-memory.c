#include <libproc.h>
#include <sys/resource.h>
#include <sys/proc_info.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <time.h>
#include <mach/mach_time.h>

// Sum the resident and its direct UI children. This is physical footprint, not RSS.
int main(int argc, char **argv) {
    if (argc != 3) return 2;
    int root = atoi(argv[1]), samples = atoi(argv[2]);
    if (root <= 0 || samples <= 0) return 2;
    mach_timebase_info_data_t timebase = {0};
    if (mach_timebase_info(&timebase) != KERN_SUCCESS || timebase.denom == 0) return 1;
    for (int sample = 0; sample < samples; sample++) {
        int pids[64] = {root};
        int bytes = proc_listpids(PROC_PPID_ONLY, root, pids + 1, sizeof(pids) - sizeof(int));
        if (bytes < 0 || bytes > (int)(sizeof(pids) - sizeof(int))) {
            fputs("Child enumeration failed or exceeded the probe limit\n", stderr);
            return 1;
        }
        int count = bytes > 0 ? 1 + bytes / (int)sizeof(int) : 1;
        unsigned long long total = 0;
        int alive = 0;
        printf("{\"members\":[");
        for (int index = 0; index < count; index++) {
            struct rusage_info_v4 usage = {0};
            if (pids[index] <= 0) continue;
            if (proc_pid_rusage(pids[index], RUSAGE_INFO_V4, (rusage_info_t *)&usage)) {
                fprintf(stderr, "Could not measure PID %d\n", pids[index]);
                return 1;
            }
            if (alive++) printf(",");
            printf("{\"pid\":%d,\"footprint_bytes\":%llu,\"cpu_nanoseconds\":%llu}",
                pids[index], usage.ri_phys_footprint, (unsigned long long)(
                    ((long double)usage.ri_user_time + usage.ri_system_time) * timebase.numer / timebase.denom));
            total += usage.ri_phys_footprint;
        }
        struct timespec time = {0};
        if (clock_gettime(CLOCK_MONOTONIC, &time)) return 1;
        printf("],\"footprint_bytes\":%llu,\"monotonic_seconds\":%.9f}\n", total,
            (double)time.tv_sec + (double)time.tv_nsec / 1e9);
        fflush(stdout);
        if (!alive) return 1;
        if (sample + 1 < samples) usleep(200000);
    }
    return 0;
}
