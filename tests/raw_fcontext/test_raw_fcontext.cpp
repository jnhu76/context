// P0 R1 correctness: raw fcontext baseline (make_fcontext + jump_fcontext).
//
// Coverage: C-01 basic transfer, C-02 local state preservation, C-03 suspend
// from inside a real nested call, C-04 normal user-body completion followed by
// terminal handoff, C-05 repeated deterministic switching. No scheduler, no
// external notification, no multithreading.

#include "p0_check.hpp"

#include "raw_fcontext_reference.hpp"

int main() {
    using namespace p0;

    // C-01 + C-05: deterministic transfer repeated many times.
    {
        const long rounds = 20000;
        RawFcontextResult r = run_raw_fcontext_pingpong(rounds);
        P0_CHECK(r.child_runs == rounds);        // C-01 / C-05
        P0_CHECK(r.final_local_state == rounds); // C-02
        P0_CHECK(r.nested_resumes == rounds);    // C-03
        P0_CHECK(r.body_returned);               // C-04
        P0_CHECK(r.terminal_handoff);            // C-04
    }

    // Small explicit run keeps the completion boundary easy to inspect.
    {
        RawFcontextResult r = run_raw_fcontext_pingpong(3);
        P0_CHECK(r.child_runs == 3);
        P0_CHECK(r.final_local_state == 3);
        P0_CHECK(r.nested_resumes == 3);
        P0_CHECK(r.body_returned);
        P0_CHECK(r.terminal_handoff);
    }

    return report("test_raw_fcontext");
}
