/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.LinearRegression.LinearPredictorClass

/-!
# Design Matrix Operations

This file defines the design matrix multiplication and its connection to empirical norms.

## Main Definitions

* `designMatrixMul`: The design matrix multiplication X maps θ ∈ ℝ^d to (⟨θ, x₁⟩, ..., ⟨θ, xₙ⟩) ∈ ℝ^n
* `designMatrixLinearMap`: The design matrix as a linear map

## Main Results

* `designMatrixMul_apply`: The design matrix applied to θ gives inner products at each sample point
* `designMatrixMul_add`: Design matrix multiplication is additive
* `designMatrixMul_smul`: Design matrix multiplication is scalar-multiplicative
* `empiricalNorm_linear_sq`: The squared empirical norm of a linear predictor equals (1/n)‖Xθ‖₂²
* `empiricalNorm_linear`: The empirical norm of a linear predictor in terms of the design matrix

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Connection Between Empirical Norm and Euclidean Norm

For g(·) = ⟨u, ·⟩ with design points x₁, ..., xₙ represented by matrix X,
the empirical norm ‖g‖_n = (1/√n)‖Xu‖₂.
-/

/-- The design matrix multiplication: X maps θ ∈ ℝ^d to (⟨θ, x₁⟩, ..., ⟨θ, xₙ⟩) ∈ ℝ^n.
We use WithLp.equiv to properly convert between Fin n → ℝ and EuclideanSpace ℝ (Fin n). -/
noncomputable def designMatrixMul (x : Fin n → EuclideanSpace ℝ (Fin d)) (θ : EuclideanSpace ℝ (Fin d)) :
    EuclideanSpace ℝ (Fin n) :=
  (WithLp.equiv 2 (Fin n → ℝ)).symm (fun i => @inner ℝ _ _ θ (x i))

/-- The design matrix applied to θ gives inner products at each sample point -/
lemma designMatrixMul_apply (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) (i : Fin n) :
    (designMatrixMul x θ) i = @inner ℝ _ _ θ (x i) := rfl

/-- Design matrix multiplication is linear in θ -/
lemma designMatrixMul_add (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ₁ θ₂ : EuclideanSpace ℝ (Fin d)) :
    designMatrixMul x (θ₁ + θ₂) = designMatrixMul x θ₁ + designMatrixMul x θ₂ := by
  ext i
  simp only [designMatrixMul, inner_add_left]
  rfl

lemma designMatrixMul_smul (x : Fin n → EuclideanSpace ℝ (Fin d))
    (c : ℝ) (θ : EuclideanSpace ℝ (Fin d)) :
    designMatrixMul x (c • θ) = c • designMatrixMul x θ := by
  ext i
  simp only [designMatrixMul, inner_smul_left, RCLike.conj_to_real]
  rfl

/-- The design matrix multiplication as a linear map from ℝ^d to ℝ^n. -/
noncomputable def designMatrixLinearMap (x : Fin n → EuclideanSpace ℝ (Fin d)) :
    EuclideanSpace ℝ (Fin d) →ₗ[ℝ] EuclideanSpace ℝ (Fin n) where
  toFun := designMatrixMul x
  map_add' := designMatrixMul_add x
  map_smul' := designMatrixMul_smul x

/-- The squared empirical norm of a linear predictor equals (1/n)‖Xθ‖₂² -/
lemma empiricalNorm_linear_sq (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) :
    (empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)))^2 =
    (n : ℝ)⁻¹ * ‖designMatrixMul x θ‖^2 := by
  rw [empiricalNorm_sq n _]
  unfold designMatrixMul
  rw [EuclideanSpace.norm_sq_eq]
  congr 1
  apply sum_congr rfl
  intro i _
  have h := WithLp.equiv_symm_apply_ofLp 2 (Fin n → ℝ) (fun i => @inner ℝ _ _ θ (x i))
  simp only [Real.norm_eq_abs, sq_abs, congrFun h i]

/-- The empirical norm of a linear predictor in terms of the design matrix -/
lemma empiricalNorm_linear (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) :
    empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)) =
    (n : ℝ)⁻¹.sqrt * ‖designMatrixMul x θ‖ := by
  have h := empiricalNorm_linear_sq x θ
  have hn_nonneg : 0 ≤ (n : ℝ)⁻¹ := inv_nonneg.mpr (Nat.cast_nonneg n)
  have hnorm_nonneg : 0 ≤ ‖designMatrixMul x θ‖ := norm_nonneg _
  rw [← Real.sqrt_sq (empiricalNorm_nonneg n _), h]
  rw [Real.sqrt_mul hn_nonneg, Real.sqrt_sq hnorm_nonneg]

end LeastSquares
