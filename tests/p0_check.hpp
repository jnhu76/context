#pragma once

// P0 check helper: deliberately tiny, no external test framework.
// A failed check is recorded and reported through the process exit code.

#include <cstdio>

namespace p0 {

inline int& failure_count() {
    static int count = 0;
    return count;
}

inline void check(bool condition, const char* expression, const char* file, int line) {
    if (!condition) {
        ++failure_count();
        std::fprintf(stderr, "FAIL %s:%d: %s\n", file, line, expression);
    }
}

inline int report(const char* suite) {
    if (failure_count() == 0) {
        std::printf("%s: PASS\n", suite);
        return 0;
    }
    std::fprintf(stderr, "%s: FAIL (%d failed checks)\n", suite, failure_count());
    return 1;
}

} // namespace p0

#define P0_CHECK(condition) ::p0::check((condition), #condition, __FILE__, __LINE__)
