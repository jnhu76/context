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

// C-04 evidence: what the resume loop actually observed on the transfer that
// ended the ping-pong. The terminal handoff is reported from this observation
// rather than restated as a constant, so the check can fail.
struct RawHandoffObservation {
    bool null_sentinel;   // recorded from the transfer that ended the loop; as a
                          // conjunct it restates the loop condition, so it is
                          // evidence, not an independent observation
    raw_fcontext_t from;  // context that performed the terminal transfer: evidence
    bool body_returned;   // the independent, load-bearing observation
};

struct RawFcontextResult {
    long rounds;             // requested round-trips
    long child_runs;         // times the child body executed
    long final_local_state;  // child-local variable after the last resume
    long nested_resumes;     // nested helper continued after each suspension
    bool body_returned;      // user body returned normally to the trampoline
    bool terminal_handoff;   // C-04: derived from handoff, not a constant
    RawHandoffObservation handoff; // observation terminal_handoff was derived from
};

namespace detail {

struct raw_state {
    long rounds;
    long child_runs;
    long final_local_state;
    long nested_resumes;
    bool body_returned;
};

// C-04 classification. The load-bearing conjunct is body_returned: the user body
// having returned is an independent observation of the execution. null_sentinel
// is recorded evidence rather than an independent one -- it restates the loop
// exit, so a mutation replacing it with a constant is undetectable and also
// harmless: the fallibility of the check rests on body_returned, which
// raw_child_entry_without_body falsifies through the production loop in
// tests/raw_fcontext. The previous 'const bool terminal_handoff = true;' had no
// such conjunct at all, which made P0_CHECK(r.terminal_handoff) unable to fail.
inline bool terminal_handoff_observed(const RawHandoffObservation& obs) {
    return obs.null_sentinel && obs.body_returned;
}

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

// Negative-control entry point, only ever reached through the explicit 'entry'
// parameter below. It performs the null-sentinel handoff without running the
// user body at all, so the observed handoff must NOT be classified as a
// completed terminal handoff. The normal path never uses it, and it changes
// neither the R1 execution contract nor the terminal lifecycle convention.
inline void raw_child_entry_without_body(raw_transfer_t t) {
    jump_fcontext(t.fctx, nullptr);
    std::abort();
}

} // namespace detail

// 'entry' exists so the C-04 classification can be driven by the real resume
// loop in a state that falsifies it. The default is the harness entry point.
inline RawFcontextResult run_raw_fcontext_pingpong(
    long rounds, void (*entry)(raw_transfer_t) = detail::raw_child_entry) {
    constexpr std::size_t kStackSize = 256 * 1024;

    // make_fcontext aligns the stack pointer itself; malloc gives a suitably
    // aligned base and the top of the stack is base + size.
    void* stack = std::malloc(kStackSize);
    if (stack == nullptr) {
        std::abort();
    }

    raw_fcontext_t child = make_fcontext(static_cast<char*>(stack) + kStackSize,
                                         kStackSize, entry);

    detail::raw_state state{rounds, 0, -1, 0, false};

    raw_transfer_t t = jump_fcontext(child, &state); // enter the child
    while (t.data != nullptr) {
        t = jump_fcontext(t.fctx, &state);
    }

    // The loop leaves only on the null sentinel. Record the observation instead
    // of assuming it: 'from' is the context the terminal transfer came from.
    RawHandoffObservation handoff;
    handoff.null_sentinel = (t.data == nullptr);
    handoff.from = t.fctx;
    handoff.body_returned = state.body_returned;
    const bool terminal_handoff = detail::terminal_handoff_observed(handoff);

    // The child is dead by contract after the handoff and is never resumed; only
    // after observing that handoff is its backing stack reclaimed.
    std::free(stack);

    return RawFcontextResult{rounds,
                             state.child_runs,
                             state.final_local_state,
                             state.nested_resumes,
                             state.body_returned,
                             terminal_handoff,
                             handoff};
}

} // namespace p0
