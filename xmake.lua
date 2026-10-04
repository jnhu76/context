-- P0 build authority: Xmake is the sole primary build entry for this repository.
-- Target platform is fixed to Linux x86-64 SysV ELF (see AGENTS.md).
--
-- Upstream source selection is explicit and auditable. Do NOT glob
-- third_party/boost-context/src/**. Every compiled upstream translation unit is
-- listed below with the reason it is required.

set_project("context")
set_version("0.1.0")
set_languages("c++17")
set_symbols("debug")
-- Keep symbols in both modes: P0 must be auditable with nm/readelf/objdump.
set_strip("none")
-- Start from -O0 and add the release flag explicitly. The recorded
-- optimization flags in the benchmark manifest are the effective setting for
-- the mode, not a verbatim command line: the real command line also carries -O0
-- (set_optimize "none") and -g (set_symbols "debug"), and the manifest does not
-- list -std=c++17 or -Wall/-Wextra.
set_optimize("none")
add_cxflags("-Wall", "-Wextra")

add_rules("mode.debug", "mode.release")

if is_mode("release") then
    -- Benchmark mode. No LTO: P1 needs intact source/function attribution.
    add_cxflags("-O2")
    add_defines('P0_BUILD_MODE="release"', 'P0_OPT_FLAGS="-O2 -g"')
else
    -- Correctness mode.
    add_defines('P0_BUILD_MODE="debug"', 'P0_OPT_FLAGS="-O0 -g"')
end

local ctx_dir = "third_party/boost-context"
local ctx_inc = ctx_dir .. "/include"

-- Minimal Boost header dependencies for the R0 (boost::context::fiber) path.
-- Audited closure: config, assert, core, smart_ptr (boost/intrusive_ptr.hpp),
-- mp11 (boost/mp11/integer_sequence.hpp). predef and pool are not part of the
-- fiber_fcontext include path and are deliberately not fetched.
local boost_dep_incs = {
    "third_party/boost-config/include",
    "third_party/boost-assert/include",
    "third_party/boost-core/include",
    "third_party/boost-smart_ptr/include",
    "third_party/boost-mp11/include",
}

-- x86-64 SysV ELF fcontext primitives, selected explicitly.
local asm_make  = ctx_dir .. "/src/asm/make_x86_64_sysv_elf_gas.S"
local asm_jump  = ctx_dir .. "/src/asm/jump_x86_64_sysv_elf_gas.S"
local asm_ontop = ctx_dir .. "/src/asm/ontop_x86_64_sysv_elf_gas.S"

-- Pin identity, recorded into the benchmark environment manifest.
-- Must equal the gitlink for third_party/boost-context and the SHA in
-- docs/UPSTREAM.md; tools/verify/p0.sh checks all three stay in sync.
local ctx_sha = "1b7bb3d6173032c592cbe82d43f4406e51c3653a"
add_defines('P0_BOOST_CONTEXT_SHA="' .. ctx_sha .. '"')
add_defines('P0_XMAKE_VERSION="' .. xmake.version() .. '"')
add_defines('P0_TARGET_ABI="x86_64-sysv-elf"')

-- R0: Boost.Context public/reference baseline (boost::context::fiber).
-- Compiled upstream sources (explicit, no glob):
--   src/asm/{make,jump,ontop}_x86_64_sysv_elf_gas.S
--   src/fcontext.cpp         wraps the C asm symbols into the namespaced C++
--                            symbols used by fiber_fcontext.hpp
--   src/posix/stack_traits.cpp  correctness dependency: the default fiber
--                            constructor calls stack_traits::default_size()
-- ontop asm is a LINK dependency of upstream fcontext.cpp, which references
-- ::ontop_fcontext unconditionally. This harness never calls it directly.
target("boost_context_reference")
    set_kind("static")
    add_files(asm_make, asm_jump, asm_ontop)
    add_files(ctx_dir .. "/src/fcontext.cpp")
    add_files(ctx_dir .. "/src/posix/stack_traits.cpp")
    add_includedirs(ctx_inc, {public = true})
    add_includedirs(boost_dep_incs, {public = true})
    add_defines("BOOST_CONTEXT_NO_LIB", {public = true})

-- R1: raw fcontext baseline. Only the two primitives the harness requires.
-- ontop_fcontext is deliberately NOT compiled here; that is what distinguishes
-- "available upstream primitive" from "required by this P0 harness".
target("raw_fcontext_reference")
    set_kind("static")
    add_files(asm_make, asm_jump)

target("test_reference")
    set_kind("binary")
    add_deps("boost_context_reference")
    add_files("tests/reference/*.cpp")
    add_includedirs("tests", "user/reference")

target("test_raw_fcontext")
    set_kind("binary")
    add_deps("raw_fcontext_reference")
    add_files("tests/raw_fcontext/*.cpp")
    add_includedirs("tests", "user/reference")

target("bench_context_switch")
    set_kind("binary")
    add_deps("boost_context_reference")
    add_files("bench/context_switch/*.cpp")
    add_includedirs("user/reference")
