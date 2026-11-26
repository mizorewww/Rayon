//
//  rayon_pty.h
//  RayonPTY
//
//  Starts a process that owns a pseudo-terminal as its controlling terminal.
//

#ifndef RAYON_PTY_H
#define RAYON_PTY_H

#include <sys/types.h>

/// Starts `path` with `argv` and `envp` in `directory`, as the leader of a
/// new session whose controlling terminal is `terminal` (a slave's path),
/// on standard input, output and error. Every other descriptor is closed and
/// every signal is at its default, unblocked. Returns the pid, or -1 with
/// errno set, also when `path` could not be executed.
pid_t rayon_pty_spawn(
    const char *path,
    char *const argv[],
    char *const envp[],
    const char *terminal,
    const char *directory
);

#endif
