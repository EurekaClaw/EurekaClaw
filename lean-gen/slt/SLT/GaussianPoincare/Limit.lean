/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianPoincare.TaylorBound
import SLT.GaussianPoincare.LevyContinuity
import SLT.GaussianLSI.Entropy
import Mathlib.Topology.ContinuousMap.Bounded.Basic
import Mathlib.Probability.Distributions.Gaussian.Real
import Mathlib.Analysis.SpecialFunctions.Pow.Asymptotics
import Mathlib.Analysis.SpecialFunctions.Complex.LogBounds

/-!
# Gaussian Poincaré Inequality via Limit of Rademacher Sums

This file proves the Gaussian Poincaré inequality by taking the limit as n → ∞
in the Taylor expansion bound for Rademacher sums.

## Main results

* `gaussianPoincare`: For `f ∈ C_c²(ℝ)` and `X ~ N(0,1)`:
  `Var(f(X)) ≤ E[f'(X)²]`

-/

noncomputable section

open MeasureTheory ProbabilityTheory Real Filter Set Function Topology Complex
open scoped ENNReal Topology BoundedContinuousFunction

namespace GaussianPoincare

open EfronSteinApp RademacherApprox TaylorBound

/-! ### Section 0: Local definitions replacing Clt.CLT and Clt.CharFun -/

/-- The standard real Gaussian `𝓝 (0, 1)`. -/
abbrev stdGaussian : ProbabilityMeasure ℝ :=
  ⟨gaussianReal 0 1, inferInstance⟩

/-- `√·` tends to `atTop`. -/
lemma tendsto_sqrt_atTop : Tendsto (√·) atTop atTop := by
  simp_rw [Real.sqrt_eq_rpow]
  exact tendsto_rpow_atTop (by norm_num)

/-- `(1 + t/n + o(1/n)) ^ n → exp t` for `t ∈ ℂ`. -/
lemma tendsto_pow_exp_of_isLittleO {f : ℕ → ℂ} (t : ℂ)
    (hf : (fun n ↦ f n - (1 + t / n)) =o[atTop] fun n ↦ 1 / (n : ℝ)) :
    Tendsto (fun n ↦ f n ^ n) atTop (𝓝 (exp t)) := by
  let g n := f n - 1
  have fg n : f n = 1 + g n := by ring
  simp_rw [fg, add_sub_add_left_eq_sub] at hf ⊢
  apply Complex.tendsto_one_add_pow_exp_of_tendsto
  rw [← tendsto_sub_nhds_zero_iff]
  apply hf.tendsto_inv_smul_nhds_zero.congr'
  filter_upwards [eventually_ne_atTop 0] with n h0
  simpa [mul_sub] using mul_div_cancel₀ t (mod_cast h0)

/-- The characteristic function of the sum of `n` i.i.d. variables with characteristic function `f`
is `f ^ n`. We express this in terms of the pushforward of the product measure by summation. -/
lemma charFun_map_sum_pi_const (μ : Measure ℝ) [IsFiniteMeasure μ] (n : ℕ) (t : ℝ) :
    charFun ((Measure.pi fun (_ : Fin n) ↦ μ).map fun x ↦ ∑ i, x i) t = charFun μ t ^ n := by
  induction n with
  | zero => simp [Measure.map_const, charFun_apply]
  | succ n ih =>
    rw [pow_succ', ← ih, ← charFun_conv]
    congr 1
    have h := (measurePreserving_piFinSuccAbove (fun (_ : Fin (n + 1)) ↦ μ) 0).map_eq
    nth_rw 2 [← μ.map_id]
    rw [Measure.conv, Measure.map_prod_map, ← h, Measure.map_map, Measure.map_map]
    · congr 1 with x
      apply Fin.sum_univ_succ
    all_goals { fun_prop }

/-! ### Section 1: Law of the Rademacher Sum -/

/-- The law of the Rademacher sum Sₙ under the n-fold product measure.
This is the pushforward of `rademacherProductMeasure n` under `rademacherSumProd n`. -/
def rademacherLaw (n : ℕ) [NeZero n] : ProbabilityMeasure ℝ :=
  ⟨(rademacherProductMeasure n).map (rademacherSumProd n),
   Measure.isProbabilityMeasure_map (Measurable.aemeasurable (measurable_rademacherSumProd n))⟩

/-- The characteristic function of the Rademacher measure: φ(t) = cos(t).
This follows from: φ(t) = (1/2)e^{it} + (1/2)e^{-it} = cos(t). -/
lemma charFun_rademacherMeasure (t : ℝ) : charFun rademacherMeasure t = Real.cos t := by
  simp only [rademacherMeasure, charFun_apply_real]
  rw [integral_add_measure, integral_smul_measure, integral_smul_measure]
  · rw [integral_dirac, integral_dirac]
    simp only [ENNReal.toReal_inv, ENNReal.toReal_ofNat, one_div, ofReal_neg,
      ofReal_one, neg_mul, mul_neg, mul_one]
    -- Goal: 2⁻¹ • exp(-it) + 2⁻¹ • exp(it) = cos(t) where 2⁻¹ : ℝ
    -- Convert ℝ smul on ℂ to multiplication using `real_smul`
    simp only [real_smul]
    -- Goal: ↑(2⁻¹) * exp(it) + ↑(2⁻¹) * exp(-it) = cos(t)
    rw [add_comm, ← mul_add]
    -- Use Complex.two_cos: 2 * cos x = exp(x*I) + exp(-x*I)
    rw [ofReal_inv]
    have h := Complex.two_cos (↑t)
    rw [neg_mul] at h
    rw [← h]
    simp only [ofReal_ofNat]
    rw [show ((2 : ℂ))⁻¹ * ((2 : ℂ) * Complex.cos ↑t) = Complex.cos ↑t by field_simp]
    exact (Complex.ofReal_cos t).symm
  · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)
  · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)

/-- The characteristic function of the sum of n IID Rademacher variables
scaled by (√n)⁻¹ is (cos(t/√n))ⁿ. -/
lemma charFun_rademacherLaw (n : ℕ) [NeZero n] (t : ℝ) :
    charFun (rademacherLaw n).toMeasure t = (Real.cos (t / Real.sqrt n)) ^ n := by
  -- rademacherLaw n = (rademacherProductMeasure n).map (rademacherSumProd n)
  -- rademacherSumProd n x = (√n)⁻¹ * ∑ᵢ xᵢ
  have h1 : (rademacherLaw n).toMeasure =
      (rademacherProductMeasure n).map (rademacherSumProd n) := rfl
  rw [h1]
  -- Use charFun_map_mul: charFun (μ.map (r * ·)) t = charFun μ (r * t)
  have hmul : rademacherSumProd n = (fun x => (Real.sqrt n)⁻¹ * x) ∘ (fun x => ∑ i, x i) := by
    ext x; simp [rademacherSumProd]
  rw [hmul, ← Measure.map_map (measurable_const_mul _)
    (Finset.measurable_sum Finset.univ (fun i _ => measurable_pi_apply i))]
  rw [charFun_map_mul]
  -- Use charFun_map_sum_pi_const: charFun ((pi μ).map (∑)) t = (charFun μ t)^n
  have hprod : rademacherProductMeasure n = Measure.pi (fun _ : Fin n => rademacherMeasure) := rfl
  rw [hprod, charFun_map_sum_pi_const, charFun_rademacherMeasure]
  congr 1
  rw [div_eq_mul_inv, mul_comm]

/-! ### Section 2: CLT and Weak Convergence -/

/-- The standard Gaussian measure. -/
abbrev stdGaussianMeasure : Measure ℝ := stdGaussian.toMeasure

instance : IsProbabilityMeasure stdGaussianMeasure := stdGaussian.prop

/-- The characteristic function of stdGaussian is exp(-t²/2). -/
lemma charFun_stdGaussian (t : ℝ) : charFun stdGaussian.toMeasure t = Complex.exp (-(t^2 / 2)) := by
  rw [stdGaussian, ProbabilityMeasure.coe_mk, charFun_gaussianReal]
  simp only [ofReal_zero, mul_zero, zero_mul, NNReal.coe_one, ofReal_one, one_mul, zero_sub]

