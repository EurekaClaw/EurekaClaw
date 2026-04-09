/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianMeasure

open MeasureTheory ProbabilityTheory Real Finset BigOperators Function

namespace LipschitzConcentration

variable {n : ℕ}

/-!
Basic Properties of Lipschitz Functions
-/

/-- Lipschitz functions are measurable (via continuity) -/
lemma lipschitz_measurable (f : (Fin n → ℝ) → ℝ) (L : ℝ)
    (hf : LipschitzWith (Real.toNNReal L) f) :
    Measurable f :=
  hf.continuous.measurable

/-- Lipschitz functions have linear growth -/
lemma lipschitz_linear_growth (f : (Fin n → ℝ) → ℝ) (L : ℝ) (hL : 0 ≤ L)
    (hf : LipschitzWith (Real.toNNReal L) f) (w : Fin n → ℝ) :
    |f w| ≤ |f 0| + L * ‖w‖ := by
  have h1 : |f w - f 0| ≤ L * ‖w - 0‖ := by
    have := hf.dist_le_mul w 0
    simp only [Real.dist_eq] at this
    calc |f w - f 0| ≤ ↑(Real.toNNReal L) * dist w 0 := this
      _ = L * dist w 0 := by rw [Real.coe_toNNReal L hL]
      _ = L * ‖w - 0‖ := by rw [dist_eq_norm]
  calc |f w| = |f w - f 0 + f 0| := by ring_nf
    _ ≤ |f w - f 0| + |f 0| := abs_add_le _ _
    _ ≤ L * ‖w - 0‖ + |f 0| := by linarith
    _ = |f 0| + L * ‖w‖ := by simp only [sub_zero]; ring

/-- Absolute value of coordinate is integrable -/
lemma integrable_abs_eval_stdGaussianPi (i : Fin n) :
    Integrable (fun w : Fin n → ℝ => |w i|) (GaussianMeasure.stdGaussianPi n) := by
  exact (GaussianMeasure.integrable_eval_stdGaussianPi i).abs

/-- Integrability of exp(t * |w_i|) under stdGaussianPi.
Key insight: exp(t * |x|) ≤ exp(t * x) + exp(-t * x) -/
lemma integrable_exp_mul_abs_eval_stdGaussianPi (t : ℝ) (i : Fin n) :
    Integrable (fun w : Fin n → ℝ => exp (t * |w i|)) (GaussianMeasure.stdGaussianPi n) := by
  -- exp(t * |x|) ≤ exp(t * x) + exp(-t * x) for all x
  have h_bound : ∀ w : Fin n → ℝ, exp (t * |w i|) ≤ exp (t * w i) + exp (-t * w i) := by
    intro w
    by_cases hx : 0 ≤ w i
    · rw [abs_of_nonneg hx]
      exact le_add_of_nonneg_right (le_of_lt (exp_pos _))
    · push_neg at hx
      rw [abs_of_neg hx]
      have h_eq : exp (t * -w i) = exp (-t * w i) := by ring_nf
      rw [h_eq]
      exact le_add_of_nonneg_left (le_of_lt (exp_pos _))
  have h_sum_int : Integrable (fun w => exp (t * w i) + exp (-t * w i)) (GaussianMeasure.stdGaussianPi n) :=
    (GaussianMeasure.integrable_exp_mul_eval_stdGaussianPi i t).add
      (GaussianMeasure.integrable_exp_mul_eval_stdGaussianPi i (-t))
  apply Integrable.mono h_sum_int
  · exact (continuous_exp.comp (continuous_const.mul (continuous_abs.comp (continuous_apply i)))).aestronglyMeasurable
  · filter_upwards with w
    simp only [Real.norm_eq_abs, abs_exp]
    have h_sum_pos : 0 ≤ exp (t * w i) + exp (-t * w i) :=
      add_nonneg (le_of_lt (exp_pos _)) (le_of_lt (exp_pos _))
    rw [abs_of_nonneg h_sum_pos]
    exact h_bound w

/-- Norm of Gaussian vector has finite moments -/
lemma norm_integrable_stdGaussianPi :
    Integrable (fun w : Fin n → ℝ => ‖w‖) (GaussianMeasure.stdGaussianPi n) := by
  -- Use ‖w‖ ≤ Σᵢ |wᵢ| for pi-norm (sup norm)
  apply Integrable.mono (integrable_finset_sum Finset.univ (fun i _ => integrable_abs_eval_stdGaussianPi i))
  · exact continuous_norm.aestronglyMeasurable
  · filter_upwards with w
    simp only [Real.norm_eq_abs]
    have h_sum_nonneg : 0 ≤ ∑ i : Fin n, |w i| := Finset.sum_nonneg (fun i _ => abs_nonneg _)
    rw [abs_of_nonneg h_sum_nonneg, abs_of_nonneg (norm_nonneg _)]
    -- Pi norm is sup of coordinate norms: ‖w‖ = sup_i ‖w i‖
    -- We need: sup_i ‖w i‖ ≤ Σ_i |w i|
    have key : ∀ i : Fin n, ‖w i‖ ≤ ∑ j : Fin n, |w j| := fun i =>
      (Real.norm_eq_abs (w i)).symm ▸
        Finset.single_le_sum (fun j _ => abs_nonneg (w j)) (Finset.mem_univ i)
    exact pi_norm_le_iff_of_nonneg h_sum_nonneg |>.mpr key

/-- Lipschitz functions are integrable under stdGaussianPi -/
lemma lipschitz_integrable_stdGaussianPi (f : (Fin n → ℝ) → ℝ) (L : ℝ) (hL : 0 ≤ L)
    (hf : LipschitzWith (Real.toNNReal L) f) :
    Integrable f (GaussianMeasure.stdGaussianPi n) := by
  -- Use linear growth: |f(w)| ≤ |f(0)| + L‖w‖
  have h_bound : ∀ w, |f w| ≤ |f 0| + L * ‖w‖ := fun w => lipschitz_linear_growth f L hL hf w
  -- g(w) = |f(0)| + L * ‖w‖ is integrable and bounds |f|
  let g : (Fin n → ℝ) → ℝ := fun w => |f 0| + L * ‖w‖
  have hg_int : Integrable g (GaussianMeasure.stdGaussianPi n) :=
    (integrable_const (|f 0|)).add (norm_integrable_stdGaussianPi.const_mul L)
  apply Integrable.mono' hg_int hf.continuous.aestronglyMeasurable
  filter_upwards with w
  simp only [Real.norm_eq_abs]
  exact h_bound w

/-- Centered Lipschitz function (f - E[f]) -/
noncomputable def centeredLipschitz (f : (Fin n → ℝ) → ℝ) : (Fin n → ℝ) → ℝ :=
  fun w => f w - ∫ w', f w' ∂(GaussianMeasure.stdGaussianPi n)

/-- Centered function has mean zero -/
lemma integral_centeredLipschitz_eq_zero (f : (Fin n → ℝ) → ℝ) (L : ℝ) (hL : 0 ≤ L)
    (hf : LipschitzWith (Real.toNNReal L) f) :
    ∫ w, centeredLipschitz f w ∂(GaussianMeasure.stdGaussianPi n) = 0 := by
  haveI : IsProbabilityMeasure (GaussianMeasure.stdGaussianPi n) :=
    GaussianMeasure.stdGaussianPi_isProbabilityMeasure
  unfold centeredLipschitz
  rw [integral_sub (lipschitz_integrable_stdGaussianPi f L hL hf) (integrable_const _)]
  simp only [integral_const, probReal_univ, smul_eq_mul, one_mul, sub_self]

end LipschitzConcentration

