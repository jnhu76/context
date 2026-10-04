#pragma once

// R1 reference layer: raw upstream fcontext primitives used directly.
//
// Only make_fcontext and jump_fcontext are used. ontop_fcontext is available
// upstream but is deliberately not part of this harness (see docs/P0-BASELINE.md).
//
// The C symbols are declared here so this header depends on the two assembly
// translation units only, with no Boost.Context C++ headers.

#include <cstddef>
#include <cstdlib>

namespace p0 {

extern "C" {

using raw_fcontext_t = void*;

struct raw_transfer_t {
    raw_fcontext_t fctx;
    void* data;
};

raw_transfer_t jump_fcontext(raw_fcontext_t to, void* vp);
raw_fcontext_t make_fcontext(void* sp, std::size_t size, void (*fn)(raw_transfer_t));

} // extern "C"

struct RawFcontextResult {
    long rounds;             // requested round-trips
    long child_runs;         // times the child body executed
    long final_local_state;  // child-local variable after the last resume
    bool terminated;         // the child transferred back with the null sentinel
};

namespace detail {

struct raw_state {
    long rounds;
    long child_runs;
    long final_local_state;
};

// C-03: suspend from inside a nested call. Its frame must survive the switch.
inline raw_transfer_t raw_suspend(raw_transfer_t t, raw_state* state) {
    return jump_fcontext(t.fctx, state);
}

inline void raw_child_entry(raw_transfer_t t) {
    raw_state* state = static_cast<raw_state*>(t.data);

    // C-02: an ordinary local variable that must survive suspend/resume.
    long local_state = 0;
    for (long i = 0; i < state->rounds; ++i) {
        ++local_state;
        ++state->child_runs;
        // Yield back to the resumer through a nested call.
        t = raw_suspend(t, state);
    }
    state->final_local_state = local_state;

    // A raw fcontext entry function must not return: transfer back with a null
    // sentinel so the resumer can observe normal termination (C-04).
    jump_fcontext(t.fctx, nullptr);
}

} // namespace detail

inline RawFcontextResult run_raw_fcontext_pingpong(long rounds) {
    constexpr std::size_t kStackSize = 256 * 1024;

    // make_fcontext aligns the stack pointer itself; malloc gives a suitably
    // aligned base and the top of the stack is base + size.
    void* stack = std::malloc(kStackSize);
    raw_fcontext_t child =
        make_fcontext(static_cast<char*>(stack) + kStackSize, kStackSize,
                      detail::raw_child_entry);

    detail::raw_state state{rounds, 0, -1};

    raw_transfer_t t = jump_fcontext(child, &state); // enter the child
    while (t.data != nullptr) {
        // Resume until the child terminates (null sentinel).
        t = jump_fcontext(t.fctx, &state);
    }

    std::free(stack);

    return RawFcontextResult{rounds, state.child_runs, state.final_local_state, true};
}

} // namespace p0
