/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.LeastSquares.LinearRegression.LocalizedBall
import SLT.LeastSquares.DudleyApplication

/-!
# Empirical Process Properties for Linear Predictors

This file proves integrability and measurability properties of empirical processes
restricted to the linear predictor class.

## Main Results

* `linear_innerProductProcess_continuous`: Inner product process is continuous on localized ball image
* `linear_empiricalProcess_sup_integrable_pos`: Positive supremum is integrable
* `linear_empiricalProcess_sup_integrable_neg`: Negative supremum is integrable

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set GaussianMeasure
open scoped NNReal ENNReal

namespace LeastSquares

variable {n d : ℕ}

/-- Inner product process is continuous when restricted to the linear localized ball image. -/
lemma linear_innerProductProcess_continuous
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (w : Fin n → ℝ) :
    Continuous (fun (v : ↥(linearLocalizedBallImage n d δ x)) => innerProductProcess n v.1 w) := by
  -- innerProductProcess is continuous on all of EmpiricalSpace n
  have hcont := innerProductProcess_continuous_v n w
  -- Restriction to a subtype is continuous if the original function is continuous
  exact hcont.comp continuous_subtype_val

/-- Helper: BddAbove for conditional iSup of transformed empirical process.
    Used for both positive and negative cases. -/
lemma linear_empiricalProcess_bddAbove (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (transform : ℝ → ℝ) (h_transform : ∀ y, transform y ≤ |y|) (w : Fin n → ℝ) :
    BddAbove (Set.range fun g => ⨆ (_ : g ∈ localizedBall (linearPredictorClass d) δ x),
      transform (empiricalProcess n x g w)) := by
  use δ / Real.sqrt n * euclideanNorm n w
  intro r hr; simp only [Set.mem_range] at hr; obtain ⟨g, rfl⟩ := hr
  by_cases hg : g ∈ localizedBall (linearPredictorClass d) δ x
  · simp only [ciSup_pos hg]
    calc transform (empiricalProcess n x g w) ≤ |empiricalProcess n x g w| := h_transform _
      _ ≤ δ / Real.sqrt n * euclideanNorm n w := empiricalProcess_le_delta_norm n hn x (linearPredictorClass d) δ hδ g hg w
  · rw [ciSup_neg hg, Real.sSup_empty]
    apply mul_nonneg (div_nonneg (le_of_lt hδ) (Real.sqrt_nonneg _)) (euclideanNorm_nonneg _ _)

/-- Helper: AEStronglyMeasurable for biSup of transformed empirical process via lower semicontinuity. -/
lemma linear_empiricalProcess_sup_aestronglyMeasurable (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (transform : ℝ → ℝ) (h_transform : ∀ y, transform y ≤ |y|)
    (h_cont : Continuous transform) :
    AEStronglyMeasurable (fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x,
      transform (empiricalProcess n x g w)) (stdGaussianPi n) := by
  set F := fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x, transform (empiricalProcess n x g w) with hF_def
  set f : ((EuclideanSpace ℝ (Fin d)) → ℝ) → (Fin n → ℝ) → ℝ := fun g w =>
    ⨆ (_ : g ∈ localizedBall (linearPredictorClass d) δ x), transform (empiricalProcess n x g w) with hf_def
  have h_bdd : ∀ w, BddAbove (Set.range fun g => f g w) := fun w => by
    simpa only [hf_def] using linear_empiricalProcess_bddAbove hn x hδ transform h_transform w
  have h_lsc : LowerSemicontinuous F := by
    rw [hF_def]
    have heq : (fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x, transform (empiricalProcess n x g w)) =
        fun w => ⨆ g, f g w := by ext w; simp only [hf_def]
    rw [heq]
    apply lowerSemicontinuous_ciSup h_bdd
    intro g; simp only [hf_def]
    by_cases hg : g ∈ localizedBall (linearPredictorClass d) δ x
    · have heq2 : (fun w => ⨆ (_ : g ∈ localizedBall (linearPredictorClass d) δ x), transform (empiricalProcess n x g w)) =
          (fun w => transform (empiricalProcess n x g w)) := by ext w; exact ciSup_pos hg
      rw [heq2]
      apply Continuous.lowerSemicontinuous
      apply h_cont.comp
      unfold empiricalProcess
      apply continuous_const.mul
      apply continuous_finset_sum _ (fun i _ => continuous_apply i |>.mul continuous_const)
    · have heq2 : (fun w => ⨆ (_ : g ∈ localizedBall (linearPredictorClass d) δ x), transform (empiricalProcess n x g w)) =
          fun _ => (0 : ℝ) := by ext w; rw [ciSup_neg hg, Real.sSup_empty]
      rw [heq2]; exact lowerSemicontinuous_const
  exact h_lsc.measurable.aestronglyMeasurable

/-- Helper: Integrability of biSup of transformed empirical process when transform(0)=0 and transform(y)≤|y|. -/
lemma linear_empiricalProcess_sup_integrable_of_transform (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ)
    (transform : ℝ → ℝ) (h_transform_zero : transform 0 = 0) (h_transform_le : ∀ y, transform y ≤ |y|)
    (h_cont : Continuous transform) :
    Integrable (fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x,
      transform (empiricalProcess n x g w)) (stdGaussianPi n) := by
  have hstar : IsStarShaped (linearPredictorClass d) := linearPredictorClass_isStarShaped
  have hint := localGaussianComplexity_integrand_integrable n (linearPredictorClass d) δ hδ x
  have h0 : (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ localizedBall (linearPredictorClass d) δ x :=
    zero_mem_localizedBall_of_starShaped n (linearPredictorClass d) δ (le_of_lt hδ) x hstar
  -- The supremum is non-negative (since 0 ∈ ball and transform(Z(0)) = transform(0) = 0)
  have h_sup_nonneg : ∀ w, 0 ≤ ⨆ g ∈ localizedBall (linearPredictorClass d) δ x, transform (empiricalProcess n x g w) := by
    intro w
    have hZ0 : transform (empiricalProcess n x 0 w) = 0 := by simp [empiricalProcess, h_transform_zero]
    have hbdd := linear_empiricalProcess_bddAbove hn x hδ transform h_transform_le w
    calc (0 : ℝ) = transform (empiricalProcess n x 0 w) := hZ0.symm
      _ = ⨆ (_ : (0 : (EuclideanSpace ℝ (Fin d)) → ℝ) ∈ localizedBall (linearPredictorClass d) δ x),
          transform (empiricalProcess n x 0 w) := by simp [h0]
      _ ≤ ⨆ g ∈ localizedBall (linearPredictorClass d) δ x, transform (empiricalProcess n x g w) := le_ciSup hbdd 0
  have h_aesm := linear_empiricalProcess_sup_aestronglyMeasurable hn x hδ transform h_transform_le h_cont
  apply hint.mono h_aesm
  filter_upwards with w
  have h_sup_abs_nonneg : 0 ≤ ⨆ g ∈ localizedBall (linearPredictorClass d) δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| :=
    Real.iSup_nonneg (fun g => Real.iSup_nonneg (fun _ => abs_nonneg _))
  rw [Real.norm_eq_abs, abs_of_nonneg (h_sup_nonneg w), Real.norm_eq_abs, abs_of_nonneg h_sup_abs_nonneg]
  apply Real.iSup_le _ h_sup_abs_nonneg
  intro g
  apply Real.iSup_le _ h_sup_abs_nonneg
  intro hg
  have hbdd : BddAbove (Set.range fun g' => ⨆ (_ : g' ∈ localizedBall (linearPredictorClass d) δ x),
      |(n : ℝ)⁻¹ * ∑ i, w i * g' (x i)|) := by
    use δ / Real.sqrt n * euclideanNorm n w
    intro r hr; simp only [Set.mem_range] at hr; obtain ⟨g', rfl⟩ := hr
    by_cases hg' : g' ∈ localizedBall (linearPredictorClass d) δ x
    · simp only [ciSup_pos hg']; exact empiricalProcess_le_delta_norm n hn x (linearPredictorClass d) δ hδ g' hg' w
    · rw [ciSup_neg hg', Real.sSup_empty]
      apply mul_nonneg (div_nonneg (le_of_lt hδ) (Real.sqrt_nonneg _)) (euclideanNorm_nonneg _ _)
  calc transform (empiricalProcess n x g w)
      ≤ |empiricalProcess n x g w| := h_transform_le _
    _ = |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := rfl
    _ = ⨆ (_ : g ∈ localizedBall (linearPredictorClass d) δ x), |(n : ℝ)⁻¹ * ∑ i, w i * g (x i)| := by simp [hg]
    _ ≤ ⨆ g' ∈ localizedBall (linearPredictorClass d) δ x, |(n : ℝ)⁻¹ * ∑ i, w i * g' (x i)| := le_ciSup hbdd g

/-- The supremum of empirical process (positive direction) is integrable for linear predictors. -/
lemma linear_empiricalProcess_sup_integrable_pos (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ) :
    Integrable (fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x,
      empiricalProcess n x g w) (stdGaussianPi n) :=
  linear_empiricalProcess_sup_integrable_of_transform hn x hδ id (by simp) le_abs_self continuous_id

/-- The supremum of negative empirical process is integrable for linear predictors. -/
lemma linear_empiricalProcess_sup_integrable_neg (hn : 0 < n)
    (x : Fin n → EuclideanSpace ℝ (Fin d)) {δ : ℝ} (hδ : 0 < δ) :
    Integrable (fun w => ⨆ g ∈ localizedBall (linearPredictorClass d) δ x,
      -empiricalProcess n x g w) (stdGaussianPi n) :=
  linear_empiricalProcess_sup_integrable_of_transform hn x hδ Neg.neg neg_zero neg_le_abs continuous_neg

end LeastSquares
