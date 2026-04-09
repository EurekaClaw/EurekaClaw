/-
Copyright (c) 2024 Kei Tsukamoto. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Kei Tsukamoto, Kazumi Kasaura, Naoto Onda, Sho sonoda, Yuma Mizuno
-/
import Mathlib.Topology.Bases
import Mathlib.Order.ConditionallyCompleteLattice.Indexed
import Mathlib.Topology.Order.Lattice
import Mathlib.Data.Real.Basic
import Mathlib.Topology.Algebra.Ring.Real

universe u v

open TopologicalSpace

lemma closure_mem_le_sSup {E : Type v} [ConditionallyCompleteLattice E] [TopologicalSpace E] [OrderClosedTopology E]
  {s : Set E} (hs' : BddAbove s) {b : E} (hb : b ∈ closure s) :
  b ≤ sSup s := by
    have : s ⊆ Set.Iic (sSup s) := by
      intro x hx
      exact ConditionallyCompleteLattice.le_csSup s x hs' hx
    have : closure s ⊆ Set.Iic (sSup s) := by
      apply closure_minimal this isClosed_Iic
    exact this hb

lemma sSup_eq_closure_sSup {E : Type v} [ConditionallyCompleteLattice E] [TopologicalSpace E] [OrderClosedTopology E]
  {s : Set E} (hs : s.Nonempty) (hs' : BddAbove s) :
  sSup s = sSup (closure s) := by
  have h' : (BddAbove (closure s)) := by
    use sSup s
    intro b hb
    exact closure_mem_le_sSup hs' hb
  apply le_antisymm
  · apply csSup_le_csSup h' hs
    exact subset_closure
  · apply csSup_le (by aesop)
    exact fun b hb ↦ closure_mem_le_sSup hs' hb

lemma closure_range_eq_closure_denseSeq {X : Type u} [TopologicalSpace X] [SeparableSpace X] [Nonempty X]
  {E : Type v} [ConditionallyCompleteLattice E] [TopologicalSpace E] [OrderClosedTopology E]
  {f : X → E} (hf : Continuous f) :
  closure (Set.range f) = closure (Set.range (f ∘ denseSeq X)) := by
  rw [Set.range_comp f (denseSeq X)]
  apply Set.Subset.antisymm
  · have : Dense (Set.range (denseSeq X)) := denseRange_denseSeq X
    have := hf.range_subset_closure_image_dense this
    exact closure_minimal this isClosed_closure
  · apply closure_mono
    exact Set.image_subset_range f (Set.range (denseSeq X))

theorem separableSpaceSup_eq {X : Type u} [TopologicalSpace X] [SeparableSpace X] [Nonempty X]
  {E : Type v} [ConditionallyCompleteLattice E] [TopologicalSpace E] [OrderClosedTopology E]
  {f : X → E} (hf : Continuous f) (hf' : BddAbove (Set.range f)) :
  ⨆ x : X, f x = ⨆ i : Nat, f (denseSeq X i) := by
  calc
    _ = sSup (closure (Set.range f)) := by
      exact sSup_eq_closure_sSup (Set.range_nonempty f) hf'
    _ = sSup (closure (Set.range (f ∘ denseSeq X))) := by
      rw [closure_range_eq_closure_denseSeq hf]
    _ = sSup (Set.range (f ∘ denseSeq X)) := by
      have hf'' : BddAbove (Set.range (f ∘ denseSeq X)) := by
        rw [Set.range_comp f (denseSeq X)]
        have := Set.image_subset_range f (Set.range (denseSeq X))
        exact BddAbove.mono this hf'
      exact (sSup_eq_closure_sSup (Set.range_nonempty (f ∘ denseSeq X)) hf'').symm

theorem separableSpaceSup_eq_real {X : Type u} [TopologicalSpace X] [SeparableSpace X] [Nonempty X]
  {f : X → ℝ} (hf : Continuous f) :
  ⨆ x : X, f x = ⨆ i : Nat, f (denseSeq X i) := by
  if bdd : BddAbove (Set.range f) then
    exact separableSpaceSup_eq hf bdd
  else
    have : ¬ (BddAbove (Set.range (f ∘ (denseSeq X)))) := by
      intro h
      have : BddAbove (closure (Set.range (f ∘ (denseSeq X)))) := bddAbove_closure.mpr h
      rw [←closure_range_eq_closure_denseSeq hf] at this
      exact bdd <| bddAbove_closure.mp this
    calc
      _ = 0 := Real.iSup_of_not_bddAbove bdd
      _ = _ := (Real.iSup_of_not_bddAbove this).symm
