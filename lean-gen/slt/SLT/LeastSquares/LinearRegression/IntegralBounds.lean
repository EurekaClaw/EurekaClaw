/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib

/-!
# Integral Bounds for Entropy Integrals

This file contains standalone analytical bounds used in entropy integral calculations.
All lemmas are pure analysis results with no project-specific dependencies.

## Main Results

* `integral_constant_bound`: The integral ∫₀¹ √(log(1 + 2/u)) du ≤ √(log 3) + √π/2
* `integral_constant_lt_two`: The integral ∫₀¹ √(log(1 + 2/u)) du < 2
* `integral_bound`: The main integral bound (1/√n) ∫₀^δ √(d * log(1+2δ/s)) ds ≤ 2δ√(d/n)

-/

open MeasureTheory Finset BigOperators Real ProbabilityTheory Metric Set
open scoped NNReal ENNReal

/-- Upper bound: 1 + 2/u ≤ 3/u for u ∈ (0, 1] -/
lemma one_plus_two_div_le_three_div {u : ℝ} (hu0 : 0 < u) (hu1 : u ≤ 1) :
    1 + 2 / u ≤ 3 / u := by
  have hu_ne : u ≠ 0 := ne_of_gt hu0
  have h1 : 1 ≤ 1 / u := by
    rw [one_le_div hu0]
    exact hu1
  have h3 : 3 / u = 1 / u + 2 / u := by field_simp; ring
  rw [h3]
  linarith

/-- log(1 + 2/u) ≤ log 3 + log(1/u) for u ∈ (0, 1] -/
lemma log_one_plus_two_div_le {u : ℝ} (hu0 : 0 < u) (hu1 : u ≤ 1) :
    Real.log (1 + 2 / u) ≤ Real.log 3 + Real.log (1 / u) := by
  have h1u_pos : 0 < 1 / u := div_pos one_pos hu0
  have h12u_pos : 0 < 1 + 2 / u := by
    have : 0 < 2 / u := div_pos (by norm_num) hu0
    linarith
  calc Real.log (1 + 2 / u)
      ≤ Real.log (3 / u) := by
        apply Real.log_le_log h12u_pos
        exact one_plus_two_div_le_three_div hu0 hu1
      _ = Real.log 3 + Real.log (1 / u) := by
        rw [div_eq_mul_one_div 3 u, Real.log_mul (by norm_num) (ne_of_gt h1u_pos)]

/-- √(a + b) ≤ √a + √b for non-negative a, b -/
lemma sqrt_add_le {a b : ℝ} (ha : 0 ≤ a) (hb : 0 ≤ b) :
    Real.sqrt (a + b) ≤ Real.sqrt a + Real.sqrt b := by
  have hsum_nonneg : 0 ≤ Real.sqrt a + Real.sqrt b := by
    apply add_nonneg (Real.sqrt_nonneg a) (Real.sqrt_nonneg b)
  rw [← Real.sqrt_sq hsum_nonneg]
  apply Real.sqrt_le_sqrt
  ring_nf
  have h1 : (Real.sqrt a) ^ 2 = a := Real.sq_sqrt ha
  have h2 : (Real.sqrt b) ^ 2 = b := Real.sq_sqrt hb
  have h3 : 0 ≤ 2 * Real.sqrt a * Real.sqrt b := by
    apply mul_nonneg
    apply mul_nonneg (by norm_num : (0 : ℝ) ≤ 2) (Real.sqrt_nonneg a)
    exact Real.sqrt_nonneg b
  linarith

/-- Pointwise bound: √(log(1 + 2/u)) ≤ √(log 3) + √(-log u) for u ∈ (0, 1) -/
lemma sqrt_log_one_plus_two_div_bound {u : ℝ} (hu : u ∈ Set.Ioo 0 1) :
    Real.sqrt (Real.log (1 + 2 / u)) ≤
    Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u) := by
  have hlog_one_u : Real.log (1 / u) = -Real.log u := by
    rw [one_div, Real.log_inv]
  have h_log_bound := log_one_plus_two_div_le hu.1 (le_of_lt hu.2)
  rw [hlog_one_u] at h_log_bound
  have hlog3_nonneg : 0 ≤ Real.log 3 := Real.log_nonneg (by norm_num : (1 : ℝ) ≤ 3)
  have hneg_log_nonneg : 0 ≤ -Real.log u := by
    rw [neg_nonneg]
    exact Real.log_nonpos (le_of_lt hu.1) (le_of_lt hu.2)
  calc Real.sqrt (Real.log (1 + 2 / u))
      ≤ Real.sqrt (Real.log 3 + (-Real.log u)) := Real.sqrt_le_sqrt h_log_bound
    _ ≤ Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u) :=
        sqrt_add_le hlog3_nonneg hneg_log_nonneg

