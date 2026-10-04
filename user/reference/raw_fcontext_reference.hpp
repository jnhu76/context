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
    long nested_resumes;     // nested helper continued after each suspension
    bool body_returned;      // user body returned normally to the trampoline
    bool terminal_handoff;   // trampoline transferred away and was not resumed
};

namespace detail {

struct raw_state {
    long rounds;
    long child_runs;
    long final_local_state;
    long nested_resumes;
    bool body_returned;
};

#if defined(__GNUC__) || defined(__clang__)
#  define P0_NOINLINE __attribute__((noinline))
#else
#  define P0_NOINLINE
#endif

// C-03 needs a real call frame, not merely source-level nesting. noinline keeps
// this helper distinct, and the observable increment after resume prevents the
// call from being reduced to a tail jump.
P0_NOINLINE inline raw_transfer_t raw_suspend(raw_transfer_t t, raw_state* state) {
    raw_transfer_t resumed = jump_fcontext(t.fctx, state);
    ++state->nested_resumes;
    return resumed;
}

// Keep the user body distinct from the raw fcontext trampoline. The body may
// return normally; the trampoline itself must not return because upstream
// make_fcontext's x86-64 SysV return path exits the process.
P0_NOINLINE inline raw_transfer_t raw_child_body(raw_transfer_t t, raw_state* state) {
    long local_state = 0;
    for (long i = 0; i < state->rounds; ++i) {
        ++local_state;
        ++state->child_runs;
        t = raw_suspend(t, state);
    }
    state->final_local_state = local_state;
    return t;
}

#undef P0_NOINLINE

inline void raw_child_entry(raw_transfer_t t) {
    raw_state* state = static_cast<raw_state*>(t.data);

    t = raw_child_body(t, state);
    state->body_returned = true;

    // Raw fcontext entry functions must not return. Completion is therefore an
    // explicit terminal handoff: transfer to the resumer with a null sentinel.
    // If this dead context is ever resumed, abort instead of continuing on a
    // backing stack whose owner is allowed to reclaim it after the handoff.
    jump_fcontext(t.fctx, nullptr);
    std::abort();
}

} // namespace detail

inline RawFcontextResult run_raw_fcontext_pingpong(long rounds) {
    constexpr std::size_t kStackSize = 256 * 1024;

    // make_fcontext aligns the stack pointer itself; malloc gives a suitably
    // aligned base and the top of the stack is base + size.
    void* stack = std::malloc(kStackSize);
    if (stack == nullptr) {
        std::abort();
    }

    raw_fcontext_t child =
        make_fcontext(static_cast<char*>(stack) + kStackSize, kStackSize,
                      detail::raw_child_entry);

    detail::raw_state state{rounds, 0, -1, 0, false};

    raw_transfer_t t = jump_fcontext(child, &state); // enter the child
    while (t.data != nullptr) {
        t = jump_fcontext(t.fctx, &state);
    }

    // The null sentinel is the terminal handoff. The child is now dead by
    // contract and is never resumed; only after observing that handoff do we
    // reclaim its backing stack.
    const bool terminal_handoff = true;
    std::free(stack);

    return RawFcontextResult{rounds,
                             state.child_runs,
                             state.final_local_state,
                             state.nested_resumes,
                             state.body_returned,
                             terminal_handoff};
}

} // namespace p0
