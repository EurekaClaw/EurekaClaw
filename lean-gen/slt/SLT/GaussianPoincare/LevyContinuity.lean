/-
Copyright (c) 2024 Thomas Zhu. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Thomas Zhu, Rémy Degenne
-/
import Mathlib.MeasureTheory.Measure.IntegralCharFun
import Mathlib.MeasureTheory.Measure.TightNormed
import Mathlib.MeasureTheory.Measure.CharacteristicFunction
import Mathlib.MeasureTheory.Measure.Prokhorov
import Mathlib.MeasureTheory.Measure.LevyProkhorovMetric
import Mathlib.Topology.MetricSpace.Sequences
import Mathlib.Order.Monotone.Union
import Mathlib.Analysis.Fourier.FourierTransformDeriv

/-!
# The Lévy Continuity Theorem

This file contains the Lévy continuity theorem, which states that weak convergence of
probability measures is equivalent to pointwise convergence of their characteristic functions.

The main result is `MeasureTheory.ProbabilityMeasure.tendsto_iff_tendsto_charFun`.

## Attribution

This file is a compressed version of the Clt library created by
https://github.com/RemyDegenne/CLT.git, containing only the declarations
needed for the Lévy continuity theorem. The original code was developed 
as part of the Central Limit Theorem formalization project.

Original source files:
- `Clt/MomentGenerating.lean`
- `Clt/Tight.lean`
- `Clt/Inversion.lean`

We gratefully acknowledge the authors of the Clt library for their foundational work
on formalizing the Central Limit Theorem and related results in Lean 4.

-/

noncomputable section

open Filter MeasureTheory ProbabilityTheory BoundedContinuousFunction Real RCLike
open scoped Topology RealInnerProductSpace ENNReal NNReal Nat

/-! ## Helper lemmas from MomentGenerating

These lemmas establish integrability properties needed for proving continuity
of characteristic functions. Originally from `Clt/MomentGenerating.lean`.
-/

section ForMathlib

variable {α : Type*} [MeasurableSpace α]

lemma integrable_norm_rpow_antitone
    (μ : Measure α) [IsFiniteMeasure μ]
    {E} [NormedAddCommGroup E] {f : α → E} (hf : AEStronglyMeasurable f μ)
    {p q : ℝ} (hp : 0 ≤ p) (hq : 0 ≤ q) (hpq : p ≤ q)
    (hint : Integrable (fun x ↦ ‖f x‖ ^ q) μ) :
    Integrable (fun x ↦ ‖f x‖ ^ p) μ := by
  rcases hp.eq_or_lt with (rfl | hp)
  · simp
  rcases hq.eq_or_lt with (rfl | hq)
  · exact (hp.not_ge hpq).elim
  revert hint
  convert fun h ↦ MemLp.mono_exponent h (ENNReal.ofReal_le_ofReal hpq) using 1
  · rw [← integrable_norm_rpow_iff hf, ENNReal.toReal_ofReal hq.le] <;> simp_all
  · rw [← integrable_norm_rpow_iff hf, ENNReal.toReal_ofReal hp.le] <;> simp_all
  · infer_instance

lemma integrable_norm_pow_antitone
    (μ : Measure α) [IsFiniteMeasure μ]
    {E} [NormedAddCommGroup E] {f : α → E} (hf : AEStronglyMeasurable f μ)
    {p q : ℕ} (hpq : p ≤ q)
    (hint : Integrable (fun x ↦ ‖f x‖ ^ q) μ) :
    Integrable (fun x ↦ ‖f x‖ ^ p) μ := by
  revert hint
  replace hpq : (p : ℝ) ≤ q := by simpa
  convert integrable_norm_rpow_antitone μ hf
    p.cast_nonneg q.cast_nonneg hpq <;> rw [Real.rpow_natCast]

end ForMathlib

section InnerProductSpace

variable {E : Type*} [NormedAddCommGroup E] [InnerProductSpace ℝ E]
  [MeasurableSpace E] [BorelSpace E] [SecondCountableTopology E]
  {μ : Measure E} [IsProbabilityMeasure μ]

