/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.LinearRegression.DesignMatrix
import SLT.CoveringNumber

/-!
# Localized Ball for Linear Regression

This file defines the localized ball for linear regression and proves its properties.

## Main Definitions

* `linearLocalizedBall`: The localized ball B_n(δ) = {g ∈ F : ‖g‖_n ≤ δ}
* `linearLocalizedBallImage`: The empirical image of the localized ball
* `linearCoveringNumber`: The covering number for linear regression in empirical space

## Main Results

* `shiftedClass_isStarShaped_of_linear`: The shifted class of linear predictors is star-shaped
* `mem_linearLocalizedBall_iff`: Membership characterization via design matrix
* `zero_mem_linearLocalizedBall`: Zero is in the localized ball
* `linearLocalizedBallImage_eq`: Characterization of the empirical image
* `diam_linearLocalizedBallImage_le`: Diameter bound of 2δ

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Localized Ball for Linear Regression

For g ∈ F* = F, we have g(·) = ⟨u, ·⟩ for some u ∈ ℝ^d.
The empirical norm satisfies ‖g‖_n² = n⁻¹ · ‖Xu‖₂².
Thus ‖g‖_n ≤ δ ⟺ ‖Xu‖₂ ≤ δ√n.
-/

/-- The shifted class of linear predictors is star-shaped. -/
theorem shiftedClass_isStarShaped_of_linear {f_star : (EuclideanSpace ℝ (Fin d)) → ℝ}
    (hf_star : f_star ∈ linearPredictorClass d) :
    IsStarShaped (shiftedClass (linearPredictorClass d) f_star) := by
  rw [shiftedClass_eq_self_of_linear hf_star]
  exact linearPredictorClass_isStarShaped

