/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.L1Regression.L1ShiftedClass
import SLT.LeastSquares.LinearRegression.DesignMatrix

/-!
# ℓ₁ Design Matrix with Column Normalization

This file defines the column normalization condition for design matrices and proves
the key lemma that relates empirical norm to ℓ₁ norm under this condition.

## Main Definitions

* `columnNormBound`: The condition that all columns of X have ‖Xⱼ‖₂ ≤ √n

## Main Results

* `empiricalNorm_le_l1norm_of_columnNormBound`: Under column norm bound, ‖f_θ‖_n ≤ ‖θ‖₁
  - Key lemma: ‖Xθ‖₂/√n ≤ Σⱼ|θⱼ|·‖Xⱼ‖₂/√n ≤ Σⱼ|θⱼ| = ‖θ‖₁

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-! ## Column Normalization Condition

The design matrix X has its columns normalized such that ‖Xⱼ‖₂ ≤ √n for all j ∈ [d].
This condition is common in high-dimensional statistics.
-/

/-- Column j of the design matrix: (X_j)_i = (x_i)_j -/
noncomputable def designMatrixColumn (x : Fin n → EuclideanSpace ℝ (Fin d)) (j : Fin d) :
    EuclideanSpace ℝ (Fin n) :=
  (WithLp.equiv 2 (Fin n → ℝ)).symm (fun i => (x i) j)

/-- The column norm bound condition: ∀ j, ‖X_j‖₂ ≤ √n -/
def columnNormBound (x : Fin n → EuclideanSpace ℝ (Fin d)) : Prop :=
  ∀ j : Fin d, ‖designMatrixColumn x j‖ ≤ Real.sqrt n

/-- The squared norm of column j equals Σᵢ (xᵢ)ⱼ² -/
lemma designMatrixColumn_norm_sq (x : Fin n → EuclideanSpace ℝ (Fin d)) (j : Fin d) :
    ‖designMatrixColumn x j‖^2 = ∑ i : Fin n, ((x i) j)^2 := by
  unfold designMatrixColumn
  rw [EuclideanSpace.norm_sq_eq]
  congr 1
  ext i
  simp only [Real.norm_eq_abs, sq_abs]
  rfl

/-- Column access lemma -/
lemma designMatrixColumn_apply (x : Fin n → EuclideanSpace ℝ (Fin d)) (j : Fin d) (i : Fin n) :
    (designMatrixColumn x j) i = (x i) j := rfl

/-- Design matrix applied to θ at index i can be expressed using columns -/
lemma designMatrixMul_apply_sum_columns (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) (i : Fin n) :
    (designMatrixMul x θ) i = ∑ j, θ j * (designMatrixColumn x j) i := by
  rw [designMatrixMul_apply]
  simp only [PiLp.inner_apply, RCLike.inner_apply, RCLike.conj_to_real, designMatrixColumn_apply]
  congr 1
  ext j
  ring

/-- The design matrix multiplication can be written as Σⱼ θⱼ · Xⱼ -/
lemma designMatrixMul_eq_sum_columns (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) :
    designMatrixMul x θ = ∑ j : Fin d, (θ j) • designMatrixColumn x j := by
  ext i
  rw [designMatrixMul_apply_sum_columns]
  -- Show: ∑ j, θ j * (designMatrixColumn x j) i = (∑ j, θ j • designMatrixColumn x j) i
  -- (∑ j, c_j • v_j) i = ∑ j, c_j * v_j i  for EuclideanSpace
  conv_rhs => rw [WithLp.ofLp_sum, Finset.sum_apply]
  simp only [WithLp.ofLp_smul, Pi.smul_apply, smul_eq_mul]

/-- Key triangle inequality for design matrix multiplication:
‖Xθ‖₂ ≤ Σⱼ |θⱼ| · ‖Xⱼ‖₂ -/
lemma designMatrixMul_norm_le_sum (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) :
    ‖designMatrixMul x θ‖ ≤ ∑ j : Fin d, ‖θ j‖ * ‖designMatrixColumn x j‖ := by
  rw [designMatrixMul_eq_sum_columns]
  calc ‖∑ j, (θ j) • designMatrixColumn x j‖
      ≤ ∑ j, ‖(θ j) • designMatrixColumn x j‖ := norm_sum_le _ _
    _ = ∑ j, ‖θ j‖ * ‖designMatrixColumn x j‖ := by
        congr 1
        ext j
        rw [norm_smul, Real.norm_eq_abs]

