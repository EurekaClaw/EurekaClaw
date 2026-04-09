/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianSobolevDense.Mollification

/-!
# Lipschitz Properties of Mollification

This file proves that mollification preserves Lipschitz constants for general Lipschitz functions
(continuous but not necessarily differentiable).

## Main Results

* `mollify_lipschitzWith` - Mollification preserves Lipschitz constant: if f is L-Lipschitz,
  then mollify ε f is also L-Lipschitz
* `mollify_smooth_of_lipschitz` - Mollification of a Lipschitz function is smooth (C^∞)
* `sup_norm_fderiv_le_of_mollify_lipschitz` - Gradient bound: ‖∇(mollify ε f)‖ ≤ L
* `mollify_dist_le_of_lipschitz'` - Explicit O(ε) rate: |f_ε(x) - f(x)| ≤ L·ε·√n
* `mollify_tendsto_of_lipschitz` - Pointwise convergence: mollify ε f x → f x as ε → 0

## Application

These lemmas enable proving Gaussian Lipschitz concentration via:
1. Approximate L-Lipschitz f by smooth f_ε with ‖∇f_ε‖ ≤ L
2. Apply Gaussian Poincaré/LSI to f_ε
3. Take limit ε → 0

-/

open MeasureTheory ProbabilityTheory Filter Topology
open scoped ENNReal NNReal Topology Convolution

namespace GaussianSobolev

variable {n : ℕ}

/-! ### Auxiliary Integrability Lemmas -/

/-- Helper: f(x - ·) * ρ_ε is integrable when f is continuous and ρ_ε has compact support. -/
lemma mollify_integrand_integrable {f : E n → ℝ} (hf_cont : Continuous f)
    {ε : ℝ} (hε : 0 < ε) (x : E n) :
    Integrable (fun y => f (x - y) * stdMollifierPi n ε y) volume := by
  have hf_sub_cont : Continuous (fun y => f (x - y)) := hf_cont.comp (continuous_sub_left x)
  have hprod_cont : Continuous (fun y => f (x - y) * stdMollifierPi n ε y) :=
    hf_sub_cont.mul (stdMollifierPi_contDiff hε).continuous
  have hprod_supp : HasCompactSupport (fun y => f (x - y) * stdMollifierPi n ε y) :=
    (stdMollifierPi_hasCompactSupport hε).mul_left
  exact hprod_cont.integrable_of_hasCompactSupport hprod_supp

/-- Helper: constant * ρ_ε is integrable. -/
lemma mollify_const_integrable {c : ℝ} {ε : ℝ} (hε : 0 < ε) :
    Integrable (fun y : E n => c * stdMollifierPi n ε y) volume :=
  Integrable.const_mul ((stdMollifierPi_contDiff hε).continuous.integrable_of_hasCompactSupport
    (stdMollifierPi_hasCompactSupport hε)) c

/-! ### Lipschitz Preservation under Mollification -/