/-- Measurability of √(d * log(1 + c/x)) -/
lemma measurable_sqrt_d_log_one_plus_c_div (d : ℕ) (c : ℝ) :
    Measurable (fun x : ℝ => Real.sqrt (d * Real.log (1 + c / x))) := by
  apply Measurable.sqrt
  apply Measurable.mul measurable_const
  apply Real.measurable_log.comp
  apply Measurable.add measurable_const
  apply Measurable.div measurable_const measurable_id

/-- log(1 + 2δ/ε) ≤ log(1 + 2δ) - log(ε) for ε ∈ (0, 1) -/
lemma log_one_plus_two_delta_div_eps_bound {δ ε : ℝ} (hδ : 0 < δ)
    (hε_pos : 0 < ε) (hε_lt : ε < 1) :
    Real.log (1 + 2 * δ / ε) ≤ Real.log (1 + 2 * δ) - Real.log ε := by
  have h_ineq : 1 + 2 * δ / ε ≤ (1 + 2 * δ) / ε := by
    rw [add_div]
    have h1 : 1 ≤ 1 / ε := by rw [one_le_div hε_pos]; linarith
    linarith
  have h12δ_pos : 0 < 1 + 2 * δ := by linarith
  calc Real.log (1 + 2 * δ / ε)
      ≤ Real.log ((1 + 2 * δ) / ε) := by
        apply Real.log_le_log (by positivity) h_ineq
      _ = Real.log (1 + 2 * δ) - Real.log ε := by
        rw [Real.log_div (ne_of_gt h12δ_pos) (ne_of_gt hε_pos)]

/-- The Gamma function at 3/2 equals √π/2 -/
lemma Gamma_three_halves : Real.Gamma (3 / 2) = Real.sqrt Real.pi / 2 := by
  have h1 : (3 : ℝ) / 2 = 1 / 2 + 1 := by norm_num
  rw [h1, Real.Gamma_add_one (by norm_num : (1 : ℝ) / 2 ≠ 0)]
  rw [Real.Gamma_one_half_eq]
  ring

/-- The integral ∫₀^∞ t^(1/2) * e^(-t) dt = Γ(3/2) = √π/2.
This is a direct consequence of the Gamma function integral representation. -/
lemma integral_sqrt_exp_neg_eq_Gamma_three_halves :
    ∫ t in Set.Ioi (0 : ℝ), t ^ ((2 : ℝ)⁻¹) * Real.exp (-t) =
    Real.sqrt Real.pi / 2 := by
  have h := integral_rpow_mul_exp_neg_rpow (p := 1) (q := 1/2) (by norm_num : (0 : ℝ) < 1)
      (by norm_num : (-1 : ℝ) < 1/2)
  simp only [Real.rpow_one, one_div] at h
  -- The integral equals 1⁻¹ * Γ((1/2 + 1)/1) = Γ(3/2) = √π/2
  have heq : ∫ t in Set.Ioi (0 : ℝ), t ^ ((2 : ℝ)⁻¹) * Real.exp (-t) =
             ∫ x in Set.Ioi (0 : ℝ), x ^ ((2 : ℝ)⁻¹) * Real.exp (-x) := rfl
  rw [heq, h]
  have h3 : ((2 : ℝ)⁻¹ + 1) / 1 = 3/2 := by norm_num
  rw [h3, Gamma_three_halves]
  simp

/-- √t = t^(1/2) for non-negative t -/
lemma sqrt_eq_rpow_half (t : ℝ) : Real.sqrt t = t ^ ((2 : ℝ)⁻¹) := by
  rw [Real.sqrt_eq_rpow, one_div]

/-- Integral equivalence: ∫ √t * e^(-t) dt = ∫ t^(1/2) * e^(-t) dt -/
lemma integral_sqrt_eq_integral_rpow :
    ∫ t in Set.Ioi (0 : ℝ), Real.sqrt t * Real.exp (-t) =
    ∫ t in Set.Ioi (0 : ℝ), t ^ ((2 : ℝ)⁻¹) * Real.exp (-t) := by
  congr 1
  ext t
  rw [sqrt_eq_rpow_half]

