/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.MeasureInfrastructure
import Mathlib.Probability.Distributions.Gaussian.Real
import Mathlib.Probability.Independence.Basic

/-!
# Gaussian Measure Properties for Product Spaces

This file establishes properties of the standard Gaussian product measure and concentration
inequalities for linear functions of Gaussian random vectors.

## Main Definitions

* `stdGaussianPi` - Product measure of n i.i.d. standard Gaussians N(0,1)

## Main Results

* `stdGaussianPi_isProbabilityMeasure` - Product Gaussian is a probability measure
* `linear_cgf_bound_stdGaussianPi` - CGF bound for linear functions of Gaussians
* `linear_tail_bound_stdGaussianPi` - Tail bound: P[⟨a,w⟩ ≥ t] ≤ exp(-t²/(2‖a‖²))
* `linear_two_sided_tail_bound_stdGaussianPi` - Two-sided tail bound
* `integral_linear_stdGaussianPi_eq_zero` - Expectation of linear combination is 0

-/

open MeasureTheory ProbabilityTheory Real Finset BigOperators

namespace GaussianMeasure

variable {n : ℕ}

/-- Standard Gaussian product measure: the product of n independent standard Gaussians N(0,1) -/
noncomputable def stdGaussianPi (n : ℕ) : Measure (Fin n → ℝ) :=
  Measure.pi fun _ : Fin n => gaussianReal 0 1

/-! ## Gaussian Measure Properties -/

/-- `stdGaussianPi` is a probability measure. -/
instance stdGaussianPi_isProbabilityMeasure : IsProbabilityMeasure (stdGaussianPi n) := by
  unfold stdGaussianPi
  infer_instance

/-- `stdGaussianPi` is a finite measure. -/
instance stdGaussianPi_isFiniteMeasure : IsFiniteMeasure (stdGaussianPi n) :=
  inferInstance

/-- `stdGaussianPi` is sigma-finite. -/
instance stdGaussianPi_isSigmaFinite : SigmaFinite (stdGaussianPi n) := by
  unfold stdGaussianPi
  infer_instance

/-! ## Standard Gaussian on EuclideanSpace -/

/-- The standard Gaussian on EuclideanSpace as pushforward of stdGaussianPi via the equivalence. -/
noncomputable def stdGaussianE (n : ℕ) : Measure (EuclideanSpace ℝ (Fin n)) :=
  Measure.map (EuclideanSpace.equiv (Fin n) ℝ).symm (stdGaussianPi n)

/-- `stdGaussianE` is a probability measure. -/
instance stdGaussianE_isProbabilityMeasure : IsProbabilityMeasure (stdGaussianE n) := by
  unfold stdGaussianE
  apply MeasureTheory.Measure.isProbabilityMeasure_map
  exact (EuclideanSpace.equiv (Fin n) ℝ).symm.continuous.measurable.aemeasurable

/-- Transfer of integrals: integrating f over stdGaussianE equals integrating f ∘ e.symm over stdGaussianPi. -/
lemma integral_stdGaussianE_eq (f : EuclideanSpace ℝ (Fin n) → ℝ) :
    ∫ x, f x ∂(stdGaussianE n) = ∫ w, f ((EuclideanSpace.equiv (Fin n) ℝ).symm w) ∂(stdGaussianPi n) := by
  unfold stdGaussianE
  exact integral_map_equiv (EuclideanSpace.equiv (Fin n) ℝ).symm.toHomeomorph.toMeasurableEquiv f

/-! ## Independence and MGF Properties

The key insight is that coordinate projections from `stdGaussianPi n` are independent
standard Gaussians. -/

/-- The coordinate projections from stdGaussianPi are independent -/
lemma iIndepFun_eval_stdGaussianPi :
    iIndepFun (fun i (w : Fin n → ℝ) => w i) (stdGaussianPi n) := by
  unfold stdGaussianPi
  exact iIndepFun_pi (fun _ => measurable_id.aemeasurable)