/-- Mollification preserves Lipschitz constant. -/
lemma mollify_lipschitzWith {f : E n → ℝ} {L : ℝ≥0} {ε : ℝ} (hε : 0 < ε)
    (hf : LipschitzWith L f) : LipschitzWith L (mollify ε f) :=
  LipschitzWith.of_dist_le_mul fun x y => by
    -- mollify ε f x - mollify ε f y = ∫ [f(x-z) - f(y-z)] ρ_ε(z) dz
    simp only [mollify]
    -- |∫ [f(x-z) - f(y-z)] ρ_ε(z) dz| ≤ ∫ |f(x-z) - f(y-z)| ρ_ε(z) dz
    calc dist (∫ z, f (x - z) * stdMollifierPi n ε z) (∫ z, f (y - z) * stdMollifierPi n ε z)
        = ‖(∫ z, f (x - z) * stdMollifierPi n ε z) - (∫ z, f (y - z) * stdMollifierPi n ε z)‖ := by
          rw [dist_eq_norm]
      _ = ‖∫ z, f (x - z) * stdMollifierPi n ε z - f (y - z) * stdMollifierPi n ε z‖ := by
          rw [integral_sub (mollify_integrand_integrable hf.continuous hε x)
              (mollify_integrand_integrable hf.continuous hε y)]
      _ = ‖∫ z, (f (x - z) - f (y - z)) * stdMollifierPi n ε z‖ := by
          congr 1
          apply integral_congr_ae
          filter_upwards with z
          ring
      _ ≤ ∫ z, ‖(f (x - z) - f (y - z)) * stdMollifierPi n ε z‖ :=
          norm_integral_le_integral_norm _
      _ = ∫ z, |f (x - z) - f (y - z)| * stdMollifierPi n ε z := by
          congr 1; funext z
          rw [Real.norm_eq_abs, abs_mul, abs_of_nonneg (stdMollifierPi_nonneg ε hε z)]
      _ ≤ ∫ z, (L : ℝ) * dist x y * stdMollifierPi n ε z := by
          apply integral_mono_of_nonneg
          · exact ae_of_all _ fun z => mul_nonneg (abs_nonneg _) (stdMollifierPi_nonneg ε hε z)
          · exact mollify_const_integrable hε
          · apply ae_of_all _
            intro z
            have h_lip : dist (f (x - z)) (f (y - z)) ≤ L * dist (x - z) (y - z) :=
              hf.dist_le_mul (x - z) (y - z)
            have h_eq : dist (x - z) (y - z) = dist x y := by
              simp only [dist_eq_norm]
              congr 1
              abel
            rw [h_eq] at h_lip
            calc |f (x - z) - f (y - z)| * stdMollifierPi n ε z
                = dist (f (x - z)) (f (y - z)) * stdMollifierPi n ε z := by
                  rw [Real.dist_eq]
              _ ≤ (L : ℝ) * dist x y * stdMollifierPi n ε z := by
                  apply mul_le_mul_of_nonneg_right h_lip (stdMollifierPi_nonneg ε hε z)
      _ = (L : ℝ) * dist x y * ∫ z, stdMollifierPi n ε z := by
          rw [MeasureTheory.integral_const_mul]
      _ = (L : ℝ) * dist x y := by
          rw [stdMollifierPi_integral_eq_one hε, mul_one]

/-- Mollification of a Lipschitz function is smooth (C^∞). -/
lemma mollify_smooth_of_lipschitz {f : E n → ℝ} {L : ℝ≥0}
    (hf : LipschitzWith L f) {ε : ℝ} (hε : 0 < ε) :
    ContDiff ℝ (⊤ : ℕ∞) (mollify ε f) := by
  have h_int : LocallyIntegrable f volume := hf.continuous.locallyIntegrable
  rw [mollify_eq_convolution f]
  apply HasCompactSupport.contDiff_convolution_right mulLR
  · exact stdMollifierPi_hasCompactSupport hε
  · exact h_int
  · exact stdMollifierPi_contDiff hε

/-- Gradient of mollified Lipschitz function is uniformly bounded by the Lipschitz constant. -/
lemma sup_norm_fderiv_le_of_mollify_lipschitz {f : E n → ℝ} {L : ℝ≥0} {ε : ℝ}
    (hε : 0 < ε) (hf : LipschitzWith L f) (x : E n) :
    ‖fderiv ℝ (mollify ε f) x‖ ≤ L := by
  -- mollify ε f is L-Lipschitz
  have h_lip : LipschitzWith L (mollify ε f) := mollify_lipschitzWith hε hf
  -- Lipschitz constant bounds gradient
  exact norm_fderiv_le_of_lipschitz ℝ h_lip

/-! ### Quantitative Convergence Rate -/

/-- First moment of the standard mollifier (finite constant depending on dimension).
This is ∫ ‖z‖ * ρ₁(z) dz where ρ₁ is the unit-scale mollifier. -/
noncomputable def mollifierFirstMoment (n : ℕ) : ℝ :=
  ∫ z : E n, ‖z‖ * stdMollifierPi n 1 z