/-- Main theorem: Under column norm bound, ‖f_θ‖_n ≤ ‖θ‖₁
This is the key insight for high-dimensional ℓ₁ regression. -/
theorem empiricalNorm_le_l1norm_of_columnNormBound (x : Fin n → EuclideanSpace ℝ (Fin d))
    (θ : EuclideanSpace ℝ (Fin d)) (hcol : columnNormBound x) (hn : 0 < n) :
    empiricalNorm n (fun i => @inner ℝ _ _ θ (x i)) ≤ l1norm θ := by
  rw [empiricalNorm_linear]
  have hn_sqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr (Nat.cast_pos.mpr hn)
  have hn_nonneg : 0 ≤ (n : ℝ) := Nat.cast_nonneg n
  have hn_inv_sqrt : (n : ℝ)⁻¹.sqrt = 1 / Real.sqrt n := by
    rw [Real.sqrt_inv n, one_div]
  rw [hn_inv_sqrt, one_div, mul_comm, ← div_eq_mul_inv]
  -- Now we need: ‖Xθ‖ / √n ≤ ‖θ‖₁
  calc ‖designMatrixMul x θ‖ / Real.sqrt n
      ≤ (∑ j, ‖θ j‖ * ‖designMatrixColumn x j‖) / Real.sqrt n := by
        apply div_le_div_of_nonneg_right (designMatrixMul_norm_le_sum x θ)
        exact le_of_lt hn_sqrt_pos
    _ = ∑ j, ‖θ j‖ * (‖designMatrixColumn x j‖ / Real.sqrt n) := by
        rw [Finset.sum_div]
        congr 1
        ext j
        ring
    _ ≤ ∑ j, ‖θ j‖ * 1 := by
        apply Finset.sum_le_sum
        intro j _
        apply mul_le_mul_of_nonneg_left
        · rw [div_le_one hn_sqrt_pos]
          exact hcol j
        · exact norm_nonneg _
    _ = l1norm θ := by simp only [mul_one, l1norm]

/-- Corollary: Under column norm bound, covering in ‖·‖₁ gives covering in ‖·‖_n -/
theorem l1_covering_implies_empirical_covering (x : Fin n → EuclideanSpace ℝ (Fin d))
    (hcol : columnNormBound x) (hn : 0 < n)
    {S : Set (EuclideanSpace ℝ (Fin d))} {T : Finset (EuclideanSpace ℝ (Fin d))} {ε : ℝ}
    (hT : ∀ θ ∈ S, ∃ θ' ∈ T, l1norm (θ - θ') ≤ ε) :
    ∀ θ ∈ S, ∃ θ' ∈ T, empiricalNorm n (fun i => @inner ℝ _ _ (θ - θ') (x i)) ≤ ε := by
  intro θ hθ
  obtain ⟨θ', hθ'_mem, hθ'_dist⟩ := hT θ hθ
  use θ'
  constructor
  · exact hθ'_mem
  · calc empiricalNorm n (fun i => @inner ℝ _ _ (θ - θ') (x i))
        ≤ l1norm (θ - θ') := empiricalNorm_le_l1norm_of_columnNormBound x (θ - θ') hcol hn
      _ ≤ ε := hθ'_dist

/-- Trivial column norm bound: all columns have norm ≤ √n when n = 0 -/
lemma columnNormBound_of_n_eq_zero (x : Fin 0 → EuclideanSpace ℝ (Fin d)) :
    columnNormBound x := by
  intro j
  unfold designMatrixColumn
  rw [EuclideanSpace.norm_eq]
  simp only [Fintype.sum_empty, Real.sqrt_zero]
  exact Real.sqrt_nonneg _

/-- The empirical norm is zero when n = 0 -/
lemma empiricalNorm_eq_zero_of_n_eq_zero (f : Fin 0 → ℝ) :
    empiricalNorm 0 f = 0 := by
  unfold empiricalNorm
  simp

end LeastSquares