/-- The pushforward of stdGaussianPi under coordinate projection is gaussianReal 0 1 -/
lemma map_eval_stdGaussianPi (i : Fin n) :
    (stdGaussianPi n).map (fun w => w i) = gaussianReal 0 1 := by
  unfold stdGaussianPi
  exact (measurePreserving_eval (fun _ : Fin n => gaussianReal 0 1) i).map_eq

/-- MGF of coordinate projection equals standard Gaussian MGF -/
lemma mgf_eval_stdGaussianPi (i : Fin n) (t : ℝ) :
    mgf (fun w : Fin n → ℝ => w i) (stdGaussianPi n) t = exp (t^2 / 2) := by
  have h_map : (stdGaussianPi n).map (fun w => w i) = gaussianReal 0 1 := map_eval_stdGaussianPi i
  rw [mgf_gaussianReal h_map t]
  simp only [zero_mul, NNReal.coe_one, one_mul, zero_add]

/-- CGF of coordinate projection equals t²/2 -/
lemma cgf_eval_stdGaussianPi (i : Fin n) (t : ℝ) :
    cgf (fun w : Fin n → ℝ => w i) (stdGaussianPi n) t = t^2 / 2 := by
  unfold cgf
  rw [mgf_eval_stdGaussianPi i t]
  exact Real.log_exp (t^2 / 2)

/-- Measurability of coordinate projection -/
lemma measurable_eval (i : Fin n) : Measurable (fun w : Fin n → ℝ => w i) :=
  measurable_pi_apply i

/-- Integrability of exp(t * w_i) under stdGaussianPi -/
lemma integrable_exp_mul_eval_stdGaussianPi (i : Fin n) (t : ℝ) :
    Integrable (fun w : Fin n → ℝ => exp (t * w i)) (stdGaussianPi n) := by
  -- Use mgf_pos_iff: 0 < mgf X μ t ↔ Integrable (fun ω => exp (t * X ω)) μ
  -- Since mgf = exp(t²/2) > 0, we have integrability
  have h_mgf : mgf (fun w : Fin n → ℝ => w i) (stdGaussianPi n) t = exp (t^2 / 2) :=
    mgf_eval_stdGaussianPi i t
  have h_pos : 0 < mgf (fun w : Fin n → ℝ => w i) (stdGaussianPi n) t := by
    rw [h_mgf]; exact exp_pos _
  exact mgf_pos_iff.mp h_pos

/-! ## Scaled Coordinates

For scaled coordinates a * w_i, we compute MGF directly. -/

/-- Measurability of scaled coordinates -/
lemma measurable_mul_eval (a : Fin n → ℝ) (i : Fin n) :
    Measurable (fun w : Fin n → ℝ => a i * w i) :=
  (measurable_const_mul (a i)).comp (measurable_pi_apply i)

/-- MGF of scaled coordinate a * w_i -/
lemma mgf_mul_eval_stdGaussianPi (a : ℝ) (i : Fin n) (t : ℝ) :
    mgf (fun w : Fin n → ℝ => a * w i) (stdGaussianPi n) t = exp ((t * a)^2 / 2) := by
  -- mgf of (a * w_i) at t equals E[exp(t * a * w_i)] = mgf of w_i at (t * a)
  unfold mgf
  have h_eq : (fun w : Fin n → ℝ => exp (t * (a * w i))) =
      (fun w => exp ((t * a) * w i)) := by ext w; ring_nf
  rw [h_eq]
  -- Now use that E[exp((t*a) * w_i)] = exp((t*a)² / 2)
  have h_mgf := mgf_eval_stdGaussianPi i (t * a)
  unfold mgf at h_mgf
  rw [h_mgf]