@[fun_prop]
theorem contDiff_charFun
    {n : ℕ} (hint : Integrable (‖·‖ ^ n) μ) :
    ContDiff ℝ n (charFun μ) := by
  have hint' (k : ℕ) (hk : k ≤ (n : ℕ∞)) : Integrable (fun x ↦ ‖x‖ ^ k * ‖(1 : E → ℂ) x‖) μ := by
    simp only [Pi.one_apply, norm_one, mul_one]
    rw [Nat.cast_le] at hk
    exact integrable_norm_pow_antitone μ aestronglyMeasurable_id hk hint
  simp_rw [funext charFun_eq_fourierIntegral']
  refine (VectorFourier.contDiff_fourierIntegral (L := innerSL ℝ) hint').comp ?_
  exact contDiff_const_smul _

@[fun_prop]
lemma continuous_charFun : Continuous (charFun μ) := by
  rw [← contDiff_zero (𝕜 := ℝ)]
  refine contDiff_charFun ?_
  suffices Integrable (fun _ ↦ (1 : ℝ)) μ by convert this
  fun_prop

end InnerProductSpace

/-! ## Tightness and characteristic functions

This section establishes that a sequence of probability measures is tight if their
characteristic functions converge pointwise to a function continuous at 0.

Originally from `Clt/Tight.lean`.
-/

section Tight

open MeasureTheory ProbabilityTheory Filter
open scoped ENNReal NNReal Topology RealInnerProductSpace

lemma tendsto_iSup_of_tendsto_limsup {u : ℕ → ℝ → ℝ≥0∞}
    (h_all : ∀ n, Tendsto (u n) atTop (𝓝 0))
    (h_tendsto : Tendsto (fun r : ℝ ↦ limsup (fun n ↦ u n r) atTop) atTop (𝓝 0))
    (h_anti : ∀ n, Antitone (u n)) :
    Tendsto (fun r : ℝ ↦ ⨆ n, u n r) atTop (𝓝 0) := by
  simp_rw [ENNReal.tendsto_atTop_zero] at h_tendsto h_all ⊢
  intro ε hε
  by_cases hε_top : ε = ∞
  · refine ⟨0, fun _ _ ↦ by simp [hε_top]⟩
  simp only [gt_iff_lt, ge_iff_le] at h_tendsto h_all hε
  obtain ⟨r, h⟩ := h_tendsto (ε / 2) (ENNReal.half_pos hε.ne')
  have h' x (hx : r ≤ x) y (hy : ε / 2 < y) : ∀ᶠ n in atTop, u n x < y := by
    specialize h x hx
    rw [limsup_le_iff] at h
    exact h y hy
  replace h' : ∀ x, r ≤ x → ∀ᶠ n in atTop, u n x < ε :=
    fun x hx ↦ h' x hx ε (ENNReal.half_lt_self hε.ne' hε_top)
  simp only [eventually_atTop, ge_iff_le] at h'
  obtain ⟨N, h⟩ := h' r le_rfl
  replace h_all : ∀ ε > 0, ∀ n, ∃ N, ∀ n_1 ≥ N, u n n_1 ≤ ε := fun ε hε n ↦ h_all n ε hε
  choose rs hrs using h_all ε hε
  refine ⟨r ⊔ ⨆ n : Finset.range N, rs n, fun v hv ↦ ?_⟩
  simp only [iSup_le_iff]
  intro n
  by_cases hn : n < N
  · refine hrs n v ?_
    calc rs n
    _ = rs (⟨n, by simp [hn]⟩ : Finset.range N) := rfl
    _ ≤ ⨆ n : Finset.range N, rs n := by
      refine le_ciSup (f := fun (x : Finset.range N) ↦ rs x) ?_ (⟨n, by simp [hn]⟩ : Finset.range N)
      exact Finite.bddAbove_range _
    _ ≤ r ⊔ ⨆ n : Finset.range N, rs n := le_max_right _ _
    _ ≤ v := hv
  · have hn_le : N ≤ n := not_lt.mp hn
    specialize h n hn_le
    refine (h_anti n ?_).trans h.le
    calc r
    _ ≤ r ⊔ ⨆ n : Finset.range N, rs n := le_max_left _ _
    _ ≤ v := hv

variable {E : Type*} {mE : MeasurableSpace E} [NormedAddCommGroup E]

section FiniteDimensional

variable [BorelSpace E] {μ : ℕ → Measure E} [∀ i, IsFiniteMeasure (μ i)]

section NormedSpace

variable [NormedSpace ℝ E] [FiniteDimensional ℝ E]

lemma isTightMeasureSet_of_tendsto_limsup_measure_norm_gt
    (h : Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | r < ‖x‖}) atTop) atTop (𝓝 0)) :
    IsTightMeasureSet (Set.range μ) := by
  refine isTightMeasureSet_of_tendsto_measure_norm_gt ?_
  simp_rw [iSup_range]
  refine tendsto_iSup_of_tendsto_limsup (fun n ↦ ?_) h fun n u v huv ↦ ?_
  · have h_tight : IsTightMeasureSet {μ n} := isTightMeasureSet_singleton
    rw [isTightMeasureSet_iff_tendsto_measure_norm_gt] at h_tight
    simpa using h_tight
  · refine measure_mono fun x hx ↦ ?_
    simp only [Set.mem_setOf_eq] at hx ⊢
    exact huv.trans_lt hx