/-- The integral ∫_{Ioi 0} √t * e^{-t} dt equals √π/2 -/
lemma integral_sqrt_mul_exp_neg_Ioi :
    ∫ t in Set.Ioi (0 : ℝ), Real.sqrt t * Real.exp (-t) = Real.sqrt Real.pi / 2 := by
  rw [integral_sqrt_eq_integral_rpow]
  exact integral_sqrt_exp_neg_eq_Gamma_three_halves

/-- The integral ∫_{Ioo 0 1} √(-log u) du = √π/2.
This follows from the substitution t = -log u via change of variables. -/
lemma integral_sqrt_neg_log_Ioo :
    ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (-Real.log u) =
    Real.sqrt Real.pi / 2 := by
  -- Use change of variables with f(t) = exp(-t) mapping Ioi 0 → Ioo 0 1
  -- f'(t) = -exp(-t), |f'(t)| = exp(-t)
  -- The formula: ∫_{image f s} g(u) du = ∫_s |f'(t)| * g(f(t)) dt
  have h_image : Set.image (fun t => Real.exp (-t)) (Set.Ioi 0) = Set.Ioo 0 1 := by
    ext u
    simp only [Set.mem_image, Set.mem_Ioi, Set.mem_Ioo]
    constructor
    · rintro ⟨t, ht, rfl⟩
      constructor
      · exact Real.exp_pos _
      · rw [Real.exp_lt_one_iff]
        linarith
    · intro ⟨hu_pos, hu_lt⟩
      use -Real.log u
      constructor
      · rw [neg_pos, Real.log_neg_iff hu_pos]
        exact hu_lt
      · rw [neg_neg, Real.exp_log hu_pos]
  rw [← h_image]
  -- Now apply change of variables
  have hmeas : MeasurableSet (Set.Ioi (0 : ℝ)) := measurableSet_Ioi
  have hderiv : ∀ x ∈ Set.Ioi (0 : ℝ), HasDerivWithinAt (fun t => Real.exp (-t))
      (-Real.exp (-x)) (Set.Ioi 0) x := by
    intro x _
    have : HasDerivAt (fun t => Real.exp (-t)) (-Real.exp (-x)) x := by
      have h := Real.hasDerivAt_exp (-x)
      have : HasDerivAt (fun t => -t) (-1 : ℝ) x := by simp [hasDerivAt_neg']
      convert h.comp x this using 1
      ring
    exact this.hasDerivWithinAt
  have hinj : Set.InjOn (fun t => Real.exp (-t)) (Set.Ioi 0) := by
    intro x hx y hy hxy
    simp only at hxy
    have := Real.exp_injective hxy
    linarith
  rw [MeasureTheory.integral_image_eq_integral_abs_deriv_smul hmeas
      (fun x hx => hderiv x hx) hinj (fun u => Real.sqrt (-Real.log u))]
  -- Now simplify the RHS
  have h_eq : ∀ t ∈ Set.Ioi (0 : ℝ), |-(Real.exp (-t))| • Real.sqrt (-Real.log (Real.exp (-t))) =
      Real.sqrt t * Real.exp (-t) := by
    intro t ht
    simp only [abs_neg, abs_of_pos (Real.exp_pos _), Real.log_exp, neg_neg]
    rw [smul_eq_mul, mul_comm]
  have h_int_eq : ∫ x in Set.Ioi (0 : ℝ), |-(Real.exp (-x))| • Real.sqrt (-Real.log (Real.exp (-x))) =
      ∫ t in Set.Ioi (0 : ℝ), Real.sqrt t * Real.exp (-t) := by
    apply MeasureTheory.setIntegral_congr_fun measurableSet_Ioi
    exact h_eq
  rw [h_int_eq]
  exact integral_sqrt_mul_exp_neg_Ioi

/-- Helper: integrability of √(-log u) on Ioo 0 1 -/
lemma integrableOn_sqrt_neg_log :
    MeasureTheory.IntegrableOn (fun u => Real.sqrt (-Real.log u)) (Set.Ioo (0 : ℝ) 1) volume := by
  -- First establish the image relationship
  have h_image : Set.image (fun t => Real.exp (-t)) (Set.Ioi 0) = Set.Ioo 0 1 := by
    ext u
    simp only [Set.mem_image, Set.mem_Ioi, Set.mem_Ioo]
    constructor
    · rintro ⟨t, ht, rfl⟩
      exact ⟨Real.exp_pos _, by rw [Real.exp_lt_one_iff]; linarith⟩
    · intro ⟨hu_pos, hu_lt⟩
      exact ⟨-Real.log u, by rw [neg_pos, Real.log_neg_iff hu_pos]; exact hu_lt,
             by rw [neg_neg, Real.exp_log hu_pos]⟩
  rw [← h_image]
  rw [MeasureTheory.integrableOn_image_iff_integrableOn_abs_deriv_smul
      measurableSet_Ioi
      (fun x _ => by
        have : HasDerivAt (fun t => Real.exp (-t)) (-Real.exp (-x)) x := by
          have h := Real.hasDerivAt_exp (-x)
          have : HasDerivAt (fun t => -t) (-1 : ℝ) x := by simp [hasDerivAt_neg']
          convert h.comp x this using 1
          ring
        exact this.hasDerivWithinAt)
      (fun x _ y _ hxy => by
        have := Real.exp_injective hxy
        linarith)]
  have h_eq : ∀ t ∈ Set.Ioi (0 : ℝ),
      |-(Real.exp (-t))| • Real.sqrt (-Real.log (Real.exp (-t))) =
      Real.sqrt t * Real.exp (-t) := by
    intro t _
    simp only [abs_neg, abs_of_pos (Real.exp_pos _), Real.log_exp, neg_neg, smul_eq_mul, mul_comm]
  have h_eq' : Set.EqOn (fun x => |-(Real.exp (-x))| • Real.sqrt (-Real.log (Real.exp (-x))))
      (fun t => Real.sqrt t * Real.exp (-t)) (Set.Ioi 0) := h_eq
  rw [MeasureTheory.integrableOn_congr_fun h_eq' measurableSet_Ioi]
  -- Use Gamma function integrability: exp(-x) * x^(s-1) is integrable on Ioi 0 for s > 0
  -- For s = 3/2, we get √x * exp(-x) is integrable
  have h_gamma := Real.GammaIntegral_convergent (by norm_num : (0 : ℝ) < 3/2)
  -- h_gamma says exp(-x) * x^(1/2) is integrable on Ioi 0
  have h_eq'' : Set.EqOn (fun t => Real.sqrt t * Real.exp (-t))
      (fun x => Real.exp (-x) * x ^ ((3 : ℝ)/2 - 1)) (Set.Ioi 0) := by
    intro t ht
    simp only [Set.mem_Ioi] at ht
    show Real.sqrt t * Real.exp (-t) = Real.exp (-t) * t ^ ((3 : ℝ)/2 - 1)
    have hsqrt : Real.sqrt t = t ^ ((2 : ℝ)⁻¹) := sqrt_eq_rpow_half t
    have hexp : (3 : ℝ) / 2 - 1 = (2 : ℝ)⁻¹ := by norm_num
    rw [hsqrt, hexp, mul_comm]
  rw [MeasureTheory.integrableOn_congr_fun h_eq'' measurableSet_Ioi]
  exact h_gamma

/-- Integrability of √d * (√(log 3) + √(-log u)) on (0,1) -/
lemma integrableOn_sqrt_d_times_bound (d : ℕ) :
    MeasureTheory.IntegrableOn
      (fun u => Real.sqrt d * (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)))
      (Set.Ioo (0 : ℝ) 1) volume := by
  have h_Ioo_finite : volume (Set.Ioo (0 : ℝ) 1) ≠ ⊤ := by
    rw [Real.volume_Ioo]; exact ENNReal.ofReal_ne_top
  have h_const_int : MeasureTheory.IntegrableOn
      (fun _ : ℝ => Real.sqrt d * Real.sqrt (Real.log 3))
      (Set.Ioo (0 : ℝ) 1) volume :=
    MeasureTheory.integrableOn_const h_Ioo_finite
  have h_sqrt_int : MeasureTheory.IntegrableOn
      (fun u => Real.sqrt d * Real.sqrt (-Real.log u)) (Set.Ioo (0 : ℝ) 1) volume := by
    apply MeasureTheory.Integrable.const_mul
    exact integrableOn_sqrt_neg_log
  simp_rw [mul_add]
  exact MeasureTheory.Integrable.add h_const_int h_sqrt_int

/-- The integral constant bound: ∫₀¹ √(log(1 + 2/u)) du ≤ √(log 3) + √π/2.

The proof follows the standard analysis argument:
1. For u ∈ (0,1]: 1 + 2/u ≤ 3/u, so log(1+2/u) ≤ log 3 + log(1/u)
2. Using √(a+b) ≤ √a + √b: √(log(1+2/u)) ≤ √(log 3) + √(log(1/u))
3. Integrating: ∫₀¹ √(log 3) du = √(log 3)
4. Via substitution t = -log u: ∫₀¹ √(log(1/u)) du = ∫₀^∞ √t e^{-t} dt = Γ(3/2) = √π/2

-/
theorem integral_constant_bound :
    ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) ≤
    Real.sqrt (Real.log 3) + Real.sqrt Real.pi / 2 := by
  -- Convert interval integral to set integral over Ioc 0 1
  rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
  -- Ioc 0 1 has the same integral as Ioo 0 1 for Lebesgue measure
  have h_Ioc_eq_Ioo : ∫ u in Set.Ioc (0 : ℝ) 1, Real.sqrt (Real.log (1 + 2 / u)) =
      ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log (1 + 2 / u)) :=
    MeasureTheory.integral_Ioc_eq_integral_Ioo
  rw [h_Ioc_eq_Ioo]
  -- Now we use the pointwise bound:
  -- For u ∈ (0, 1]: √(log(1+2/u)) ≤ √(log 3) + √(log(1/u))
  -- Note: log(1/u) = -log u for u > 0
  have h_pointwise : ∀ u ∈ Set.Ioo (0 : ℝ) 1,
      Real.sqrt (Real.log (1 + 2 / u)) ≤
      Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u) := by
    intro u ⟨hu_pos, hu_lt⟩
    have hlog_one_u : Real.log (1 / u) = -Real.log u := by
      rw [one_div, Real.log_inv]
    have h_bound := log_one_plus_two_div_le hu_pos (le_of_lt hu_lt)
    rw [hlog_one_u] at h_bound
    -- We have: log(1+2/u) ≤ log 3 + (-log u)
    -- Need: √(log(1+2/u)) ≤ √(log 3) + √(-log u)
    have hlog3_nonneg : 0 ≤ Real.log 3 := Real.log_nonneg (by norm_num : (1 : ℝ) ≤ 3)
    have hneg_log_nonneg : 0 ≤ -Real.log u := by
      rw [neg_nonneg]
      exact Real.log_nonpos (le_of_lt hu_pos) (le_of_lt hu_lt)
    calc Real.sqrt (Real.log (1 + 2 / u))
        ≤ Real.sqrt (Real.log 3 + (-Real.log u)) := by
          apply Real.sqrt_le_sqrt
          exact h_bound
        _ ≤ Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u) :=
          sqrt_add_le hlog3_nonneg hneg_log_nonneg
  -- Apply integral monotonicity using setIntegral_mono_on
  -- First establish integrability of RHS using our helper lemma
  -- IntegrableOn f s μ is defined as Integrable f (μ.restrict s)
  have h_Ioo_finite : volume (Set.Ioo (0 : ℝ) 1) ≠ ⊤ := by
    rw [Real.volume_Ioo]
    exact ENNReal.ofReal_ne_top
  have h_const_int : MeasureTheory.IntegrableOn
      (fun _ : ℝ => Real.sqrt (Real.log 3)) (Set.Ioo (0 : ℝ) 1) volume :=
    MeasureTheory.integrableOn_const h_Ioo_finite
  have h_rhs_int : MeasureTheory.IntegrableOn
      (fun u => Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) (Set.Ioo (0 : ℝ) 1) volume :=
    MeasureTheory.Integrable.add h_const_int integrableOn_sqrt_neg_log
  -- Integrability of LHS: we use Integrable.mono' with the bound on Ioo 0 1
  have h_lhs_int : MeasureTheory.IntegrableOn
      (fun u => Real.sqrt (Real.log (1 + 2 / u))) (Set.Ioo (0 : ℝ) 1) volume := by
    apply MeasureTheory.Integrable.mono' h_rhs_int
    · -- AEStronglyMeasurable on the restricted measure
      apply Measurable.aestronglyMeasurable
      apply Measurable.sqrt
      apply Measurable.log
      apply Measurable.add measurable_const
      apply Measurable.div measurable_const measurable_id
    · -- The bound holds ae on Ioo 0 1 with respect to the restricted measure
      filter_upwards [MeasureTheory.ae_restrict_mem measurableSet_Ioo] with u hu
      rw [Real.norm_eq_abs, abs_of_nonneg (Real.sqrt_nonneg _)]
      exact h_pointwise u hu
  have h_le : ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log (1 + 2 / u)) ≤
      ∫ u in Set.Ioo (0 : ℝ) 1, (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) := by
    apply MeasureTheory.setIntegral_mono_on h_lhs_int h_rhs_int measurableSet_Ioo
    intro u hu
    exact h_pointwise u hu
  -- Now split the integral on the RHS
  have h_split : ∫ u in Set.Ioo (0 : ℝ) 1, (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) =
      (∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log 3)) +
      ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (-Real.log u) :=
    MeasureTheory.integral_add h_const_int integrableOn_sqrt_neg_log
  -- Evaluate the first integral: ∫ √(log 3) du over Ioo 0 1 = √(log 3) * measure(Ioo 0 1) = √(log 3)
  have h_const : ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log 3) = Real.sqrt (Real.log 3) := by
    rw [MeasureTheory.setIntegral_const]
    -- Need to show: volume.real (Set.Ioo 0 1) • √(log 3) = √(log 3)
    -- This is: (volume (Set.Ioo 0 1)).toReal • √(log 3) = √(log 3)
    have h_meas_real : volume.real (Set.Ioo (0 : ℝ) 1) = 1 := by
      simp only [MeasureTheory.Measure.real, Real.volume_Ioo]
      rw [ENNReal.toReal_ofReal (by norm_num : (0 : ℝ) ≤ 1 - 0)]
      norm_num
    rw [h_meas_real, one_smul]
  -- Combine the results
  calc ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log (1 + 2 / u))
      ≤ ∫ u in Set.Ioo (0 : ℝ) 1, (Real.sqrt (Real.log 3) + Real.sqrt (-Real.log u)) := h_le
      _ = (∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (Real.log 3)) +
          ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (-Real.log u) := h_split
      _ = Real.sqrt (Real.log 3) + ∫ u in Set.Ioo (0 : ℝ) 1, Real.sqrt (-Real.log u) := by
          rw [h_const]
      _ = Real.sqrt (Real.log 3) + Real.sqrt Real.pi / 2 := by
          rw [integral_sqrt_neg_log_Ioo]

