// P0 benchmark: context-switch ping-pong against the Boost.Context reference.
//
// Release build only. This establishes a reproducible baseline. It does NOT
// prove optimization and deliberately reports no p99, throughput regime,
// million-fiber, multi-worker, or kernel-scheduling numbers.

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <string>

#include <sys/utsname.h>

#include <boost/context/fiber.hpp>

#ifndef P0_BOOST_CONTEXT_SHA
#define P0_BOOST_CONTEXT_SHA "unknown"
#endif
#ifndef P0_XMAKE_VERSION
#define P0_XMAKE_VERSION "unknown"
#endif
#ifndef P0_BUILD_MODE
#define P0_BUILD_MODE "unknown"
#endif
#ifndef P0_TARGET_ABI
#define P0_TARGET_ABI "unknown"
#endif
#ifndef P0_OPT_FLAGS
#define P0_OPT_FLAGS "unknown"
#endif

#if defined(__clang__)
#  define P0_COMPILER "clang"
#elif defined(__GNUC__)
#  define P0_COMPILER "gcc"
#else
#  define P0_COMPILER "unknown"
#endif

namespace {

std::string cpu_model() {
    std::FILE* f = std::fopen("/proc/cpuinfo", "r");
    if (f == nullptr) {
        return "unknown";
    }
    char line[512];
    std::string model = "unknown";
    while (std::fgets(line, sizeof(line), f) != nullptr) {
        if (std::strncmp(line, "model name", 10) == 0) {
            const char* colon = std::strchr(line, ':');
            if (colon != nullptr) {
                const char* p = colon + 1;
                while (*p == ' ' || *p == '\t') {
                    ++p;
                }
                model = p;
                while (!model.empty() && (model.back() == '\n' || model.back() == '\r' ||
                                          model.back() == ' ')) {
                    model.pop_back();
                }
            }
            break;
        }
    }
    std::fclose(f);
    return model;
}

// One deterministic ping-pong round-trip = main -> child -> main.
long pingpong(long rounds) {
    namespace ctx = boost::context;

    long runs = 0;
    ctx::fiber child{[&runs, rounds](ctx::fiber&& main) -> ctx::fiber {
        ctx::fiber caller = std::move(main);
        for (long i = 0; i < rounds; ++i) {
            ++runs;
            caller = std::move(caller).resume();
        }
        return caller; // implicit move; fiber is move-only
    }};

    for (long i = 0; i < rounds; ++i) {
        child = std::move(child).resume();
    }
    child = std::move(child).resume(); // normal termination
    return runs;
}

} // namespace

int main(int argc, char** argv) {
    long rounds = 200000;
    if (argc > 1) {
        rounds = std::atol(argv[1]);
        if (rounds <= 0) {
            std::fprintf(stderr, "usage: %s [positive-rounds]\n", argv[0]);
            return 2;
        }
    }

    const long warmup_rounds = rounds < 20000 ? rounds : 20000;
    volatile long sink = pingpong(warmup_rounds);
    (void)sink;

    const auto t0 = std::chrono::steady_clock::now();
    const long runs = pingpong(rounds);
    const auto t1 = std::chrono::steady_clock::now();

    const double elapsed_ns = std::chrono::duration<double, std::nano>(t1 - t0).count();
    const double per_roundtrip_ns = elapsed_ns / static_cast<double>(rounds);
    const double per_transfer_ns = elapsed_ns / static_cast<double>(2 * rounds);

    struct utsname u;
    const char* os_name = "unknown";
    const char* kernel = "unknown";
    const char* arch = "unknown";
    if (uname(&u) == 0) {
        os_name = u.sysname;
        kernel = u.release;
        arch = u.machine;
    }
    const std::string cpu = cpu_model();

    std::printf("P0 context-switch benchmark (ping-pong, boost::context::fiber)\n");
    std::printf("  os: %s\n", os_name);
    std::printf("  kernel: %s\n", kernel);
    std::printf("  arch: %s\n", arch);
    std::printf("  cpu: %s\n", cpu.c_str());
    std::printf("  compiler: %s\n", P0_COMPILER);
    std::printf("  compiler_version: %s\n", __VERSION__);
    std::printf("  xmake: %s\n", P0_XMAKE_VERSION);
    std::printf("  build_mode: %s\n", P0_BUILD_MODE);
    std::printf("  target_abi: %s\n", P0_TARGET_ABI);
    std::printf("  boost_context_sha: %s\n", P0_BOOST_CONTEXT_SHA);
    std::printf("  optimization_flags: %s\n", P0_OPT_FLAGS);
    std::printf("  warmup_rounds: %ld\n", warmup_rounds);
    std::printf("  rounds: %ld\n", rounds);
    std::printf("  transfers: %ld\n", 2 * rounds);
    std::printf("  elapsed_ns: %.0f\n", elapsed_ns);
    std::printf("  ns_per_roundtrip: %.3f\n", per_roundtrip_ns);
    std::printf("  ns_per_transfer: %.3f\n", per_transfer_ns);

    if (runs != rounds) {
        std::fprintf(stderr, "benchmark error: child ran %ld times, expected %ld\n", runs, rounds);
        return 1;
    }
    return 0;
}
