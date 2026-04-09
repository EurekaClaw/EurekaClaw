/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib
import SLT.LeastSquares.Defs
import SLT.CoveringNumber

/-!
# ℓ₁-Constrained Linear Predictor Class

This file defines the ℓ₁-constrained linear predictor class F = {f_θ(·) = ⟨θ, ·⟩ : θ ∈ B₁^d(R)}
and proves its basic properties including star-shapedness.

## Main Definitions

* `l1PredictorClass`: The class of ℓ₁-constrained linear predictors

## Main Results

* `zero_mem_l1PredictorClass`: Zero function is in F (since 0 ∈ B₁^d(R))
* `smul_mem_l1PredictorClass`: α ∈ [0,1], f ∈ F → αf ∈ F (B₁ is star-shaped)
* `l1PredictorClass_isStarShaped`: F is star-shaped
* `mem_l1PredictorClass_iff`: f ∈ F ↔ ∃ θ with ‖θ‖₁ ≤ R and f = ⟨θ, ·⟩

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## ℓ₁-Constrained Linear Predictor Class

The class of ℓ₁-constrained linear predictors F = {f_θ(·) = ⟨θ, ·⟩ : θ ∈ B₁^d(R)}
-/

/-- The class of ℓ₁-constrained linear predictors: functions of the form x ↦ ⟨θ, x⟩
for θ ∈ B₁^d(R), i.e., ‖θ‖₁ ≤ R. -/
def l1PredictorClass (d : ℕ) (R : ℝ) : Set ((EuclideanSpace ℝ (Fin d)) → ℝ) :=
  {f | ∃ θ : EuclideanSpace ℝ (Fin d), l1norm θ ≤ R ∧ f = fun x => @inner ℝ _ _ θ x}

/-- Membership characterization for l1PredictorClass -/
lemma mem_l1PredictorClass_iff {f : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ} :
    f ∈ l1PredictorClass d R ↔
    ∃ θ : EuclideanSpace ℝ (Fin d), l1norm θ ≤ R ∧ f = fun x => @inner ℝ _ _ θ x := by
  rfl

/-- ℓ₁ norm is non-negative -/
lemma l1norm_nonneg (θ : EuclideanSpace ℝ (Fin d)) : 0 ≤ l1norm θ :=
  Finset.sum_nonneg fun i _ => norm_nonneg (θ i)

/-- ℓ₁ norm of zero is zero -/
lemma l1norm_zero : l1norm (0 : EuclideanSpace ℝ (Fin d)) = 0 := by
  simp [l1norm]

/-- ℓ₁ norm scales by |c| -/
lemma l1norm_smul (c : ℝ) (θ : EuclideanSpace ℝ (Fin d)) :
    l1norm (c • θ) = |c| * l1norm θ := by
  unfold l1norm
  simp only [PiLp.smul_apply, norm_smul, Real.norm_eq_abs]
  rw [Finset.mul_sum]

