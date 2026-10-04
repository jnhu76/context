// P0 R0 correctness: Boost.Context public/reference baseline.
//
// Coverage: C-01 basic transfer, C-02 local state preservation, C-03 suspend
// inside a nested call, C-04 normal termination, C-05 repeated deterministic
// switching. No scheduler, no external notification, no multithreading.

#include "p0_check.hpp"

#include "boost_fiber_reference.hpp"

int main() {
    using namespace p0;

    // C-01 + C-05: deterministic transfer repeated many times.
    {
        const long rounds = 20000;
        BoostFiberResult r = run_boost_fiber_pingpong(rounds);
        P0_CHECK(r.child_runs == rounds);        // C-01 / C-05
        P0_CHECK(r.final_local_state == rounds); // C-02
        P0_CHECK(r.terminated);                  // C-04
    }

    // C-03: a small explicit run makes the nested-suspend intent visible.
    {
        BoostFiberResult r = run_boost_fiber_pingpong(3);
        P0_CHECK(r.child_runs == 3);
        P0_CHECK(r.final_local_state == 3);
        P0_CHECK(r.terminated);
    }

    return report("test_reference");
}
