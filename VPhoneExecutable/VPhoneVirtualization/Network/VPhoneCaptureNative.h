#pragma once
#include <stddef.h>
#include <stdint.h>
typedef struct {
    uint32_t seconds, microseconds, capturedLength, originalLength;
    size_t dataOffset;
} VPhoneBPFRecord;
int vp_capture_open(const char *interface, uint32_t *bufferLength, uint32_t *linkType, char *error, size_t errorLength);
int vp_capture_next(const uint8_t *bytes, size_t length, size_t *offset, VPhoneBPFRecord *record);
int vp_capture_stats(int fd, uint32_t *received, uint32_t *dropped);
