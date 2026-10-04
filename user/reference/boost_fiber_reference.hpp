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
    bool terminated;         // the child returned and was not resumed again
};

// C-01 basic transfer, C-02 local state preservation, C-03 suspend inside a
// nested call, C-04 normal termination.
inline BoostFiberResult run_boost_fiber_pingpong(long rounds) {
    namespace ctx = boost::context;

    BoostFiberResult result{rounds, 0, -1, false};

    ctx::fiber child{
        [&result, rounds](ctx::fiber&& main) -> ctx::fiber {
            // C-02: an ordinary local variable that must survive suspend/resume.
            long local_state = 0;
            ctx::fiber caller = std::move(main);

            // C-03: the suspend point lives inside a nested call.
            auto suspend = [&caller]() {
                caller = std::move(caller).resume();
            };

            for (long i = 0; i < rounds; ++i) {
                ++local_state;
                ++result.child_runs;
                suspend();
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
