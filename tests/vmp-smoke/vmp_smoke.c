#include <stdint.h>

#define NDKP_VMP __attribute__((annotate("ndkp.vmp")))
#define EXPORTED __attribute__((noinline, used, visibility("default")))

NDKP_VMP EXPORTED
uint64_t vmp_annotated_mix(uint64_t value) {
    uint64_t state = value ^ UINT64_C(0x9e3779b97f4a7c15);
    for (unsigned i = 0; i < 7; ++i) {
        state ^= state >> 12;
        state ^= state << 25;
        state ^= state >> 27;
        state *= UINT64_C(0x2545f4914f6cdd1d);
    }
    return state;
}

EXPORTED
uint32_t vmp_named_mix(uint32_t value) {
    value ^= value << 13;
    value ^= value >> 17;
    value ^= value << 5;
    return value + UINT32_C(0x6d2b79f5);
}

EXPORTED
uint32_t native_control(uint32_t value) {
    return (value * 33u) ^ UINT32_C(0xa5a5a5a5);
}

typedef uint32_t uint32x4 __attribute__((vector_size(16)));

NDKP_VMP EXPORTED
uint32x4 unsupported_vector(uint32x4 value) {
    const uint32x4 mask = {1u, 3u, 5u, 7u};
    return value ^ mask;
}
