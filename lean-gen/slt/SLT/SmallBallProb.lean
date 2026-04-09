/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.Probability.Moments.Basic
import Mathlib.Probability.Density
import Mathlib.MeasureTheory.Integral.Bochner.Set
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.Analysis.SpecialFunctions.ImproperIntegrals
import Mathlib.MeasureTheory.Integral.IntegralEqImproper
import Mathlib.MeasureTheory.Integral.ExpDecay

/-!
# Small Ball Probabilities

This file formalizes small ball probability bounds for non-negative independent random variables
with bounded densities.

## Main Results

* `mgf_neg_le_inv`: For a non-negative random variable X with pdf bounded by 1,
  the MGF satisfies E[exp(-tX)] ≤ 1/t for all t > 0.
* `small_ball_prob`: For independent non-negative random variables with bounded densities,
  P(∑ᵢ Xᵢ ≤ εN) ≤ (eε)^N.
-/

open MeasureTheory ProbabilityTheory Real Set Filter
open scoped ENNReal NNReal Topology

namespace SmallBallProbability

variable {Ω : Type*} [MeasurableSpace Ω] {μ : Measure Ω}

/-! ## Part (a): MGF bound for non-negative random variables with bounded density -/

/-- The integral of exp(-t*x) over [0, ∞) equals 1/t for t > 0. -/
lemma integral_exp_neg_mul_Ioi_zero (t : ℝ) (ht : 0 < t) :
    ∫ x : ℝ in Ioi 0, exp (-t * x) = 1 / t := by
  have h1 : ∫ x : ℝ in Ioi 0, exp (-t * x) = t⁻¹ • ∫ y : ℝ in Ioi 0, exp (-y) := by
    have heq : ∀ x, exp (-t * x) = (fun y => exp (-y)) (t * x) := fun x => by ring_nf
    simp_rw [heq]
    rw [integral_comp_mul_left_Ioi (fun y => exp (-y)) 0 ht]
    simp [mul_zero]
  rw [h1, integral_exp_neg_Ioi_zero, smul_eq_mul, mul_one, one_div]

/-- For a function f : ℝ → ℝ≥0∞ bounded by 1 and supported on [0, ∞),
    the integral of f(x).toReal * exp(-tx) is at most 1/t. -/
