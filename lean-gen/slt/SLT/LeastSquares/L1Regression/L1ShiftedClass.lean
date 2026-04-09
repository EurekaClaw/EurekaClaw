/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.L1Regression.L1PredictorClass

/-!
# Shifted ℓ₁-Constrained Class

This file defines the shifted class H* = F - {f*} for ℓ₁-constrained linear predictors
and proves its star-shaped property.

## Main Definitions

* `l1ShiftedClass`: The shifted class H* = {f - f* : f ∈ l1PredictorClass}

## Main Results

* `l1ShiftedClass_isStarShaped`: H* is star-shaped (since B₁^d(R) is convex)
* `shiftedClass_eq_l1ShiftedClass`: shiftedClass F f* = H* (explicit characterization)
* `l1ShiftedClass_param_bound`: Functions in H* correspond to Δ with ‖Δ‖₁ ≤ 2R

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Shifted ℓ₁-Constrained Class

For f* = ⟨θ*, ·⟩ with ‖θ*‖₁ ≤ R, the shifted class H* = F - {f*} consists of
functions of the form ⟨Δ, ·⟩ where Δ = θ - θ* for some θ ∈ B₁^d(R).
-/

/-- The shifted class for ℓ₁-constrained predictors. For f* ∈ F, this is
H* = {f - f* : f ∈ F} = {⟨Δ, ·⟩ : ∃ θ ∈ B₁^d(R), Δ = θ - θ*} -/
def l1ShiftedClass (d : ℕ) (R : ℝ) (θ_star : EuclideanSpace ℝ (Fin d)) :
    Set ((EuclideanSpace ℝ (Fin d)) → ℝ) :=
  {h | ∃ θ : EuclideanSpace ℝ (Fin d), l1norm θ ≤ R ∧
       h = fun x => @inner ℝ _ _ (θ - θ_star) x}

/-- Membership characterization for l1ShiftedClass -/
lemma mem_l1ShiftedClass_iff {h : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ}
    {θ_star : EuclideanSpace ℝ (Fin d)} :
    h ∈ l1ShiftedClass d R θ_star ↔
    ∃ θ : EuclideanSpace ℝ (Fin d), l1norm θ ≤ R ∧
      h = fun x => @inner ℝ _ _ (θ - θ_star) x := by
  rfl

/-- Zero is in the shifted class when θ* ∈ B₁^d(R) -/
lemma zero_mem_l1ShiftedClass {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) :
    (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ l1ShiftedClass d R θ_star := by
  use θ_star
  constructor
  · exact hθ_star
  · ext x
    simp only [Pi.zero_apply, sub_self, inner_zero_left]

/-- Scalar multiplication preserves membership in shifted class for α ∈ [0,1] -/
lemma smul_mem_l1ShiftedClass {h : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ}
    {θ_star : EuclideanSpace ℝ (Fin d)} {α : ℝ}
    (hθ_star : l1norm θ_star ≤ R) (hh : h ∈ l1ShiftedClass d R θ_star)
    (hα_pos : 0 ≤ α) (hα_le : α ≤ 1) :
    α • h ∈ l1ShiftedClass d R θ_star := by
  obtain ⟨θ, hθ_norm, hθ_eq⟩ := hh
  -- Use convex combination: α • θ + (1-α) • θ* is in B₁^d(R)
  use α • θ + (1 - α) • θ_star
  have h1mα : 0 ≤ 1 - α := by linarith
  constructor
  · -- Show ‖α • θ + (1-α) • θ*‖₁ ≤ R
    calc l1norm (α • θ + (1 - α) • θ_star)
        ≤ l1norm (α • θ) + l1norm ((1 - α) • θ_star) := l1norm_add_le _ _
      _ = |α| * l1norm θ + |1 - α| * l1norm θ_star := by rw [l1norm_smul, l1norm_smul]
      _ = α * l1norm θ + (1 - α) * l1norm θ_star := by
          rw [abs_of_nonneg hα_pos, abs_of_nonneg h1mα]
      _ ≤ α * R + (1 - α) * R := by
          apply add_le_add
          · exact mul_le_mul_of_nonneg_left hθ_norm hα_pos
          · exact mul_le_mul_of_nonneg_left hθ_star h1mα
      _ = R := by ring
  · -- Show the function equals α • h
    ext x
    simp only [Pi.smul_apply, smul_eq_mul, hθ_eq, inner_sub_left, inner_add_left,
               inner_smul_left, RCLike.conj_to_real]
    ring

/-- The shifted class is star-shaped when θ* ∈ B₁^d(R) -/
theorem l1ShiftedClass_isStarShaped {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) :
    IsStarShaped (l1ShiftedClass d R θ_star) := by
  constructor
  · exact zero_mem_l1ShiftedClass hθ_star
  · intro h hh α hα_pos hα_le
    exact smul_mem_l1ShiftedClass hθ_star hh hα_pos hα_le

/-- The shifted class equals the standard shiftedClass when f* is a linear predictor in F -/
theorem shiftedClass_eq_l1ShiftedClass {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)} :
    shiftedClass (l1PredictorClass d R) (fun x => @inner ℝ _ _ θ_star x) =
    l1ShiftedClass d R θ_star := by
  ext h
  constructor
  · -- h ∈ shiftedClass → h ∈ l1ShiftedClass
    intro ⟨f, hf_mem, hf_eq⟩
    obtain ⟨θ, hθ_norm, hθ_eq⟩ := hf_mem
    use θ
    constructor
    · exact hθ_norm
    · rw [hf_eq, hθ_eq]
      ext x
      simp only [Pi.sub_apply, inner_sub_left]
  · -- h ∈ l1ShiftedClass → h ∈ shiftedClass
    intro ⟨θ, hθ_norm, hθ_eq⟩
    use fun x => @inner ℝ _ _ θ x
    constructor
    · exact ⟨θ, hθ_norm, rfl⟩
    · rw [hθ_eq]
      ext x
      simp only [Pi.sub_apply, inner_sub_left]

