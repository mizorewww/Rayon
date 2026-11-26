//
//  rayon_pty.c
//  RayonPTY
//
//  posix_spawn cannot give a child a controlling terminal: XNU runs the file
//  actions before POSIX_SPAWN_SETSID, so the terminal is opened outside the
//  new session, and there is no TIOCSCTTY action. Without one, the terminal
//  sends no signals (Ctrl-C, Ctrl-Z) and the shell gets no job control.
//  Hence fork, in C: after fork in a multithreaded process the child may
//  only make async-signal-safe calls until it execs, and everything below
//  is one; the parent prepares all memory beforehand.
//

#include "rayon_pty.h"

#include <TargetConditionals.h>

#if TARGET_OS_OSX

#include <errno.h>
#include <pthread.h>
#include <fcntl.h>
#include <signal.h>
#include <sys/ioctl.h>
#include <sys/wait.h>
#include <unistd.h>

pid_t rayon_pty_spawn(
    const char *path,
    char *const argv[],
    char *const envp[],
    const char *terminal,
    const char *directory
) {
    // Every signal stays blocked from before fork until the child has put
    // each back to its default: a handler of this process run in the child
    // would touch memory another thread of this process may have held.
    sigset_t all, previous;
    sigfillset(&all);
    pthread_sigmask(SIG_SETMASK, &all, &previous);

    // The child reports a failed exec through this pipe; it closes on a
    // successful one. Darwin has no pipe2, so close-on-exec is set right
    // after: a process another thread forks in between inherits the ends,
    // but only until it execs.
    int report[2];
    if (pipe(report) != 0) {
        int saved = errno;
        pthread_sigmask(SIG_SETMASK, &previous, NULL);
        errno = saved;
        return -1;
    }
    fcntl(report[0], F_SETFD, FD_CLOEXEC);
    fcntl(report[1], F_SETFD, FD_CLOEXEC);
    int highest = getdtablesize();

    pid_t pid = fork();
    if (pid != 0) {
        int saved = errno;
        pthread_sigmask(SIG_SETMASK, &previous, NULL);
        errno = saved;
    }
    if (pid < 0) {
        int saved = errno;
        close(report[0]);
        close(report[1]);
        errno = saved;
        return -1;
    }
    if (pid == 0) {
        struct sigaction action = { .sa_handler = SIG_DFL };
        sigemptyset(&action.sa_mask);
        for (int signal = 1; signal < NSIG; signal++) sigaction(signal, &action, NULL);
        int fd = -1;
        if (setsid() < 0) goto fail;
        // A session leader's first terminal open makes it the controlling
        // one; TIOCSCTTY says so explicitly.
        fd = open(terminal, O_RDWR);
        if (fd < 0 || ioctl(fd, TIOCSCTTY, 0) < 0) goto fail;
        if (dup2(fd, STDIN_FILENO) < 0 || dup2(fd, STDOUT_FILENO) < 0 || dup2(fd, STDERR_FILENO) < 0) goto fail;
        for (int other = STDERR_FILENO + 1; other < highest; other++) {
            if (other != report[1]) close(other);
        }
        if (chdir(directory) != 0) goto fail;
        sigset_t none;
        sigemptyset(&none);
        sigprocmask(SIG_SETMASK, &none, NULL);
        execve(path, argv, envp);
    fail:;
        int code = errno;
        (void)write(report[1], &code, sizeof code);
        _exit(127);
    }

    close(report[1]);
    int code = 0;
    ssize_t got;
    do {
        got = read(report[0], &code, sizeof code);
    } while (got < 0 && errno == EINTR);
    close(report[0]);
    if (got == sizeof code) {
        int status;
        while (waitpid(pid, &status, 0) < 0 && errno == EINTR) {}
        errno = code;
        return -1;
    }
    return pid;
}

#endif