lemma integral_exp_neg_mul_le_inv_of_dens_le_one
    {f : ℝ → ℝ≥0∞} (hf_meas : Measurable f) (hf_le : ∀ x, f x ≤ 1)
    (hf_supp : ∀ x, x < 0 → f x = 0)
    (t : ℝ) (ht : 0 < t) :
    ∫ x : ℝ, (f x).toReal * exp (-t * x) ≤ 1 / t := by
  -- First show that the integrand is non-negative and bounded by exp(-tx) on Ici 0
  have h_nonneg : ∀ x, 0 ≤ (f x).toReal * exp (-t * x) := fun x =>
    mul_nonneg ENNReal.toReal_nonneg (exp_pos _).le
  have h_bound : ∀ x ∈ Ici (0 : ℝ), (f x).toReal * exp (-t * x) ≤ exp (-t * x) := by
    intro x _
    calc (f x).toReal * exp (-t * x)
        ≤ 1 * exp (-t * x) := by
          apply mul_le_mul_of_nonneg_right _ (exp_pos _).le
          have h1 : (f x).toReal ≤ (1 : ℝ≥0∞).toReal :=
            ENNReal.toReal_mono (by norm_num : (1 : ℝ≥0∞) ≠ ⊤) (hf_le x)
          simp at h1
          exact h1
      _ = exp (-t * x) := one_mul _
  -- The function is integrable
  have h_int : Integrable (fun x => (f x).toReal * exp (-t * x)) volume := by
    rw [← integrableOn_univ, ← Iio_union_Ici (a := (0 : ℝ)), integrableOn_union]
    constructor
    · -- On Iio 0: the function is 0
      have h_zero : EqOn (fun _ => 0) (fun x => (f x).toReal * exp (-t * x)) (Iio 0) := by
        intro x hx
        simp [hf_supp x hx]
      exact integrableOn_zero.congr_fun h_zero measurableSet_Iio
    · -- On Ici 0: bounded by exp(-tx) which is integrable
      have hf_aesm : AEStronglyMeasurable (fun x => (f x).toReal * exp (-t * x)) (volume.restrict (Ici 0)) :=
        (hf_meas.ennreal_toReal.mul (measurable_exp.comp (measurable_const.mul measurable_id))).aestronglyMeasurable
      -- exp(-tx) is integrable on Ici 0 = Ioi 0 ∪ {0}
      have h_exp_int_Ici : IntegrableOn (fun x => exp (-t * x)) (Ici 0) volume := by
        rw [show Ici (0 : ℝ) = Ioi 0 ∪ {0} by ext; simp [le_iff_lt_or_eq, eq_comm]]
        exact (exp_neg_integrableOn_Ioi 0 ht).union (integrableOn_singleton (hx := by simp))
      refine Integrable.mono' h_exp_int_Ici hf_aesm ?_
      filter_upwards with x
      simp only [norm_of_nonneg (h_nonneg x)]
      by_cases hx : x ∈ Ici 0
      · exact h_bound x hx
      · simp at hx
        simp [hf_supp x hx, (exp_pos _).le]
  -- Compute the integral by splitting
  have h_iio_zero : ∫ x in Iio 0, (f x).toReal * exp (-t * x) = 0 := by
    apply setIntegral_eq_zero_of_forall_eq_zero
    intro x hx
    simp [hf_supp x (mem_Iio.mp hx)]
  have h_split : ∫ x, (f x).toReal * exp (-t * x) ∂volume =
      ∫ x in Iio 0, (f x).toReal * exp (-t * x) ∂volume +
      ∫ x in Ici 0, (f x).toReal * exp (-t * x) ∂volume := by
    have h_univ : (Set.univ : Set ℝ) = Iio 0 ∪ Ici 0 := by ext; simp
    conv_lhs => rw [← setIntegral_univ (μ := volume), h_univ]
    exact setIntegral_union (Iio_disjoint_Ici (le_refl (0 : ℝ))) measurableSet_Ici
      h_int.integrableOn h_int.integrableOn
  have h_eq_Ici : ∫ x, (f x).toReal * exp (-t * x) = ∫ x in Ici 0, (f x).toReal * exp (-t * x) := by
    simp_rw [show ∀ x, -t * x = -(t * x) by intro; ring] at h_split h_iio_zero ⊢
    linarith [h_split, h_iio_zero]
  calc ∫ x, (f x).toReal * exp (-t * x)
      = ∫ x in Ici 0, (f x).toReal * exp (-t * x) := h_eq_Ici
    _ ≤ ∫ x in Ici 0, exp (-t * x) := by
        have h_exp_int_Ici : IntegrableOn (fun x => exp (-t * x)) (Ici 0) volume := by
          rw [show Ici (0 : ℝ) = Ioi 0 ∪ {0} by ext; simp [le_iff_lt_or_eq, eq_comm]]
          exact (exp_neg_integrableOn_Ioi 0 ht).union (integrableOn_singleton (hx := by simp))
        apply setIntegral_mono_on h_int.integrableOn h_exp_int_Ici measurableSet_Ici h_bound
    _ = ∫ x in Ioi 0, exp (-t * x) := by
        have h_eq : Ici (0 : ℝ) = Ioi 0 ∪ {0} := by ext; simp [le_iff_lt_or_eq, eq_comm]
        rw [h_eq]
        have h_sing : IntegrableOn (fun x => exp (-t * x)) {0} volume :=
          integrableOn_singleton (hx := by simp)
        rw [setIntegral_union (disjoint_singleton_right.mpr notMem_Ioi_self)
          (measurableSet_singleton 0) (exp_neg_integrableOn_Ioi 0 ht) h_sing]
        simp
    _ = 1 / t := integral_exp_neg_mul_Ioi_zero t ht

