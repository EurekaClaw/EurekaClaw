/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.Defs

/-!
# Basic Inequality for Least Squares Regression

This file contains the fundamental Basic Inequality for least squares regression.

## Main Results

* `basic_inequality` - For least squares estimator f̂ with f* ∈ F:
  (1/2)‖f̂ - f*‖_n² ≤ (σ/n) Σᵢ wᵢ(f̂(xᵢ) - f*(xᵢ))

-/

open MeasureTheory Finset BigOperators Real

namespace LeastSquares

variable {n : ℕ} {X : Type*}


/-- Basic inequality: (1/2)‖Δ̂‖_n² ≤ (σ/n) Σᵢ wᵢΔ̂(xᵢ)
where Δ̂ = f̂ - f* is the estimation error. -/
theorem basic_inequality (hn : 0 < n)
    (M : RegressionModel n X) (F : Set (X → ℝ))
    (f_hat : X → ℝ) (w : Fin n → ℝ)
    (hf_hat : isLeastSquaresEstimator (M.response w) F M.x f_hat)
    (hf_star : M.f_star ∈ F) :
    (1 / 2) * (empiricalNorm n (fun i => f_hat (M.x i) - M.f_star (M.x i)))^2 ≤
      M.σ / n * ∑ i : Fin n, w i * (f_hat (M.x i) - M.f_star (M.x i)) := by
  -- Abbreviations for readability
  set y := M.response w with hy_def
  set Δ := fun i => f_hat (M.x i) - M.f_star (M.x i) with hΔ_def

  -- Sample size positivity (real)
  have h2_1_1 : (0 : ℝ) < n := Nat.cast_pos.mpr hn

  -- Sample size inverse positivity
  have h2_1_2 : (0 : ℝ) < (n : ℝ)⁻¹ := inv_pos.mpr h2_1_1

  -- y_i - f̂(x_i) = σw_i - Δ(x_i)
  have h2_1_6 : ∀ i, y i - f_hat (M.x i) = M.σ * w i - Δ i := fun i => by
    simp only [hy_def, RegressionModel.response_apply, hΔ_def]
    ring

  -- y_i - f*(x_i) = σw_i
  have h2_1_7 : ∀ i, y i - M.f_star (M.x i) = M.σ * w i := fun i => by
    simp only [hy_def, RegressionModel.response_apply]
    ring

  -- Σ(y_i - f*(x_i))² = σ² Σ w_i²
  have h2_1_10 : ∑ i, (y i - M.f_star (M.x i))^2 = M.σ^2 * ∑ i, w i^2 := by
    simp only [h2_1_7, mul_pow]
    rw [← Finset.mul_sum]

  -- Σ(y_i - f̂(x_i))² ≤ Σ(y_i - f*(x_i))²
  have h2_1_11 : ∑ i, (y i - f_hat (M.x i))^2 ≤ ∑ i, (y i - M.f_star (M.x i))^2 :=
    hf_hat.le_of_mem hf_star

  -- Σ(σw_i - Δ(x_i))² ≤ σ² Σ w_i²
  have h2_1_12 : ∑ i, (M.σ * w i - Δ i)^2 ≤ M.σ^2 * ∑ i, w i^2 := by
    calc ∑ i, (M.σ * w i - Δ i)^2
        = ∑ i, (y i - f_hat (M.x i))^2 := by
          apply sum_congr rfl
          intro i _
          rw [h2_1_6 i]
      _ ≤ ∑ i, (y i - M.f_star (M.x i))^2 := h2_1_11
      _ = M.σ^2 * ∑ i, w i^2 := h2_1_10

  -- Σ(σw_i - Δ_i)² = σ²Σw_i² - 2σΣw_iΔ_i + ΣΔ_i²
  have h2_1_9 : ∑ i, (M.σ * w i - Δ i)^2 =
      M.σ^2 * ∑ i, w i^2 - 2 * M.σ * ∑ i, w i * Δ i + ∑ i, Δ i^2 := by
    have h_expand : ∀ i, (M.σ * w i - Δ i)^2 =
        M.σ^2 * w i^2 - 2 * M.σ * (w i * Δ i) + Δ i^2 := fun i => by ring
    simp only [h_expand]
    rw [Finset.sum_add_distrib, Finset.sum_sub_distrib]
    rw [← Finset.mul_sum, ← Finset.mul_sum]

  -- ΣΔ_i² ≤ 2σΣw_iΔ_i
  have h2_1_15 : ∑ i, Δ i^2 ≤ 2 * M.σ * ∑ i, w i * Δ i := by linarith

  -- ‖Δ‖_n² = n⁻¹ Σ Δ_i²
  have h2_1_16 : (empiricalNorm n Δ)^2 = (n : ℝ)⁻¹ * ∑ i, Δ i^2 := by
    rw [empiricalNorm_sq n Δ]

  -- n⁻¹ ΣΔ_i² ≤ 2σ · n⁻¹ Σw_iΔ_i
  have h2_1_17 : (n : ℝ)⁻¹ * ∑ i, Δ i^2 ≤ 2 * M.σ * ((n : ℝ)⁻¹ * ∑ i, w i * Δ i) := by
    have h := mul_le_mul_of_nonneg_left h2_1_15 (le_of_lt h2_1_2)
    calc (n : ℝ)⁻¹ * ∑ i, Δ i^2
        ≤ (n : ℝ)⁻¹ * (2 * M.σ * ∑ i, w i * Δ i) := h
      _ = 2 * M.σ * ((n : ℝ)⁻¹ * ∑ i, w i * Δ i) := by ring

  -- ‖Δ‖_n² ≤ (2σ/n) Σw_iΔ_i
  have h2_1_18 : (empiricalNorm n Δ)^2 ≤ 2 * M.σ / n * ∑ i, w i * Δ i := by
    rw [h2_1_16]
    calc (n : ℝ)⁻¹ * ∑ i, Δ i^2
        ≤ 2 * M.σ * ((n : ℝ)⁻¹ * ∑ i, w i * Δ i) := h2_1_17
      _ = 2 * M.σ / n * ∑ i, w i * Δ i := by
          rw [div_eq_mul_inv]
          ring

  -- (1/2)‖Δ‖_n² ≤ (σ/n) Σw_iΔ_i
  calc (1 / 2) * (empiricalNorm n Δ)^2
      ≤ (1 / 2) * (2 * M.σ / n * ∑ i, w i * Δ i) := by
        apply mul_le_mul_of_nonneg_left h2_1_18
        linarith
    _ = M.σ / n * ∑ i, w i * Δ i := by ring

end LeastSquares