/-- The first moment of the mollifier is finite and nonnegative. -/
lemma mollifierFirstMoment_nonneg : 0 ≤ mollifierFirstMoment n := by
  unfold mollifierFirstMoment
  apply integral_nonneg
  intro z
  exact mul_nonneg (norm_nonneg _) (stdMollifierPi_nonneg 1 one_pos z)

/-- Integrability of ‖z‖ * ρ_ε(z) (the mollifier has compact support). -/
lemma integrable_norm_mul_stdMollifierPi {ε : ℝ} (hε : 0 < ε) :
    Integrable (fun z : E n => ‖z‖ * stdMollifierPi n ε z) volume := by
  -- ‖z‖ * ρ_ε(z) is continuous
  have h_cont : Continuous (fun z : E n => ‖z‖ * stdMollifierPi n ε z) :=
    continuous_norm.mul (stdMollifierPi_contDiff hε).continuous
  -- The support is contained in the support of ρ_ε which is compact
  have h_supp : HasCompactSupport (fun z : E n => ‖z‖ * stdMollifierPi n ε z) :=
    (stdMollifierPi_hasCompactSupport hε).mul_left
  exact h_cont.integrable_of_hasCompactSupport h_supp

/-- Quantitative mollification approximation error for Lipschitz functions. -/
theorem mollify_dist_le_of_lipschitz {f : E n → ℝ} {L : ℝ≥0} {ε : ℝ}
    (hε : 0 < ε) (hf : LipschitzWith L f) (x : E n) :
    dist (mollify ε f x) (f x) ≤ L * ∫ z : E n, ‖z‖ * stdMollifierPi n ε z := by
  -- f_ε(x) - f(x) = ∫ [f(x-z) - f(x)] ρ_ε(z) dz  (using ∫ρ_ε = 1)
  have h_int_one := stdMollifierPi_integral_eq_one (n := n) hε
  rw [dist_eq_norm]
  -- Unfold mollify and work with the explicit integral
  show ‖mollify ε f x - f x‖ ≤ _
  simp only [mollify]
  calc ‖(∫ y, f (x - y) * stdMollifierPi n ε y) - f x‖
      = ‖(∫ z, f (x - z) * stdMollifierPi n ε z) - f x * ∫ z, stdMollifierPi n ε z‖ := by
        rw [h_int_one, mul_one]
    _ = ‖(∫ z, f (x - z) * stdMollifierPi n ε z) - ∫ z, f x * stdMollifierPi n ε z‖ := by
        rw [MeasureTheory.integral_const_mul]
    _ = ‖∫ z, (f (x - z) - f x) * stdMollifierPi n ε z‖ := by
        rw [← integral_sub (mollify_integrand_integrable hf.continuous hε x)
            (mollify_const_integrable hε)]
        congr 1
        apply integral_congr_ae
        filter_upwards with z
        ring
    _ ≤ ∫ z, ‖(f (x - z) - f x) * stdMollifierPi n ε z‖ := norm_integral_le_integral_norm _
    _ = ∫ z, |f (x - z) - f x| * stdMollifierPi n ε z := by
        congr 1; funext z
        rw [Real.norm_eq_abs, abs_mul, abs_of_nonneg (stdMollifierPi_nonneg ε hε z)]
    _ ≤ ∫ z, (L : ℝ) * (‖z‖ * stdMollifierPi n ε z) := by
        apply integral_mono_of_nonneg
        · exact ae_of_all _ fun z => mul_nonneg (abs_nonneg _) (stdMollifierPi_nonneg ε hε z)
        · exact Integrable.const_mul (integrable_norm_mul_stdMollifierPi hε) L
        · apply ae_of_all _
          intro z
          have h_lip : dist (f (x - z)) (f x) ≤ L * dist (x - z) x := hf.dist_le_mul (x - z) x
          simp only [dist_eq_norm, sub_sub_cancel_left, norm_neg] at h_lip
          calc |f (x - z) - f x| * stdMollifierPi n ε z
              = dist (f (x - z)) (f x) * stdMollifierPi n ε z := by rw [Real.dist_eq]
            _ ≤ (L : ℝ) * ‖z‖ * stdMollifierPi n ε z := by
                apply mul_le_mul_of_nonneg_right h_lip (stdMollifierPi_nonneg ε hε z)
            _ = (L : ℝ) * (‖z‖ * stdMollifierPi n ε z) := by ring
    _ = (L : ℝ) * ∫ z, ‖z‖ * stdMollifierPi n ε z := by
        rw [MeasureTheory.integral_const_mul]

