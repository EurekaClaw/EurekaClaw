/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.Localization
import SLT.LeastSquares.BasicInequality
import SLT.LeastSquares.SubGaussianity
import SLT.LeastSquares.DudleyApplication

/-!
# Critical Radius for Least Squares

The critical radius δ* is the smallest positive δ satisfying the critical inequality
G_n(δ)/δ ≤ δ/(2σ), where G_n(δ) is the local Gaussian complexity.

## Main Definitions

* `CriticalInequalitySet` - The set S = {δ > 0 : G_n(δ)/δ ≤ δ/(2σ)}
* `criticalRadius` - The infimum of the critical inequality set
* `CriticalRadiusExists` - Structure packaging existence conditions

## Main Results

* `criticalRadius_le_of_satisfies_CI` - Critical radius is a lower bound for CI solutions
* `critical_radius_exists_of_complexity_bound` - Existence from bounded complexity
* `CriticalInequalitySet_nonempty_of_bounded` - Nonemptiness under boundedness
-/

open MeasureTheory Finset BigOperators Real

namespace LeastSquares

variable {n : ℕ} {X : Type*}

/-! ## Critical Inequality Set -/

/-- S = {δ > 0 : G_n(δ)/δ ≤ δ/(2σ)} -/
def CriticalInequalitySet (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (x : Fin n → X) : Set ℝ :=
  {δ | 0 < δ ∧ satisfiesCriticalInequality n σ δ H x}

lemma CriticalInequalitySet_subset_pos {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X} :
    CriticalInequalitySet n σ H x ⊆ Set.Ioi 0 :=
  fun _ hδ => hδ.1

lemma CriticalInequalitySet_bddBelow {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X} :
    BddBelow (CriticalInequalitySet n σ H x) :=
  ⟨0, fun _ hδ => le_of_lt hδ.1⟩

/-! ## Critical Radius -/

/-- δ* = inf S, the smallest δ satisfying the critical inequality. -/
noncomputable def criticalRadius (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (x : Fin n → X) : ℝ :=
  sInf (CriticalInequalitySet n σ H x)

/-! ## Basic Properties -/

lemma criticalRadius_le_of_satisfies_CI {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X}
    {δ : ℝ} (hδ_pos : 0 < δ) (hδ_CI : satisfiesCriticalInequality n σ δ H x) :
    criticalRadius n σ H x ≤ δ := by
  apply csInf_le CriticalInequalitySet_bddBelow
  exact ⟨hδ_pos, hδ_CI⟩

lemma criticalRadius_smallest {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X}
    {δ' : ℝ} (hδ' : δ' ∈ CriticalInequalitySet n σ H x) :
    criticalRadius n σ H x ≤ δ' :=
  csInf_le CriticalInequalitySet_bddBelow hδ'

/-! ## Existence Conditions

The structure `CriticalRadiusExists` packages the three conditions needed for a
well-defined critical radius: nonemptiness, positivity, and satisfying CI.
-/

/-- Packages existence conditions: S nonempty, δ* > 0, and δ* ∈ S. -/
structure CriticalRadiusExists (n : ℕ) (σ : ℝ) (H : Set (X → ℝ)) (x : Fin n → X) : Prop where
  nonempty : (CriticalInequalitySet n σ H x).Nonempty
  pos : 0 < criticalRadius n σ H x
  satisfies_CI : satisfiesCriticalInequality n σ (criticalRadius n σ H x) H x

lemma criticalRadius_pos_of_exists {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X}
    (h : CriticalRadiusExists n σ H x) :
    0 < criticalRadius n σ H x :=
  h.pos

lemma criticalRadius_satisfies_CI_of_exists {n : ℕ} {σ : ℝ} {H : Set (X → ℝ)} {x : Fin n → X}
    (h : CriticalRadiusExists n σ H x) :
    satisfiesCriticalInequality n σ (criticalRadius n σ H x) H x :=
  h.satisfies_CI

/-! ## Existence Theorems

For large δ, G_n(δ)/δ → 0 while δ/(2σ) → ∞, so the curves must cross.
-/

/-- Bounded Gaussian complexity implies existence of δ satisfying CI. -/
lemma critical_radius_exists_of_complexity_bound {n : ℕ} {σ : ℝ} (hσ : 0 < σ)
    {H : Set (X → ℝ)} {x : Fin n → X}
    {M : ℝ} (hM : 0 ≤ M)
    (hbound : ∀ δ : ℝ, 0 < δ → LocalGaussianComplexity n H δ x ≤ M) :
    ∃ δ : ℝ, 0 < δ ∧ satisfiesCriticalInequality n σ δ H x := by
  set δ := max 1 (2 * Real.sqrt (2 * σ * M))
  use δ
  constructor
  · -- δ > 0
    apply lt_of_lt_of_le zero_lt_one (le_max_left _ _)
  · -- satisfiesCriticalInequality
    unfold satisfiesCriticalInequality
    have hδ_pos : 0 < δ := lt_of_lt_of_le zero_lt_one (le_max_left _ _)
    have hδ_ge : δ ≥ 2 * Real.sqrt (2 * σ * M) := le_max_right _ _
    -- G_n(δ)/δ ≤ M/δ
    have h1 : LocalGaussianComplexity n H δ x / δ ≤ M / δ := by
      apply div_le_div_of_nonneg_right (hbound δ hδ_pos) (le_of_lt hδ_pos)
    -- M/δ ≤ δ/(2σ) ⟺ 2σM ≤ δ²
    have h2 : M / δ ≤ δ / (2 * σ) := by
      rw [div_le_div_iff₀ hδ_pos (by linarith : 0 < 2 * σ)]
      calc M * (2 * σ) = 2 * σ * M := by ring
        _ ≤ (2 * Real.sqrt (2 * σ * M)) ^ 2 := by
          by_cases hM0 : M = 0
          · simp [hM0]
          · have hpos : 0 < 2 * σ * M := by positivity
            rw [mul_pow, sq_sqrt (le_of_lt hpos)]
            nlinarith [sq_nonneg (Real.sqrt (2 * σ * M))]
        _ ≤ δ ^ 2 := by
          have h_sqrt_nonneg : 0 ≤ 2 * Real.sqrt (2 * σ * M) := by positivity
          exact sq_le_sq' (by linarith) hδ_ge
        _ = δ * δ := sq δ
    linarith

/-- Simplified version: If the Gaussian complexity is uniformly bounded, CI set is nonempty -/
lemma CriticalInequalitySet_nonempty_of_bounded {n : ℕ} {σ : ℝ} (hσ : 0 < σ)
    {H : Set (X → ℝ)} {x : Fin n → X}
    {M : ℝ} (hM : 0 ≤ M)
    (hbound : ∀ δ : ℝ, 0 < δ → LocalGaussianComplexity n H δ x ≤ M) :
    (CriticalInequalitySet n σ H x).Nonempty := by
  obtain ⟨δ, hδ_pos, hδ_CI⟩ := critical_radius_exists_of_complexity_bound hσ hM hbound
  exact ⟨δ, hδ_pos, hδ_CI⟩

/-- Empirical process evaluated at the error Δ̂ = f̂ - f*. -/
lemma empiricalProcess_error_eq {n : ℕ} {X : Type*} (M : RegressionModel n X)
    (f_hat : X → ℝ) (w : Fin n → ℝ) :
    (n : ℝ)⁻¹ * ∑ i, w i * (f_hat (M.x i) - M.f_star (M.x i)) =
    empiricalProcess n M.x (fun y => f_hat y - M.f_star y) w := by
  rfl

end LeastSquares
