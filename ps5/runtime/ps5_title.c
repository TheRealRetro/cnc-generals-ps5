/*
 * C&C Generals PS5 - title lifecycle: logging and the exit through the shell.
 * SPDX-License-Identifier: GPL-3.0-or-later
 *
 * The console calls are exports of its system modules that no SDK header
 * declares; their use follows PS5_VulkanTemplate and PS5_vkQuake, which run
 * them on hardware.
 */
#include "ps5_title.h"

#include <ps5platform/klog.h>

#include <errno.h>
#include <fcntl.h>
#include <pthread.h>
#include <signal.h>
#include <stdarg.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <ucontext.h>
#include <unistd.h>

int sceSystemServiceLoadExec(const char *path, const char *const *argv);
int sceKernelUsleep(uint32_t microseconds);

static int log_fd = -1;
static void install_crash_handler(void);

void ps5_title_init(const char *name)
{
    static char prefix[64];
    snprintf(prefix, sizeof(prefix), "[%s] ", name);
    const int captured = ps5_klog_capture_stderr(prefix);
    install_crash_handler();
    ps5_say("starts (stderr to klog: %s)", captured == 0 ? "yes" : "no");
}

/* A crash, in the log: the signal, the faulting instruction and the return
 * addresses of the calls that led to it, read from the frame pointers (the
 * title is built with them). ps5_title_init's address is printed as the
 * anchor that relates them to the linked ELF, from which
 * scripts/symbolize-crash.sh names them. Written straight to the log file and klog, since stderr's
 * thread may not run again. The handler then lets the fault happen again
 * with the default action, so the console still sees the title crash. */
static void crash_line(const char *text, int length)
{
    if (length <= 0)
        return;
    if (log_fd >= 0)
        (void)write(log_fd, text, (size_t)length);
    sceKernelDebugOutText(0, text);
}

static void crash_handler(int signal_number, siginfo_t *info, void *context)
{
    const ucontext_t *const uc = context;
    char line[192];
    crash_line(line, snprintf(line, sizeof(line),
        "CRASH: signal %d (code %d) at address %p, pc %p, anchor %p\n", signal_number,
        info ? info->si_code : 0, info ? info->si_addr : NULL, (void *)uc->uc_mcontext.mc_rip,
        (void *)&ps5_title_init));
    uintptr_t frame_pointer = (uintptr_t)uc->uc_mcontext.mc_rbp;
    for (int depth = 0; depth < 48 && frame_pointer != 0 && (frame_pointer & 7) == 0; depth++) {
        const uintptr_t *const frame = (const uintptr_t *)frame_pointer;
        crash_line(line, snprintf(line, sizeof(line), "CRASH:   #%d %p\n", depth, (void *)frame[1]));
        if (frame[0] <= frame_pointer)
            break;
        frame_pointer = frame[0];
    }
}

static void install_crash_handler(void)
{
    /* Its own stack, so a stack overflow is reported too. */
    static uint8_t crash_stack[64 * 1024] __attribute__((aligned(16)));
    stack_t alternate;
    memset(&alternate, 0, sizeof(alternate));
    alternate.ss_sp = crash_stack;
    alternate.ss_size = sizeof(crash_stack);
    (void)sigaltstack(&alternate, NULL);

    struct sigaction action;
    memset(&action, 0, sizeof(action));
    action.sa_sigaction = crash_handler;
    action.sa_flags = SA_SIGINFO | SA_ONSTACK | SA_RESETHAND;
    sigemptyset(&action.sa_mask);
    const int signals[] = { SIGSEGV, SIGBUS, SIGILL, SIGFPE, SIGABRT };
    for (size_t i = 0; i < sizeof(signals) / sizeof(signals[0]); i++)
        (void)sigaction(signals[i], &action, NULL);
}

/* The log file: stderr becomes a pipe in front of the klog stream, and a
 * thread copies what arrives into both. Each chunk is written straight to the
 * file, so the log survives the title being closed or crashing. A title may
 * not dup2, so the stream stderr is replaced, as ps5_klog_capture_stderr does. */
static int log_read_end = -1;
static FILE *log_klog;

/* A run that logs every frame stops filling the file here; klog still gets it all. */
#define LOG_FILE_LIMIT (32u << 20)

