#include "VPhoneCaptureNative.h"
#include <errno.h>
#include <fcntl.h>
#include <net/if.h>
#include <stdio.h>
#include <string.h>
#include <sys/ioctl.h>
#include <sys/ioccom.h>
#include <unistd.h>
#include <TargetConditionals.h>
#if TARGET_OS_OSX
#include <net/bpf.h>
#else
// iOS omits net/bpf.h from its SDK. This is the ioctl/record ABI declared
// by XNU's net/bpf.h (timeval32 on LP64), not instruction patch logic.
struct bpf_hdr {
    struct { int32_t tv_sec, tv_usec; } bh_tstamp;
    uint32_t bh_caplen, bh_datalen;
    uint16_t bh_hdrlen;
};
struct bpf_stat { unsigned bs_recv, bs_drop; };
#define BIOCGBLEN _IOR('B', 102, unsigned)
#define BIOCGDLT _IOR('B', 106, unsigned)
#define BIOCSETIF _IOW('B', 108, struct ifreq)
#define BIOCGSTATS _IOR('B', 111, struct bpf_stat)
#define BIOCIMMEDIATE _IOW('B', 112, unsigned)
#endif

int vp_capture_open(const char *interface, uint32_t *bufferLength, uint32_t *linkType, char *error, size_t errorLength) {
    int fd = -1;
    for (int i = 0; i < 256; i++) {
        char path[32]; snprintf(path, sizeof(path), "/dev/bpf%d", i);
        fd = open(path, O_RDONLY | O_NONBLOCK | O_CLOEXEC);
        if (fd >= 0 || errno != EBUSY) break;
    }
    if (fd < 0) { snprintf(error, errorLength, "Cannot open guest BPF device: %s", strerror(errno)); return -1; }
    struct ifreq request = {0};
    strlcpy(request.ifr_name, interface, sizeof(request.ifr_name));
    unsigned immediate = 1;
    if (ioctl(fd, BIOCSETIF, &request) < 0 || ioctl(fd, BIOCIMMEDIATE, &immediate) < 0 ||
        ioctl(fd, BIOCGBLEN, bufferLength) < 0 || ioctl(fd, BIOCGDLT, linkType) < 0 ||
        *bufferLength < 64 || *bufferLength > 2 * 1024 * 1024) {
        snprintf(error, errorLength, "BPF setup failed: %s", strerror(errno)); close(fd); return -1;
    }
    // There is deliberately no promiscuous mode or packet injection surface.
    return fd;
}

int vp_capture_next(const uint8_t *bytes, size_t length, size_t *offset, VPhoneBPFRecord *record) {
    if (*offset == length) return 0;
    const size_t minimum = offsetof(struct bpf_hdr, bh_hdrlen) + sizeof(uint16_t);
    if (*offset > length || length - *offset < minimum) return -1;
    struct bpf_hdr header = {0};
    size_t remaining = length - *offset;
    memcpy(&header, bytes + *offset, remaining < sizeof(header) ? remaining : sizeof(header));
    if (header.bh_hdrlen < minimum || header.bh_hdrlen > remaining || header.bh_caplen > remaining - header.bh_hdrlen ||
        header.bh_caplen > header.bh_datalen || header.bh_tstamp.tv_usec < 0 || header.bh_tstamp.tv_usec >= 1000000) return -1;
    record->seconds = (uint32_t)header.bh_tstamp.tv_sec;
    record->microseconds = (uint32_t)header.bh_tstamp.tv_usec;
    record->capturedLength = header.bh_caplen; record->originalLength = header.bh_datalen;
    record->dataOffset = *offset + header.bh_hdrlen;
    size_t body = header.bh_hdrlen + header.bh_caplen;
    size_t aligned = (body + 3) & ~(size_t)3;
    *offset += aligned <= remaining ? aligned : body;
    return 1;
}

int vp_capture_stats(int fd, uint32_t *received, uint32_t *dropped) {
    struct bpf_stat stats;
    if (ioctl(fd, BIOCGSTATS, &stats) < 0) return -1;
    *received = stats.bs_recv; *dropped = stats.bs_drop; return 0;
}
