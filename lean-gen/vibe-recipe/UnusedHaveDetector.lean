/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Lean
import Lean.Meta.Basic
import Lean.Elab.Command

/-!
# Unused `have` Statement Detector

A metaprogram that identifies unused `have` statements in Lean 4 proofs.

## How it works

In Lean 4's `Expr` type, `have` statements compile to **non-dependent `let` bindings**:

```
| letE (declName : Name) (type : Expr) (value : Expr) (body : Expr) (nondep : Bool)
```

When `nondep = true`, this represents a `have` statement (vs. a dependent `let` when `nondep = false`).

The detector:
1. Extracts the proof term from a theorem definition
2. Traverses the `Expr` tree, entering binders properly
3. When encountering `letE { nondep := true }`:
   - Creates an `FVarId` for the bound variable
   - Checks if `body.containsFVar(fvarId)` returns `false`
   - If unused, records the location and name
4. Reports all unused `have` statements
-/

namespace UnusedHaveDetector

open Lean Meta Elab Command

/-- Information about an unused have statement -/
structure UnusedHave where
  name : Name
  type : Expr
  depth : Nat  -- nesting depth for context
  deriving Inhabited

/-- State for tracking unused have statements during traversal -/
structure TraverseState where
  unused : Array UnusedHave := #[]
  depth : Nat := 0

/-- Check if a `letE` body uses its bound variable.
    For `have h : T := v; body`, we check if `h` appears free in `body`. -/
def checkLetEUsage (declName : Name) (type : Expr) (value : Expr)
    (body : Expr) (nondep : Bool) (st : TraverseState) : MetaM TraverseState := do
  if !nondep then return st  -- Only check `have` (nondep = true)

  -- Enter the let binder to get proper fvarId
  withLetDecl declName type value fun fvar => do
    let fvarId := fvar.fvarId!
    let bodyInst := body.instantiate1 fvar

    -- Check if fvar is used in body
    if !bodyInst.containsFVar fvarId then
      return { st with
        unused := st.unused.push { name := declName, type := type, depth := st.depth }
      }
    else
      return st

/-- Recursively traverse an expression looking for unused have statements -/
partial def traverseExpr (e : Expr) (st : TraverseState) : MetaM TraverseState := do
  match e with
  | .letE declName type value body nondep =>
    -- Check this let binding
    let st' ← checkLetEUsage declName type value body nondep st
    -- Recurse into value and body
    let st'' ← traverseExpr value { st' with depth := st'.depth + 1 }
    withLetDecl declName type value fun fvar => do
      let bodyInst := body.instantiate1 fvar
      traverseExpr bodyInst { st'' with depth := st'.depth + 1 }

  | .lam _ type body _ =>
    let st' ← traverseExpr type st
    withLocalDecl `_ .default type fun fvar => do
      let bodyInst := body.instantiate1 fvar
      traverseExpr bodyInst st'

  | .forallE _ type body _ =>
    let st' ← traverseExpr type st
    withLocalDecl `_ .default type fun fvar => do
      let bodyInst := body.instantiate1 fvar
      traverseExpr bodyInst st'

  | .app fn arg =>
    let st' ← traverseExpr fn st
    traverseExpr arg st'

  | .mdata _ e => traverseExpr e st
  | .proj _ _ e => traverseExpr e st
  | _ => return st

/-- Analyze a declaration for unused have statements -/
def analyzeDecl (declName : Name) : MetaM (Array UnusedHave) := do
  let env ← getEnv
  let some info := env.find? declName
    | throwError "Declaration {declName} not found"

  let some value := info.value?
    | throwError "Declaration {declName} has no value (axiom or opaque?)"

  let st ← traverseExpr value {}
  return st.unused

/-- Command to check for unused have statements -/
elab "#check_unused_have " id:ident : command => do
  let declName := id.getId
  let unused ← liftTermElabM <| MetaM.run' (analyzeDecl declName)

  if unused.isEmpty then
    logInfo m!"No unused have statements found in {declName}"
  else
    let msgs := unused.map fun u => m!"  • {u.name} : {u.type}"
    logWarning m!"Found {unused.size} unused have statement(s) in {declName}:\n{msgs.foldl (· ++ m!"\n" ++ ·) m!""}"

/-- Analyze all declarations in an environment that match a prefix -/
def analyzeAllWithPrefix (prefix_ : Name) : MetaM (Array (Name × Array UnusedHave)) := do
  let env ← getEnv
  let mut results := #[]
  for (name, _) in env.constants.fold (init := #[]) (fun acc n i => acc.push (n, i)) do
    if prefix_.isPrefixOf name then
      try
        let unused ← analyzeDecl name
        if !unused.isEmpty then
          results := results.push (name, unused)
      catch _ => pure ()
  return results

/-- Command to check all declarations with a given prefix -/
elab "#check_unused_have_prefix " id:ident : command => do
  let prefix_ := id.getId
  let results ← liftTermElabM <| MetaM.run' (analyzeAllWithPrefix prefix_)

  if results.isEmpty then
    logInfo m!"No unused have statements found in declarations with prefix {prefix_}"
  else
    let totalUnused : Nat := results.foldl (fun acc (_, unused) => acc + unused.size) (0 : Nat)
    let mut msg := m!"Found {totalUnused} unused have statement(s) across {results.size} declaration(s):\n"
    for (name, unused) in results do
      msg := msg ++ m!"\n{name}:\n"
      for u in unused do
        msg := msg ++ m!"  • {u.name} : {u.type}\n"
    logWarning msg

/-- Count total have statements (both used and unused) in a declaration -/
partial def countHaveStatements (e : Expr) : MetaM Nat := do
  match e with
  | .letE declName type value body nondep =>
    let thisCount := if nondep then 1 else 0
    let valueCount ← countHaveStatements value
    let bodyCount ← withLetDecl declName type value fun fvar => do
      let bodyInst := body.instantiate1 fvar
      countHaveStatements bodyInst
    return thisCount + valueCount + bodyCount

  | .lam _ type body _ =>
    let typeCount ← countHaveStatements type
    let bodyCount ← withLocalDecl `_ .default type fun fvar => do
      let bodyInst := body.instantiate1 fvar
      countHaveStatements bodyInst
    return typeCount + bodyCount

  | .forallE _ type body _ =>
    let typeCount ← countHaveStatements type
    let bodyCount ← withLocalDecl `_ .default type fun fvar => do
      let bodyInst := body.instantiate1 fvar
      countHaveStatements bodyInst
    return typeCount + bodyCount

  | .app fn arg =>
    let fnCount ← countHaveStatements fn
    let argCount ← countHaveStatements arg
    return fnCount + argCount

  | .mdata _ e => countHaveStatements e
  | .proj _ _ e => countHaveStatements e
  | _ => return 0

/-- Get statistics for a declaration -/
def getDeclStats (declName : Name) : MetaM (Nat × Nat) := do
  let env ← getEnv
  let some info := env.find? declName
    | throwError "Declaration {declName} not found"

  let some value := info.value?
    | throwError "Declaration {declName} has no value"

  let total ← countHaveStatements value
  let unused ← analyzeDecl declName
  return (total, unused.size)

/-- Command to show statistics -/
elab "#have_stats " id:ident : command => do
  let declName := id.getId
  let (total, unused) ← liftTermElabM <| MetaM.run' (getDeclStats declName)
  let used := total - unused
  logInfo m!"{declName}: {total} have statements total, {used} used, {unused} unused"

end UnusedHaveDetector