/-- Variant with a.e. conditions: For a function f : ℝ → ℝ≥0∞ bounded by 1 a.e.
    and equal to 0 a.e. on (-∞, 0), the integral of f(x).toReal * exp(-tx) is at most 1/t. -/
lemma integral_exp_neg_mul_le_inv_of_dens_le_one_ae
    {f : ℝ → ℝ≥0∞} (hf_meas : Measurable f)
    (hf_le : ∀ᵐ x ∂volume, f x ≤ 1)
    (hf_supp : ∀ᵐ x ∂volume, x < 0 → f x = 0)
    (t : ℝ) (ht : 0 < t) :
    ∫ x : ℝ, (f x).toReal * exp (-t * x) ≤ 1 / t := by
  -- The integrand is bounded a.e. by exp(-tx) on [0, ∞) and is 0 a.e. on (-∞, 0)
  have h_nonneg : ∀ x, 0 ≤ (f x).toReal * exp (-t * x) := fun x =>
    mul_nonneg ENNReal.toReal_nonneg (exp_pos _).le
  have h_bound_ae : ∀ᵐ x ∂volume, (f x).toReal * exp (-t * x) ≤ exp (-t * x) := by
    filter_upwards [hf_le] with x hfx
    calc (f x).toReal * exp (-t * x)
        ≤ 1 * exp (-t * x) := by
          apply mul_le_mul_of_nonneg_right _ (exp_pos _).le
          have h1 : (f x).toReal ≤ (1 : ℝ≥0∞).toReal :=
            ENNReal.toReal_mono (by norm_num : (1 : ℝ≥0∞) ≠ ⊤) hfx
          simp at h1
          exact h1
      _ = exp (-t * x) := one_mul _
  have h_zero_ae : ∀ᵐ x ∂(volume.restrict (Iio 0)), (f x).toReal * exp (-t * x) = 0 := by
    rw [ae_restrict_iff' measurableSet_Iio]
    filter_upwards [hf_supp] with x hfx hx_mem
    simp [hfx (mem_Iio.mp hx_mem)]
  -- Integrability
  have h_int : Integrable (fun x => (f x).toReal * exp (-t * x)) volume := by
    rw [← integrableOn_univ, ← Iio_union_Ici (a := (0 : ℝ)), integrableOn_union]
    constructor
    · -- On Iio 0: the function is 0 a.e.
      exact integrableOn_zero.congr (Filter.EventuallyEq.symm h_zero_ae)
    · -- On Ici 0: bounded by exp(-tx)
      have hf_aesm : AEStronglyMeasurable (fun x => (f x).toReal * exp (-t * x))
          (volume.restrict (Ici 0)) :=
        (hf_meas.ennreal_toReal.mul
          (measurable_exp.comp (measurable_const.mul measurable_id))).aestronglyMeasurable
      have h_exp_int_Ici : IntegrableOn (fun x => exp (-t * x)) (Ici 0) volume := by
        rw [show Ici (0 : ℝ) = Ioi 0 ∪ {0} by ext; simp [le_iff_lt_or_eq, eq_comm]]
        exact (exp_neg_integrableOn_Ioi 0 ht).union (integrableOn_singleton (hx := by simp))
      refine Integrable.mono' h_exp_int_Ici hf_aesm ?_
      filter_upwards [ae_restrict_of_ae h_bound_ae] with x hx
      simp only [norm_of_nonneg (h_nonneg x)]
      exact hx
  -- The integral on Iio 0 is 0
  have h_iio_zero : ∫ x in Iio 0, (f x).toReal * exp (-t * x) = 0 := by
    have h_ae' : ∀ᵐ x ∂volume, x ∈ Iio 0 → (f x).toReal * exp (-t * x) = 0 := by
      rw [← ae_restrict_iff' measurableSet_Iio]
      exact h_zero_ae
    exact setIntegral_eq_zero_of_ae_eq_zero h_ae'
  -- The full integral equals the integral on Ici 0
  have h_split : ∫ x, (f x).toReal * exp (-t * x) ∂volume =
      ∫ x in Iio 0, (f x).toReal * exp (-t * x) ∂volume +
      ∫ x in Ici 0, (f x).toReal * exp (-t * x) ∂volume := by
    have h_univ : (Set.univ : Set ℝ) = Iio 0 ∪ Ici 0 := by ext; simp
    conv_lhs => rw [← setIntegral_univ (μ := volume), h_univ]
    exact setIntegral_union (Iio_disjoint_Ici (le_refl (0 : ℝ))) measurableSet_Ici
      h_int.integrableOn h_int.integrableOn
  have h_eq_Ici : ∫ x, (f x).toReal * exp (-t * x) = ∫ x in Ici 0, (f x).toReal * exp (-t * x) := by
    simp_rw [show ∀ x, -t * x = -(t * x) by intro; ring] at h_split h_iio_zero ⊢
    linarith [h_split, h_iio_zero]
  calc ∫ x, (f x).toReal * exp (-t * x)
      = ∫ x in Ici 0, (f x).toReal * exp (-t * x) := h_eq_Ici
    _ ≤ ∫ x in Ici 0, exp (-t * x) := by
        have h_exp_int_Ici : IntegrableOn (fun x => exp (-t * x)) (Ici 0) volume := by
          rw [show Ici (0 : ℝ) = Ioi 0 ∪ {0} by ext; simp [le_iff_lt_or_eq, eq_comm]]
          exact (exp_neg_integrableOn_Ioi 0 ht).union (integrableOn_singleton (hx := by simp))
        exact setIntegral_mono_ae h_int.integrableOn h_exp_int_Ici h_bound_ae
    _ = ∫ x in Ioi 0, exp (-t * x) := by
        have h_eq : Ici (0 : ℝ) = Ioi 0 ∪ {0} := by ext; simp [le_iff_lt_or_eq, eq_comm]
        rw [h_eq]
        have h_sing : IntegrableOn (fun x => exp (-t * x)) {0} volume :=
          integrableOn_singleton (hx := by simp)
        rw [setIntegral_union (disjoint_singleton_right.mpr notMem_Ioi_self)
          (measurableSet_singleton 0) (exp_neg_integrableOn_Ioi 0 ht) h_sing]
        simp
    _ = 1 / t := integral_exp_neg_mul_Ioi_zero t ht

/-! ## Part (b): Small ball probability bound -/

/-- The MGF bound for a single random variable: if X has pdf bounded by 1 supported on [0, ∞),
    then mgf(X, -t) ≤ 1/t for t > 0. This is a corollary stated in terms of the mgf function. -/
theorem mgf_neg_le_inv_of_pdf_bounded
    {X : Ω → ℝ} [IsProbabilityMeasure μ] (hX : Measurable X)
    [hpdf : HasPDF X μ volume]
    (hX_nn : ∀ᵐ ω ∂μ, 0 ≤ X ω)
    (hpdf_le : ∀ᵐ x ∂volume, pdf X μ volume x ≤ 1)
    (t : ℝ) (ht : 0 < t) :
    mgf X μ (-t) ≤ 1 / t := by
  unfold mgf
  -- Use the law of the unconscious statistician
  have h_eq : ∫ ω, exp ((-t) * X ω) ∂μ = ∫ x, (pdf X μ volume x).toReal * exp ((-t) * x) := by
    have hf_aesm : AEStronglyMeasurable (fun x : ℝ => exp ((-t) * x)) volume :=
      (measurable_exp.comp (measurable_const.mul measurable_id)).aestronglyMeasurable
    have h := @pdf.integral_pdf_smul _ _ _ _ μ volume _ _ _ _ X hpdf (fun x => exp ((-t) * x)) hf_aesm
    simp only [smul_eq_mul] at h
    exact h.symm
  rw [h_eq]
  -- The pdf is bounded by 1 a.e. (from hypothesis) and supported on [0, ∞) a.e. (since X ≥ 0 a.e.)
  have hf_supp : ∀ᵐ x ∂volume, x < 0 → pdf X μ volume x = 0 := by
    -- X ≥ 0 a.e. means the pushforward measure is supported on [0, ∞)
    -- So pdf is 0 a.e. on (-∞, 0)
    have h_map : μ.map X (Iio 0) = 0 := by
      rw [Measure.map_apply hX measurableSet_Iio]
      have h_subset : X ⁻¹' Iio 0 ⊆ {ω | ¬(0 ≤ X ω)} := fun ω hω => not_le.mpr (Set.mem_preimage.mp hω)
      exact measure_mono_null h_subset (ae_iff.mp hX_nn)
    -- Use that pdf integrates to the pushforward measure
    have h_integral : ∫⁻ x in Iio 0, pdf X μ volume x ∂volume ≤ μ.map X (Iio 0) :=
      setLIntegral_pdf_le_map X μ volume (Iio 0)
    rw [h_map, le_zero_iff] at h_integral
    -- Since pdf is non-negative and integral is 0, pdf is 0 a.e.
    have h_ae_zero : ∀ᵐ x ∂volume, x ∈ Iio 0 → pdf X μ volume x = 0 :=
      (setLIntegral_eq_zero_iff measurableSet_Iio (measurable_pdf X μ volume)).mp h_integral
    filter_upwards [h_ae_zero] with x hx hx_neg
    exact hx (Set.mem_Iio.mpr hx_neg)
  calc ∫ x, (pdf X μ volume x).toReal * exp ((-t) * x)
      = ∫ x, (pdf X μ volume x).toReal * exp (-t * x) := by ring_nf
    _ ≤ 1 / t := integral_exp_neg_mul_le_inv_of_dens_le_one_ae
        (measurable_pdf X μ volume) hpdf_le hf_supp t ht

/-- Helper lemma: exp(-t*x) is integrable when t > 0 and x ≥ 0 a.e. -/
private lemma integrable_exp_neg_mul_of_nonneg {X : Ω → ℝ}
    [IsProbabilityMeasure μ] (hX : Measurable X) (hX_nn : ∀ᵐ ω ∂μ, 0 ≤ X ω) (t : ℝ) (ht : 0 < t) :
    Integrable (fun ω => exp (-t * X ω)) μ := by
  refine Integrable.mono' (integrable_const 1) ?_ ?_
  · exact (measurable_exp.comp (measurable_const.mul hX)).aestronglyMeasurable
  · filter_upwards [hX_nn] with ω hω
    simp only [Real.norm_eq_abs, abs_of_pos (exp_pos _)]
    exact exp_le_one_iff.mpr (mul_nonpos_of_nonpos_of_nonneg (neg_nonpos.mpr (le_of_lt ht)) hω)

/-- Small ball probability bound: For N independent non-negative random variables Xᵢ,
    each with pdf bounded by 1, we have P(∑ Xᵢ ≤ εN) ≤ (eε)^N for ε > 0.

    This follows from Markov's inequality applied to exp(-t∑Xᵢ/ε):
    P(∑Xᵢ ≤ εN) = P(∑Xᵢ/ε ≤ N) ≤ exp(N) * E[exp(-∑Xᵢ/ε)]
                = exp(N) * ∏ᵢ E[exp(-Xᵢ/ε)]  (by independence)
                ≤ exp(N) * ε^N = (eε)^N       (using part (a) with t=1/ε)
-/
theorem small_ball_prob {ι : Type*} [Fintype ι] (X : ι → Ω → ℝ)
    [hμ : IsProbabilityMeasure μ]
    (hX_meas : ∀ i, Measurable (X i))
    (hX_indep : iIndepFun X μ)
    (hX_nn : ∀ i, ∀ᵐ ω ∂μ, 0 ≤ X i ω)
    (hX_pdf : ∀ i, HasPDF (X i) μ volume)
    (hX_pdf_le : ∀ i, ∀ᵐ x ∂volume, pdf (X i) μ volume x ≤ 1)
    (ε : ℝ) (hε : 0 < ε) (N : ℕ) (hN : N = Fintype.card ι) :
    (μ {ω : Ω | (∑ i : ι, X i ω) ≤ ε * N}).toReal ≤ ((Real.exp 1 * ε : ℝ) ^ N : ℝ) := by
  -- Parameter definitions
  have ht : 0 < ε⁻¹ := inv_pos.mpr hε
  -- Integrability of exp(-t * Xᵢ) for each i
  have h_int_each (i : ι) : Integrable (fun ω => exp (-ε⁻¹ * X i ω)) μ :=
    integrable_exp_neg_mul_of_nonneg (hX_meas i) (hX_nn i) ε⁻¹ ht
  -- Integrability of exp(-t * ∑ Xᵢ)
  have h_int : Integrable (fun ω => exp (-ε⁻¹ * ∑ i, X i ω)) μ := by
    have := iIndepFun.integrable_exp_mul_sum (t := -ε⁻¹) (s := Finset.univ) hX_indep hX_meas
      (fun i _ => h_int_each i)
    simp only [Finset.sum_apply] at this
    exact this
  -- Apply Markov bound
  have h_markov := measure_le_le_exp_mul_mgf (X := fun ω => ∑ i, X i ω)
    (ε := ε * N) (t := -ε⁻¹) (by linarith : -ε⁻¹ ≤ 0) h_int
  -- Simplify exp(-(-ε⁻¹) * εN) = exp(N)
  have h_exp_simp : exp (-(-ε⁻¹) * (ε * N)) = exp N := by
    congr 1
    field_simp
  -- mgf of sum = product of mgfs
  have h_mgf_sum : mgf (fun ω => ∑ i, X i ω) μ (-ε⁻¹) = ∏ i, mgf (X i) μ (-ε⁻¹) := by
    have := iIndepFun.mgf_sum (t := -ε⁻¹) (s := Finset.univ) hX_indep hX_meas
    convert this using 2
    ext ω
    simp only [Finset.sum_apply]
  -- Each mgf bounded by ε
  have h_mgf_bound (i : ι) : mgf (X i) μ (-ε⁻¹) ≤ ε := by
    haveI := hX_pdf i
    have h := mgf_neg_le_inv_of_pdf_bounded (hX_meas i) (hX_nn i) (hX_pdf_le i) ε⁻¹ ht
    simp only [one_div] at h
    convert h using 2; field_simp
  -- Product bound
  have h_prod_bound : ∏ i, mgf (X i) μ (-ε⁻¹) ≤ ε ^ N := by
    calc ∏ i, mgf (X i) μ (-ε⁻¹)
        ≤ ∏ _i : ι, ε := Finset.prod_le_prod (fun i _ => mgf_nonneg) (fun i _ => h_mgf_bound i)
      _ = ε ^ N := by simp only [Finset.prod_const, Finset.card_univ, hN]
  -- Final calculation
  calc (μ {ω : Ω | (∑ i : ι, X i ω) ≤ ε * N}).toReal
      ≤ exp (-(-ε⁻¹) * (ε * N)) * mgf (fun ω => ∑ i, X i ω) μ (-ε⁻¹) := h_markov
    _ = exp N * mgf (fun ω => ∑ i, X i ω) μ (-ε⁻¹) := by rw [h_exp_simp]
    _ = exp N * ∏ i, mgf (X i) μ (-ε⁻¹) := by rw [h_mgf_sum]
    _ ≤ exp N * ε ^ N := mul_le_mul_of_nonneg_left h_prod_bound (exp_pos _).le
    _ = (exp 1 * ε) ^ N := by
        have h : exp N = (exp 1 : ℝ) ^ N := by
          rw [← exp_nat_mul]; ring_nf
        rw [h, mul_comm ((exp 1) ^ N), ← mul_pow, mul_comm]

end SmallBallProbability
