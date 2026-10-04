#pragma once

// R0 reference layer: boost::context::fiber used as a behavior/reference oracle.
//
// This is NOT a performance model and contains no scheduler. It is the simplest
// deterministic ping-pong between the main context and one child fiber. It is
// shared by tests/reference (correctness) and can be reused by future harnesses.

#include <boost/context/fiber.hpp>

namespace p0 {

struct BoostFiberResult {
    long rounds;             // requested round-trips
    long child_runs;         // times the child body executed
    long final_local_state;  // child-local variable after the last resume
    long nested_resumes;     // nested helper continued after each suspension
    bool terminated;         // the child returned and was not resumed again
};

namespace detail {

#if defined(__GNUC__) || defined(__clang__)
#  define P0_NOINLINE __attribute__((noinline))
#else
#  define P0_NOINLINE
#endif

// C-03 needs a real call frame, not merely source-level nesting. noinline keeps
// this helper distinct, and the observable increment after resume prevents the
// call from being reduced to a tail jump.
P0_NOINLINE inline void suspend_from_nested_call(boost::context::fiber& caller,
                                                  long& nested_resumes) {
    caller = std::move(caller).resume();
    ++nested_resumes;
}

#undef P0_NOINLINE

} // namespace detail

// C-01 basic transfer, C-02 local state preservation, C-03 suspend inside a
// real nested call, C-04 normal termination.
inline BoostFiberResult run_boost_fiber_pingpong(long rounds) {
    namespace ctx = boost::context;

    BoostFiberResult result{rounds, 0, -1, 0, false};

    ctx::fiber child{
        [&result, rounds](ctx::fiber&& main) -> ctx::fiber {
            // C-02: an ordinary local variable that must survive suspend/resume.
            long local_state = 0;
            ctx::fiber caller = std::move(main);

            for (long i = 0; i < rounds; ++i) {
                ++local_state;
                ++result.child_runs;
                detail::suspend_from_nested_call(caller, result.nested_resumes);
            }

            result.final_local_state = local_state;
            return caller; // implicit move; fiber is move-only
        }
    };

    for (long i = 0; i < rounds; ++i) {
        child = std::move(child).resume();
    }

    // Let the child run to normal termination. After this, `child` is invalid
    // and must never be resumed again (C-04).
    child = std::move(child).resume();
    result.terminated = !static_cast<bool>(child);

    return result;
}

} // namespace p0
