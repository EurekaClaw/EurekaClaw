import Lake
open Lake DSL

abbrev linter : Array LeanOption := #[
  ⟨`linter.hashCommand, true⟩,
  ⟨`linter.missingEnd, true⟩,
  ⟨`linter.cdot, true⟩,
  ⟨`linter.dollarSyntax, true⟩,
  ⟨`linter.style.lambdaSyntax, true⟩,
  ⟨`linter.longLine, true⟩,
  ⟨`linter.oldObtain, true,⟩,
  ⟨`linter.refine, true⟩,
  ⟨`linter.setOption, true⟩
]

/-- These options are passed as `leanOptions` to building mathlib, as well as the
`Archive` and `Counterexamples`. (`tests` omits the first two options.) -/
abbrev options := #[
    ⟨`pp.unicode.fun, true⟩, -- pretty-prints `fun a ↦ b`
    ⟨`autoImplicit, false⟩
  ] ++ -- options that are used in `lake build`
    linter.map fun s ↦ { s with name := `weak ++ s.name }


package «SLT» where
  -- add any package configuration options here
  leanOptions := options
  moreServerOptions := linter

require mathlib from git
  "https://github.com/leanprover-community/mathlib4.git" @ "master"

@[default_target]
lean_lib «SLT» where
  globs := #[.submodules `SLT]

meta if get_config? env = some "dev" then
require «doc-gen4» from git
  "https://github.com/leanprover/doc-gen4" @ "main"