/-- (cos(t/√n))^n → exp(-t²/2) via Taylor expansion of cosine. -/
lemma tendsto_cos_pow_exp (t : ℝ) :
    Tendsto (fun n : ℕ => (Complex.ofReal (Real.cos (t / Real.sqrt n)))^n) atTop
      (𝓝 (Complex.exp (-(t^2 / 2)))) := by
  apply tendsto_pow_exp_of_isLittleO (-(↑t^2 / 2))
  rw [Asymptotics.isLittleO_iff]
  intro c hc
  -- Use cos(x) = 1 - x²/2 + O(x⁴) and eventually |t/√n| ≤ 1
  filter_upwards [eventually_ge_atTop (max (Nat.ceil (t^2) + 1) (Nat.ceil (|t|^4 * (5/96) / c) + 1))]
    with n hn
  have hn1 : n ≥ Nat.ceil (t^2) + 1 := le_of_max_le_left hn
  have hn2 : n ≥ Nat.ceil (|t|^4 * (5/96) / c) + 1 := le_of_max_le_right hn
  have hn_pos : (0 : ℝ) < n := by
    have : 1 ≤ n := le_trans (Nat.le_add_left 1 _) hn1
    exact Nat.cast_pos.mpr (Nat.pos_of_ne_zero (Nat.one_le_iff_ne_zero.mp this))
  have hn_nonneg : (0 : ℝ) ≤ n := le_of_lt hn_pos
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  -- |t/√n| ≤ 1
  have hsmall : |t / Real.sqrt n| ≤ 1 := by
    rw [abs_div, abs_of_pos hsqrt_pos, div_le_one hsqrt_pos]
    rw [← Real.sqrt_sq_eq_abs]
    exact Real.sqrt_le_sqrt (by
      have h1 : t^2 ≤ Nat.ceil (t^2) := Nat.le_ceil _
      have h2 : (Nat.ceil (t^2) : ℝ) + 1 ≤ n := by exact_mod_cast hn1
      linarith)
  -- Use Real.cos_bound
  have hcos := Real.cos_bound hsmall
  have hxsq : (t / Real.sqrt n)^2 = t^2 / n := by rw [div_pow, Real.sq_sqrt hn_nonneg]
  have heq : Complex.ofReal (Real.cos (t / Real.sqrt n)) - (1 + -((t : ℂ)^2 / 2) / n) =
      Complex.ofReal (Real.cos (t / Real.sqrt n) - (1 - (t / Real.sqrt n)^2/2)) := by
    simp only [ofReal_sub, ofReal_one, hxsq]; push_cast; ring
  rw [heq, Complex.norm_real, Real.norm_eq_abs]
  have hbound : |t|^4 * (5/96) / c ≤ n := by
    have h1 : (Nat.ceil (|t|^4 * (5/96) / c) : ℝ) + 1 ≤ n := by exact_mod_cast hn2
    have h2 : |t|^4 * (5/96) / c ≤ Nat.ceil (|t|^4 * (5/96) / c) := Nat.le_ceil _
    linarith
  have hsqrt4 : Real.sqrt n ^ 4 = n^2 := by
    have h1 : Real.sqrt n ^ 4 = (Real.sqrt n ^ 2) ^ 2 := by ring
    rw [h1, Real.sq_sqrt hn_nonneg, sq]
  calc |Real.cos (t / Real.sqrt n) - (1 - (t / Real.sqrt n)^2/2)|
      ≤ |t / Real.sqrt n|^4 * (5/96) := hcos
    _ = |t|^4 / n^2 * (5/96) := by
        rw [abs_div, abs_of_pos hsqrt_pos, div_pow, hsqrt4]
    _ ≤ c / n := by
        -- We need: |t|^4 / n² * (5/96) ≤ c / n
        -- From hbound: |t|^4 * (5/96) / c ≤ n, so |t|^4 * (5/96) ≤ c * n
        have h1 : |t|^4 * (5/96) ≤ c * n := by
          have hcne : c ≠ 0 := ne_of_gt hc
          calc |t|^4 * (5/96) = |t|^4 * (5/96) / c * c := by field_simp
            _ ≤ n * c := mul_le_mul_of_nonneg_right hbound (le_of_lt hc)
            _ = c * n := mul_comm _ _
        -- |t|^4 / n² * (5/96) = |t|^4 * (5/96) / n² ≤ c * n / n² = c / n
        have hne : (n : ℝ) ≠ 0 := ne_of_gt hn_pos
        calc |t|^4 / (n : ℝ)^2 * (5/96)
            = |t|^4 * (5/96) / n^2 := by ring
          _ ≤ c * n / n^2 := div_le_div_of_nonneg_right h1 (sq_nonneg _)
          _ = c / n := by field_simp
    _ ≤ c * ‖(1 : ℝ) / n‖ := by
        rw [Real.norm_eq_abs, abs_of_pos (one_div_pos.mpr hn_pos), one_div, div_eq_mul_inv]

/-- **Central Limit Theorem for Rademacher Product Space**:
The law of Sₙ under the n-fold product Rademacher measure converges weakly to stdGaussian. -/
theorem rademacherLaw_tendsto_stdGaussian :
    Tendsto (fun n : ℕ => rademacherLaw (n + 1)) atTop (𝓝 stdGaussian) := by
  rw [ProbabilityMeasure.tendsto_iff_tendsto_charFun]
  intro t
  -- Characteristic function of rademacherLaw (n+1) equals (cos(t/√(n+1)))^(n+1)
  have hcf (n : ℕ) : charFun (rademacherLaw (n + 1)).toMeasure t =
      (↑(Real.cos (t / Real.sqrt (n + 1))) : ℂ)^(n + 1) := by
    rw [charFun_rademacherLaw]
    simp only [Nat.cast_add, Nat.cast_one]
  -- Characteristic function of stdGaussian equals exp(-t²/2)
  have hstd : charFun stdGaussian.toMeasure t = Complex.exp (-(t^2 / 2)) := charFun_stdGaussian t
  -- Rewrite goal using these facts
  simp_rw [hcf, hstd]
  -- The goal is: Tendsto (fun n ↦ cos(t/√(↑n+1))^(n+1)) atTop (𝓝 (exp(-t²/2)))
  -- We have tendsto_cos_pow_exp: Tendsto (fun n ↦ cos(t/√↑n)^n) atTop (𝓝 (exp(-t²/2)))
  -- Need to show (↑n + 1) = ↑(n+1)
  have heq : (fun n : ℕ => (↑(Real.cos (t / Real.sqrt ((n : ℝ) + 1))) : ℂ) ^ (n + 1)) =
      (fun n : ℕ => (↑(Real.cos (t / Real.sqrt (n : ℝ))) : ℂ) ^ n) ∘ (fun n : ℕ => n + 1) := by
    ext n
    simp only [Function.comp_apply, Nat.cast_add, Nat.cast_one]
  rw [heq]
  exact (tendsto_cos_pow_exp t).comp (tendsto_add_atTop_nat 1)

/-- Convergence in distribution implies convergence of expectations for BCFs. -/
theorem tendsto_integral_of_tendsto_probabilityMeasure
    {μs : ℕ → ProbabilityMeasure ℝ} {μ : ProbabilityMeasure ℝ}
    (h : Tendsto μs atTop (𝓝 μ)) (g : BoundedContinuousFunction ℝ ℝ) :
    Tendsto (fun n => ∫ x, g x ∂(μs n).toMeasure) atTop (𝓝 (∫ x, g x ∂μ.toMeasure)) := by
  rw [ProbabilityMeasure.tendsto_iff_forall_integral_tendsto] at h
  exact h g

/-! ### Section 3: Bounded Continuous Functions from C_c² -/

/-- A compactly supported smooth function is a bounded continuous function. -/
def compactlySupportedToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  BoundedContinuousFunction.ofNormedAddCommGroup f hf.continuous
    (Classical.choose hf.bounded) (Classical.choose_spec hf.bounded)

