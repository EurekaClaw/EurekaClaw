/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.L1Regression.L1DesignMatrix

/-!
# Localized Balls for ℓ₁-Constrained Linear Predictors

This file characterizes the localized balls B_n(δ) for ℓ₁-constrained linear predictors
and proves key properties about their parameter space representation.

## Main Definitions

* `l1LocalizedBall`: The localized ball B_n(δ) = {h ∈ H* : ‖h‖_n ≤ δ}

## Main Results

* `l1LocalizedBall_subset_l1ShiftedClass`: B_n(δ) ⊆ H*
* `l1LocalizedBall_param_bound`: Functions in B_n(δ) correspond to Δ with ‖Δ‖₁ ≤ 2R
* `l1LocalizedBall_zero_mem`: 0 ∈ B_n(δ) when θ* ∈ B₁^d(R) and δ ≥ 0
* `l1LocalizedBallImage_subset`: The image of B_n(δ) in EmpiricalSpace is bounded

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Localized Ball for ℓ₁ Regression

The localized ball B_n(δ) in the shifted class H* consists of functions h with ‖h‖_n ≤ δ.
For ℓ₁-constrained predictors, these correspond to parameter differences Δ = θ - θ*.
-/

/-- The localized ball for ℓ₁-constrained linear predictors:
B_n(δ) = {h ∈ H* : ‖h‖_n ≤ δ} where H* = l1ShiftedClass d R θ_star -/
def l1LocalizedBall (d : ℕ) (R δ : ℝ) (θ_star : EuclideanSpace ℝ (Fin d))
    (x : Fin n → EuclideanSpace ℝ (Fin d)) : Set ((EuclideanSpace ℝ (Fin d)) → ℝ) :=
  {h | h ∈ l1ShiftedClass d R θ_star ∧
       empiricalNorm n (fun i => h (x i)) ≤ δ}