lemma isTightMeasureSet_iff_tendsto_limsup_measure_norm_gt :
    IsTightMeasureSet (Set.range μ)
      ↔ Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | r < ‖x‖}) atTop) atTop (𝓝 0) := by
  refine ⟨fun h ↦ ?_, isTightMeasureSet_of_tendsto_limsup_measure_norm_gt⟩
  have h_sup := tendsto_measure_norm_gt_of_isTightMeasureSet h
  refine tendsto_of_tendsto_of_tendsto_of_le_of_le tendsto_const_nhds h_sup (fun _ ↦ zero_le') ?_
  intro r
  simp_rw [iSup_range]
  exact limsup_le_iSup

end NormedSpace

section InnerProductSpace

variable [InnerProductSpace ℝ E] [FiniteDimensional ℝ E]

lemma isTightMeasureSet_of_tendsto_limsup_inner
    (h : ∀ z, Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | r < |⟪z, x⟫|}) atTop) atTop (𝓝 0)) :
    IsTightMeasureSet (Set.range μ) := by
  refine isTightMeasureSet_of_inner_tendsto (𝕜 := ℝ) fun z ↦ ?_
  simp_rw [iSup_range]
  refine tendsto_iSup_of_tendsto_limsup (fun n ↦ ?_) (h z) fun n u v huv ↦ ?_
  · have h_tight : IsTightMeasureSet {(μ n).map (fun x ↦ ⟪z, x⟫)} := isTightMeasureSet_singleton
    rw [isTightMeasureSet_iff_tendsto_measure_norm_gt] at h_tight
    have h_map r : (μ n).map (fun x ↦ ⟪z, x⟫) {x | r < |x|} = μ n {x | r < |⟪z, x⟫|} := by
      rw [Measure.map_apply (by fun_prop)]
      · simp
      · exact MeasurableSet.preimage measurableSet_Ioi (by fun_prop)
    simpa [h_map] using h_tight
  · exact measure_mono fun x hx ↦ huv.trans_lt hx