@[simp]
lemma compactlySupportedToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    compactlySupportedToBCF hf x = f x := by
  simp only [compactlySupportedToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-- The square of a compactly supported smooth function is bounded continuous. -/
def compactlySupportedSqToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  let C := Classical.choose hf.bounded
  BoundedContinuousFunction.ofNormedAddCommGroup (fun x => (f x)^2)
    (hf.continuous.pow 2) (C^2) (fun x => by
      simp only [Real.norm_eq_abs]
      rw [abs_pow]
      have hCnonneg : 0 ≤ C := le_trans (norm_nonneg _) (Classical.choose_spec hf.bounded 0)
      have habs := Classical.choose_spec hf.bounded x
      rw [Real.norm_eq_abs] at habs
      refine sq_le_sq' ?_ habs
      calc -C ≤ 0 := neg_nonpos_of_nonneg hCnonneg
           _ ≤ |f x| := abs_nonneg _)

lemma compactlySupportedSqToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    compactlySupportedSqToBCF hf x = (f x)^2 := by
  simp only [compactlySupportedSqToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-- The derivative of a C_c² function is also bounded continuous. -/
def derivToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  let C := Classical.choose (deriv_bounded_of_compactlySupported hf)
  BoundedContinuousFunction.ofNormedAddCommGroup (deriv f)
    (deriv_continuous_of_compactlySupported hf) C
    (fun x => by
      rw [Real.norm_eq_abs]
      exact (Classical.choose_spec (deriv_bounded_of_compactlySupported hf)).2 x)

lemma derivToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    derivToBCF hf x = deriv f x := by
  simp only [derivToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-- The absolute value of the derivative of a C_c² function is bounded continuous. -/
def derivAbsToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  let C := Classical.choose (deriv_bounded_of_compactlySupported hf)
  BoundedContinuousFunction.ofNormedAddCommGroup (fun x => |deriv f x|)
    ((deriv_continuous_of_compactlySupported hf).abs) C
    (fun x => by
      simp only [Real.norm_eq_abs, abs_abs]
      exact (Classical.choose_spec (deriv_bounded_of_compactlySupported hf)).2 x)

lemma derivAbsToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    derivAbsToBCF hf x = |deriv f x| := by
  simp only [derivAbsToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-- The squared derivative of a C_c² function is bounded continuous. -/
def derivSqToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  let C := Classical.choose (deriv_bounded_of_compactlySupported hf)
  BoundedContinuousFunction.ofNormedAddCommGroup (fun x => (deriv f x)^2)
    ((deriv_continuous_of_compactlySupported hf).pow 2) (C^2)
    (fun x => by
      simp only [Real.norm_eq_abs]
      rw [abs_pow]
      have hCnonneg : 0 ≤ C := (Classical.choose_spec (deriv_bounded_of_compactlySupported hf)).1
      have habs := (Classical.choose_spec (deriv_bounded_of_compactlySupported hf)).2 x
      refine sq_le_sq' ?_ habs
      calc -C ≤ 0 := neg_nonpos_of_nonneg hCnonneg
           _ ≤ |deriv f x| := abs_nonneg _)

lemma derivSqToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    derivSqToBCF hf x = (deriv f x)^2 := by
  simp only [derivSqToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-! ### Section 4: Convergence of Expectations -/

/-- Expectations of f under the law of Sₙ converge to expectations under Gaussian. -/
lemma tendsto_integral_f {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, f x ∂(rademacherLaw (n + 1)).toMeasure) atTop
      (𝓝 (∫ x, f x ∂stdGaussianMeasure)) := by
  have h := tendsto_integral_of_tendsto_probabilityMeasure rademacherLaw_tendsto_stdGaussian
    (compactlySupportedToBCF hf)
  simp only [compactlySupportedToBCF_apply] at h
  exact h

/-- Expectations of f² under the law of Sₙ converge to expectations under Gaussian. -/
lemma tendsto_integral_f_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure) atTop
      (𝓝 (∫ x, (f x)^2 ∂stdGaussianMeasure)) := by
  have h := tendsto_integral_of_tendsto_probabilityMeasure rademacherLaw_tendsto_stdGaussian
    (compactlySupportedSqToBCF hf)
  simp only [compactlySupportedSqToBCF_apply] at h
  exact h

/-- Expectations of (f')² under the law of Sₙ converge to expectations under Gaussian. -/
lemma tendsto_integral_deriv_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure) atTop
      (𝓝 (∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
  have h := tendsto_integral_of_tendsto_probabilityMeasure rademacherLaw_tendsto_stdGaussian
    (derivSqToBCF hf)
  simp only [derivSqToBCF_apply] at h
  exact h

/-- Expectations of |f'| under the law of Sₙ converge to expectations under Gaussian. -/
lemma tendsto_integral_deriv_abs {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure) atTop
      (𝓝 (∫ x, |deriv f x| ∂stdGaussianMeasure)) := by
  have h := tendsto_integral_of_tendsto_probabilityMeasure rademacherLaw_tendsto_stdGaussian
    (derivAbsToBCF hf)
  simp only [derivAbsToBCF_apply] at h
  exact h

/-! ### Section 5: Variance Convergence -/

/-- The variance of f under the law of Sₙ converges to the variance under Gaussian.
Variance = E[f²] - (E[f])², and both terms converge. -/
lemma tendsto_variance_f {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure -
                      (∫ x, f x ∂(rademacherLaw (n + 1)).toMeasure)^2) atTop
      (𝓝 (∫ x, (f x)^2 ∂stdGaussianMeasure - (∫ x, f x ∂stdGaussianMeasure)^2)) := by
  apply Tendsto.sub (tendsto_integral_f_sq hf)
  apply Tendsto.pow
  exact tendsto_integral_f hf

/-! ### Section 6: Error Terms Vanish -/

/-- The error term 4K²/n tends to 0. -/
lemma tendsto_error_term_1 (K : ℝ) :
    Tendsto (fun n : ℕ => 4 * K^2 / (n + 1 : ℝ)) atTop (𝓝 0) := by
  have h : Tendsto (fun n : ℕ => ((n : ℝ) + 1)⁻¹) atTop (𝓝 0) := by
    have h1 : Tendsto (fun n : ℕ => (n : ℝ) + 1) atTop atTop :=
      Filter.tendsto_atTop_add_const_right atTop 1 tendsto_natCast_atTop_atTop
    exact tendsto_inv_atTop_zero.comp h1
  have h2 : Tendsto (fun n : ℕ => 4 * K^2 * ((n : ℝ) + 1)⁻¹) atTop (𝓝 0) := by
    simpa using h.const_mul (4 * K^2)
  simp_rw [div_eq_mul_inv]
  exact h2

/-- The error term (4K/√n) * C tends to 0. -/
lemma tendsto_error_term_2 (K C : ℝ) :
    Tendsto (fun n : ℕ => 4 * K / Real.sqrt (n + 1 : ℝ) * C) atTop (𝓝 0) := by
  have h : Tendsto (fun n : ℕ => (Real.sqrt (n + 1 : ℝ))⁻¹) atTop (𝓝 0) := by
    have h1 : Tendsto (fun n : ℕ => (n : ℝ) + 1) atTop atTop :=
      Filter.tendsto_atTop_add_const_right atTop 1 tendsto_natCast_atTop_atTop
    have h2 : Tendsto (fun n : ℕ => Real.sqrt ((n : ℝ) + 1)) atTop atTop :=
      tendsto_sqrt_atTop.comp h1
    exact tendsto_inv_atTop_zero.comp h2
  have h' : Tendsto (fun n : ℕ => 4 * K * C * (Real.sqrt (n + 1 : ℝ))⁻¹) atTop (𝓝 0) := by
    simpa using h.const_mul (4 * K * C)
  simp_rw [div_eq_mul_inv] at h' ⊢
  convert h' using 2 with n
  ring

/-! ### Section 7: Taylor Bound on the Law -/

/-- The Taylor bound expressed in terms of the law of Sₙ.
This uses the change of variables formula: ∫ g(Sₙ) dμₙ = ∫ g d(μₙ.map Sₙ). -/
lemma taylor_bound_on_law {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (n : ℕ) :
    ∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure -
      (∫ x, f x ∂(rademacherLaw (n + 1)).toMeasure)^2 ≤
    ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure +
    4 * secondDerivBound f hf / Real.sqrt (n + 1 : ℝ) *
      ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure +
    4 * (secondDerivBound f hf)^2 / (n + 1 : ℝ) := by
  -- The Taylor bound is stated on the product space
  have hprod := variance_rademacherSum_taylor_bound (n := n + 1) hf
  -- The law of Sₙ under rademacherProductMeasure is rademacherLaw
  have hrademacherLaw : (rademacherLaw (n + 1)).toMeasure =
      (rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) := rfl
  -- Use change of variables: ∫ g d(μ.map Sₙ) = ∫ g ∘ Sₙ dμ
  simp only [hrademacherLaw]
  have haem : AEMeasurable (rademacherSumProd (n + 1)) (rademacherProductMeasure (n + 1)) :=
    Measurable.aemeasurable (measurable_rademacherSumProd (n + 1))
  -- Rewrite each integral using change of variables
  have eq1 : ∫ x, (f x)^2 ∂(rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) =
      ∫ x, (f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1) := by
    rw [integral_map haem (hf.continuous.pow 2).aestronglyMeasurable]
  have eq2 : ∫ x, f x ∂(rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) =
      ∫ x, f (rademacherSumProd (n + 1) x) ∂rademacherProductMeasure (n + 1) := by
    rw [integral_map haem hf.continuous.aestronglyMeasurable]
  have eq3 : ∫ x, (deriv f x)^2 ∂(rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) =
      ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1) := by
    rw [integral_map haem ((deriv_continuous_of_compactlySupported hf).pow 2).aestronglyMeasurable]
  have eq4 : ∫ x, |deriv f x| ∂(rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) =
      ∫ x, |deriv f (rademacherSumProd (n + 1) x)| ∂rademacherProductMeasure (n + 1) := by
    rw [integral_map haem (deriv_continuous_of_compactlySupported hf).abs.aestronglyMeasurable]
  rw [eq1, eq2, eq3, eq4]
  -- Convert variance on product space
  have hvar : variance (fun x => f (rademacherSumProd (n + 1) x)) (rademacherProductMeasure (n + 1)) =
      ∫ x, (f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1) -
      (∫ x, f (rademacherSumProd (n + 1) x) ∂rademacherProductMeasure (n + 1))^2 := by
    rw [variance_eq_sub]
    · simp only [Pi.pow_apply]
    · -- Use that f ∘ rademacherSumProd is MemLp 2
      obtain ⟨C, hC⟩ := hf.bounded
      have hasm : AEStronglyMeasurable (fun x => f (rademacherSumProd (n + 1) x))
          (rademacherProductMeasure (n + 1)) :=
        hf.continuous.aestronglyMeasurable.comp_aemeasurable haem
      refine memLp_of_bounded (a := -C) (b := C) ?_ hasm 2
      refine ae_of_all _ (fun x => ?_)
      simp only [Set.mem_Icc]
      have hbound := hC (rademacherSumProd (n + 1) x)
      rw [Real.norm_eq_abs] at hbound
      have habs := abs_le.mp hbound
      exact ⟨habs.1, habs.2⟩
  rw [← hvar]
  -- Now use the Taylor bound, adjusting for cast differences
  have hcast2 : (n + 1 : ℕ) = ((n : ℝ) + 1) := by simp
  simp only [hcast2] at hprod
  exact hprod

/-! ### Section 8: Main Theorem -/

/-- Helper: MemLp for bounded continuous functions -/
lemma memLp_of_compactlySupported {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f)
    {μ : Measure ℝ} [IsProbabilityMeasure μ] : MemLp f 2 μ := by
  obtain ⟨C, hC⟩ := hf.bounded
  refine memLp_of_bounded (a := -C) (b := C) ?_ hf.continuous.aestronglyMeasurable 2
  refine ae_of_all _ (fun x => ?_)
  simp only [Set.mem_Icc]
  have h := hC x
  rw [Real.norm_eq_abs] at h
  have habs := abs_le.mp h
  exact ⟨habs.1, habs.2⟩

/-- **Gaussian Poincaré Inequality**

For `f ∈ C_c²(ℝ)` and `X ~ N(0,1)`:
  `Var(f(X)) ≤ E[f'(X)²]`

This is proved by:
1. Using the Taylor bound for Rademacher sums (variance_rademacherSum_taylor_bound)
2. Using the CLT to show Sₙ →ᵈ N(0,1)
3. Weak convergence gives E[g(Sₙ)] → E[g(X)] for bounded continuous g
4. The error terms vanish
5. Using le_of_tendsto_of_tendsto' to preserve the inequality in the limit
-/
theorem gaussianPoincare {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    variance (fun x => f x) stdGaussianMeasure ≤
    ∫ x, (deriv f x)^2 ∂stdGaussianMeasure := by
  -- Step 1: Get the bounds for f'
  let K := secondDerivBound f hf
  obtain ⟨C', hC'_nonneg, hC'⟩ := deriv_bounded_of_compactlySupported hf

  -- Step 2: Express variance as E[f²] - (E[f])²
  have hvar_def : variance (fun x => f x) stdGaussianMeasure =
      ∫ x, (f x)^2 ∂stdGaussianMeasure - (∫ x, f x ∂stdGaussianMeasure)^2 := by
    rw [variance_eq_sub]
    · simp only [Pi.pow_apply]
    · exact memLp_of_compactlySupported hf

  rw [hvar_def]

  -- Step 3: Define the sequences for the limit argument
  let a := fun n : ℕ => ∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure -
                         (∫ x, f x ∂(rademacherLaw (n + 1)).toMeasure)^2

  let b := fun n : ℕ => ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure +
    4 * K / Real.sqrt (n + 1 : ℝ) * ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure +
    4 * K^2 / (n + 1 : ℝ)

  -- Step 4: Show aₙ → Var(f(X))
  have ha : Tendsto a atTop (𝓝 (∫ x, (f x)^2 ∂stdGaussianMeasure -
                                  (∫ x, f x ∂stdGaussianMeasure)^2)) := by
    exact tendsto_variance_f hf

  -- Step 5: Show bₙ → E[(f')²(X)]
  have hb : Tendsto b atTop (𝓝 (∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
    -- The main term converges
    have h1 : Tendsto (fun n => ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure) atTop
        (𝓝 (∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := tendsto_integral_deriv_sq hf
    -- Error term 1: 4K²/n → 0
    have h2 : Tendsto (fun n : ℕ => 4 * K^2 / (n + 1 : ℝ)) atTop (𝓝 0) := tendsto_error_term_1 K
    -- Error term 2: (4K/√n) * ∫|f'| → 0
    -- First, ∫|f'| is bounded by C' for any probability measure
    have h3 : Tendsto (fun n : ℕ => 4 * K / Real.sqrt (n + 1 : ℝ) *
        ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure) atTop (𝓝 0) := by
      -- The integral is bounded by C'
      have hbd : ∀ n, |∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure| ≤ C' := by
        intro n
        rw [abs_of_nonneg]
        · calc ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure
              ≤ ∫ _, C' ∂(rademacherLaw (n + 1)).toMeasure := by
                  apply integral_mono_of_nonneg
                  · exact ae_of_all _ (fun _ => abs_nonneg _)
                  · exact integrable_const C'
                  · exact ae_of_all _ (fun x => hC' x)
            _ = C' := by simp
        · exact integral_nonneg (fun _ => abs_nonneg _)
      -- (4K/√n) * (bounded term) → 0
      have hsqrt_tendsto : Tendsto (fun n : ℕ => (Real.sqrt (n + 1 : ℝ))⁻¹) atTop (𝓝 0) := by
        have h' : Tendsto (fun n : ℕ => (n : ℝ) + 1) atTop atTop :=
          Filter.tendsto_atTop_add_const_right atTop 1 tendsto_natCast_atTop_atTop
        exact tendsto_inv_atTop_zero.comp (tendsto_sqrt_atTop.comp h')
      have h4K : Tendsto (fun n : ℕ => 4 * K * (Real.sqrt (n + 1 : ℝ))⁻¹) atTop (𝓝 0) := by
        simpa using hsqrt_tendsto.const_mul (4 * K)
      have h4KC' : Tendsto (fun n : ℕ => |4 * K * (Real.sqrt (n + 1 : ℝ))⁻¹| * C') atTop (𝓝 0) := by
        have := h4K.abs.mul_const C'
        simp only [abs_zero, zero_mul] at this
        exact this
      apply squeeze_zero_norm _ h4KC'
      intro n
      rw [Real.norm_eq_abs]
      calc |4 * K / Real.sqrt (n + 1 : ℝ) *
            ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure|
          = |4 * K / Real.sqrt (n + 1 : ℝ)| *
            |∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure| := abs_mul _ _
        _ ≤ |4 * K / Real.sqrt (n + 1 : ℝ)| * C' := by
            apply mul_le_mul_of_nonneg_left (hbd n) (abs_nonneg _)
        _ = |4 * K * (Real.sqrt (n + 1 : ℝ))⁻¹| * C' := by
            simp only [div_eq_mul_inv]
    -- Combine: main + error1 + error2 → main + 0 + 0 = main
    have hsum : Tendsto (fun n => ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure +
        4 * K / Real.sqrt (n + 1 : ℝ) * ∫ x, |deriv f x| ∂(rademacherLaw (n + 1)).toMeasure +
        4 * K^2 / (n + 1 : ℝ)) atTop
        (𝓝 (∫ x, (deriv f x)^2 ∂stdGaussianMeasure + 0 + 0)) := by
      apply Tendsto.add
      apply Tendsto.add h1 h3
      exact h2
    simp only [add_zero] at hsum
    exact hsum

  -- Step 6: Show aₙ ≤ bₙ for all n (using Taylor bound)
  have hab : ∀ n : ℕ, a n ≤ b n := by
    intro n
    exact taylor_bound_on_law hf n

  -- Step 7: Apply le_of_tendsto_of_tendsto' to get the limit inequality
  exact le_of_tendsto_of_tendsto' ha hb hab

/-! ### Section 9: The Limit of Sum of Squared Differences -/

/-- The rescaled difference function: g(x) = (√n / 2) * (f(a⁺) - f(a⁻)).
By MVT, g(x) = f'(ξ) for some ξ between a⁻ and a⁺. -/
def rescaledDiff (n : ℕ) [NeZero n] (f : ℝ → ℝ) (x : RademacherSpace n) : ℝ :=
  Real.sqrt n / 2 * (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))

/-- The rescaled difference equals f'(ξ) for some ξ between a⁻ and a⁺.
This is a consequence of MVT. -/
lemma rescaledDiff_eq_deriv_at_intermediate {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f)
    (n : ℕ) [NeZero n] (x : RademacherSpace n) :
    ∃ ξ : ℝ, ξ ∈ Set.Ioo (aMinusProd n 0 x) (aPlusProd n 0 x) ∧
      rescaledDiff n f x = deriv f ξ := by
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero (NeZero.ne n))
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  have hdiff := aPlusProd_sub_aMinusProd n x
  have hlt : aMinusProd n 0 x < aPlusProd n 0 x := by
    have hpos : (2 : ℝ) / Real.sqrt n > 0 := div_pos (by norm_num) hsqrt_pos
    linarith [hdiff]
  have hdiff_f := TaylorBound.differentiable_of_contDiff2 hf.1
  obtain ⟨ξ, hξ_mem, hξ_eq⟩ := exists_deriv_eq_slope f hlt
    hdiff_f.continuous.continuousOn (hdiff_f.differentiableOn.mono Set.Ioo_subset_Icc_self)
  use ξ, hξ_mem
  unfold rescaledDiff
  have hne : aPlusProd n 0 x - aMinusProd n 0 x ≠ 0 := by
    rw [hdiff]
    exact ne_of_gt (div_pos (by norm_num) hsqrt_pos)
  calc Real.sqrt n / 2 * (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))
      = Real.sqrt n / 2 * (deriv f ξ * (aPlusProd n 0 x - aMinusProd n 0 x)) := by
          congr 1
          field_simp [hne] at hξ_eq ⊢
          linarith
    _ = Real.sqrt n / 2 * deriv f ξ * (2 / Real.sqrt n) := by rw [hdiff]; ring
    _ = deriv f ξ := by field_simp

/-- The rescaled difference is bounded by the first derivative bound. -/
lemma rescaledDiff_bounded {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f)
    (n : ℕ) [NeZero n] (x : RademacherSpace n) :
    |rescaledDiff n f x| ≤ firstDerivBound f hf := by
  obtain ⟨ξ, _, heq⟩ := rescaledDiff_eq_deriv_at_intermediate hf n x
  rw [heq]
  exact firstDerivBound_spec hf ξ

/-- The difference between the rescaled difference squared and (f'(Sₙ))² is O(1/√n).
This is the key estimate: |g² - (f'(Sₙ))²| ≤ 4KC'/√n where K = sup|f''|, C' = sup|f'|. -/
lemma sq_rescaledDiff_sub_sq_deriv_bound {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f)
    (n : ℕ) [NeZero n] (x : RademacherSpace n) (hx : x 0 = 1 ∨ x 0 = -1) :
    |(rescaledDiff n f x)^2 - (deriv f (rademacherSumProd n x))^2| ≤
    4 * secondDerivBound f hf * firstDerivBound f hf / Real.sqrt n := by
  let g := rescaledDiff n f x
  let S := rademacherSumProd n x
  let K := secondDerivBound f hf
  let C' := firstDerivBound f hf
  have hK_nonneg := secondDerivBound_nonneg hf
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero (NeZero.ne n))
  have hsqrt_pos : 0 < Real.sqrt n := Real.sqrt_pos.mpr hn_pos
  -- Get ξ such that g = f'(ξ)
  obtain ⟨ξ, hξ_mem, hg_eq⟩ := rescaledDiff_eq_deriv_at_intermediate hf n x
  -- Bound |ξ - S| ≤ 2/√n (from TaylorBound)
  have hξ_bound : |ξ - S| ≤ 2 / Real.sqrt n := by
    rcases hx with hpos | hneg
    · -- x 0 = 1: a⁺ = S, a⁻ = S - 2/√n
      have haplus_eq : aPlusProd n 0 x = S := by
        simp only [aPlusProd, hpos, sub_self, zero_div, add_zero]; rfl
      have haminus_eq : aMinusProd n 0 x = S - 2 / Real.sqrt n := by
        simp only [aMinusProd, hpos]
        ring
      rw [haplus_eq, haminus_eq] at hξ_mem
      have h1 : S - ξ > 0 := sub_pos.mpr hξ_mem.2
      have h2 : S - ξ < 2 / Real.sqrt n := by linarith [hξ_mem.1]
      calc |ξ - S| = |-(S - ξ)| := by ring_nf
        _ = S - ξ := by rw [abs_neg, abs_of_pos h1]
        _ ≤ 2 / Real.sqrt n := le_of_lt h2
    · -- x 0 = -1: a⁺ = S + 2/√n, a⁻ = S
      have haplus_eq : aPlusProd n 0 x = S + 2 / Real.sqrt n := by
        simp only [aPlusProd, hneg]
        ring
      have haminus_eq : aMinusProd n 0 x = S := by
        simp only [aMinusProd, hneg, add_neg_cancel, zero_div, sub_zero]; rfl
      rw [haplus_eq, haminus_eq] at hξ_mem
      have h1 : ξ - S > 0 := sub_pos.mpr hξ_mem.1
      have h2 : ξ - S < 2 / Real.sqrt n := by linarith [hξ_mem.2]
      calc |ξ - S| = ξ - S := abs_of_pos h1
        _ ≤ 2 / Real.sqrt n := le_of_lt h2
  -- Bound |f'(ξ) - f'(S)| ≤ K * |ξ - S| ≤ 2K/√n
  have hderiv_diff : |deriv f ξ - deriv f S| ≤ 2 * K / Real.sqrt n := by
    by_cases hξS : ξ = S
    · simp only [hξS, sub_self, abs_zero]
      exact div_nonneg (mul_nonneg (by norm_num) hK_nonneg) (le_of_lt hsqrt_pos)
    · rcases Ne.lt_or_gt hξS with hlt | hlt
      · obtain ⟨η, _, hη_eq⟩ := exists_deriv_eq_slope (deriv f) hlt
          (TaylorBound.deriv_differentiable_of_contDiff2 hf.1).continuous.continuousOn
          ((TaylorBound.deriv_differentiable_of_contDiff2 hf.1).differentiableOn.mono
            Set.Ioo_subset_Icc_self)
        calc |deriv f ξ - deriv f S|
            = |deriv f S - deriv f ξ| := abs_sub_comm _ _
          _ = |deriv (deriv f) η * (S - ξ)| := by
              have hne : S - ξ ≠ 0 := sub_ne_zero.mpr (ne_of_gt hlt)
              rw [hη_eq]; field_simp
          _ = |deriv (deriv f) η| * |S - ξ| := abs_mul _ _
          _ ≤ K * |S - ξ| := mul_le_mul_of_nonneg_right (secondDerivBound_spec hf η) (abs_nonneg _)
          _ = K * |ξ - S| := by rw [abs_sub_comm]
          _ ≤ K * (2 / Real.sqrt n) := mul_le_mul_of_nonneg_left hξ_bound hK_nonneg
          _ = 2 * K / Real.sqrt n := by ring
      · obtain ⟨η, _, hη_eq⟩ := exists_deriv_eq_slope (deriv f) hlt
          (TaylorBound.deriv_differentiable_of_contDiff2 hf.1).continuous.continuousOn
          ((TaylorBound.deriv_differentiable_of_contDiff2 hf.1).differentiableOn.mono
            Set.Ioo_subset_Icc_self)
        calc |deriv f ξ - deriv f S|
            = |deriv (deriv f) η * (ξ - S)| := by
                have hne : ξ - S ≠ 0 := sub_ne_zero.mpr (ne_of_gt hlt)
                rw [hη_eq]; field_simp
          _ = |deriv (deriv f) η| * |ξ - S| := abs_mul _ _
          _ ≤ K * |ξ - S| := mul_le_mul_of_nonneg_right (secondDerivBound_spec hf η) (abs_nonneg _)
          _ ≤ K * (2 / Real.sqrt n) := mul_le_mul_of_nonneg_left hξ_bound hK_nonneg
          _ = 2 * K / Real.sqrt n := by ring
  -- Now bound |g² - (f'(S))²| = |g - f'(S)| * |g + f'(S)|
  have hg_bound : |g| ≤ C' := rescaledDiff_bounded hf n x
  have hfS_bound : |deriv f S| ≤ C' := firstDerivBound_spec hf S
  calc |g^2 - (deriv f S)^2|
      = |(g - deriv f S) * (g + deriv f S)| := by ring_nf
    _ = |g - deriv f S| * |g + deriv f S| := abs_mul _ _
    _ = |deriv f ξ - deriv f S| * |g + deriv f S| := by
        rw [show g = deriv f ξ from hg_eq]
    _ ≤ (2 * K / Real.sqrt n) * |g + deriv f S| :=
        mul_le_mul_of_nonneg_right hderiv_diff (abs_nonneg _)
    _ ≤ (2 * K / Real.sqrt n) * (|g| + |deriv f S|) :=
        mul_le_mul_of_nonneg_left (abs_add_le _ _)
          (div_nonneg (mul_nonneg (by norm_num) hK_nonneg) (le_of_lt hsqrt_pos))
    _ ≤ (2 * K / Real.sqrt n) * (C' + C') := by
        apply mul_le_mul_of_nonneg_left (add_le_add hg_bound hfS_bound)
        exact div_nonneg (mul_nonneg (by norm_num) hK_nonneg) (le_of_lt hsqrt_pos)
    _ = 4 * K * C' / Real.sqrt n := by ring

/-- The integral of n * (f(a⁺) - f(a⁻))² equals 4 times the integral of (rescaledDiff)². -/
lemma integral_n_sq_diff_eq_four_sq_rescaledDiff {f : ℝ → ℝ} (_ : CompactlySupportedSmooth f)
    (n : ℕ) [NeZero n] :
    (n : ℝ) * ∫ x, (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 ∂rademacherProductMeasure n =
    4 * ∫ x, (rescaledDiff n f x)^2 ∂rademacherProductMeasure n := by
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr (Nat.pos_of_ne_zero (NeZero.ne n))
  have hsqrt_sq : (Real.sqrt n)^2 = n := Real.sq_sqrt (le_of_lt hn_pos)
  -- rescaledDiff² = (√n/2)² * (f(a⁺)-f(a⁻))² = (n/4) * (f(a⁺)-f(a⁻))²
  have heq_pointwise : ∀ x, (rescaledDiff n f x)^2 =
      (n : ℝ) / 4 * (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 := by
    intro x
    simp only [rescaledDiff, mul_pow, div_pow]
    rw [hsqrt_sq]
    ring
  simp_rw [heq_pointwise, MeasureTheory.integral_const_mul]
  ring

/-- **Key Intermediate Result**: The difference between n * E[(f(a⁺)-f(a⁻))²] and 4*E[(f'(Sₙ))²]
tends to zero as n → ∞.

This follows from the MVT: f(a⁺) - f(a⁻) = f'(ξ) * (2/√n) where |ξ - Sₙ| ≤ 2/√n,
and the Lipschitz continuity of f'. -/
theorem tendsto_n_sq_diff_sub_four_deriv_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n : ℕ => (↑(n + 1) : ℝ) *
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) -
      4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 0) := by
  let K := secondDerivBound f hf
  let C' := firstDerivBound f hf
  have hC'_nonneg := firstDerivBound_nonneg hf
  -- The bound is 16KC'/√(n+1) which tends to 0 (4 from inside integral bound × 4 from outside)
  have hbound : Tendsto (fun n : ℕ => 16 * K * C' / Real.sqrt (↑(n + 1) : ℝ)) atTop (𝓝 0) := by
    have hsqrt_tendsto : Tendsto (fun n : ℕ => (Real.sqrt (↑(n + 1) : ℝ))⁻¹) atTop (𝓝 0) := by
      have h' : Tendsto (fun n : ℕ => (↑(n + 1) : ℝ)) atTop atTop := by
        simp only [Nat.cast_add, Nat.cast_one]
        exact Filter.tendsto_atTop_add_const_right atTop 1 tendsto_natCast_atTop_atTop
      exact tendsto_inv_atTop_zero.comp (tendsto_sqrt_atTop.comp h')
    have h16KC' : Tendsto (fun n : ℕ => 16 * K * C' * (Real.sqrt (↑(n + 1) : ℝ))⁻¹) atTop (𝓝 0) := by
      simpa using hsqrt_tendsto.const_mul (16 * K * C')
    simp_rw [div_eq_mul_inv]
    exact h16KC'
  apply squeeze_zero_norm _ hbound
  intro n
  rw [Real.norm_eq_abs]
  -- Rewrite using rescaledDiff
  have heq : (↑(n + 1) : ℝ) * ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
        ∂rademacherProductMeasure (n + 1) =
      4 * ∫ x, (rescaledDiff (n + 1) f x)^2 ∂rademacherProductMeasure (n + 1) :=
    integral_n_sq_diff_eq_four_sq_rescaledDiff hf (n + 1)
  rw [heq]
  -- Now bound |4 * ∫ g² - 4 * ∫ (f'(S))²| = 4 * |∫ (g² - (f'(S))²)|
  have hint_diff : Integrable (fun x => (rescaledDiff (n + 1) f x)^2 -
      (deriv f (rademacherSumProd (n + 1) x))^2) (rademacherProductMeasure (n + 1)) := by
    apply Integrable.sub
    · -- rescaledDiff² is integrable (bounded by C'²)
      apply integrable_sq_of_bounded (C := C')
      · unfold rescaledDiff
        apply AEStronglyMeasurable.mul aestronglyMeasurable_const
        apply AEStronglyMeasurable.sub
        · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
            ((measurable_rademacherSumProd (n + 1)).add
              ((measurable_const.sub (measurable_pi_apply 0)).div measurable_const)).aemeasurable
        · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
            ((measurable_rademacherSumProd (n + 1)).sub
              ((measurable_const.add (measurable_pi_apply 0)).div measurable_const)).aemeasurable
      · exact hC'_nonneg
      · filter_upwards with x
        exact rescaledDiff_bounded hf (n + 1) x
    · -- (f'(S))² is integrable
      exact integrable_deriv_sq (n + 1) hf
  calc |4 * ∫ x, (rescaledDiff (n + 1) f x)^2 ∂rademacherProductMeasure (n + 1) -
        4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1)|
      = |4 * (∫ x, (rescaledDiff (n + 1) f x)^2 ∂rademacherProductMeasure (n + 1) -
          ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1))| := by
          ring_nf
    _ = 4 * |∫ x, ((rescaledDiff (n + 1) f x)^2 - (deriv f (rademacherSumProd (n + 1) x))^2)
          ∂rademacherProductMeasure (n + 1)| := by
          rw [abs_mul, abs_of_nonneg (by norm_num : (4 : ℝ) ≥ 0)]
          congr 1
          rw [← MeasureTheory.integral_sub]
          · apply integrable_sq_of_bounded (C := C')
            · unfold rescaledDiff
              apply AEStronglyMeasurable.mul aestronglyMeasurable_const
              apply AEStronglyMeasurable.sub
              · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
                  ((measurable_rademacherSumProd (n + 1)).add
                    ((measurable_const.sub (measurable_pi_apply 0)).div measurable_const)).aemeasurable
              · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
                  ((measurable_rademacherSumProd (n + 1)).sub
                    ((measurable_const.add (measurable_pi_apply 0)).div measurable_const)).aemeasurable
            · exact hC'_nonneg
            · filter_upwards with x
              exact rescaledDiff_bounded hf (n + 1) x
          · exact integrable_deriv_sq (n + 1) hf
    _ ≤ 4 * ∫ x, |((rescaledDiff (n + 1) f x)^2 - (deriv f (rademacherSumProd (n + 1) x))^2)|
          ∂rademacherProductMeasure (n + 1) := by
          apply mul_le_mul_of_nonneg_left abs_integral_le_integral_abs (by norm_num)
    _ ≤ 4 * ∫ _, (4 * K * C' / Real.sqrt (↑(n + 1) : ℝ)) ∂rademacherProductMeasure (n + 1) := by
          apply mul_le_mul_of_nonneg_left _ (by norm_num)
          apply integral_mono_ae
          · exact hint_diff.abs
          · exact integrable_const _
          · filter_upwards [coord_values_ae (n + 1) 0] with x hx
            exact sq_rescaledDiff_sub_sq_deriv_bound hf (n + 1) x hx
    _ = 16 * K * C' / Real.sqrt (↑(n + 1) : ℝ) := by simp; ring

/-- **Main Intermediate Result (n times single term version)**:

For f ∈ C_c²(ℝ), as n → ∞:
  n · E[(f(a⁺₀) - f(a⁻₀))²] → 4 · E[f'(X)²]

This is equivalent to the sum version by symmetry of Rademacher variables. -/
theorem tendsto_n_times_sq_diff {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n : ℕ => (↑(n + 1) : ℝ) *
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 (4 * ∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
  -- We show this by writing aₙ = (aₙ - bₙ) + bₙ where
  -- aₙ = n * E[(f(a⁺) - f(a⁻))²]
  -- bₙ = 4 * E[(f'(Sₙ))²]
  -- We've shown aₙ - bₙ → 0 and bₙ → 4 * E[(f'(X))²]
  have h1 : Tendsto (fun n : ℕ => (↑(n + 1) : ℝ) *
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) -
      4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 0) := tendsto_n_sq_diff_sub_four_deriv_sq hf
  have h2 : Tendsto (fun n => 4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2
        ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 (4 * ∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
    apply Tendsto.const_mul
    -- Use change of variables: ∫ g(Sₙ) dμ = ∫ g d(law of Sₙ)
    have hcov : ∀ n, ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2
        ∂rademacherProductMeasure (n + 1) =
        ∫ x, (deriv f x)^2 ∂(rademacherLaw (n + 1)).toMeasure := by
      intro n
      have hrademacherLaw : (rademacherLaw (n + 1)).toMeasure =
          (rademacherProductMeasure (n + 1)).map (rademacherSumProd (n + 1)) := rfl
      rw [hrademacherLaw]
      exact (integral_map (measurable_rademacherSumProd (n + 1)).aemeasurable
        ((deriv_continuous_of_compactlySupported hf).pow 2).aestronglyMeasurable).symm
    simp_rw [hcov]
    exact tendsto_integral_deriv_sq hf
  -- Combine: aₙ = (aₙ - bₙ) + bₙ
  have heq : (fun n : ℕ => (↑(n + 1) : ℝ) *
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1)) =
      (fun n : ℕ => ((↑(n + 1) : ℝ) *
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) -
      4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1)) +
      4 * ∫ x, (deriv f (rademacherSumProd (n + 1) x))^2 ∂rademacherProductMeasure (n + 1)) := by
    ext n; ring
  rw [heq]
  simpa using h1.add h2

/-- **Main Intermediate Result (sum version)**:

For f ∈ C_c²(ℝ), as n → ∞:
  ∑ᵢ E[(f(Sₙ + (1-εᵢ)/√n) - f(Sₙ - (1+εᵢ)/√n))²] → 4 · E[f'(X)²]

where X ~ N(0,1).

This follows from the n-times version by symmetry: all terms in the sum are equal. -/
theorem tendsto_sum_sq_diff_four_deriv_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∑ i : Fin (n + 1), ∫ x,
        (f (aPlusProd (n + 1) i x) - f (aMinusProd (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 (4 * ∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
  -- By symmetry, all terms are equal (same argument as in variance_rademacherSum_efronStein)
  have hsum_eq : ∀ n : ℕ, ∑ i : Fin (n + 1), ∫ x,
      (f (aPlusProd (n + 1) i x) - f (aMinusProd (n + 1) i x))^2
        ∂rademacherProductMeasure (n + 1) =
      (↑(n + 1) : ℝ) * ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
        ∂rademacherProductMeasure (n + 1) := by
    intro n
    -- All terms are equal by symmetry
    have hall_eq : ∀ i ∈ Finset.univ, ∫ x,
        (f (aPlusProd (n + 1) i x) - f (aMinusProd (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) =
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) := by
      intro i _
      -- Use coordinate swap symmetry
      let σ : Equiv.Perm (Fin (n + 1)) := Equiv.swap 0 i
      let swapEquiv := MeasurableEquiv.piCongrLeft (fun _ : Fin (n + 1) => ℝ) σ
      have hσ_symm : σ.symm = σ := Equiv.symm_swap 0 i
      have hσ_i : σ i = 0 := Equiv.swap_apply_right 0 i
      -- rademacherSumProd is invariant under coordinate permutation
      have hsum_inv : ∀ x, rademacherSumProd (n + 1) (swapEquiv x) = rademacherSumProd (n + 1) x := by
        intro x
        unfold rademacherSumProd
        rw [MeasurableEquiv.coe_piCongrLeft]
        simp only [Equiv.piCongrLeft_apply_eq_cast, hσ_symm, cast_eq]
        rw [← Finset.sum_equiv σ (g := fun j => x j)]
        · simp only [Finset.mem_univ, implies_true]
        · intro j _; rfl
      have hswap_i : ∀ x, (swapEquiv x) i = x 0 := by
        intro x
        show (Equiv.piCongrLeft (fun _ => ℝ) σ) x i = x 0
        simp only [Equiv.piCongrLeft_apply_eq_cast, cast_eq, hσ_symm, hσ_i]
      have haPlus : ∀ x, aPlusProd (n + 1) i (swapEquiv x) = aPlusProd (n + 1) 0 x := by
        intro x; unfold aPlusProd; rw [hsum_inv, hswap_i]
      have haMinus : ∀ x, aMinusProd (n + 1) i (swapEquiv x) = aMinusProd (n + 1) 0 x := by
        intro x; unfold aMinusProd; rw [hsum_inv, hswap_i]
      have hpreserves : MeasurePreserving swapEquiv (rademacherProductMeasure (n + 1))
          (rademacherProductMeasure (n + 1)) := by
        unfold rademacherProductMeasure
        exact measurePreserving_piCongrLeft (fun _ => rademacherMeasure) σ
      rw [← hpreserves.integral_comp']
      congr 1
      ext x
      rw [haPlus, haMinus]
    rw [Finset.sum_eq_card_nsmul hall_eq]
    simp only [Finset.card_univ, Fintype.card_fin, nsmul_eq_mul]
  simp_rw [hsum_eq]
  exact tendsto_n_times_sq_diff hf

/-- The shifted Rademacher sum: `Sₙ - 2εᵢ/√n`.
This represents Sₙ with coordinate i's contribution subtracted twice. -/
def rademacherSumShifted (n : ℕ) [NeZero n] (i : Fin n) (x : RademacherSpace n) : ℝ :=
  rademacherSumProd n x - 2 * x i / Real.sqrt n

/-- The shifted sum is measurable. -/
lemma measurable_rademacherSumShifted (n : ℕ) [NeZero n] (i : Fin n) :
    Measurable (rademacherSumShifted n i) := by
  unfold rademacherSumShifted
  apply Measurable.sub (measurable_rademacherSumProd n)
  apply Measurable.div (Measurable.const_mul (measurable_pi_apply i) 2) measurable_const

/-- Key identity: When εᵢ = 1, we have aPlusProd = Sₙ and aMinusProd = Sₙ - 2/√n = shifted. -/
lemma aPlusProd_aMinusProd_eq_when_eps_pos (n : ℕ) [NeZero n] (x : RademacherSpace n)
    (hx : x 0 = 1) :
    aPlusProd n 0 x = rademacherSumProd n x ∧
    aMinusProd n 0 x = rademacherSumShifted n 0 x := by
  constructor
  · unfold aPlusProd; simp [hx]
  · unfold aMinusProd rademacherSumShifted; simp [hx]; ring

/-- Key identity: When εᵢ = -1, we have aPlusProd = Sₙ + 2/√n = shifted, and aMinusProd = Sₙ. -/
lemma aPlusProd_aMinusProd_eq_when_eps_neg (n : ℕ) [NeZero n] (x : RademacherSpace n)
    (hx : x 0 = -1) :
    aPlusProd n 0 x = rademacherSumShifted n 0 x ∧
    aMinusProd n 0 x = rademacherSumProd n x := by
  constructor
  · -- aPlusProd = Sₙ + (1-(-1))/√n = Sₙ + 2/√n
    -- rademacherSumShifted = Sₙ - 2*(-1)/√n = Sₙ + 2/√n
    unfold aPlusProd rademacherSumShifted; simp [hx]; ring
  · unfold aMinusProd; simp [hx]

/-- **Key Identity**: The squared difference (f(a⁺) - f(a⁻))² equals (f(Sₙ) - f(Sₙ - 2εᵢ/√n))² a.s.

This is because:
- When εᵢ = 1: a⁺ = Sₙ, a⁻ = Sₙ - 2/√n = shifted, so the differences are equal.
- When εᵢ = -1: a⁺ = Sₙ + 2/√n, a⁻ = Sₙ, shifted = Sₙ + 2/√n.
  f(a⁺) - f(a⁻) = f(Sₙ + 2/√n) - f(Sₙ)
  f(Sₙ) - f(shifted) = f(Sₙ) - f(Sₙ + 2/√n) = -(f(a⁺) - f(a⁻))
  But the squares are equal. -/
lemma sq_aPlusMinus_eq_sq_shifted (n : ℕ) [NeZero n] {f : ℝ → ℝ} (x : RademacherSpace n)
    (hx : x 0 = 1 ∨ x 0 = -1) :
    (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 =
    (f (rademacherSumProd n x) - f (rademacherSumShifted n 0 x))^2 := by
  rcases hx with hpos | hneg
  · -- Case εᵢ = 1: a⁺ = Sₙ, a⁻ = shifted
    obtain ⟨haplus, haminus⟩ := aPlusProd_aMinusProd_eq_when_eps_pos n x hpos
    rw [haplus, haminus]
  · -- Case εᵢ = -1: a⁺ = shifted + offset, a⁻ = Sₙ
    -- We have a⁺ - a⁻ = 2/√n (constant), so a⁺ = Sₙ + 2/√n, a⁻ = Sₙ
    -- shifted = Sₙ - 2*(-1)/√n = Sₙ + 2/√n = a⁺
    have hshifted_eq_aplus : rademacherSumShifted n 0 x = aPlusProd n 0 x := by
      unfold rademacherSumShifted aPlusProd
      simp [hneg]; ring
    have haminus_eq_sum : aMinusProd n 0 x = rademacherSumProd n x := by
      unfold aMinusProd; simp [hneg]
    rw [hshifted_eq_aplus, haminus_eq_sum]
    ring

/-- Almost everywhere version of the squared difference identity. -/
lemma sq_aPlusMinus_eq_sq_shifted_ae (n : ℕ) [NeZero n] {f : ℝ → ℝ} :
    ∀ᵐ x ∂(rademacherProductMeasure n),
    (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 =
    (f (rademacherSumProd n x) - f (rademacherSumShifted n 0 x))^2 := by
  filter_upwards [coord_values_ae n 0] with x hx
  exact sq_aPlusMinus_eq_sq_shifted n x hx

/-- The integral of the squared difference using aPlusProd/aMinusProd equals
the integral using rademacherSumProd/rademacherSumShifted. -/
lemma integral_sq_diff_eq_integral_sq_shifted (n : ℕ) [NeZero n] (f : ℝ → ℝ) :
    ∫ x, (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 ∂(rademacherProductMeasure n) =
    ∫ x, (f (rademacherSumProd n x) - f (rademacherSumShifted n 0 x))^2
      ∂(rademacherProductMeasure n) := by
  apply integral_congr_ae
  exact sq_aPlusMinus_eq_sq_shifted_ae n

/-- **Main Intermediate Result (refactored formulation)**:

For f ∈ C_c²(ℝ), as n → ∞:
  ∑ᵢ E[(f(Sₙ) - f(Sₙ - 2εᵢ/√n))²] → 4 · E[f'(X)²]

where X ~ N(0,1).

This is the refactored version of `tendsto_sum_sq_diff_four_deriv_sq`,
using the shifted sum formulation instead of aPlusProd/aMinusProd. -/
theorem tendsto_sum_sq_shifted_four_deriv_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∑ i : Fin (n + 1), ∫ x,
        (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1))
    atTop (𝓝 (4 * ∫ x, (deriv f x)^2 ∂stdGaussianMeasure)) := by
  -- First, show that each term equals the corresponding term with aPlusProd/aMinusProd
  have hsum_convert : ∀ n : ℕ,
      ∑ i : Fin (n + 1), ∫ x,
        (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) =
      ∑ i : Fin (n + 1), ∫ x,
        (f (aPlusProd (n + 1) i x) - f (aMinusProd (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) := by
    intro n
    -- By symmetry, all terms are equal, so we can relate both sums to n+1 times the i=0 term
    -- First, show all terms in the LHS sum are equal (to the i=0 term)
    have hlhs_eq : ∀ i ∈ Finset.univ, ∫ x,
        (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) =
        ∫ x, (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) := by
      intro i _
      -- Use coordinate swap symmetry
      let σ : Equiv.Perm (Fin (n + 1)) := Equiv.swap 0 i
      let swapEquiv := MeasurableEquiv.piCongrLeft (fun _ : Fin (n + 1) => ℝ) σ
      have hσ_symm : σ.symm = σ := Equiv.symm_swap 0 i
      have hσ_i : σ i = 0 := Equiv.swap_apply_right 0 i
      -- rademacherSumProd is invariant under coordinate permutation
      have hsum_inv : ∀ x, rademacherSumProd (n + 1) (swapEquiv x) = rademacherSumProd (n + 1) x := by
        intro x
        unfold rademacherSumProd
        rw [MeasurableEquiv.coe_piCongrLeft]
        simp only [Equiv.piCongrLeft_apply_eq_cast, hσ_symm, cast_eq]
        rw [← Finset.sum_equiv σ (g := fun j => x j)]
        · simp only [Finset.mem_univ, implies_true]
        · intro j _; rfl
      have hswap_i : ∀ x, (swapEquiv x) i = x 0 := by
        intro x
        show (Equiv.piCongrLeft (fun _ => ℝ) σ) x i = x 0
        simp only [Equiv.piCongrLeft_apply_eq_cast, cast_eq, hσ_symm, hσ_i]
      have hShifted : ∀ x, rademacherSumShifted (n + 1) i (swapEquiv x) =
          rademacherSumShifted (n + 1) 0 x := by
        intro x; unfold rademacherSumShifted; rw [hsum_inv, hswap_i]
      have hpreserves : MeasurePreserving swapEquiv (rademacherProductMeasure (n + 1))
          (rademacherProductMeasure (n + 1)) := by
        unfold rademacherProductMeasure
        exact measurePreserving_piCongrLeft (fun _ => rademacherMeasure) σ
      rw [← hpreserves.integral_comp']
      congr 1
      ext x
      rw [hsum_inv, hShifted]
    -- Similarly for RHS
    have hrhs_eq : ∀ i ∈ Finset.univ, ∫ x,
        (f (aPlusProd (n + 1) i x) - f (aMinusProd (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) =
        ∫ x, (f (aPlusProd (n + 1) 0 x) - f (aMinusProd (n + 1) 0 x))^2
          ∂rademacherProductMeasure (n + 1) := by
      intro i _
      let σ : Equiv.Perm (Fin (n + 1)) := Equiv.swap 0 i
      let swapEquiv := MeasurableEquiv.piCongrLeft (fun _ : Fin (n + 1) => ℝ) σ
      have hσ_symm : σ.symm = σ := Equiv.symm_swap 0 i
      have hσ_i : σ i = 0 := Equiv.swap_apply_right 0 i
      have hsum_inv : ∀ x, rademacherSumProd (n + 1) (swapEquiv x) = rademacherSumProd (n + 1) x := by
        intro x
        unfold rademacherSumProd
        rw [MeasurableEquiv.coe_piCongrLeft]
        simp only [Equiv.piCongrLeft_apply_eq_cast, hσ_symm, cast_eq]
        rw [← Finset.sum_equiv σ (g := fun j => x j)]
        · simp only [Finset.mem_univ, implies_true]
        · intro j _; rfl
      have hswap_i : ∀ x, (swapEquiv x) i = x 0 := by
        intro x
        show (Equiv.piCongrLeft (fun _ => ℝ) σ) x i = x 0
        simp only [Equiv.piCongrLeft_apply_eq_cast, cast_eq, hσ_symm, hσ_i]
      have haPlus : ∀ x, aPlusProd (n + 1) i (swapEquiv x) = aPlusProd (n + 1) 0 x := by
        intro x; unfold aPlusProd; rw [hsum_inv, hswap_i]
      have haMinus : ∀ x, aMinusProd (n + 1) i (swapEquiv x) = aMinusProd (n + 1) 0 x := by
        intro x; unfold aMinusProd; rw [hsum_inv, hswap_i]
      have hpreserves : MeasurePreserving swapEquiv (rademacherProductMeasure (n + 1))
          (rademacherProductMeasure (n + 1)) := by
        unfold rademacherProductMeasure
        exact measurePreserving_piCongrLeft (fun _ => rademacherMeasure) σ
      rw [← hpreserves.integral_comp']
      congr 1
      ext x
      rw [haPlus, haMinus]
    -- Both sums equal (n+1) times their respective i=0 terms
    rw [Finset.sum_eq_card_nsmul hlhs_eq, Finset.sum_eq_card_nsmul hrhs_eq]
    simp only [Finset.card_univ, Fintype.card_fin, nsmul_eq_mul]
    congr 1
    -- Now show the i=0 terms are equal
    exact (integral_sq_diff_eq_integral_sq_shifted (n + 1) f).symm
  simp_rw [hsum_convert]
  exact tendsto_sum_sq_diff_four_deriv_sq hf

/-! ### Section 10: Entropy Convergence -/

/-- The function x * log x is bounded on [0, C²] for any C ≥ 0.
    This is because x * log x → 0 as x → 0⁺ and is continuous on (0, ∞). -/
lemma mul_log_bounded_on_Icc (C : ℝ) (_ : 0 ≤ C) :
    ∃ M : ℝ, ∀ x ∈ Set.Icc 0 (C^2), |x * Real.log x| ≤ M := by
  -- The function x * log x is continuous on ℝ (with convention 0 * log 0 = 0)
  -- and [0, C²] is compact, so it attains a maximum
  have hcont : ContinuousOn (fun x => x * Real.log x) (Set.Icc 0 (C^2)) :=
    Real.continuous_mul_log.continuousOn
  have hcompact : IsCompact (Set.Icc 0 (C^2)) := isCompact_Icc
  obtain ⟨M, hM⟩ := hcompact.exists_bound_of_continuousOn hcont
  use M
  intro x hx
  exact hM x hx

/-- For f with compact support and bounded by C, the function (f x)² * log((f x)²)
    is bounded. -/
lemma sq_mul_log_sq_bounded_of_compactlySupported {f : ℝ → ℝ}
    (hf : CompactlySupportedSmooth f) :
    ∃ M : ℝ, ∀ x : ℝ, |(f x)^2 * Real.log ((f x)^2)| ≤ M := by
  obtain ⟨C, hC⟩ := hf.bounded
  have hCnonneg : 0 ≤ C := le_trans (norm_nonneg _) (hC 0)
  -- Get bound M on x * log x for x ∈ [0, C²]
  obtain ⟨M, hM⟩ := mul_log_bounded_on_Icc C hCnonneg
  use M
  intro x
  -- (f x)² ∈ [0, C²] since |f x| ≤ C
  have hfx_bound : (f x)^2 ∈ Set.Icc 0 (C^2) := by
    constructor
    · exact sq_nonneg _
    · have h := hC x
      rw [Real.norm_eq_abs] at h
      have habs : |f x| ≤ C := h
      calc (f x)^2 = |f x|^2 := (sq_abs (f x)).symm
        _ ≤ C^2 := by
          apply sq_le_sq'
          · calc -C ≤ 0 := neg_nonpos_of_nonneg hCnonneg
              _ ≤ |f x| := abs_nonneg _
          · exact habs
  exact hM _ hfx_bound

/-- The function (f x)² * log((f x)²) is continuous when f is C² with compact support. -/
lemma continuous_sq_mul_log_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Continuous (fun x => (f x)^2 * Real.log ((f x)^2)) :=
  (hf.continuous.pow 2).mul_log

/-- The squared function composed with log is a bounded continuous function
    for compactly supported smooth f. -/
def compactlySupportedSqMulLogToBCF {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    BoundedContinuousFunction ℝ ℝ :=
  let M := Classical.choose (sq_mul_log_sq_bounded_of_compactlySupported hf)
  BoundedContinuousFunction.ofNormedAddCommGroup (fun x => (f x)^2 * Real.log ((f x)^2))
    (continuous_sq_mul_log_sq hf) M (fun x => by
      rw [Real.norm_eq_abs]; exact Classical.choose_spec (sq_mul_log_sq_bounded_of_compactlySupported hf) x)

@[simp]
lemma compactlySupportedSqMulLogToBCF_apply {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (x : ℝ) :
    compactlySupportedSqMulLogToBCF hf x = (f x)^2 * Real.log ((f x)^2) := by
  simp only [compactlySupportedSqMulLogToBCF]
  rw [BoundedContinuousFunction.coe_ofNormedAddCommGroup]

/-- The entropy integrand (f x)² * log((f x)²) converges in expectation under weak convergence. -/
lemma tendsto_integral_f_sq_mul_log {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => ∫ x, (f x)^2 * Real.log ((f x)^2) ∂(rademacherLaw (n + 1)).toMeasure) atTop
      (𝓝 (∫ x, (f x)^2 * Real.log ((f x)^2) ∂stdGaussianMeasure)) := by
  have h := tendsto_integral_of_tendsto_probabilityMeasure rademacherLaw_tendsto_stdGaussian
    (compactlySupportedSqMulLogToBCF hf)
  simp only [compactlySupportedSqMulLogToBCF_apply] at h
  exact h

/-- **Entropy Convergence Theorem**

For f ∈ C_c²(ℝ), as n → ∞:
  Ent[f(Sₙ)² ; μₙ] → Ent[f(X)² ; N(0,1)]

where Sₙ = (1/√n) ∑ᵢ εᵢ is the normalized Rademacher sum and X ~ N(0,1).

This follows from weak convergence (CLT): since f² * log(f²) is bounded continuous
for compactly supported smooth f, the expectations converge.

The entropy is defined as:
  Ent_μ(g) = ∫ g log g dμ - (∫ g dμ) log(∫ g dμ)

For g = (f ∘ Sₙ)², both terms converge:
- ∫ (f(x))² log((f(x))²) d(law of Sₙ) → ∫ (f(x))² log((f(x))²) d(Gaussian)
- ∫ (f(x))² d(law of Sₙ) → ∫ (f(x))² d(Gaussian)
-/
theorem tendsto_entropy_f_sq {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => LogSobolev.entropy (rademacherLaw (n + 1)).toMeasure (fun x => (f x)^2))
      atTop (𝓝 (LogSobolev.entropy stdGaussianMeasure (fun x => (f x)^2))) := by
  -- Entropy = ∫ f² log f² - (∫ f²) log (∫ f²)
  -- Both terms converge separately
  unfold LogSobolev.entropy
  -- Term 1: ∫ f² log f² converges
  have h1 : Tendsto (fun n => ∫ x, (f x)^2 * Real.log ((f x)^2) ∂(rademacherLaw (n + 1)).toMeasure)
      atTop (𝓝 (∫ x, (f x)^2 * Real.log ((f x)^2) ∂stdGaussianMeasure)) :=
    tendsto_integral_f_sq_mul_log hf
  -- Term 2: ∫ f² converges
  have h2 : Tendsto (fun n => ∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure)
      atTop (𝓝 (∫ x, (f x)^2 ∂stdGaussianMeasure)) :=
    tendsto_integral_f_sq hf
  -- Term 3: (∫ f²) * log(∫ f²) converges (composition of h2 with continuous function x * log x)
  have h3 : Tendsto (fun n => (∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure) *
      Real.log (∫ x, (f x)^2 ∂(rademacherLaw (n + 1)).toMeasure))
      atTop (𝓝 ((∫ x, (f x)^2 ∂stdGaussianMeasure) * Real.log (∫ x, (f x)^2 ∂stdGaussianMeasure))) := by
    -- Use that x * log x is continuous, so g(aₙ) → g(a) when aₙ → a
    exact Real.continuous_mul_log.continuousAt.tendsto.comp h2
  -- Combine: entropy = term1 - term3
  exact h1.sub h3

/-- Alternative formulation using the Ent notation. -/
theorem tendsto_entropy_f_sq' {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Tendsto (fun n => Ent[(f · ^2) ; (rademacherLaw (n + 1)).toMeasure])
      atTop (𝓝 (Ent[(f · ^2) ; stdGaussianMeasure])) :=
  tendsto_entropy_f_sq hf

end GaussianPoincare

end