/-- The localized ball for linear regression: B_n(δ) = {g ∈ F : ‖g‖_n ≤ δ} -/
def linearLocalizedBall (n d : ℕ) (δ : ℝ) (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    Set ((EuclideanSpace ℝ (Fin d)) → ℝ) :=
  localizedBall (linearPredictorClass d) δ x

/-- A linear predictor ⟨θ, ·⟩ is in the localized ball iff ‖Xθ‖ ≤ δ√n -/
theorem mem_linearLocalizedBall_iff (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (δ : ℝ) (θ : EuclideanSpace ℝ (Fin d)) :
    (fun z => @inner ℝ _ _ θ z) ∈ linearLocalizedBall n d δ x ↔
    ‖designMatrixMul x θ‖ ≤ δ * Real.sqrt n := by
  unfold linearLocalizedBall localizedBall
  simp only [Set.mem_sep_iff]
  constructor
  · intro ⟨hmem, hnorm⟩
    -- From empiricalNorm ≤ δ, derive ‖Xθ‖ ≤ δ√n
    rw [empiricalNorm_linear x θ] at hnorm
    have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
    have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
    have hsqrt_inv_pos : 0 < (n : ℝ)⁻¹.sqrt := by
      rw [Real.sqrt_inv n]
      exact inv_pos.mpr hsqrt_pos
    -- (n⁻¹).sqrt * ‖Xθ‖ ≤ δ implies ‖Xθ‖ ≤ δ / (n⁻¹).sqrt = δ * √n
    have h1 : ‖designMatrixMul x θ‖ ≤ δ / (n : ℝ)⁻¹.sqrt := by
      rw [le_div_iff₀ hsqrt_inv_pos, mul_comm]
      exact hnorm
    rw [Real.sqrt_inv n] at h1
    rw [div_inv_eq_mul] at h1
    exact h1
  · intro hnorm
    constructor
    · -- ⟨θ, ·⟩ ∈ linearPredictorClass d
      exact ⟨θ, rfl⟩
    · -- empiricalNorm ≤ δ
      rw [empiricalNorm_linear x θ]
      have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
      have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
      rw [Real.sqrt_inv n]
      rw [mul_comm, ← div_eq_mul_inv]
      rw [div_le_iff₀' hsqrt_pos]
      rw [mul_comm]
      exact hnorm

/-- Membership in the localized ball for zero parameter -/
lemma zero_mem_linearLocalizedBall (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 ≤ δ) :
    (fun _ => (0 : ℝ)) ∈ linearLocalizedBall n d δ x := by
  unfold linearLocalizedBall localizedBall
  simp only [Set.mem_sep_iff]
  constructor
  · exact zero_mem_linearPredictorClass
  · convert empiricalNorm_zero n ▸ hδ

/-! ## Covering Number in Empirical Space

The covering number N_δ(s) counts the minimum number of s-balls needed
to cover the localized ball in empirical space.
-/

/-- The empirical image of the localized ball for linear regression -/
def linearLocalizedBallImage (n d : ℕ) (δ : ℝ) (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    Set (EmpiricalSpace n) :=
  empiricalMetricImage n x '' linearLocalizedBall n d δ x

/-- The covering number for linear regression in empirical space -/
noncomputable def linearCoveringNumber (n d : ℕ) (s δ : ℝ) (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    WithTop ℕ :=
  coveringNumber s (linearLocalizedBallImage n d δ x)

/-- Characterization of the empirical image of the localized ball -/
theorem linearLocalizedBallImage_eq (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) (δ : ℝ) :
    linearLocalizedBallImage n d δ x =
    {v : EmpiricalSpace n | ∃ θ : EuclideanSpace ℝ (Fin d),
      ‖designMatrixMul x θ‖ ≤ δ * Real.sqrt n ∧
      v = fun i => @inner ℝ _ _ θ (x i)} := by
  unfold linearLocalizedBallImage
  ext v
  simp only [Set.mem_image, Set.mem_setOf_eq]
  constructor
  · rintro ⟨g, hg, rfl⟩
    unfold linearLocalizedBall localizedBall at hg
    obtain ⟨⟨θ, rfl⟩, hnorm⟩ := hg
    use θ
    constructor
    · rw [empiricalNorm_linear x θ] at hnorm
      have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
      have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
      rw [Real.sqrt_inv n] at hnorm
      rw [mul_comm, ← div_eq_mul_inv] at hnorm
      rw [mul_comm]
      exact (div_le_iff₀' hsqrt_pos).mp hnorm
    · rfl
  · rintro ⟨θ, hnorm, rfl⟩
    use fun z => @inner ℝ _ _ θ z
    constructor
    · rw [mem_linearLocalizedBall_iff hn x δ θ]
      exact hnorm
    · rfl

/-- Zero is in the empirical image when δ ≥ 0 -/
lemma zero_mem_linearLocalizedBallImage (x : Fin n → EuclideanSpace ℝ (Fin d))
    {δ : ℝ} (hδ : 0 ≤ δ) :
    (0 : EmpiricalSpace n) ∈ linearLocalizedBallImage n d δ x := by
  unfold linearLocalizedBallImage
  use fun _ => (0 : ℝ)
  constructor
  · exact zero_mem_linearLocalizedBall x hδ
  · rfl

/-- The localized ball image is nonempty when δ ≥ 0 -/
lemma linearLocalizedBallImage_nonempty (x : Fin n → EuclideanSpace ℝ (Fin d))
    {δ : ℝ} (hδ : 0 ≤ δ) :
    (linearLocalizedBallImage n d δ x).Nonempty :=
  ⟨0, zero_mem_linearLocalizedBallImage x hδ⟩

/-- Diameter bound: the diameter of the localized ball image is at most 2δ -/
theorem diam_linearLocalizedBallImage_le (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 ≤ δ) :
    Metric.diam (linearLocalizedBallImage n d δ x) ≤ 2 * δ := by
  apply Metric.diam_le_of_forall_dist_le (by linarith : 0 ≤ 2 * δ)
  intro v₁ hv₁ v₂ hv₂
  -- Unfold the image membership
  rw [linearLocalizedBallImage_eq hn x δ] at hv₁ hv₂
  obtain ⟨θ₁, hθ₁_norm, rfl⟩ := hv₁
  obtain ⟨θ₂, hθ₂_norm, rfl⟩ := hv₂
  -- dist(v₁, v₂) = empiricalNorm of difference
  show empiricalNorm n (fun i => @inner ℝ _ _ θ₁ (x i) - @inner ℝ _ _ θ₂ (x i)) ≤ 2 * δ
  -- The difference is ⟨θ₁ - θ₂, ·⟩
  have h_diff : (fun i => @inner ℝ _ _ θ₁ (x i) - @inner ℝ _ _ θ₂ (x i)) =
      (fun i => @inner ℝ _ _ (θ₁ - θ₂) (x i)) := by
    ext i
    simp only [inner_sub_left]
  rw [h_diff, empiricalNorm_linear x (θ₁ - θ₂)]
  -- Use triangle inequality on ‖X(θ₁ - θ₂)‖
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hsqrt_inv_nonneg : 0 ≤ (n : ℝ)⁻¹.sqrt := Real.sqrt_nonneg _
  -- ‖X(θ₁ - θ₂)‖ = ‖Xθ₁ - Xθ₂‖ ≤ ‖Xθ₁‖ + ‖Xθ₂‖
  have h_linear : designMatrixMul x (θ₁ - θ₂) = designMatrixMul x θ₁ - designMatrixMul x θ₂ := by
    ext i
    simp only [designMatrixMul_apply, inner_sub_left]
    rfl
  have h_norm_bound : ‖designMatrixMul x (θ₁ - θ₂)‖ ≤ ‖designMatrixMul x θ₁‖ + ‖designMatrixMul x θ₂‖ := by
    rw [h_linear]
    exact norm_sub_le _ _
  calc (n : ℝ)⁻¹.sqrt * ‖designMatrixMul x (θ₁ - θ₂)‖
      ≤ (n : ℝ)⁻¹.sqrt * (‖designMatrixMul x θ₁‖ + ‖designMatrixMul x θ₂‖) := by
        apply mul_le_mul_of_nonneg_left h_norm_bound hsqrt_inv_nonneg
      _ = (n : ℝ)⁻¹.sqrt * ‖designMatrixMul x θ₁‖ + (n : ℝ)⁻¹.sqrt * ‖designMatrixMul x θ₂‖ := by ring
      _ ≤ δ + δ := by
        apply add_le_add
        · -- (n⁻¹).sqrt * ‖Xθ₁‖ ≤ δ
          rw [Real.sqrt_inv n, mul_comm, ← div_eq_mul_inv]
          rw [div_le_iff₀' hsqrt_pos]
          rw [mul_comm]
          exact hθ₁_norm
        · -- (n⁻¹).sqrt * ‖Xθ₂‖ ≤ δ
          rw [Real.sqrt_inv n, mul_comm, ← div_eq_mul_inv]
          rw [div_le_iff₀' hsqrt_pos]
          rw [mul_comm]
          exact hθ₂_norm
      _ = 2 * δ := by ring

end LeastSquares