/-- Numerical bound: √(log 3) + √π/2 < 2 -/
lemma sqrt_log3_plus_sqrt_pi_div_2_lt_two :
    Real.sqrt (Real.log 3) + Real.sqrt Real.pi / 2 < 2 := by
  -- √(log 3) ≈ 1.048, √π/2 ≈ 0.886, sum ≈ 1.934 < 2
  -- We prove: log 3 < 1.1, so √(log 3) < √1.1 < 1.05
  -- And: π < 3.15, so √π < √3.15 < 1.78, so √π/2 < 0.89
  -- Total: 1.05 + 0.89 = 1.94 < 2
  have hlog3_lt : Real.log 3 < 1.1 := by
    -- We show exp 1.1 > 3, hence log 3 < 1.1
    -- exp 1.1 ≈ 3.0041... > 3
    -- Numerical verification: exp 1.1 = e^1.1 ≈ 3.00417
    have hexp_gt : Real.exp 1.1 > 3 := by
      -- exp 1 > 2.718281 (from exp_one_gt_d9)
      have h1 : Real.exp 1 > 2.718281 := by
        have := Real.exp_one_gt_d9
        linarith
      -- exp 0.1 > 1.105 (from exp x ≥ 1 + x + x²/2)
      -- Use quadratic lower bound: exp x ≥ 1 + x + x²/2 for x ≥ 0
      have h01 : Real.exp 0.1 ≥ 1.105 := by
        have hquad := Real.quadratic_le_exp_of_nonneg (by norm_num : (0 : ℝ) ≤ 0.1)
        linarith
      -- exp 1 > 2.718281 (strict) and exp 0.1 ≥ 1.105 (non-strict)
      -- Since exp 1 > 2.718281 > 0 and exp 0.1 ≥ 1.105 > 0,
      -- we get exp 1 * exp 0.1 > 2.718281 * 1.105 > 3
      calc Real.exp 1.1 = Real.exp (1 + 0.1) := by ring_nf
        _ = Real.exp 1 * Real.exp 0.1 := Real.exp_add 1 0.1
        _ > 2.718281 * 1.105 := by
          nlinarith [Real.exp_one_gt_d9, Real.exp_pos 0.1]
        _ > 3 := by norm_num
    have h : Real.log 3 < Real.log (Real.exp 1.1) := by
      apply Real.log_lt_log (by norm_num : (0 : ℝ) < 3) hexp_gt
    simp only [Real.log_exp] at h
    exact h
  have hsqrt_log3 : Real.sqrt (Real.log 3) < 1.05 := by
    have hlog3_nonneg : 0 ≤ Real.log 3 := Real.log_nonneg (by norm_num : (1 : ℝ) ≤ 3)
    have h1 : Real.log 3 < 1.05 ^ 2 := by
      calc Real.log 3 < 1.1 := hlog3_lt
        _ < 1.1025 := by norm_num
        _ = 1.05 ^ 2 := by norm_num
    have h2 := Real.sqrt_lt_sqrt hlog3_nonneg h1
    simp only [Real.sqrt_sq (by norm_num : (0 : ℝ) ≤ 1.05)] at h2
    exact h2
  have hpi_lt : Real.pi < 3.15 := Real.pi_lt_d2
  have hsqrt_pi : Real.sqrt Real.pi < 1.78 := by
    have hpi_nonneg : 0 ≤ Real.pi := le_of_lt Real.pi_pos
    have h1 : Real.pi < 1.78 ^ 2 := by
      calc Real.pi < 3.15 := hpi_lt
        _ < 3.1684 := by norm_num
        _ = 1.78 ^ 2 := by norm_num
    have h2 := Real.sqrt_lt_sqrt hpi_nonneg h1
    simp only [Real.sqrt_sq (by norm_num : (0 : ℝ) ≤ 1.78)] at h2
    exact h2
  calc Real.sqrt (Real.log 3) + Real.sqrt Real.pi / 2
      < 1.05 + 1.78 / 2 := by linarith
      _ = 1.05 + 0.89 := by norm_num
      _ = 1.94 := by norm_num
      _ < 2 := by norm_num