lemma isTightMeasureSet_iff_tendsto_limsup_inner :
    IsTightMeasureSet (Set.range μ)
      ↔ ∀ z, Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | r < |⟪z, x⟫|}) atTop) atTop (𝓝 0) := by
  refine ⟨fun h z ↦ ?_, isTightMeasureSet_of_tendsto_limsup_inner⟩
  rw [isTightMeasureSet_iff_inner_tendsto ℝ] at h
  refine tendsto_of_tendsto_of_tendsto_of_le_of_le tendsto_const_nhds (h z)
    (fun _ ↦ zero_le') fun r ↦ ?_
  simp_rw [iSup_range]
  exact limsup_le_iSup

lemma isTightMeasureSet_of_tendsto_limsup_inner_of_norm_eq_one
    (h : ∀ z, ‖z‖ = 1
      → Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | r < |⟪z, x⟫|}) atTop) atTop (𝓝 0)) :
    IsTightMeasureSet (Set.range μ) := by
  have : ProperSpace E := FiniteDimensional.proper ℝ E
  refine isTightMeasureSet_of_tendsto_limsup_inner fun y ↦ ?_
  by_cases hy : y = 0
  · simp only [hy, inner_zero_left, abs_zero]
    refine (tendsto_congr' ?_).mpr tendsto_const_nhds
    filter_upwards [eventually_ge_atTop 0] with r hr
    simp [not_lt.mpr hr]
  have h' : Tendsto (fun r : ℝ ↦ limsup (fun n ↦ μ n {x | ‖y‖⁻¹ * r < |⟪‖y‖⁻¹ • y, x⟫|}) atTop)
      atTop (𝓝 0) := by
    specialize h (‖y‖⁻¹ • y) ?_
    · simp only [norm_smul, norm_inv, norm_norm]
      rw [inv_mul_cancel₀ (by positivity)]
    exact h.comp <| (tendsto_const_mul_atTop_of_pos (by positivity)).mpr tendsto_id
  convert h' using 7 with r n x
  rw [inner_smul_left]
  simp only [map_inv₀, conj_trivial, abs_mul, abs_inv, abs_norm]
  rw [mul_lt_mul_iff_right₀]
  positivity

/-- If the characteristic functions converge pointwise to a function which is continuous at 0,
then `{μ n | n}` is tight. -/
lemma isTightMeasureSet_of_tendsto_charFun {μ : ℕ → Measure E} [∀ i, IsProbabilityMeasure (μ i)]
    {f : E → ℂ} (hf : ContinuousAt f 0) (hf_meas : Measurable f)
    (h : ∀ t, Tendsto (fun n ↦ charFun (μ n) t) atTop (𝓝 (f t))) :
    IsTightMeasureSet (Set.range μ) := by
  refine isTightMeasureSet_of_tendsto_limsup_inner_of_norm_eq_one fun z hz ↦ ?_
  suffices Tendsto (fun r : ℝ ↦ limsup (fun n ↦ (μ n).real {x | r < |⟪z, x⟫|}) atTop) atTop (𝓝 0) by
    have h_ofReal r : limsup (fun n ↦ μ n {x | r < |⟪z, x⟫|}) atTop
        = ENNReal.ofReal (limsup (fun n ↦ (μ n).real {x | r < |⟪z, x⟫|}) atTop) := by
      simp_rw [measureReal_def,
        ENNReal.limsup_toReal_eq (b := 1) (by simp) (.of_forall fun _ ↦ prob_le_one)]
      rw [ENNReal.ofReal_toReal]
      refine ne_top_of_le_ne_top (by simp : 1 ≠ ∞) ?_
      refine limsup_le_of_le ?_ (.of_forall fun _ ↦ prob_le_one)
      exact IsCoboundedUnder.of_frequently_ge <| .of_forall fun _ ↦ zero_le'
    simp_rw [h_ofReal]
    rw [← ENNReal.ofReal_zero]
    exact ENNReal.tendsto_ofReal this
  have h_le_4 n r (hr : 0 < r) :
      2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - charFun (μ n) (t • z)‖ ≤ 4 := by
    have hr' : -(2 * r⁻¹) ≤ 2 * r⁻¹ := by rw [neg_le_self_iff]; positivity
    calc 2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - charFun (μ n) (t • z)‖
    _ ≤ 2⁻¹ * r * ∫ t in -(2 * r⁻¹)..2 * r⁻¹, ‖1 - charFun (μ n) (t • z)‖ := by
      simp only [neg_mul]
      gcongr
      rw [intervalIntegral.integral_of_le hr', intervalIntegral.integral_of_le hr']
      exact norm_integral_le_integral_norm _
    _ ≤ 2⁻¹ * r * ∫ t in -(2 * r⁻¹)..2 * r⁻¹, 2 := by
      gcongr
      rw [intervalIntegral.integral_of_le hr', intervalIntegral.integral_of_le hr']
      refine integral_mono_of_nonneg ?_ (by fun_prop) ?_
      · exact ae_of_all _ fun _ ↦ by positivity
      · refine ae_of_all _ fun x ↦ norm_one_sub_charFun_le_two
    _ ≤ 4 := by
      simp only [intervalIntegral.integral_const, sub_neg_eq_add, smul_eq_mul]
      ring_nf
      rw [mul_inv_cancel₀ hr.ne', one_mul]
  have h_le n r := measureReal_abs_inner_gt_le_integral_charFun (μ := μ n) (a := z) (r := r)
  -- We introduce an upper bound for the limsup.
  -- This is where we use the fact that `charFun (μ n)` converges to `f`.
  have h_limsup_le r (hr : 0 < r) :
      limsup (fun n ↦ (μ n).real {x | r < |⟪z, x⟫|}) atTop
        ≤ 2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - f (t • z)‖ := by
    calc limsup (fun n ↦ (μ n).real {x | r < |⟪z, x⟫|}) atTop
    _ ≤ limsup (fun n ↦ 2⁻¹ * r
        * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - charFun (μ n) (t • z)‖) atTop := by
      refine limsup_le_limsup (.of_forall fun n ↦ h_le n r hr) ?_ ?_
      · exact IsCoboundedUnder.of_frequently_ge <| .of_forall fun _ ↦ ENNReal.toReal_nonneg
      · refine ⟨4, ?_⟩
        simp only [eventually_map, eventually_atTop, ge_iff_le]
        exact ⟨0, fun n _ ↦ h_le_4 n r hr⟩
    _ = 2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - f (t • z)‖ := by
      refine ((Tendsto.norm ?_).const_mul _).limsup_eq
      simp only [neg_mul]
      have hr' : -(2 * r⁻¹) ≤ 2 * r⁻¹ := by rw [neg_le_self_iff]; positivity
      simp_rw [intervalIntegral.integral_of_le hr']
      refine tendsto_integral_of_dominated_convergence (fun _ ↦ 2) ?_ (by fun_prop) ?_ ?_
      · exact fun _ ↦ Measurable.aestronglyMeasurable <| by fun_prop
      · exact fun _ ↦ ae_of_all _ fun _ ↦ norm_one_sub_charFun_le_two
      · exact ae_of_all _ fun x ↦ tendsto_const_nhds.sub (h _)
  -- It suffices to show that the upper bound tends to 0.
  refine tendsto_of_tendsto_of_tendsto_of_le_of_le' tendsto_const_nhds
    (h := fun r ↦ 2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - f (t • z)‖) ?_ ?_ ?_
  rotate_left
  · filter_upwards [eventually_gt_atTop 0] with r hr
    refine le_limsup_of_le ?_ fun u hu ↦ ?_
    · refine ⟨4, ?_⟩
      simp only [eventually_map, eventually_atTop, ge_iff_le]
      exact ⟨0, fun n _ ↦ (h_le n r hr).trans (h_le_4 n r hr)⟩
    · exact ENNReal.toReal_nonneg.trans hu.exists.choose_spec
  · filter_upwards [eventually_gt_atTop 0] with r hr using h_limsup_le r hr
  -- We now show that the upper bound tends to 0.
  -- This will follow from the fact that `f` is continuous at `0`.
  -- `⊢ Tendsto (fun r ↦ 2⁻¹ * r * ‖∫ t in -2 * r⁻¹..2 * r⁻¹, 1 - f (t • z)‖) atTop (𝓝 0)`
  have hf_tendsto := hf.tendsto
  rw [Metric.tendsto_nhds_nhds] at hf_tendsto
  rw [Metric.tendsto_atTop]
  intro ε hε
  have hf0 : f 0 = 1 := by symm; simpa using h 0
  simp only [gt_iff_lt, dist_eq_norm_sub', zero_sub, norm_neg, hf0] at hf_tendsto
  simp only [ge_iff_le, neg_mul, dist_zero_right, norm_mul, norm_inv,
    Real.norm_ofNat, Real.norm_eq_abs]
  simp_rw [abs_of_nonneg (norm_nonneg _)]
  obtain ⟨δ, hδ, hδ_lt⟩ : ∃ δ, 0 < δ ∧ ∀ ⦃x : E⦄, ‖x‖ < δ → ‖1 - f x‖ < ε / 4 :=
    hf_tendsto (ε / 4) (by positivity)
  refine ⟨4 * δ⁻¹, fun r hrδ ↦ ?_⟩
  have hr : 0 < r := lt_of_lt_of_le (by positivity) hrδ
  have hr' : -(2 * r⁻¹) ≤ 2 * r⁻¹ := by rw [neg_le_self_iff]; positivity
  have h_le_Ioc x (hx : x ∈ Set.Ioc (-(2 * r⁻¹)) (2 * r⁻¹)) :
      ‖1 - f (x • z)‖ ≤ ε / 4 := by
    refine (hδ_lt ?_).le
    simp only [norm_smul, Real.norm_eq_abs, mul_one, hz]
    calc |x|
    _ ≤ 2 * r⁻¹ := by
      rw [abs_le]
      rw [Set.mem_Ioc] at hx
      exact ⟨hx.1.le, hx.2⟩
    _ < δ := by
      rw [← lt_div_iff₀' (by positivity), inv_lt_comm₀ hr (by positivity)]
      refine lt_of_lt_of_le ?_ hrδ
      ring_nf
      gcongr
      norm_num
  rw [abs_of_nonneg hr.le]
  calc 2⁻¹ * r * ‖∫ t in -(2 * r⁻¹)..2 * r⁻¹, 1 - f (t • z)‖
  _ ≤ 2⁻¹ * r * ∫ t in -(2 * r⁻¹)..2 * r⁻¹, ‖1 - f (t • z)‖ := by
    gcongr
    rw [intervalIntegral.integral_of_le hr', intervalIntegral.integral_of_le hr']
    exact norm_integral_le_integral_norm _
  _ ≤ 2⁻¹ * r * ∫ t in -(2 * r⁻¹)..2 * r⁻¹, ε / 4 := by
    gcongr
    rw [intervalIntegral.integral_of_le hr', intervalIntegral.integral_of_le hr']
    refine integral_mono_ae ?_ (by fun_prop) ?_
    · refine Integrable.mono' (integrable_const (ε / 4)) ?_ ?_
      · exact Measurable.aestronglyMeasurable <| by fun_prop
      · simp_rw [norm_norm]
        exact ae_restrict_of_forall_mem measurableSet_Ioc h_le_Ioc
    · exact ae_restrict_of_forall_mem measurableSet_Ioc h_le_Ioc
  _ = ε / 2 := by
    simp only [intervalIntegral.integral_div, intervalIntegral.integral_const, sub_neg_eq_add,
      smul_eq_mul]
    ring_nf
    rw [mul_inv_cancel₀ hr.ne', one_mul]
  _ < ε := by simp [hε]

end InnerProductSpace

end FiniteDimensional

end Tight

/-! ## Inverting the characteristic function

This section contains the main results: the Lévy continuity theorem stating that
weak convergence of probability measures is equivalent to pointwise convergence
of their characteristic functions.

Originally from `Clt/Inversion.lean`.
-/

variable (𝕜 : Type*) [RCLike 𝕜]

lemma MeasureTheory.ProbabilityMeasure.tendsto_of_tight_of_separatesPoints
    {E : Type*} [MeasurableSpace E]
    [MetricSpace E] [CompleteSpace E] [SecondCountableTopology E] [BorelSpace E]
    {μ : ℕ → ProbabilityMeasure E}
    (h_tight : IsTightMeasureSet {(μ n : Measure E) | n}) {μ₀ : ProbabilityMeasure E}
    {A : StarSubalgebra 𝕜 (E →ᵇ 𝕜)} (hA : (A.map (toContinuousMapStarₐ 𝕜)).SeparatesPoints)
    (heq : ∀ g ∈ A, Tendsto (fun n ↦ ∫ x, g x ∂(μ n)) atTop (𝓝 (∫ x, g x ∂μ₀))) :
    Tendsto μ atTop (𝓝 μ₀) := by
  refine Filter.tendsto_of_subseq_tendsto fun ns hns ↦ ?_
  have h_compact : IsCompact (closure {μ n | n}) :=
    isCompact_closure_of_isTightMeasureSet (S := {μ n | n}) ?_
  swap; · convert h_tight; simp
  obtain ⟨μ', hμ'_mem, phi, hphi_mono, hphi_tendsto⟩ : ∃ μ' ∈ closure {μ n | n},
      ∃ phi, StrictMono phi ∧ Tendsto ((fun n ↦ μ (ns n)) ∘ phi) atTop (𝓝 μ') :=
    IsCompact.tendsto_subseq h_compact (x := fun n ↦ μ (ns n)) fun n ↦ subset_closure ⟨ns n, rfl⟩
  refine ⟨phi, ?_⟩
  suffices μ' = μ₀ from this ▸ hphi_tendsto
  suffices (μ' : Measure E) = μ₀ by ext; rw [this]
  refine ext_of_forall_mem_subalgebra_integral_eq_of_pseudoEMetric_complete_countable hA
    fun g hg ↦ ?_
  specialize heq g hg
  suffices Tendsto (fun n ↦ ∫ x, g x ∂(μ (ns (phi n)))) atTop (𝓝 (∫ x, g x ∂μ')) from
    tendsto_nhds_unique this <| heq.comp (hns.comp hphi_mono.tendsto_atTop)
  rw [ProbabilityMeasure.tendsto_iff_forall_integral_rclike_tendsto 𝕜] at hphi_tendsto
  exact hphi_tendsto g

variable {E : Type*} [NormedAddCommGroup E] [InnerProductSpace ℝ E]
  [MeasurableSpace E] [BorelSpace E]
  {μ : ℕ → ProbabilityMeasure E} {μ₀ : ProbabilityMeasure E}

lemma MeasureTheory.ProbabilityMeasure.tendsto_charPoly_of_tendsto_charFun
    (h : ∀ t : E, Tendsto (fun n ↦ charFun (μ n) t) atTop (𝓝 (charFun μ₀ t)))
    {g : E →ᵇ ℂ}
    (hg : g ∈ charPoly continuous_probChar (L := innerₗ E) continuous_inner) :
    Tendsto (fun n ↦ ∫ x, g x ∂(μ n)) atTop (𝓝 (∫ x, g x ∂μ₀)) := by
  rw [mem_charPoly] at hg
  obtain ⟨w, hw⟩ := hg
  have h_eq (μ : Measure E) (hμ : IsProbabilityMeasure μ) :
      ∫ x, g x ∂μ = ∑ a ∈ w.support, w a * ∫ x, (probChar (innerₗ E x a) : ℂ) ∂μ := by
    simp_rw [hw]
    rw [integral_finset_sum]
    · congr with y
      rw [integral_const_mul]
    · intro i hi
      refine Integrable.const_mul ?_ _
      change Integrable (fun x ↦ innerProbChar i x) μ
      exact BoundedContinuousFunction.integrable μ _
  simp_rw [h_eq (μ _), h_eq μ₀]
  refine tendsto_finset_sum _ fun y hy ↦ Tendsto.const_mul _ ?_
  simp only [innerₗ_apply_apply]
  simp_rw [← charFun_eq_integral_probChar]
  exact h y

lemma MeasureTheory.ProbabilityMeasure.tendsto_of_tendsto_charFun
    [FiniteDimensional ℝ E]
    (h : ∀ t : E, Tendsto (fun n ↦ charFun (μ n) t) atTop (𝓝 (charFun μ₀ t))) :
    Tendsto μ atTop (𝓝 μ₀) := by
  have h_tight : IsTightMeasureSet (𝓧 := E) {μ n | n} :=
    isTightMeasureSet_of_tendsto_charFun (by fun_prop) (by fun_prop) h
  refine tendsto_of_tight_of_separatesPoints h_tight (𝕜 := ℂ)
    (A := charPoly continuous_probChar (L := innerₗ E) continuous_inner) ?_ ?_
  · refine separatesPoints_charPoly continuous_probChar probChar_ne_one _ ?_
    exact fun v hv ↦ DFunLike.ne_iff.mpr ⟨v, inner_self_ne_zero.mpr hv⟩
  · exact fun g ↦ tendsto_charPoly_of_tendsto_charFun h

/--
The Lévy continuity theorem https://en.wikipedia.org/wiki/L%C3%A9vy%27s_continuity_theorem.

See blueprint.

The <= direction follows from definition, but it is not needed.
The => direction is much harder:
* If `μs` is tight, then the statement follows in general
  * For each subsequence of `μs`, we need find a sub-subsequence that converges weakly to `μ`.
    This requires Prokhorov's theorem for relative compactness.
* μs is tight in `ℝ^d` if their `charFun`s converge to a function continuous at 0

-/
theorem MeasureTheory.ProbabilityMeasure.tendsto_iff_tendsto_charFun
    [FiniteDimensional ℝ E] :
    Tendsto μ atTop (𝓝 μ₀) ↔
      ∀ t : E, Tendsto (fun n ↦ charFun (μ n) t) atTop (𝓝 (charFun μ₀ t)) := by
  refine ⟨fun h t ↦ ?_, tendsto_of_tendsto_charFun⟩
  rw [ProbabilityMeasure.tendsto_iff_forall_integral_rclike_tendsto ℂ] at h
  simp_rw [charFun_eq_integral_innerProbChar]
  exact h (innerProbChar t)
