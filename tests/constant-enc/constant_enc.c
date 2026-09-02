#include <stdint.h>

__attribute__((noinline, used, visibility("default")))
uint64_t encrypted_integer_mix(uint64_t value) {
    value += UINT64_C(0x13579bdf2468ace0);
    value ^= UINT64_C(0xfedcba9876543210);
    return value * UINT64_C(0x9e3779b97f4a7c15);
}

__attribute__((noinline, used, visibility("default")))
double encrypted_float_mix(double value) {
    return value * 3.141592653589793 + 0.125;
}