/-- CGF of scaled coordinate a * w_i -/
lemma cgf_mul_eval_stdGaussianPi (a : ℝ) (i : Fin n) (t : ℝ) :
    cgf (fun w : Fin n → ℝ => a * w i) (stdGaussianPi n) t = (t * a)^2 / 2 := by
  unfold cgf
  rw [mgf_mul_eval_stdGaussianPi a i t]
  exact Real.log_exp ((t * a)^2 / 2)

/-- Independence of scaled coordinates -/
lemma iIndepFun_mul_eval_stdGaussianPi (a : Fin n → ℝ) :
    iIndepFun (fun i (w : Fin n → ℝ) => a i * w i) (stdGaussianPi n) := by
  apply iIndepFun.comp iIndepFun_eval_stdGaussianPi
  intro i
  exact measurable_const_mul (a i)

/-- Integrability of exp(t * (a * w_i)) under stdGaussianPi -/
lemma integrable_exp_mul_mul_eval_stdGaussianPi (a : ℝ) (i : Fin n) (t : ℝ) :
    Integrable (fun w : Fin n → ℝ => exp (t * (a * w i))) (stdGaussianPi n) := by
  have h_eq : (fun w : Fin n → ℝ => exp (t * (a * w i))) =
      (fun w => exp ((t * a) * w i)) := by ext w; ring_nf
  rw [h_eq]
  exact integrable_exp_mul_eval_stdGaussianPi i (t * a)

/-! ## CGF of Linear Sum -/

/-- CGF of linear sum ∑ aᵢwᵢ -/
lemma cgf_linear_sum_stdGaussianPi (a : Fin n → ℝ) (t : ℝ) :
    cgf (fun w : Fin n → ℝ => ∑ i, a i * w i) (stdGaussianPi n) t =
      ∑ i : Fin n, (t * a i)^2 / 2 := by
  -- Rewrite as sum of independent random variables
  have h_eq : (fun w : Fin n → ℝ => ∑ i, a i * w i) =
      (∑ i : Fin n, fun w => a i * w i) := by
    ext w
    simp only [Finset.sum_apply]
  rw [h_eq]
  -- Apply iIndepFun.cgf_sum
  have h_indep := iIndepFun_mul_eval_stdGaussianPi a
  have h_meas : ∀ i : Fin n, Measurable (fun w : Fin n → ℝ => a i * w i) :=
    fun i => measurable_mul_eval a i
  have h_int : ∀ i ∈ Finset.univ, Integrable (fun w => exp (t * (a i * w i))) (stdGaussianPi n) :=
    fun i _ => integrable_exp_mul_mul_eval_stdGaussianPi (a i) i t
  rw [h_indep.cgf_sum h_meas h_int]
  -- Now sum the individual CGFs
  apply Finset.sum_congr rfl
  intro i _
  exact cgf_mul_eval_stdGaussianPi (a i) i t

/-- Simplified CGF formula for linear sum -/
lemma cgf_linear_sum_stdGaussianPi' (a : Fin n → ℝ) (t : ℝ) :
    cgf (fun w : Fin n → ℝ => ∑ i, a i * w i) (stdGaussianPi n) t =
      t^2 * (∑ i : Fin n, (a i)^2) / 2 := by
  rw [cgf_linear_sum_stdGaussianPi]
  -- Transform ∑ i, (t * a i)^2 / 2 to (∑ i, (t * a i)^2) / 2 to t^2 * (∑ i, (a i)^2) / 2
  rw [← Finset.sum_div]
  congr 1
  rw [Finset.mul_sum]
  apply Finset.sum_congr rfl
  intro i _
  ring

/-! ## CGF Bound -/

