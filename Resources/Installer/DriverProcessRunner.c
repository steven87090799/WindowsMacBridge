// One installer job, one bounded pipe buffer. No resident process or runtime timer.
#include <errno.h>
#include <fcntl.h>
#include <poll.h>
#include <pwd.h>
#include <signal.h>
#include <spawn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <time.h>
#include <unistd.h>
#include <grp.h>

#ifndef WMB_MANAGER_PATH
#define WMB_MANAGER_PATH "/Applications/.Karabiner-VirtualHIDDevice-Manager.app/Contents/MacOS/Karabiner-VirtualHIDDevice-Manager"
#endif
#ifndef WMB_DRIVER_TIMEOUT
#define WMB_DRIVER_TIMEOUT 90
#endif
extern char **environ;
static double now(void) {
    struct timespec value;
    if (clock_gettime(CLOCK_MONOTONIC, &value)) return -1;
    return value.tv_sec + value.tv_nsec / 1e9;
}
static int operation(const char *value) {
    return !strcmp(value,"activate") || !strcmp(value,"forceActivate") || !strcmp(value,"deactivate");
}
int main(int argc, char **argv) {
    // launchctl enters the console user's bootstrap context while retaining root.
    // Drop credentials here, without sudo's separate PTY/process group or a shell.
    if (argc == 4 && !strcmp(argv[1],"--child")) {
        struct stat console; char *end = NULL;
        unsigned long uid = strtoul(argv[2], &end, 10);
        if (geteuid() != 0 || !end || *end || !uid || !operation(argv[3]) ||
            stat("/dev/console", &console) || uid != console.st_uid) return 77;
        struct passwd *user = getpwuid(console.st_uid);
        if (!user || initgroups(user->pw_name,user->pw_gid) || setgid(user->pw_gid) || setuid(console.st_uid)) return 77;
        execl(WMB_MANAGER_PATH,WMB_MANAGER_PATH,argv[3],(char *)NULL);
        return 127;
    }
    if (argc != 4 || strcmp(argv[1],WMB_MANAGER_PATH) || !operation(argv[2]) ||
        strncmp(argv[3],"/private/var/tmp/WindowsMacBridge-install.",strlen("/private/var/tmp/WindowsMacBridge-install.")) ||
        strlen(argv[3]) >= 4096) return 64;
    char directory[4096]; strcpy(directory,argv[3]);
    char *filename = strrchr(directory,'/');
    if (!filename || (strcmp(filename+1,"driver-activate.log") && strcmp(filename+1,"driver-restore.log"))) return 64;
    *filename++ = 0;
    int parent = open(directory,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    struct stat attributes;
    if (parent < 0 || fstat(parent,&attributes) || attributes.st_uid != geteuid() || (attributes.st_mode & 077)) return 73;
    int log = openat(parent,filename,O_WRONLY|O_CREAT|O_NOFOLLOW|O_CLOEXEC,0600);
    close(parent);
    if (log < 0 || fstat(log,&attributes) || !S_ISREG(attributes.st_mode) ||
        attributes.st_uid != geteuid() || attributes.st_nlink != 1 || (attributes.st_mode & 077) || ftruncate(log,0)) return 73;
    int channel[2];
    if (pipe(channel)) { close(log); return 71; }
    if (fcntl(channel[0],F_SETFL,O_NONBLOCK)) return 71;
    posix_spawn_file_actions_t files;
    posix_spawnattr_t attributes_spawn;
    if (posix_spawn_file_actions_init(&files) || posix_spawnattr_init(&attributes_spawn) ||
        posix_spawn_file_actions_adddup2(&files,channel[1],STDOUT_FILENO) ||
        posix_spawn_file_actions_adddup2(&files,channel[1],STDERR_FILENO) ||
        posix_spawn_file_actions_addclose(&files,channel[0]) ||
        posix_spawn_file_actions_addclose(&files,channel[1]) ||
        posix_spawnattr_setflags(&attributes_spawn,POSIX_SPAWN_SETPGROUP|POSIX_SPAWN_CLOEXEC_DEFAULT) ||
        posix_spawnattr_setpgroup(&attributes_spawn,0)) return 71;
    char *direct[] = {argv[1],argv[2],NULL};
    char console_uid[24]; struct stat console;
    char *as_user[] = {"/bin/launchctl","asuser",console_uid,argv[0],"--child",console_uid,argv[2],NULL};
    if (geteuid() == 0) {
        if (stat("/dev/console",&console) || !console.st_uid || argv[0][0] != '/') return 77;
        snprintf(console_uid,sizeof(console_uid),"%u",console.st_uid);
    }
    pid_t child;
    int error = posix_spawn(&child,geteuid() == 0 ? as_user[0] : direct[0],&files,&attributes_spawn,
                           geteuid() == 0 ? as_user : direct,environ);
    posix_spawn_file_actions_destroy(&files); posix_spawnattr_destroy(&attributes_spawn);
    close(channel[1]);
    if (error) { close(channel[0]); close(log); return 71; }
    double deadline = now() + WMB_DRIVER_TIMEOUT, stop_at = 0;
    int status = 0, done = 0, eof = 0, failure = 0, killed = 0;
    size_t written = 0; char buffer[4096];
    while (!done || !eof) {
        struct pollfd descriptor = {channel[0],POLLIN|POLLHUP,0};
        if (poll(eof ? NULL : &descriptor,eof ? 0 : 1,100) < 0 && errno != EINTR) failure = 74;
        ssize_t count;
        while (!eof && (count = read(channel[0],buffer,sizeof(buffer))) > 0) {
            if ((size_t)count > 65536-written) { failure = 125; break; }
            size_t offset = 0;
            while (offset < (size_t)count) {
                ssize_t result = write(log,buffer+offset,(size_t)count-offset);
                if (result < 0 && errno == EINTR) continue;
                if (result <= 0) { failure = 74; break; }
                offset += (size_t)result;
            }
            written += offset;
            if (failure) break;
        }
        if (!eof && count == 0) eof = 1;
        double time = now();
        if (time < 0 || time >= deadline) { if (!failure) failure = 124; }
        if (failure && !stop_at) { kill(-child,SIGTERM); stop_at = time; }
        if (stop_at && time-stop_at >= 1 && !killed) { kill(-child,SIGKILL); killed = 1; }
        // A zombie leader reserves its PID until the group has been terminated.
        // Never leave a manager grandchild that can activate after rollback.
        if (!done) {
            siginfo_t info; memset(&info,0,sizeof(info));
            int result = waitid(P_PID,child,&info,WEXITED|WNOHANG|WNOWAIT);
            if (!result && info.si_pid == child) done = 1;
            else if (result < 0 && errno != EINTR) { failure = 71; done = 1; }
        }
        if (stop_at && time-stop_at >= 3) { failure = failure ? failure : 124; break; }
    }
    kill(-child,SIGKILL);
    if (waitpid(child,&status,WNOHANG) != child && !failure) failure = 71;
    close(channel[0]); fsync(log); close(log);
    if (failure) return failure;
    return WIFEXITED(status) ? WEXITSTATUS(status) : 128+WTERMSIG(status);
}