static void *log_reader(void *unused)
{
    (void)unused;
    char chunk[1024];
    size_t logged = 0;
    for (;;) {
        const ssize_t got = read(log_read_end, chunk, sizeof(chunk));
        if (got < 0 && errno == EINTR)
            continue;
        if (got <= 0)
            break;
        if (logged < LOG_FILE_LIMIT) {
            (void)write(log_fd, chunk, (size_t)got);
            logged += (size_t)got;
            if (logged >= LOG_FILE_LIMIT) {
                static const char full[] = "\n[log file full: the rest went to klog only]\n";
                (void)write(log_fd, full, sizeof(full) - 1);
            }
        }
        fwrite(chunk, 1, (size_t)got, log_klog);
        fflush(log_klog);
    }
    return NULL;
}

int ps5_title_log_file(const char *path)
{
    if (log_fd >= 0)
        return 0;
    const int fd = open(path, O_WRONLY | O_CREAT | O_TRUNC, 0666);
    if (fd < 0)
        return -1;
    int ends[2];
    if (pipe(ends) != 0) {
        close(fd);
        return -1;
    }
    FILE *const stream = fdopen(ends[1], "w");
    if (stream == NULL) {
        close(ends[0]);
        close(ends[1]);
        close(fd);
        return -1;
    }
    setvbuf(stream, NULL, _IOLBF, 0);
    log_fd = fd;
    log_read_end = ends[0];
    fflush(stderr);
    log_klog = stderr;
    pthread_t thread;
    const int created = pthread_create(&thread, NULL, log_reader, NULL);
    if (created != 0) {
        fclose(stream);
        close(ends[0]);
        close(fd);
        log_fd = log_read_end = -1;
        errno = created;
        return -1;
    }
    pthread_detach(thread);
    stderr = stream;
    return 0;
}

int sceUserServiceInitialize(const void *params);
int sceUserServiceGetInitialUser(int32_t *user_id);
int sceUserServiceGetUserName(int32_t user_id, char *name, size_t size);

int ps5_title_user_name(char *name, size_t size)
{
    if (name == NULL || size == 0)
        return -1;
    name[0] = '\0';
    /* Already initialized (SDL's controller driver does it first) is fine. */
    (void)sceUserServiceInitialize(NULL);
    int32_t user = -1;
    char raw[64];
    memset(raw, 0, sizeof(raw));
    const int got_user = sceUserServiceGetInitialUser(&user);
    const int got_name = got_user < 0 || user < 0 ? -1 : sceUserServiceGetUserName(user, raw, sizeof(raw) - 1);
    if (got_name < 0) {
        ps5_say("user name: initial user %#x (%d), name %#x", (unsigned)got_user, (int)user, (unsigned)got_name);
        return -1;
    }
    size_t length = 0;
    for (const char *c = raw; *c != '\0' && length + 1 < size; c++) {
        if (*c >= 0x20 && *c < 0x7f)
            name[length++] = *c;
    }
    name[length] = '\0';
    return length > 0 ? 0 : -1;
}

/* The request libkernel's sceKernelSendNotificationRequest takes: the text
 * at byte 45 (the payload SDK's samples/hello_world and notify_debug). */
typedef struct {
    char reserved[45];
    char message[3075];
} ps5_notify_request;

int sceKernelSendNotificationRequest(int device, ps5_notify_request *request, size_t size, int blocking);

int ps5_title_notify(const char *message)
{
    ps5_say("notify: %s", message);
    ps5_notify_request request;
    memset(&request, 0, sizeof(request));
    snprintf(request.message, sizeof(request.message), "%s", message);
    const int result = sceKernelSendNotificationRequest(0, &request, sizeof(request), 0);
    if (result < 0)
        ps5_say("notify: sceKernelSendNotificationRequest %#x", (unsigned)result);
    return result;
}

void ps5_say(const char *format, ...)
{
    va_list args;
    va_start(args, format);
    vfprintf(stderr, format, args);
    va_end(args);
    fputc('\n', stderr);
    fflush(stderr);
}

void ps5_title_exit(int status)
{
    ps5_say("ends: status %d", status);
    fflush(NULL);
    (void)sceSystemServiceLoadExec("exit", NULL);
    /* The shell closes the title asynchronously. */
    for (;;)
        sceKernelUsleep(100000);
}

/* The CRT calls this when main returns (PS5_Vulkan's app_crt.cpp). */
void catchReturnFromMain(int status)
{
    ps5_title_exit(status);
}
