#pragma once
#include <stdint.h>

typedef struct {
    uint64_t value;
} aileron_atomic_u64;

static inline void aileron_atomic_init(aileron_atomic_u64 *a, uint64_t v) {
    __atomic_store_n(&a->value, v, __ATOMIC_RELAXED);
}

static inline uint64_t aileron_atomic_load_relaxed(const aileron_atomic_u64 *a) {
    return __atomic_load_n(&a->value, __ATOMIC_RELAXED);
}

static inline uint64_t aileron_atomic_load_acquire(const aileron_atomic_u64 *a) {
    return __atomic_load_n(&a->value, __ATOMIC_ACQUIRE);
}

static inline void aileron_atomic_store_release(aileron_atomic_u64 *a, uint64_t v) {
    __atomic_store_n(&a->value, v, __ATOMIC_RELEASE);
}

static inline uint64_t aileron_atomic_fetch_add_relaxed(aileron_atomic_u64 *a, uint64_t delta) {
    return __atomic_fetch_add(&a->value, delta, __ATOMIC_RELAXED);
}

static inline uint64_t aileron_atomic_exchange_relaxed(aileron_atomic_u64 *a, uint64_t v) {
    return __atomic_exchange_n(&a->value, v, __ATOMIC_RELAXED);
}