/-- The integral constant is less than 2 -/
theorem integral_constant_lt_two :
    ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) < 2 := by
  calc ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u))
      ≤ Real.sqrt (Real.log 3) + Real.sqrt Real.pi / 2 := integral_constant_bound
      _ < 2 := sqrt_log3_plus_sqrt_pi_div_2_lt_two

/-- Helper: Scaling the integral ∫₀^δ f(s) ds = δ ∫₀^1 f(δu) du via change of variable -/
lemma integral_scale {f : ℝ → ℝ} {δ : ℝ} (_hδ : 0 < δ) (_hf : IntervalIntegrable f volume 0 δ) :
    ∫ s in (0 : ℝ)..δ, f s = δ * ∫ u in (0 : ℝ)..1, f (δ * u) := by
  -- Use substitution s = δ * u
  have h := @intervalIntegral.mul_integral_comp_mul_left 0 1 f δ
  simp only [mul_zero, mul_one] at h
  exact h.symm

/-- (1/√n) δ * ∫₀^1 √(d * log(1+2/u)) du ≤ 2δ√(d/n) -/
theorem intermediate_integral_bound
    {n d : ℕ} (hn : 0 < n) (hd : 0 < d)
    {δ : ℝ} (hδ : 0 < δ) :
    (n : ℝ)⁻¹.sqrt * (δ * ∫ u in (0 : ℝ)..1, Real.sqrt (d * Real.log (1 + 2 / u))) ≤
    2 * δ * Real.sqrt ((d : ℝ) / n) := by
  -- Factor out √d from the integral
  have hd_pos : (0 : ℝ) < d := Nat.cast_pos.mpr hd
  have hn_pos : (0 : ℝ) < n := Nat.cast_pos.mpr hn
  have h_sqrt_factor : ∀ u, Real.sqrt (d * Real.log (1 + 2 / u)) =
      Real.sqrt d * Real.sqrt (Real.log (1 + 2 / u)) := fun u => by
    by_cases hlog : 0 ≤ Real.log (1 + 2 / u)
    · exact Real.sqrt_mul (Nat.cast_nonneg d) _
    · push_neg at hlog
      have h1 : Real.sqrt (d * Real.log (1 + 2 / u)) = 0 := by
        apply Real.sqrt_eq_zero'.mpr
        exact mul_nonpos_of_nonneg_of_nonpos (Nat.cast_nonneg d) (le_of_lt hlog)
      have h2 : Real.sqrt (Real.log (1 + 2 / u)) = 0 := by
        apply Real.sqrt_eq_zero'.mpr
        exact le_of_lt hlog
      simp [h1, h2]
  simp_rw [h_sqrt_factor]
  rw [intervalIntegral.integral_const_mul]
  -- Rearrange: √(n⁻¹) * (δ * (√d * ∫...)) = δ * √(d/n) * ∫...
  have h_rearrange : (n : ℝ)⁻¹.sqrt * (δ * (Real.sqrt d * ∫ u in (0 : ℝ)..1,
      Real.sqrt (Real.log (1 + 2 / u)))) =
      δ * Real.sqrt ((d : ℝ) / n) * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u)) := by
    have hsqrt_div : Real.sqrt ((d : ℝ) / n) = Real.sqrt d / Real.sqrt n := by
      rw [Real.sqrt_div (Nat.cast_nonneg d)]
    have hsqrt_inv : (n : ℝ)⁻¹.sqrt = 1 / Real.sqrt n := by
      rw [Real.sqrt_inv n, one_div]
    rw [hsqrt_inv, hsqrt_div]
    ring
  rw [h_rearrange]
  -- Apply the integral bound
  have hint := integral_constant_lt_two
  have hcalc : δ * Real.sqrt ((d : ℝ) / n) * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u))
      < 2 * δ * Real.sqrt ((d : ℝ) / n) := by
    calc δ * Real.sqrt ((d : ℝ) / n) * ∫ u in (0 : ℝ)..1, Real.sqrt (Real.log (1 + 2 / u))
        < δ * Real.sqrt ((d : ℝ) / n) * 2 := by
          apply mul_lt_mul_of_pos_left hint
          apply mul_pos hδ
          apply Real.sqrt_pos.mpr
          exact div_pos hd_pos hn_pos
        _ = 2 * δ * Real.sqrt ((d : ℝ) / n) := by ring
  exact le_of_lt hcalc