/-- Parameter bound: if h = ⟨Δ, ·⟩ is in H* with both θ and θ* in B₁^d(R),
then ‖Δ‖₁ ≤ 2R -/
lemma l1ShiftedClass_param_bound {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) {h : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hh : h ∈ l1ShiftedClass d R θ_star) :
    ∃ Δ : EuclideanSpace ℝ (Fin d), l1norm Δ ≤ 2 * R ∧
      h = fun x => @inner ℝ _ _ Δ x := by
  obtain ⟨θ, hθ_norm, hθ_eq⟩ := hh
  use θ - θ_star
  constructor
  · have hsub : θ - θ_star = θ + (-θ_star) := sub_eq_add_neg θ θ_star
    calc l1norm (θ - θ_star) = l1norm (θ + (-θ_star)) := by rw [hsub]
      _ ≤ l1norm θ + l1norm (-θ_star) := l1norm_add_le _ _
      _ = l1norm θ + l1norm θ_star := by rw [l1norm_neg]
      _ ≤ R + R := add_le_add hθ_norm hθ_star
      _ = 2 * R := by ring
  · exact hθ_eq

/-- Alternative characterization: l1ShiftedClass contains functions ⟨Δ, ·⟩
where θ* + Δ ∈ B₁^d(R), which implies ‖Δ‖₁ ≤ 2R -/
lemma mem_l1ShiftedClass_of_delta {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    {Δ : EuclideanSpace ℝ (Fin d)}
    (hsum : l1norm (θ_star + Δ) ≤ R) :
    (fun x => @inner ℝ _ _ Δ x) ∈ l1ShiftedClass d R θ_star := by
  use θ_star + Δ
  constructor
  · exact hsum
  · ext x
    simp only [add_sub_cancel_left]

/-- The full ℓ₁ shifted class with radius 2R contains all linear predictors with ‖Δ‖₁ ≤ 2R -/
lemma l1ShiftedClass_superset {R : ℝ} {θ_star : EuclideanSpace ℝ (Fin d)}
    (hθ_star : l1norm θ_star ≤ R) :
    l1ShiftedClass d R θ_star ⊆
    {h | ∃ Δ : EuclideanSpace ℝ (Fin d), l1norm Δ ≤ 2 * R ∧
         h = fun x => @inner ℝ _ _ Δ x} := by
  intro h hh
  exact l1ShiftedClass_param_bound hθ_star hh

end LeastSquares
