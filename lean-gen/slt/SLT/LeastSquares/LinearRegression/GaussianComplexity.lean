/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.LinearRegression.EntropyIntegral
import SLT.LeastSquares.LinearRegression.EmpiricalProcess

/-!
# Gaussian Complexity Bound for Linear Predictors

This file proves the main local Gaussian complexity bound for linear predictors.

## Main Results

* `linear_local_gaussian_complexity_bound`: The local Gaussian complexity of the linear predictor
  class at radius δ satisfies G_n(δ) ≤ (96 · √2) · δ · √d / √n

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-- Main theorem: Linear local Gaussian complexity bound.

The local Gaussian complexity of the linear predictor class at radius δ satisfies:
  G_n(δ) ≤ (96 · √2) · δ · √d / √n

This follows from:
1. The general local_gaussian_complexity_bound which gives G_n(δ) ≤ (24√2)/√n · entropyIntegral
2. The linearEntropyIntegral_le which bounds entropyIntegral < 4δ√d
3. Combining: G_n(δ) ≤ (24√2)/√n · 4δ√d = (96√2)·δ·√d/√n
-/
theorem linear_local_gaussian_complexity_bound (n d : ℕ) (hn : 0 < n) (hd : 0 < d)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hinj : Function.Injective (designMatrixMul x)) :
    LocalGaussianComplexity n (linearPredictorClass d) δ x ≤
    (96 * Real.sqrt 2) * δ * Real.sqrt d / Real.sqrt n := by
  -- Step 1: Apply local_gaussian_complexity_bound
  have h1 := local_gaussian_complexity_bound n hn (linearPredictorClass d) δ hδ x
    linearPredictorClass_isStarShaped
    (by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linearLocalizedBallImage_totallyBounded hn x δ)
    (by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linearEntropyIntegralENNReal_ne_top hn hd x hδ hinj)
    (fun w => by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linear_innerProductProcess_continuous x w)
    (linear_empiricalProcess_sup_integrable_pos hn x hδ)
    (linear_empiricalProcess_sup_integrable_neg hn x hδ)
  -- Step 2: Get the entropy integral bound
  have h2 := linearEntropyIntegral_le hn hd x hδ hinj
  -- Step 3: Connect linearEntropyIntegral to entropyIntegral
  have heq : linearEntropyIntegral n d δ (2*δ) x =
      entropyIntegral (empiricalMetricImage n x '' localizedBall (linearPredictorClass d) δ x) (2*δ) := by
    unfold linearEntropyIntegral
    rw [← linearLocalizedBallImage_eq_empiricalImage]
  rw [heq] at h2
  -- Step 4: Combine bounds
  calc LocalGaussianComplexity n (linearPredictorClass d) δ x
      ≤ (24 * Real.sqrt 2) / Real.sqrt n *
          entropyIntegral (empiricalMetricImage n x '' localizedBall (linearPredictorClass d) δ x) (2*δ) := h1
    _ ≤ (24 * Real.sqrt 2) / Real.sqrt n * (4 * δ * Real.sqrt d) := by
        apply mul_le_mul_of_nonneg_left (le_of_lt h2)
        apply div_nonneg _ (Real.sqrt_nonneg n)
        apply mul_nonneg (by norm_num : (0 : ℝ) ≤ 24) (Real.sqrt_nonneg 2)
    _ = (96 * Real.sqrt 2) * δ * Real.sqrt d / Real.sqrt n := by ring

/-- Rank-based linear local Gaussian complexity bound.

The local Gaussian complexity of the linear predictor class at radius δ satisfies:
  G_n(δ) ≤ (96 · √2) · δ · √r / √n

where r = designMatrixRank x is the rank of the design matrix.

This generalizes `linear_local_gaussian_complexity_bound` by replacing the full-rank
assumption `hinj` with the weaker assumption `0 < designMatrixRank x`.
-/
theorem linear_local_gaussian_complexity_bound_rank (n d : ℕ) (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (hr : 0 < designMatrixRank x) :
    LocalGaussianComplexity n (linearPredictorClass d) δ x ≤
    (96 * Real.sqrt 2) * δ * Real.sqrt (designMatrixRank x) / Real.sqrt n := by
  -- Step 1: Apply local_gaussian_complexity_bound
  have h1 := local_gaussian_complexity_bound n hn (linearPredictorClass d) δ hδ x
    linearPredictorClass_isStarShaped
    (by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linearLocalizedBallImage_totallyBounded hn x δ)
    (by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linearEntropyIntegralENNReal_rank_ne_top hn x hδ hr)
    (fun w => by rw [← linearLocalizedBallImage_eq_empiricalImage]; exact linear_innerProductProcess_continuous x w)
    (linear_empiricalProcess_sup_integrable_pos hn x hδ)
    (linear_empiricalProcess_sup_integrable_neg hn x hδ)
  -- Step 2: Get the entropy integral bound using rank
  have h2 := linearEntropyIntegral_rank_le hn x hδ hr
  -- Step 3: Connect linearEntropyIntegral to entropyIntegral
  have heq : linearEntropyIntegral n d δ (2*δ) x =
      entropyIntegral (empiricalMetricImage n x '' localizedBall (linearPredictorClass d) δ x) (2*δ) := by
    unfold linearEntropyIntegral
    rw [← linearLocalizedBallImage_eq_empiricalImage]
  rw [heq] at h2
  -- Step 4: Combine bounds
  calc LocalGaussianComplexity n (linearPredictorClass d) δ x
      ≤ (24 * Real.sqrt 2) / Real.sqrt n *
          entropyIntegral (empiricalMetricImage n x '' localizedBall (linearPredictorClass d) δ x) (2*δ) := h1
    _ ≤ (24 * Real.sqrt 2) / Real.sqrt n * (4 * δ * Real.sqrt (designMatrixRank x)) := by
        apply mul_le_mul_of_nonneg_left (le_of_lt h2)
        apply div_nonneg _ (Real.sqrt_nonneg n)
        apply mul_nonneg (by norm_num : (0 : ℝ) ≤ 24) (Real.sqrt_nonneg 2)
    _ = (96 * Real.sqrt 2) * δ * Real.sqrt (designMatrixRank x) / Real.sqrt n := by ring

end LeastSquares