/-- The main integral bound: (1/√n) ∫₀^δ √(d * log(1+2δ/s)) ds ≤ 2δ√(d/n).

This follows from the change of variables s = δu, giving:
  ∫₀^δ √(d * log(1+2δ/s)) ds = δ ∫₀^1 √(d * log(1+2δ/(δu))) du = δ ∫₀^1 √(d * log(1+2/u)) du
Then `intermediate_integral_bound` provides the final bound. -/
theorem integral_bound {n d : ℕ} (hn : 0 < n) (hd : 0 < d) {δ : ℝ} (hδ : 0 < δ) :
    (n : ℝ)⁻¹.sqrt * ∫ s in (0 : ℝ)..δ, Real.sqrt (d * Real.log (1 + 2 * δ / s)) ≤
    2 * δ * Real.sqrt ((d : ℝ) / n) := by
  -- Step 1: Change of variables via s = δu, so ∫₀^δ f(s) ds = δ ∫₀^1 f(δu) du
  have h_cov : ∫ s in (0 : ℝ)..δ, Real.sqrt (↑d * Real.log (1 + 2 * δ / s)) =
      δ * ∫ u in (0 : ℝ)..1, Real.sqrt (↑d * Real.log (1 + 2 * δ / (δ * u))) := by
    have := @intervalIntegral.mul_integral_comp_mul_left 0 1
        (fun s => Real.sqrt (↑d * Real.log (1 + 2 * δ / s))) δ
    simp only [mul_zero, mul_one] at this
    exact this.symm
  -- Step 2: Simplify 2δ/(δu) = 2/u on (0, 1]
  have h_simp : ∫ u in (0 : ℝ)..1, Real.sqrt (↑d * Real.log (1 + 2 * δ / (δ * u))) =
      ∫ u in (0 : ℝ)..1, Real.sqrt (↑d * Real.log (1 + 2 / u)) := by
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    rw [intervalIntegral.integral_of_le (by norm_num : (0 : ℝ) ≤ 1)]
    apply MeasureTheory.setIntegral_congr_fun measurableSet_Ioc
    intro u ⟨hu_pos, _⟩
    have hu_ne : u ≠ 0 := ne_of_gt hu_pos
    have hδ_ne : δ ≠ 0 := ne_of_gt hδ
    field_simp
  -- Combine and apply intermediate_integral_bound
  rw [h_cov, h_simp]
  exact intermediate_integral_bound hn hd hδ
