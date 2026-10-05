// P0 R1 correctness: raw fcontext baseline (make_fcontext + jump_fcontext).
//
// Coverage: C-01 basic transfer, C-02 local state preservation, C-03 suspend
// from inside a real nested call, C-04 normal user-body completion followed by
// terminal handoff, C-05 repeated deterministic switching. No scheduler, no
// external notification, no multithreading.
//
// C-04 is checked through an observation, not a constant, and the last case here
// is the control that proves the check can fail.

#include "p0_check.hpp"

#include "raw_fcontext_reference.hpp"

namespace {

// C-04 fallibility control. The terminal-handoff flag is derived from what the
// resume loop observed, so it must be able to come out false. This drives the
// same production entry point with a child that hands off the null sentinel
// without ever running the user body: the null sentinel is observed, but the
// body never returned, so no completed terminal handoff may be reported. The
// 20000-round case below asserts the flag is true, so together they show the
// check is neither a tautology nor permanently false.
void terminal_handoff_oracle_is_fallible() {
    using namespace p0;

    RawFcontextResult r =
        run_raw_fcontext_pingpong(3, detail::raw_child_entry_without_body);

    P0_CHECK(r.child_runs == 0);        // the user body really did not run
    P0_CHECK(!r.body_returned);         // the trampoline never saw completion
    P0_CHECK(r.handoff.null_sentinel);  // the null sentinel was still observed
    P0_CHECK(!r.terminal_handoff);      // ... and the C-04 check fails
}

} // namespace

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
        P0_CHECK(r.handoff.null_sentinel);       // C-04: observed, not assumed
        P0_CHECK(r.handoff.body_returned);       // C-04: observed, not assumed
        P0_CHECK(r.handoff.from != nullptr);     // C-04: a real context handed off
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

    terminal_handoff_oracle_is_fallible();

    return report("test_raw_fcontext");
}