/-! ### Convergence as ε → 0 -/

/-- The first moment integral ∫ ‖z‖ * ρ_ε(z) dz is bounded by ε * √n.

On the support of ρ_ε (contained in closedBall 0 (ε√n)), we have ‖z‖ ≤ ε√n.
Since ∫ ρ_ε = 1, we get ∫ ‖z‖ * ρ_ε ≤ ε√n. -/
lemma integral_norm_mul_stdMollifierPi_le {ε : ℝ} (hε : 0 < ε) :
    ∫ z : E n, ‖z‖ * stdMollifierPi n ε z ≤ ε * Real.sqrt n := by
  calc ∫ z : E n, ‖z‖ * stdMollifierPi n ε z
      ≤ ∫ z : E n, (ε * Real.sqrt n) * stdMollifierPi n ε z := by
        apply integral_mono_of_nonneg
        · exact ae_of_all _ fun z => mul_nonneg (norm_nonneg _) (stdMollifierPi_nonneg ε hε z)
        · exact mollify_const_integrable hε
        · apply ae_of_all _
          intro z
          by_cases hz : z ∈ tsupport (stdMollifierPi n ε)
          · -- On the support, ‖z‖ ≤ ε * √n
            have h_in_ball := stdMollifierPi_tsupport_subset hε hz
            rw [Metric.mem_closedBall, dist_zero_right] at h_in_ball
            exact mul_le_mul_of_nonneg_right h_in_ball (stdMollifierPi_nonneg ε hε z)
          · -- Outside the support, ρ_ε(z) = 0
            have hz_zero : stdMollifierPi n ε z = 0 := by
              by_contra h
              exact hz (subset_closure (Function.mem_support.mpr h))
            simp only [hz_zero, mul_zero, le_refl]
    _ = (ε * Real.sqrt n) * ∫ z : E n, stdMollifierPi n ε z := by
        rw [MeasureTheory.integral_const_mul]
    _ = ε * Real.sqrt n := by
        rw [stdMollifierPi_integral_eq_one hε, mul_one]

/-- **Corollary (Explicit O(ε) Rate)**: Mollification error is O(ε) with explicit constants.

Combines the general bound with the first moment estimate to give:
  dist(f_ε(x), f(x)) ≤ L · ε · √n
-/
theorem mollify_dist_le_of_lipschitz' {f : E n → ℝ} {L : ℝ≥0} {ε : ℝ}
    (hε : 0 < ε) (hf : LipschitzWith L f) (x : E n) :
    dist (mollify ε f x) (f x) ≤ L * ε * Real.sqrt n := by
  calc dist (mollify ε f x) (f x)
      ≤ L * ∫ z : E n, ‖z‖ * stdMollifierPi n ε z := mollify_dist_le_of_lipschitz hε hf x
    _ ≤ L * (ε * Real.sqrt n) := by
        apply mul_le_mul_of_nonneg_left (integral_norm_mul_stdMollifierPi_le hε)
        exact NNReal.coe_nonneg L
    _ = L * ε * Real.sqrt n := by ring