/-- The CGF bound for linear functions (sub-Gaussian condition) -/
lemma linear_cgf_bound_stdGaussianPi (a : Fin n → ℝ) (t : ℝ) :
    cgf (fun w => ∑ i, a i * w i) (stdGaussianPi n) t ≤
      t^2 * (Real.sqrt (∑ i, (a i)^2))^2 / 2 := by
  rw [cgf_linear_sum_stdGaussianPi']
  rw [Real.sq_sqrt (sum_nonneg fun _ _ => sq_nonneg _)]

/-! ## Integrability -/

/-- Linear combinations of Gaussians have integrable exponentials -/
lemma integrable_exp_mul_linear_stdGaussianPi (a : Fin n → ℝ) (t : ℝ) :
    Integrable (fun w => exp (t * ∑ i, a i * w i)) (stdGaussianPi n) := by
  -- Use the independence-based integrability theorem
  have h := (iIndepFun_mul_eval_stdGaussianPi a).integrable_exp_mul_sum
    (fun i => measurable_mul_eval a i)
    (s := Finset.univ)
    (fun i _ => integrable_exp_mul_mul_eval_stdGaussianPi (a i) i t)
  -- The goal and h differ only by how the sum is written
  refine h.congr ?_
  filter_upwards with w
  simp only [Finset.sum_apply]

/-! ## Tail Bounds -/

/-- One-sided tail bound for linear functions of Gaussians -/
theorem linear_tail_bound_stdGaussianPi (a : Fin n → ℝ) (u : ℝ) (hu : 0 < u)
    (ha : 0 < ∑ i, (a i)^2) :
    (stdGaussianPi n {w | u ≤ ∑ i, a i * w i}).toReal ≤
      exp (-u^2 / (2 * ∑ i, (a i)^2)) := by
  -- Use chernoff_bound_subGaussian with σ = √(Σ aᵢ²)
  have hσ : 0 < Real.sqrt (∑ i, (a i)^2) := Real.sqrt_pos.mpr ha
  have h_cgf : ∀ t, cgf (fun w => ∑ i, a i * w i) (stdGaussianPi n) t ≤
      t^2 * (Real.sqrt (∑ i, (a i)^2))^2 / 2 := linear_cgf_bound_stdGaussianPi a
  have h_int : ∀ t, Integrable (fun w => exp (t * ∑ i, a i * w i)) (stdGaussianPi n) :=
    integrable_exp_mul_linear_stdGaussianPi a
  have h_bound := chernoff_bound_subGaussian hσ hu h_cgf h_int
  -- Simplify: √(Σaᵢ²)² = Σaᵢ²
  simp only [Real.sq_sqrt (sum_nonneg fun _ _ => sq_nonneg _)] at h_bound
  exact h_bound

/-- Two-sided tail bound for linear functions of Gaussians -/
theorem linear_two_sided_tail_bound_stdGaussianPi (a : Fin n → ℝ) (u : ℝ)
    (hu : 0 < u) (ha : 0 < ∑ i, (a i)^2) :
    (stdGaussianPi n {w | u ≤ |∑ i, a i * w i|}).toReal ≤
      2 * exp (-u^2 / (2 * ∑ i, (a i)^2)) := by
  -- The two-sided bound follows from union bound on positive and negative tails
  -- Note: u ≤ |x| ↔ (u ≤ x ∨ u ≤ -x) when u > 0
  have h_union : {w : Fin n → ℝ | u ≤ |∑ i, a i * w i|} ⊆
      {w | u ≤ ∑ i, a i * w i} ∪ {w | u ≤ -(∑ i, a i * w i)} := by
    intro w hw
    simp only [Set.mem_setOf_eq] at hw
    simp only [Set.mem_union, Set.mem_setOf_eq]
    rcases le_or_gt 0 (∑ i, a i * w i) with h | h
    · left
      rwa [abs_of_nonneg h] at hw
    · right
      rwa [abs_of_neg h] at hw
  -- Bound by sum of two one-sided bounds
  calc (stdGaussianPi n {w | u ≤ |∑ i, a i * w i|}).toReal
      ≤ (stdGaussianPi n ({w | u ≤ ∑ i, a i * w i} ∪ {w | u ≤ -(∑ i, a i * w i)})).toReal := by
        apply ENNReal.toReal_mono (measure_ne_top _ _)
        exact measure_mono h_union
    _ ≤ (stdGaussianPi n {w | u ≤ ∑ i, a i * w i}).toReal +
        (stdGaussianPi n {w | u ≤ -(∑ i, a i * w i)}).toReal := by
        rw [← ENNReal.toReal_add (measure_ne_top _ _) (measure_ne_top _ _)]
        apply ENNReal.toReal_mono
        · exact ENNReal.add_ne_top.mpr ⟨measure_ne_top _ _, measure_ne_top _ _⟩
        · exact measure_union_le _ _
    _ ≤ exp (-u^2 / (2 * ∑ i, (a i)^2)) + exp (-u^2 / (2 * ∑ i, (a i)^2)) := by
        apply add_le_add
        · exact linear_tail_bound_stdGaussianPi a u hu ha
        · -- For the negative, use symmetry: -⟨a,w⟩ = ⟨-a, w⟩
          have ha' : ∑ i, (-a i)^2 = ∑ i, (a i)^2 := by simp
          have h_bound := linear_tail_bound_stdGaussianPi (fun i => -a i) u hu (ha' ▸ ha)
          simp only [ha'] at h_bound
          convert h_bound using 2
          congr 1
          ext w : 1
          simp [Finset.sum_neg_distrib]
    _ = 2 * exp (-u^2 / (2 * ∑ i, (a i)^2)) := by ring

/-! ## Expectation and Centering -/

/-- Integrability of identity over Gaussian with nonzero variance -/
lemma integrable_id_gaussianReal {v : NNReal} (hv : v ≠ 0) :
    Integrable id (gaussianReal 0 v) := by
  rw [gaussianReal_of_var_ne_zero 0 hv]
  rw [integrable_withDensity_iff (measurable_gaussianPDF 0 v)]
  · -- Need to show: Integrable (fun x => x * (gaussianPDF 0 v x).toReal) volume
    have hv_pos : (0 : ℝ) < v := NNReal.coe_pos.mpr (pos_iff_ne_zero.mpr hv)
    have h1 : (0 : ℝ) < (2 * (v : ℝ))⁻¹ := by
      simp only [inv_pos]
      exact mul_pos two_pos hv_pos
    have hint : Integrable (fun x : ℝ => x * exp (-(2 * (v : ℝ))⁻¹ * x ^ 2)) volume := by
      have := integrable_mul_exp_neg_mul_sq h1
      convert this using 2
    -- gaussianPDF 0 v x = ENNReal.ofReal ((√(2 * π * v))⁻¹ * exp (-(2 * v)⁻¹ * x ^ 2))
    -- So we need to show integrability of x * (√(2 * π * v))⁻¹ * exp(...)
    have hconst : (0 : ℝ) < (Real.sqrt (2 * π * v))⁻¹ := by
      simp only [inv_pos, Real.sqrt_pos]
      exact mul_pos (mul_pos two_pos Real.pi_pos) hv_pos
    have hpdf_eq : ∀ x, (gaussianPDF 0 v x).toReal = (Real.sqrt (2 * π * v))⁻¹ * exp (-(2 * (v : ℝ))⁻¹ * x ^ 2) := by
      intro x
      simp only [gaussianPDF, gaussianPDFReal, sub_zero]
      rw [ENNReal.toReal_ofReal]
      · ring_nf
      · apply mul_nonneg (le_of_lt hconst) (Real.exp_nonneg _)
    simp only [id]
    simp_rw [hpdf_eq]
    have h2 : (fun x : ℝ => x * ((Real.sqrt (2 * π * (v : ℝ)))⁻¹ * exp (-(2 * (v : ℝ))⁻¹ * x ^ 2)))
        = (fun x => (Real.sqrt (2 * π * v))⁻¹ * (x * exp (-(2 * (v : ℝ))⁻¹ * x ^ 2))) := by
      ext x; ring
    rw [h2]
    exact Integrable.const_mul hint _
  · -- PDF is a.e. less than ⊤
    exact ae_of_all _ (fun x => ENNReal.ofReal_lt_top)

/-- The integral of id over standard Gaussian with mean 0 is 0, by symmetry -/
lemma integral_id_gaussianReal_zero (v : NNReal) : ∫ x, x ∂(gaussianReal 0 v) = 0 := by
  by_cases hv : v = 0
  · simp [hv, gaussianReal_zero_var]
  · -- Use symmetry: gaussianReal 0 v is symmetric under x ↦ -x
    have h_symm : (gaussianReal 0 v).map ((-1 : ℝ) * ·) = gaussianReal 0 v := by
      have := gaussianReal_map_const_mul (μ := 0) (v := v) (-1)
      simp only [neg_one_mul, neg_zero, neg_one_sq] at this
      convert this using 2
      · ext x; ring
      · simp only [NNReal.mk_one, one_mul]
    -- So ∫ x, x = ∫ y, (-y) = -∫ y, y, hence both are 0
    have h_neg : ∫ x, x ∂(gaussianReal 0 v) = -(∫ y, y ∂(gaussianReal 0 v)) := by
      calc ∫ x, x ∂(gaussianReal 0 v)
          = ∫ y, ((-1 : ℝ) * y) ∂((gaussianReal 0 v).map ((-1 : ℝ) * ·)) := by
            rw [integral_map (measurable_const_mul _).aemeasurable
                (measurable_const_mul _).aestronglyMeasurable]
            simp only [neg_one_mul, neg_neg]
        _ = ∫ y, ((-1 : ℝ) * y) ∂(gaussianReal 0 v) := by rw [h_symm]
        _ = -(∫ y, y ∂(gaussianReal 0 v)) := by
            simp only [neg_one_mul]
            exact integral_neg (fun y => y)
    linarith

/-- Integrability of coordinate projections over stdGaussianPi -/
lemma integrable_eval_stdGaussianPi (i : Fin n) :
    Integrable (fun w : Fin n → ℝ => w i) (stdGaussianPi n) := by
  have h : Integrable id (gaussianReal 0 1) := integrable_id_gaussianReal one_ne_zero
  have hmeas : AEMeasurable (fun w : Fin n → ℝ => w i) (stdGaussianPi n) :=
    (measurable_pi_apply i).aemeasurable
  rw [show (fun w : Fin n → ℝ => w i) = id ∘ (fun w => w i) from rfl]
  have hg : AEStronglyMeasurable id ((stdGaussianPi n).map (fun w => w i)) := by
    rw [map_eval_stdGaussianPi i]
    exact measurable_id.aestronglyMeasurable
  rw [← integrable_map_measure hg hmeas, map_eval_stdGaussianPi i]
  exact h

/-- Integrability of (w i)^2 over stdGaussianPi.
Uses the fact that exp(t * w_i) is integrable for all t, which implies all polynomial moments exist.
Key bound: |x|^2 ≤ 4 * max(exp(x), exp(-x)) ≤ 4 * (exp(x) + exp(-x)). -/
lemma integrable_sq_eval_stdGaussianPi (i : Fin n) :
    Integrable (fun w : Fin n → ℝ => (w i) ^ 2) (stdGaussianPi n) := by
  have h_exp_pos : Integrable (fun w : Fin n → ℝ => exp (w i)) (stdGaussianPi n) := by
    have h := integrable_exp_mul_eval_stdGaussianPi i 1
    convert h using 1; ext w; ring_nf
  have h_exp_neg : Integrable (fun w : Fin n → ℝ => exp (-(w i))) (stdGaussianPi n) := by
    have h := integrable_exp_mul_eval_stdGaussianPi i (-1)
    convert h using 1; ext w; ring_nf
  -- Use the bound |x|^p ≤ (p/t)^p * max(exp(t*x), exp(-t*x))
  -- With p=2, t=1: |x|² ≤ 4 * max(exp(x), exp(-x)) ≤ 4 * (exp(x) + exp(-x))
  apply Integrable.mono' ((h_exp_pos.add h_exp_neg).const_mul 4)
  · exact ((measurable_pi_apply i).pow_const 2).aestronglyMeasurable
  · filter_upwards with w
    rw [Real.norm_eq_abs, abs_of_nonneg (sq_nonneg _)]
    simp only [Pi.add_apply]
    have h_bound : |w i|^2 ≤ 4 * max (exp (w i)) (exp (-(w i))) := by
      have := ProbabilityTheory.rpow_abs_le_mul_max_exp_of_pos (w i) (p := 2) (t := 1)
        (by norm_num : (0 : ℝ) ≤ 2) (by norm_num : (0 : ℝ) < 1)
      simp only [div_one, one_mul, neg_mul] at this
      convert this using 2 <;> norm_num
    have h_max_le : max (exp (w i)) (exp (-(w i))) ≤ exp (w i) + exp (-(w i)) := by
      rcases le_or_gt (exp (w i)) (exp (-(w i))) with h | h
      · simp only [max_eq_right h]; linarith [Real.exp_pos (w i)]
      · simp only [max_eq_left (le_of_lt h)]; linarith [Real.exp_pos (-(w i))]
    calc (w i) ^ 2 = |w i| ^ 2 := by rw [sq_abs]
      _ ≤ 4 * max (exp (w i)) (exp (-(w i))) := h_bound
      _ ≤ 4 * (exp (w i) + exp (-(w i))) := by linarith [h_max_le]

/-- Integral of coordinate projection equals 0 (since Gaussian has mean 0) -/
lemma integral_eval_stdGaussianPi (i : Fin n) :
    ∫ w, w i ∂(stdGaussianPi n) = 0 := by
  have hmeas : AEMeasurable (fun w : Fin n → ℝ => w i) (stdGaussianPi n) :=
    (measurable_pi_apply i).aemeasurable
  have hg : AEStronglyMeasurable id ((stdGaussianPi n).map (fun w => w i)) := by
    rw [map_eval_stdGaussianPi i]
    exact measurable_id.aestronglyMeasurable
  calc ∫ w, w i ∂(stdGaussianPi n)
      = ∫ x, id x ∂((stdGaussianPi n).map (fun w => w i)) := by
          rw [integral_map hmeas hg]; rfl
    _ = ∫ x, id x ∂(gaussianReal 0 1) := by rw [map_eval_stdGaussianPi i]
    _ = 0 := integral_id_gaussianReal_zero 1

/-- Expectation of linear combination is 0 -/
theorem integral_linear_stdGaussianPi_eq_zero (a : Fin n → ℝ) :
    ∫ w, ∑ i, a i * w i ∂(stdGaussianPi n) = 0 := by
  rw [integral_finset_sum]
  · simp only [integral_const_mul, integral_eval_stdGaussianPi, mul_zero, Finset.sum_const_zero]
  · intro i _
    exact Integrable.const_mul (integrable_eval_stdGaussianPi i) (a i)

/-- Tail bound for centered linear combination (mean is 0) -/
theorem linear_centered_tail_bound_stdGaussianPi (a : Fin n → ℝ) (u : ℝ)
    (hu : 0 < u) (ha : 0 < ∑ i, (a i)^2) :
    (stdGaussianPi n
      {w | u ≤ (∑ i, a i * w i) - ∫ w', ∑ i, a i * w' i ∂(stdGaussianPi n)}).toReal ≤
      exp (-u^2 / (2 * ∑ i, (a i)^2)) := by
  rw [integral_linear_stdGaussianPi_eq_zero]
  simp only [sub_zero]
  exact linear_tail_bound_stdGaussianPi a u hu ha

end GaussianMeasure