/-- Zero function is in l1PredictorClass (with θ = 0) when R ≥ 0 -/
lemma zero_mem_l1PredictorClass {R : ℝ} (hR : 0 ≤ R) :
    (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ l1PredictorClass d R := by
  use 0
  refine ⟨?_, ?_⟩
  · simp only [l1norm, PiLp.zero_apply, norm_zero, Finset.sum_const_zero]
    exact hR
  · ext x
    simp only [Pi.zero_apply, inner_zero_left]

/-- Scalar multiplication preserves membership for α ∈ [0,1] -/
lemma smul_mem_l1PredictorClass {f : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ} {α : ℝ}
    (hf : f ∈ l1PredictorClass d R) (hα_pos : 0 ≤ α) (hα_le : α ≤ 1) :
    α • f ∈ l1PredictorClass d R := by
  obtain ⟨θ, hθ_norm, hθ_eq⟩ := hf
  use α • θ
  constructor
  · -- ‖α • θ‖₁ ≤ R
    calc l1norm (α • θ) = |α| * l1norm θ := l1norm_smul α θ
      _ = α * l1norm θ := by rw [abs_of_nonneg hα_pos]
      _ ≤ 1 * l1norm θ := by apply mul_le_mul_of_nonneg_right hα_le (l1norm_nonneg θ)
      _ = l1norm θ := one_mul _
      _ ≤ R := hθ_norm
  · ext x
    simp only [Pi.smul_apply, smul_eq_mul, hθ_eq, inner_smul_left, RCLike.conj_to_real]

/-- The ℓ₁-constrained predictor class is star-shaped when R ≥ 0 -/
theorem l1PredictorClass_isStarShaped {R : ℝ} (hR : 0 ≤ R) :
    IsStarShaped (l1PredictorClass d R) := by
  constructor
  · exact zero_mem_l1PredictorClass hR
  · intro h hh α hα_pos hα_le
    exact smul_mem_l1PredictorClass hh hα_pos hα_le

/-- Any linear predictor (without norm constraint) is in l1PredictorClass for large enough R -/
lemma linearPredictor_mem_l1PredictorClass {θ : EuclideanSpace ℝ (Fin d)} {R : ℝ}
    (hθ : l1norm θ ≤ R) :
    (fun x => @inner ℝ _ _ θ x) ∈ l1PredictorClass d R :=
  ⟨θ, hθ, rfl⟩

/-- ℓ₁ norm satisfies triangle inequality -/
lemma l1norm_add_le (θ₁ θ₂ : EuclideanSpace ℝ (Fin d)) :
    l1norm (θ₁ + θ₂) ≤ l1norm θ₁ + l1norm θ₂ := by
  unfold l1norm
  calc ∑ i : Fin d, ‖(θ₁ + θ₂) i‖
      ≤ ∑ i : Fin d, (‖θ₁ i‖ + ‖θ₂ i‖) := by
        apply Finset.sum_le_sum
        intro i _
        simp only [PiLp.add_apply]
        exact norm_add_le (θ₁ i) (θ₂ i)
    _ = (∑ i, ‖θ₁ i‖) + (∑ i, ‖θ₂ i‖) := Finset.sum_add_distrib

/-- Addition in l1PredictorClass: if f, g ∈ F with radii R₁, R₂, then f + g is in F with radius R₁ + R₂ -/
lemma add_mem_l1PredictorClass_of_radii {f g : (EuclideanSpace ℝ (Fin d)) → ℝ} {R₁ R₂ : ℝ}
    (hf : f ∈ l1PredictorClass d R₁) (hg : g ∈ l1PredictorClass d R₂) :
    f + g ∈ l1PredictorClass d (R₁ + R₂) := by
  obtain ⟨θ₁, hθ₁_norm, hθ₁_eq⟩ := hf
  obtain ⟨θ₂, hθ₂_norm, hθ₂_eq⟩ := hg
  use θ₁ + θ₂
  constructor
  · -- ‖θ₁ + θ₂‖₁ ≤ R₁ + R₂
    calc l1norm (θ₁ + θ₂) ≤ l1norm θ₁ + l1norm θ₂ := l1norm_add_le θ₁ θ₂
      _ ≤ R₁ + R₂ := add_le_add hθ₁_norm hθ₂_norm
  · ext x
    simp only [Pi.add_apply, hθ₁_eq, hθ₂_eq, inner_add_left]

/-- ℓ₁ norm of negation equals ℓ₁ norm -/
lemma l1norm_neg (θ : EuclideanSpace ℝ (Fin d)) : l1norm (-θ) = l1norm θ := by
  unfold l1norm
  congr 1
  ext i
  simp only [PiLp.neg_apply, norm_neg]

/-- Negation preserves l1PredictorClass membership -/
lemma neg_mem_l1PredictorClass {f : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ}
    (hf : f ∈ l1PredictorClass d R) :
    -f ∈ l1PredictorClass d R := by
  obtain ⟨θ, hθ_norm, hθ_eq⟩ := hf
  use -θ
  constructor
  · rw [l1norm_neg]; exact hθ_norm
  · ext x
    simp only [Pi.neg_apply, hθ_eq, inner_neg_left]

/-- Subtraction: if f ∈ F(R₁) and g ∈ F(R₂), then f - g ∈ F(R₁ + R₂) -/
lemma sub_mem_l1PredictorClass_of_radii {f g : (EuclideanSpace ℝ (Fin d)) → ℝ} {R₁ R₂ : ℝ}
    (hf : f ∈ l1PredictorClass d R₁) (hg : g ∈ l1PredictorClass d R₂) :
    f - g ∈ l1PredictorClass d (R₁ + R₂) := by
  have hsub : f - g = f + (-g) := sub_eq_add_neg f g
  rw [hsub]
  exact add_mem_l1PredictorClass_of_radii hf (neg_mem_l1PredictorClass hg)

/-- Get the parameter θ from a function in l1PredictorClass -/
lemma exists_param_of_mem_l1PredictorClass {f : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ}
    (hf : f ∈ l1PredictorClass d R) :
    ∃ θ : EuclideanSpace ℝ (Fin d), l1norm θ ≤ R ∧ ∀ x, f x = @inner ℝ _ _ θ x := by
  obtain ⟨θ, hθ_norm, hθ_eq⟩ := hf
  exact ⟨θ, hθ_norm, fun x => congrFun hθ_eq x⟩

/-- Convex combination stays in l1PredictorClass -/
lemma convex_comb_mem_l1PredictorClass {f g : (EuclideanSpace ℝ (Fin d)) → ℝ} {R : ℝ} {t : ℝ}
    (hf : f ∈ l1PredictorClass d R) (hg : g ∈ l1PredictorClass d R)
    (ht_pos : 0 ≤ t) (ht_le : t ≤ 1) :
    t • f + (1 - t) • g ∈ l1PredictorClass d R := by
  obtain ⟨θ₁, hθ₁_norm, hθ₁_eq⟩ := hf
  obtain ⟨θ₂, hθ₂_norm, hθ₂_eq⟩ := hg
  use t • θ₁ + (1 - t) • θ₂
  have h1mt_pos : 0 ≤ 1 - t := by linarith
  constructor
  · -- ‖t • θ₁ + (1-t) • θ₂‖₁ ≤ R
    calc l1norm (t • θ₁ + (1 - t) • θ₂)
        ≤ l1norm (t • θ₁) + l1norm ((1 - t) • θ₂) := l1norm_add_le _ _
      _ = |t| * l1norm θ₁ + |1 - t| * l1norm θ₂ := by rw [l1norm_smul, l1norm_smul]
      _ = t * l1norm θ₁ + (1 - t) * l1norm θ₂ := by
          rw [abs_of_nonneg ht_pos, abs_of_nonneg h1mt_pos]
      _ ≤ t * R + (1 - t) * R := by
          apply add_le_add
          · exact mul_le_mul_of_nonneg_left hθ₁_norm ht_pos
          · exact mul_le_mul_of_nonneg_left hθ₂_norm h1mt_pos
      _ = R := by ring
  · ext x
    simp only [Pi.add_apply, Pi.smul_apply, smul_eq_mul, hθ₁_eq, hθ₂_eq,
               inner_add_left, inner_smul_left, RCLike.conj_to_real]

end LeastSquares