/-- Alternative characterization using localizedBall -/
lemma l1LocalizedBall_eq_localizedBall (d : ℕ) (R δ : ℝ) (θ_star : EuclideanSpace ℝ (Fin d))
    (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    l1LocalizedBall d R δ θ_star x = localizedBall (l1ShiftedClass d R θ_star) δ x := rfl

/-- B_n(δ) is a subset of the shifted class H* -/
lemma l1LocalizedBall_subset_l1ShiftedClass (d : ℕ) (R δ : ℝ)
    (θ_star : EuclideanSpace ℝ (Fin d)) (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    l1LocalizedBall d R δ θ_star x ⊆ l1ShiftedClass d R θ_star := fun _ hh => hh.1

/-- Zero function is in B_n(δ) when θ* ∈ B₁^d(R) and δ ≥ 0 -/
lemma zero_mem_l1LocalizedBall (d : ℕ) {R δ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) (hδ : 0 ≤ δ) (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ l1LocalizedBall d R δ θ_star x := by
  constructor
  · exact zero_mem_l1ShiftedClass hθ_star
  · simp only [Pi.zero_apply]
    calc empiricalNorm n (fun _ => 0) = 0 := empiricalNorm_zero n
      _ ≤ δ := hδ

/-- Membership characterization: h ∈ B_n(δ) iff h ∈ H* and ‖h‖_n ≤ δ -/
lemma mem_l1LocalizedBall_iff {d : ℕ} {R δ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {x : Fin n → EuclideanSpace ℝ (Fin d)} {h : (EuclideanSpace ℝ (Fin d)) → ℝ} :
    h ∈ l1LocalizedBall d R δ θ_star x ↔
    h ∈ l1ShiftedClass d R θ_star ∧ empiricalNorm n (fun i => h (x i)) ≤ δ := Iff.rfl

/-- Functions in B_n(δ) correspond to parameter differences Δ with ‖Δ‖₁ ≤ 2R -/
theorem l1LocalizedBall_param_bound {d : ℕ} {R δ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) {x : Fin n → EuclideanSpace ℝ (Fin d)}
    {h : (EuclideanSpace ℝ (Fin d)) → ℝ} (hh : h ∈ l1LocalizedBall d R δ θ_star x) :
    ∃ Δ : EuclideanSpace ℝ (Fin d), l1norm Δ ≤ 2 * R ∧
      (h = fun y => @inner ℝ _ _ Δ y) ∧
      empiricalNorm n (fun i => @inner ℝ _ _ Δ (x i)) ≤ δ := by
  obtain ⟨h_shifted, h_norm⟩ := hh
  obtain ⟨Δ, hΔ_norm, hΔ_eq⟩ := l1ShiftedClass_param_bound hθ_star h_shifted
  exact ⟨Δ, hΔ_norm, hΔ_eq, by rw [hΔ_eq] at h_norm; exact h_norm⟩

/-- Under column norm bound, functions in B_n(δ) correspond to Δ with ‖Δ‖₁ ≤ 2R and ‖Δ‖₁-controlled empirical norm -/
theorem l1LocalizedBall_param_empirical_bound {d : ℕ} {R δ : ℝ}
    {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) {x : Fin n → EuclideanSpace ℝ (Fin d)}
    (hcol : columnNormBound x) (hn : 0 < n)
    {h : (EuclideanSpace ℝ (Fin d)) → ℝ} (hh : h ∈ l1LocalizedBall d R δ θ_star x) :
    ∃ Δ : EuclideanSpace ℝ (Fin d), l1norm Δ ≤ 2 * R ∧
      (h = fun y => @inner ℝ _ _ Δ y) ∧
      empiricalNorm n (fun i => @inner ℝ _ _ Δ (x i)) ≤ min δ (l1norm Δ) := by
  obtain ⟨Δ, hΔ_bound, hΔ_eq, hΔ_norm⟩ := l1LocalizedBall_param_bound hθ_star hh
  use Δ, hΔ_bound, hΔ_eq
  apply le_min hΔ_norm
  rw [hΔ_eq] at hh
  -- Use column norm bound
  exact empiricalNorm_le_l1norm_of_columnNormBound x Δ hcol hn

/-- If ‖Δ‖₁ ≤ 2R and empirical norm ≤ δ, then the function is in B_n(δ) -/
lemma mem_l1LocalizedBall_of_param {d : ℕ} {R δ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {x : Fin n → EuclideanSpace ℝ (Fin d)} {θ : EuclideanSpace ℝ (Fin d)}
    (hθ : l1norm θ ≤ R)
    (h_emp : empiricalNorm n (fun i => @inner ℝ _ _ (θ - θ_star) (x i)) ≤ δ) :
    (fun y => @inner ℝ _ _ (θ - θ_star) y) ∈ l1LocalizedBall d R δ θ_star x := by
  constructor
  · -- Show membership in l1ShiftedClass
    use θ, hθ
  · -- Show empirical norm bound
    exact h_emp

/-- Monotonicity: B_n(δ₁) ⊆ B_n(δ₂) when δ₁ ≤ δ₂ -/
lemma l1LocalizedBall_mono {d : ℕ} {R δ₁ δ₂ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {x : Fin n → EuclideanSpace ℝ (Fin d)} (hδ : δ₁ ≤ δ₂) :
    l1LocalizedBall d R δ₁ θ_star x ⊆ l1LocalizedBall d R δ₂ θ_star x := by
  intro h ⟨h_mem, h_norm⟩
  exact ⟨h_mem, le_trans h_norm hδ⟩

/-- B_n(0) contains only functions with zero empirical norm -/
lemma l1LocalizedBall_zero_radius {d : ℕ} {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {x : Fin n → EuclideanSpace ℝ (Fin d)} {h : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hh : h ∈ l1LocalizedBall d R 0 θ_star x) :
    empiricalNorm n (fun i => h (x i)) = 0 := by
  obtain ⟨_, h_norm⟩ := hh
  exact le_antisymm h_norm (empiricalNorm_nonneg n _)

/-! ## Image of Localized Ball in Empirical Space

The image of B_n(δ) under the empirical metric map is a subset of the ball of radius δ
in EmpiricalSpace.
-/

/-- The empirical image of a function in the shifted class -/
def l1EmpiricalImage (x : Fin n → EuclideanSpace ℝ (Fin d))
    (h : (EuclideanSpace ℝ (Fin d)) → ℝ) : EmpiricalSpace n :=
  fun i => h (x i)

/-- Distance from 0 in EmpiricalSpace equals empirical norm -/
lemma l1EmpiricalImage_dist_zero (x : Fin n → EuclideanSpace ℝ (Fin d))
    (h : (EuclideanSpace ℝ (Fin d)) → ℝ) :
    dist (l1EmpiricalImage x h) (0 : EmpiricalSpace n) = empiricalNorm n (fun i => h (x i)) := by
  unfold dist EmpiricalSpace.instDist
  show empiricalNorm n ((l1EmpiricalImage x h) - (0 : EmpiricalSpace n)) = empiricalNorm n (fun i => h (x i))
  congr 1
  ext i
  -- (l1EmpiricalImage x h - 0) i = h (x i)
  show (l1EmpiricalImage x h) i - (0 : EmpiricalSpace n) i = h (x i)
  have h0 : (0 : EmpiricalSpace n) i = 0 := rfl
  rw [l1EmpiricalImage, h0, sub_zero]

/-- The image of B_n(δ) in EmpiricalSpace is contained in the ball of radius δ -/
theorem l1LocalizedBallImage_subset {d : ℕ} {R δ : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {x : Fin n → EuclideanSpace ℝ (Fin d)} :
    l1EmpiricalImage x '' (l1LocalizedBall d R δ θ_star x) ⊆
    Metric.closedBall (0 : EmpiricalSpace n) δ := by
  intro v ⟨h, hh, hv⟩
  rw [Metric.mem_closedBall, ← hv, l1EmpiricalImage_dist_zero]
  exact hh.2

/-- Diameter bound: the diameter of the empirical image of B_n(δ) is at most 2δ -/
theorem l1LocalizedBallImage_diameter_le {d : ℕ} {R δ : ℝ} (hδ : 0 ≤ δ)
    {θ_star : EuclideanSpace ℝ (Fin d)} {x : Fin n → EuclideanSpace ℝ (Fin d)} :
    Metric.diam (l1EmpiricalImage x '' (l1LocalizedBall d R δ θ_star x)) ≤ 2 * δ := by
  apply Metric.diam_le_of_forall_dist_le (by linarith)
  intro v₁ ⟨h₁, hh₁, hv₁⟩ v₂ ⟨h₂, hh₂, hv₂⟩
  have hdist1 : dist v₁ 0 ≤ δ := by
    rw [← hv₁, l1EmpiricalImage_dist_zero]
    exact hh₁.2
  have hdist2 : dist v₂ 0 ≤ δ := by
    rw [← hv₂, l1EmpiricalImage_dist_zero]
    exact hh₂.2
  calc dist v₁ v₂ ≤ dist v₁ 0 + dist 0 v₂ := dist_triangle v₁ 0 v₂
    _ = dist v₁ 0 + dist v₂ 0 := by rw [dist_comm 0 v₂]
    _ ≤ δ + δ := add_le_add hdist1 hdist2
    _ = 2 * δ := by ring

end LeastSquares