/-- The first moment integral tends to 0 as ε → 0. -/
lemma tendsto_integral_norm_mul_stdMollifierPi :
    Filter.Tendsto (fun ε => ∫ z : E n, ‖z‖ * stdMollifierPi n ε z)
      (nhdsWithin 0 (Set.Ioi 0)) (nhds 0) := by
  rw [Metric.tendsto_nhdsWithin_nhds]
  intro δ hδ
  -- Choose ε₀ such that ε₀ * √n < δ
  use δ / (Real.sqrt n + 1)
  constructor
  · positivity
  · intro ε hε_mem hε_dist
    have hε_pos : 0 < ε := hε_mem
    rw [Real.dist_0_eq_abs, abs_of_nonneg (integral_nonneg fun z =>
        mul_nonneg (norm_nonneg _) (stdMollifierPi_nonneg ε hε_pos z))]
    have hε_small : ε < δ / (Real.sqrt n + 1) := by
      rw [dist_zero_right, Real.norm_eq_abs, abs_of_pos hε_pos] at hε_dist
      exact hε_dist
    have h_sqrt_bound : Real.sqrt n ≤ Real.sqrt n + 1 := by linarith
    calc ∫ z : E n, ‖z‖ * stdMollifierPi n ε z
        ≤ ε * Real.sqrt n := integral_norm_mul_stdMollifierPi_le hε_pos
      _ ≤ ε * (Real.sqrt n + 1) := by
          apply mul_le_mul_of_nonneg_left h_sqrt_bound (le_of_lt hε_pos)
      _ < (δ / (Real.sqrt n + 1)) * (Real.sqrt n + 1) := by
          apply mul_lt_mul_of_pos_right hε_small
          have : 0 ≤ Real.sqrt n := Real.sqrt_nonneg n
          linarith
      _ = δ := by field_simp

/-- Mollification of a Lipschitz function converges pointwise as ε → 0.

This is a direct consequence of the quantitative bound:
  dist (mollify ε f x) (f x) ≤ L * ∫ ‖z‖ * ρ_ε(z) dz → 0
-/
theorem mollify_tendsto_of_lipschitz {f : E n → ℝ} {L : ℝ≥0}
    (hf : LipschitzWith L f) (x : E n) :
    Filter.Tendsto (fun ε => mollify ε f x) (nhdsWithin 0 (Set.Ioi 0)) (nhds (f x)) := by
  rw [Metric.tendsto_nhdsWithin_nhds]
  intro δ hδ
  -- Use the convergence of the first moment integral
  have h_int_tendsto := tendsto_integral_norm_mul_stdMollifierPi (n := n)
  rw [Metric.tendsto_nhdsWithin_nhds] at h_int_tendsto
  -- Get ε₀ such that L * ∫ ‖z‖ * ρ_ε < δ for ε < ε₀
  obtain ⟨ε₀, hε₀_pos, hε₀_bound⟩ := h_int_tendsto (δ / (L + 1)) (by positivity)
  use ε₀
  constructor
  · exact hε₀_pos
  · intro ε hε_mem hε_dist
    have hε_pos : 0 < ε := hε_mem
    have h_int_small := hε₀_bound hε_mem hε_dist
    rw [Real.dist_0_eq_abs, abs_of_nonneg (integral_nonneg fun z =>
        mul_nonneg (norm_nonneg _) (stdMollifierPi_nonneg ε hε_pos z))] at h_int_small
    have hL1_pos : (0 : ℝ) < (L : ℝ) + 1 := by positivity
    calc dist (mollify ε f x) (f x)
        ≤ L * ∫ z : E n, ‖z‖ * stdMollifierPi n ε z := mollify_dist_le_of_lipschitz hε_pos hf x
      _ ≤ (↑L + 1) * ∫ z : E n, ‖z‖ * stdMollifierPi n ε z := by
          apply mul_le_mul_of_nonneg_right _ (integral_nonneg fun z =>
              mul_nonneg (norm_nonneg _) (stdMollifierPi_nonneg ε hε_pos z))
          linarith
      _ < (↑L + 1) * (δ / (↑L + 1)) := by
          apply mul_lt_mul_of_pos_left h_int_small hL1_pos
      _ = δ := by field_simp

end GaussianSobolev
