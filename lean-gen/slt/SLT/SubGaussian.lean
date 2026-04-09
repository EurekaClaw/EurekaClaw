/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.MeasureInfrastructure
import Mathlib.Topology.MetricSpace.Basic
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Probability.Moments.Basic
import Mathlib.Probability.Moments.IntegrableExpMul
import Mathlib.Probability.Moments.MGFAnalytic
import Mathlib.Analysis.SpecialFunctions.Gaussian.GaussianIntegral

/-!
# Sub-Gaussian Processes

This file defines sub-Gaussian processes and proves tail bounds needed for Dudley's
entropy integral bound.

## Main definitions

* `IsSubGaussianProcess`: A stochastic process indexed by a pseudo-metric space
  satisfies the sub-Gaussian MGF bound for increments.
* `IsSubGaussianProcess'`: Equivalent formulation using `mgf` directly.

## Main results

* `subGaussian_tail_bound_one_sided`: One-sided Chernoff bound P(X_s - X_t ≥ u).
* `subGaussian_tail_bound`: Two-sided tail bound P(|X_s - X_t| ≥ u).
* `gaussian_tail_integral`: The Gaussian tail integral ∫₀^∞ 2·exp(-r²/(2τ²)) dr = τ·√(2π).
* `ae_eq_zero_of_mgf_le_one`: MGF ≤ 1 for all λ implies Y = 0 a.e.
* `subGaussian_first_moment_bound`: E[|X_s - X_t|] ≤ √(2π)·σ·d(s,t).
* `subGaussian_finite_max_bound`: E[max_{t∈T} X_t] ≤ σ·diam(T)·√(2 log|T|).

-/

open MeasureTheory ProbabilityTheory Real Set Metric
open scoped ENNReal BigOperators

noncomputable section

universe u v

variable {Ω : Type u} [MeasurableSpace Ω] {A : Type v} [PseudoMetricSpace A]

/-- A stochastic process {X_θ : θ ∈ A} indexed by a pseudo-metric space A is sub-Gaussian
    with parameter σ if for all θ, θ' ∈ A and all t ∈ ℝ:
    E[exp(t(X_θ - X_θ'))] ≤ exp(t² σ² d(θ,θ')² / 2)

    This is the canonical sub-Gaussian condition for stochastic processes. -/
def IsSubGaussianProcess (μ : Measure Ω) (X : A → Ω → ℝ) (σ : ℝ) : Prop :=
  ∀ s t : A, ∀ l : ℝ, μ[fun ω => exp (l * (X s ω - X t ω))] ≤
    exp (l^2 * σ^2 * (dist s t)^2 / 2)

/-- Alternative formulation: X is sub-Gaussian if X_s - X_t is sub-Gaussian with
    variance proxy σ² d(s,t)². -/
def IsSubGaussianProcess' (μ : Measure Ω) (X : A → Ω → ℝ) (σ : ℝ) : Prop :=
  ∀ s t : A, ∀ l : ℝ, mgf (fun ω => X s ω - X t ω) μ l ≤
    exp (l^2 * σ^2 * (dist s t)^2 / 2)

lemma IsSubGaussianProcess_iff_IsSubGaussianProcess' {μ : Measure Ω} {X : A → Ω → ℝ} {σ : ℝ} :
    IsSubGaussianProcess μ X σ ↔ IsSubGaussianProcess' μ X σ :=
  ⟨fun h s t l => h s t l, fun h s t l => h s t l⟩

/-!
## Basic properties of sub-Gaussian processes
-/

/-- Sub-Gaussian processes are symmetric in the parameter. -/
lemma IsSubGaussianProcess.symm {μ : Measure Ω} {X : A → Ω → ℝ} {σ : ℝ}
    (h : IsSubGaussianProcess μ X σ) (s t : A) (l : ℝ) :
    μ[fun ω => exp (l * (X t ω - X s ω))] ≤ exp (l^2 * σ^2 * (dist t s)^2 / 2) :=
  h t s l

/-- If σ ≤ σ', then σ-sub-Gaussian implies σ'-sub-Gaussian. -/
lemma IsSubGaussianProcess.mono {μ : Measure Ω} {X : A → Ω → ℝ} {σ σ' : ℝ}
    (h : IsSubGaussianProcess μ X σ) (hσ : 0 ≤ σ) (hσ' : σ ≤ σ') :
    IsSubGaussianProcess μ X σ' := by
  intro s t l
  calc μ[fun ω => exp (l * (X s ω - X t ω))]
    _ ≤ exp (l^2 * σ^2 * (dist s t)^2 / 2) := h s t l
    _ ≤ exp (l^2 * σ'^2 * (dist s t)^2 / 2) := by
        apply exp_le_exp.mpr
        apply div_le_div_of_nonneg_right _ (by norm_num : (0 : ℝ) ≤ 2)
        apply mul_le_mul_of_nonneg_right _ (sq_nonneg _)
        apply mul_le_mul_of_nonneg_left _ (sq_nonneg _)
        exact sq_le_sq' (by linarith) hσ'

/-!
## Tail bounds for sub-Gaussian processes

The key result is that sub-Gaussian increments have exponentially decaying tails.
-/

/-- Chernoff bound: for any sub-Gaussian increment, P(X_s - X_t ≥ u) ≤ exp(-u²/(2σ²d(s,t)²)).
    This is the one-sided tail bound.
    Note: In a PseudoMetricSpace, we require dist s t > 0 explicitly (unlike MetricSpace
    where this follows from s ≠ t). -/
theorem subGaussian_tail_bound_one_sided {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ} (hσ : 0 < σ)
    (hX : IsSubGaussianProcess μ X σ)
    (s t : A) (u : ℝ) (hu : 0 < u) (hd : 0 < dist s t)
    (h_int : ∀ l : ℝ, Integrable (fun ω => exp (l * (X s ω - X t ω))) μ) :
    (μ {ω | X s ω - X t ω ≥ u}).toReal ≤ exp (-u^2 / (2 * σ^2 * (dist s t)^2)) := by
  have hσd : 0 < σ * dist s t := mul_pos hσ hd
  have h_sgb : ∀ l : ℝ, cgf (fun ω => X s ω - X t ω) μ l ≤ l^2 * (σ * dist s t)^2 / 2 := by
    intro l
    unfold cgf mgf
    have h_mgf_bound : μ[fun ω => exp (l * (X s ω - X t ω))] ≤ exp (l^2 * (σ * dist s t)^2 / 2) := by
      calc μ[fun ω => exp (l * (X s ω - X t ω))]
        _ ≤ exp (l^2 * σ^2 * (dist s t)^2 / 2) := hX s t l
        _ = exp (l^2 * (σ * dist s t)^2 / 2) := by ring_nf
    have h_mgf_pos : 0 < mgf (fun ω => X s ω - X t ω) μ l := mgf_pos (h_int l)
    calc log (μ[fun ω => exp (l * (X s ω - X t ω))])
      _ ≤ log (exp (l^2 * (σ * dist s t)^2 / 2)) := log_le_log h_mgf_pos h_mgf_bound
      _ = l^2 * (σ * dist s t)^2 / 2 := log_exp _
  have h_result := chernoff_bound_subGaussian hσd hu h_sgb h_int
  have h_eq : -u^2 / (2 * σ^2 * (dist s t)^2) = -u^2 / (2 * (σ * dist s t)^2) := by
    rw [mul_pow]; ring
  rw [h_eq]
  exact h_result

/-- Two-sided tail bound for sub-Gaussian increments. -/
theorem subGaussian_tail_bound {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ} (hσ : 0 < σ)
    (hX : IsSubGaussianProcess μ X σ)
    (s t : A) (u : ℝ) (hu : 0 < u) (hd : 0 < dist s t)
    (h_int : ∀ l : ℝ, Integrable (fun ω => exp (l * (X s ω - X t ω))) μ)
    (h_int' : ∀ l : ℝ, Integrable (fun ω => exp (l * (X t ω - X s ω))) μ) :
    (μ {ω | |X s ω - X t ω| ≥ u}).toReal ≤ 2 * exp (-u^2 / (2 * σ^2 * (dist s t)^2)) := by
  -- Union bound over both tails: {|Y| ≥ u} ⊆ {Y ≥ u} ∪ {-Y ≥ u}
  have h_subset : {ω | |X s ω - X t ω| ≥ u} ⊆
      {ω | X s ω - X t ω ≥ u} ∪ {ω | X t ω - X s ω ≥ u} := by
    intro ω hω
    simp only [ge_iff_le, mem_setOf_eq, mem_union] at hω ⊢
    by_cases h' : u ≤ X s ω - X t ω
    · left; exact h'
    · right
      push_neg at h'
      -- We have h' : X s ω - X t ω < u and hω : u ≤ |X s ω - X t ω|
      -- If X s ω - X t ω ≥ 0, then |X s ω - X t ω| = X s ω - X t ω < u, contradiction with hω
      -- So X s ω - X t ω < 0
      have h_neg : X s ω - X t ω < 0 := by
        by_contra h_nonneg
        push_neg at h_nonneg
        have : |X s ω - X t ω| = X s ω - X t ω := abs_of_nonneg h_nonneg
        linarith
      have habs : |X s ω - X t ω| = -(X s ω - X t ω) := abs_of_neg h_neg
      rw [habs] at hω
      linarith
  -- Bound by sum of individual tails using measure_union_le
  have h_bound1 := subGaussian_tail_bound_one_sided hσ hX s t u hu hd h_int
  have hd' : 0 < dist t s := by rw [dist_comm]; exact hd
  have h_bound2 := subGaussian_tail_bound_one_sided hσ hX t s u hu hd' h_int'
  calc (μ {ω | |X s ω - X t ω| ≥ u}).toReal
    _ ≤ (μ ({ω | X s ω - X t ω ≥ u} ∪ {ω | X t ω - X s ω ≥ u})).toReal := by
        apply ENNReal.toReal_mono (measure_ne_top μ _) (measure_mono h_subset)
    _ ≤ (μ {ω | X s ω - X t ω ≥ u} + μ {ω | X t ω - X s ω ≥ u}).toReal := by
        apply ENNReal.toReal_mono
        · exact ENNReal.add_ne_top.mpr ⟨measure_ne_top μ _, measure_ne_top μ _⟩
        · exact measure_union_le _ _
    _ = (μ {ω | X s ω - X t ω ≥ u}).toReal + (μ {ω | X t ω - X s ω ≥ u}).toReal := by
        rw [ENNReal.toReal_add (measure_ne_top μ _) (measure_ne_top μ _)]
    _ ≤ exp (-u^2 / (2 * σ^2 * (dist s t)^2)) + exp (-u^2 / (2 * σ^2 * (dist t s)^2)) := by
        apply add_le_add h_bound1 h_bound2
    _ = 2 * exp (-u^2 / (2 * σ^2 * (dist s t)^2)) := by
        rw [dist_comm t s]
        ring

/-!
## First moment bound for sub-Gaussian increments
-/

/-- The Gaussian integral ∫₀^∞ 2·exp(-r²/(2τ²)) dr = τ·√(2π) for τ > 0. -/
lemma gaussian_tail_integral {τ : ℝ} (hτ : 0 < τ) :
    ∫ r in Ioi (0 : ℝ), 2 * exp (-r^2 / (2 * τ^2)) = τ * sqrt (2 * π) := by
  have h1 : ∫ r in Ioi (0 : ℝ), 2 * exp (-r^2 / (2 * τ^2)) =
      2 * ∫ r in Ioi (0 : ℝ), exp (-r^2 / (2 * τ^2)) := integral_const_mul 2 _
  have key : ∀ r : ℝ, -r^2 / (2 * τ^2) = -(1 / (2 * τ^2)) * r^2 := fun r => by field_simp
  have h2 : ∫ r in Ioi (0 : ℝ), exp (-r^2 / (2 * τ^2)) =
      ∫ r in Ioi (0 : ℝ), exp (-(1 / (2 * τ^2)) * r^2) := by
    congr 1 with r; rw [key r]
  rw [h1, h2, integral_gaussian_Ioi (1 / (2 * τ^2))]
  have h_simp : π / (1 / (2 * τ^2)) = π * (2 * τ^2) := by
    rw [one_div, div_inv_eq_mul]
  rw [h_simp]
  have h3 : sqrt (π * (2 * τ^2)) = τ * sqrt (2 * π) := by
    rw [show π * (2 * τ^2) = (2 * π) * τ^2 by ring,
        sqrt_mul (by positivity : 0 ≤ 2 * π), sqrt_sq (le_of_lt hτ), mul_comm]
  linarith [h3, sqrt_nonneg (2 * π), hτ]

/-- A random variable with MGF bounded by 1 for all λ is zero a.s.

    Key lemma for the degenerate case of sub-Gaussian processes with zero variance proxy. -/
lemma ae_eq_zero_of_mgf_le_one {μ : Measure Ω} [IsProbabilityMeasure μ]
    {Y : Ω → ℝ}
    (hY_mgf : ∀ l : ℝ, μ[fun ω => exp (l * Y ω)] ≤ 1)
    (hY_int_exp_pos : ∀ l : ℝ, 0 < l → Integrable (fun ω => exp (l * Y ω)) μ)
    (hY_int_exp_neg : ∀ l : ℝ, l < 0 → Integrable (fun ω => exp (l * Y ω)) μ) :
    Y =ᵐ[μ] (fun _ => 0) := by
  have h_le_zero : ∀ᵐ ω ∂μ, Y ω ≤ 0 := by
    rw [ae_iff]
    have h_tail_zero : ∀ ε : ℝ, 0 < ε → μ {ω | Y ω > ε} = 0 := fun ε hε => by
      have h_bound : ∀ k : ℕ, μ {ω | Y ω > ε} ≤ ENNReal.ofReal (exp (-(k : ℝ) * ε)) := fun k => by
        have hk1 : (0 : ℝ) < k + 1 := Nat.cast_add_one_pos k
        have h_markov := mul_meas_ge_le_integral_of_nonneg
          (μ := μ) (f := fun ω => exp ((k + 1 : ℝ) * Y ω))
          (ae_of_all μ (fun _ => (exp_pos _).le))
          (hY_int_exp_pos (k + 1) hk1) (exp ((k + 1 : ℝ) * ε))
        have h_subset : {ω | Y ω > ε} ⊆ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * Y ω)} := by
          intro ω hω
          simp only [mem_setOf_eq] at hω ⊢
          exact exp_le_exp.mpr (mul_lt_mul_of_pos_left hω hk1).le
        have h_toReal_bound : (μ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * Y ω)}).toReal ≤
            (exp ((k + 1 : ℝ) * ε))⁻¹ * ∫ ω, exp ((k + 1 : ℝ) * Y ω) ∂μ := by
          rw [le_inv_mul_iff₀ (exp_pos _), mul_comm]
          rw [mul_comm] at h_markov
          exact h_markov
        calc μ {ω | Y ω > ε}
          _ ≤ μ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * Y ω)} := measure_mono h_subset
          _ ≤ ENNReal.ofReal ((exp ((k + 1 : ℝ) * ε))⁻¹ * ∫ ω, exp ((k + 1 : ℝ) * Y ω) ∂μ) := by
              rw [← ENNReal.ofReal_toReal (measure_ne_top μ _)]
              exact ENNReal.ofReal_le_ofReal h_toReal_bound
          _ ≤ ENNReal.ofReal ((exp ((k + 1 : ℝ) * ε))⁻¹ * 1) := by
              apply ENNReal.ofReal_le_ofReal
              gcongr
              exact hY_mgf (k + 1)
          _ = ENNReal.ofReal (exp (-((k + 1 : ℝ) * ε))) := by
              congr 1; rw [mul_one, exp_neg]
          _ ≤ ENNReal.ofReal (exp (-(k : ℝ) * ε)) := by
              apply ENNReal.ofReal_le_ofReal
              apply exp_le_exp.mpr
              simp only [neg_mul, neg_le_neg_iff]
              have : (k : ℝ) ≤ (k : ℝ) + 1 := le_add_of_nonneg_right (by norm_num)
              exact mul_le_mul_of_nonneg_right this hε.le
      rw [← nonpos_iff_eq_zero]
      have h_lim : Filter.Tendsto (fun n : ℕ => ENNReal.ofReal (exp (-(n : ℝ) * ε)))
          Filter.atTop (nhds 0) := by
        have h1 : Filter.Tendsto (fun n : ℕ => (n : ℝ) * ε) Filter.atTop Filter.atTop :=
          Filter.Tendsto.atTop_mul_const hε tendsto_natCast_atTop_atTop
        have h2 : Filter.Tendsto (fun n : ℕ => exp (-((n : ℝ) * ε))) Filter.atTop (nhds 0) :=
          by simpa only [Function.comp] using tendsto_exp_neg_atTop_nhds_zero.comp h1
        have h3' := ENNReal.tendsto_ofReal h2
        simp only [ENNReal.ofReal_zero] at h3'
        have h_eq : (fun n : ℕ => ENNReal.ofReal (exp (-(n : ℝ) * ε))) =
            (fun n : ℕ => ENNReal.ofReal (exp (-((n : ℝ) * ε)))) := by ext n; ring_nf
        rw [h_eq]; exact h3'
      exact ge_of_tendsto' h_lim (fun n => h_bound n)
    apply measure_mono_null (t := ⋃ n : ℕ, {ω | Y ω > 1/((n : ℝ)+1)})
    · intro ω hω
      simp only [mem_iUnion, mem_setOf_eq, not_le] at hω ⊢
      obtain ⟨n, hn⟩ := exists_nat_gt (1 / Y ω)
      use n
      have hY_pos : 0 < Y ω := hω
      calc (1 : ℝ) / ((n : ℝ) + 1) < 1 / (1 / Y ω) := by
            apply one_div_lt_one_div_of_lt (one_div_pos.mpr hY_pos); linarith
        _ = Y ω := one_div_one_div _
    · rw [measure_iUnion_null_iff]
      intro n; exact h_tail_zero (1 / ((n : ℝ) + 1)) (by positivity)
  have h_ge_zero : ∀ᵐ ω ∂μ, Y ω ≥ 0 := by
    rw [ae_iff]
    have h_neg_mgf : ∀ l : ℝ, μ[fun ω => exp (l * (-Y ω))] ≤ 1 := fun l => by
      convert hY_mgf (-l) using 2; ext ω; ring_nf
    have h_neg_int_exp_pos : ∀ l : ℝ, 0 < l → Integrable (fun ω => exp (l * (-Y ω))) μ := fun l hl => by
      have h_neg_l : -l < 0 := by linarith
      convert hY_int_exp_neg (-l) h_neg_l using 1; ext ω; ring_nf
    have h_tail_zero_neg : ∀ ε : ℝ, 0 < ε → μ {ω | -Y ω > ε} = 0 := fun ε hε => by
      have h_bound : ∀ k : ℕ, μ {ω | -Y ω > ε} ≤ ENNReal.ofReal (exp (-(k : ℝ) * ε)) := fun k => by
        have hk1 : (0 : ℝ) < k + 1 := Nat.cast_add_one_pos k
        have h_markov := mul_meas_ge_le_integral_of_nonneg
          (μ := μ) (f := fun ω => exp ((k + 1 : ℝ) * (-Y ω)))
          (ae_of_all μ (fun _ => (exp_pos _).le))
          (h_neg_int_exp_pos (k + 1) hk1) (exp ((k + 1 : ℝ) * ε))
        have h_subset : {ω | -Y ω > ε} ⊆ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * (-Y ω))} := by
          intro ω hω
          simp only [mem_setOf_eq] at hω ⊢
          exact exp_le_exp.mpr (mul_lt_mul_of_pos_left hω hk1).le
        have h_toReal_bound : (μ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * (-Y ω))}).toReal ≤
            (exp ((k + 1 : ℝ) * ε))⁻¹ * ∫ ω, exp ((k + 1 : ℝ) * (-Y ω)) ∂μ := by
          rw [le_inv_mul_iff₀ (exp_pos _), mul_comm]
          rw [mul_comm] at h_markov; exact h_markov
        calc μ {ω | -Y ω > ε}
          _ ≤ μ {ω | exp ((k + 1 : ℝ) * ε) ≤ exp ((k + 1 : ℝ) * (-Y ω))} := measure_mono h_subset
          _ ≤ ENNReal.ofReal ((exp ((k + 1 : ℝ) * ε))⁻¹ * ∫ ω, exp ((k + 1 : ℝ) * (-Y ω)) ∂μ) := by
              rw [← ENNReal.ofReal_toReal (measure_ne_top μ _)]
              exact ENNReal.ofReal_le_ofReal h_toReal_bound
          _ ≤ ENNReal.ofReal ((exp ((k + 1 : ℝ) * ε))⁻¹ * 1) := by
              apply ENNReal.ofReal_le_ofReal; gcongr; exact h_neg_mgf (k + 1)
          _ = ENNReal.ofReal (exp (-((k + 1 : ℝ) * ε))) := by congr 1; rw [mul_one, exp_neg]
          _ ≤ ENNReal.ofReal (exp (-(k : ℝ) * ε)) := by
              apply ENNReal.ofReal_le_ofReal; apply exp_le_exp.mpr
              simp only [neg_mul, neg_le_neg_iff]
              have : (k : ℝ) ≤ (k : ℝ) + 1 := le_add_of_nonneg_right (by norm_num)
              exact mul_le_mul_of_nonneg_right this hε.le
      rw [← nonpos_iff_eq_zero]
      have h_lim : Filter.Tendsto (fun n : ℕ => ENNReal.ofReal (exp (-(n : ℝ) * ε)))
          Filter.atTop (nhds 0) := by
        have h1 : Filter.Tendsto (fun n : ℕ => (n : ℝ) * ε) Filter.atTop Filter.atTop :=
          Filter.Tendsto.atTop_mul_const hε tendsto_natCast_atTop_atTop
        have h2 : Filter.Tendsto (fun n : ℕ => exp (-((n : ℝ) * ε))) Filter.atTop (nhds 0) :=
          by simpa only [Function.comp] using tendsto_exp_neg_atTop_nhds_zero.comp h1
        have h3' := ENNReal.tendsto_ofReal h2
        simp only [ENNReal.ofReal_zero] at h3'
        have h_eq : (fun n : ℕ => ENNReal.ofReal (exp (-(n : ℝ) * ε))) =
            (fun n : ℕ => ENNReal.ofReal (exp (-((n : ℝ) * ε)))) := by ext n; ring_nf
        rw [h_eq]; exact h3'
      exact ge_of_tendsto' h_lim (fun n => h_bound n)
    apply measure_mono_null (t := ⋃ n : ℕ, {ω | -Y ω > 1/((n : ℝ)+1)})
    · intro ω hω
      simp only [mem_iUnion, mem_setOf_eq, ge_iff_le, not_le] at hω ⊢
      have hY_neg' : 0 < -Y ω := by linarith
      obtain ⟨n, hn⟩ := exists_nat_gt (1 / (-Y ω))
      use n
      calc (1 : ℝ) / ((n : ℝ) + 1) < 1 / (1 / (-Y ω)) := by
            apply one_div_lt_one_div_of_lt (one_div_pos.mpr hY_neg'); linarith
        _ = -Y ω := one_div_one_div _
    · rw [measure_iUnion_null_iff]
      intro n; exact h_tail_zero_neg (1 / ((n : ℝ) + 1)) (by positivity)
  filter_upwards [h_le_zero, h_ge_zero] with ω h1 h2
  linarith

/-- If Y = 0 a.e., then ∫|Y| = 0. -/
lemma integral_abs_eq_zero_of_ae_eq_zero {μ : Measure Ω} {Y : Ω → ℝ}
    (hY_ae : Y =ᵐ[μ] (fun _ => 0)) : ∫ ω, |Y ω| ∂μ = 0 := by
  have h_ae : (fun ω => |Y ω|) =ᵐ[μ] (fun _ => (0 : ℝ)) := by
    filter_upwards [hY_ae] with ω hω
    simp [hω]
  rw [integral_congr_ae h_ae, integral_zero]

/-- Integral of absolute value of sub-Gaussian increment with variance proxy 0. -/
lemma integral_abs_subGaussian_zero {μ : Measure Ω} [IsProbabilityMeasure μ]
    {Y : Ω → ℝ}
    (hY_mgf_le_one : ∀ l : ℝ, μ[fun ω => exp (l * Y ω)] ≤ 1)
    (hY_int_exp : ∀ l : ℝ, Integrable (fun ω => exp (l * Y ω)) μ) :
    ∫ ω, |Y ω| ∂μ = 0 := by
  have hY_ae := ae_eq_zero_of_mgf_le_one
    hY_mgf_le_one
    (fun l _ => hY_int_exp l)
    (fun l _ => hY_int_exp l)
  exact integral_abs_eq_zero_of_ae_eq_zero hY_ae

/-- Sub-Gaussian first moment bound: E[|X_s - X_t|] ≤ √(2π) · σ · d(s,t).

    **Proof sketch** (via layer-cake formula):
    1. From `subGaussian_tail_bound`: P(|X_s - X_t| ≥ r) ≤ 2·exp(-r²/(2σ²d(s,t)²))
    2. By layer-cake: E[|X_s - X_t|] = ∫₀^∞ P(|X_s - X_t| ≥ r) dr
    3. Computing: ∫₀^∞ 2·exp(-r²/(2τ²)) dr = τ·√(2π) where τ = σ·d(s,t)
    4. Therefore: E[|X_s - X_t|] ≤ √(2π) · σ · d(s,t) -/
theorem subGaussian_first_moment_bound {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ} (hσ : 0 < σ)
    (hX : IsSubGaussianProcess μ X σ)
    (s t : A)
    (h_int : Integrable (fun ω => X s ω - X t ω) μ)
    (h_int_exp : ∀ l : ℝ, Integrable (fun ω => exp (l * (X s ω - X t ω))) μ) :
    ∫ ω, |X s ω - X t ω| ∂μ ≤ Real.sqrt (2 * Real.pi) * σ * dist s t := by
  set Y : Ω → ℝ := fun ω => X s ω - X t ω
  by_cases hd : dist s t = 0
  · simp only [hd, mul_zero]
    have hY_mgf_le_one : ∀ l : ℝ, μ[fun ω => exp (l * Y ω)] ≤ 1 := fun l => by
      calc μ[fun ω => exp (l * Y ω)]
        _ ≤ exp (l^2 * σ^2 * (dist s t)^2 / 2) := hX s t l
        _ = 1 := by simp [hd]
    have h_eq := integral_abs_subGaussian_zero hY_mgf_le_one h_int_exp
    linarith
  · have hd_pos : 0 < dist s t := lt_of_le_of_ne dist_nonneg (Ne.symm hd)
    set τ := σ * dist s t
    have hτ_pos : 0 < τ := mul_pos hσ hd_pos
    calc ∫ ω, |Y ω| ∂μ
      _ ≤ τ * sqrt (2 * π) := by
          have h_int_abs : Integrable (fun ω => |Y ω|) μ := h_int.abs
          have h_tail : ∀ r : ℝ, 0 < r →
              (μ {ω | |Y ω| ≥ r}).toReal ≤ 2 * exp (-r^2 / (2 * τ^2)) := fun r hr => by
            have h_int' : ∀ l : ℝ, Integrable (fun ω => exp (l * (X t ω - X s ω))) μ := fun l => by
              convert h_int_exp (-l) using 2
              simp only [show ∀ ω, l * (X t ω - X s ω) = -l * (X s ω - X t ω) by intro ω; ring]
            have h := subGaussian_tail_bound hσ hX s t r hr hd_pos h_int_exp h_int'
            convert h using 3
            field_simp; ring
          have h_abs_nonneg : 0 ≤ᵐ[μ] (fun ω => |Y ω|) := ae_of_all μ (fun _ => abs_nonneg _)
          have h_abs_meas : AEStronglyMeasurable (fun ω => |Y ω|) μ := h_int_abs.aestronglyMeasurable
          have h_abs_aemeas : AEMeasurable (fun ω => |Y ω|) μ := h_abs_meas.aemeasurable
          rw [integral_eq_lintegral_of_nonneg_ae h_abs_nonneg h_abs_meas]
          rw [lintegral_eq_lintegral_tail h_abs_aemeas h_abs_nonneg]
          have h_tail_ennreal : ∀ r : ℝ, 0 < r →
              μ {ω | r ≤ |Y ω|} ≤ ENNReal.ofReal (2 * exp (-r^2 / (2 * τ^2))) := fun r hr => by
            have h := h_tail r hr
            rw [← ENNReal.toReal_le_toReal (measure_ne_top μ _) ENNReal.ofReal_ne_top]
            convert h using 2
            rw [ENNReal.toReal_ofReal (by positivity : 0 ≤ 2 * exp (-r^2 / (2 * τ^2)))]
          have h_lintegral_bound : ∫⁻ t in Ioi (0 : ℝ), μ {ω | t ≤ |Y ω|} ≤
              ∫⁻ t in Ioi (0 : ℝ), ENNReal.ofReal (2 * exp (-t^2 / (2 * τ^2))) := by
            apply MeasureTheory.lintegral_mono_ae
            filter_upwards [ae_restrict_mem measurableSet_Ioi] with t ht
            exact h_tail_ennreal t (Set.mem_Ioi.mp ht)
          have h_gaussian_integrable : Integrable (fun t => 2 * exp (-t^2 / (2 * τ^2))) (volume.restrict (Ioi (0 : ℝ))) := by
            apply Integrable.const_mul
            have h_form : (fun t : ℝ => exp (-t^2 / (2 * τ^2))) = (fun t : ℝ => exp (-(1/(2*τ^2)) * t^2)) := by
              ext t; congr 1; field_simp
            rw [h_form]
            exact integrableOn_Ioi_exp_neg_mul_sq_iff.mpr (by positivity : 0 < 1 / (2 * τ^2))
          have h_gaussian_nonneg : 0 ≤ᵐ[volume.restrict (Ioi (0 : ℝ))] (fun t => 2 * exp (-t^2 / (2 * τ^2))) :=
            ae_of_all _ (fun _ => by positivity)
          have h_ofReal_lintegral : ∫⁻ t in Ioi (0 : ℝ), ENNReal.ofReal (2 * exp (-t^2 / (2 * τ^2))) =
              ENNReal.ofReal (∫ t in Ioi (0 : ℝ), 2 * exp (-t^2 / (2 * τ^2))) := by
            rw [← ofReal_integral_eq_lintegral_ofReal h_gaussian_integrable h_gaussian_nonneg]
          rw [h_ofReal_lintegral] at h_lintegral_bound
          rw [gaussian_tail_integral hτ_pos] at h_lintegral_bound
          exact ENNReal.toReal_le_of_le_ofReal (by positivity) h_lintegral_bound
      _ = sqrt (2 * π) * σ * dist s t := by ring

/-!
## Maximum over finite sets

For Dudley's chaining argument, we need bounds on the expected maximum of a sub-Gaussian
process over finite sets.
-/

omit [PseudoMetricSpace A] in
/-- For a finite nonempty set, the subtype iSup equals sup'.
    This avoids the issue with biSup and sSup ∅ for ℝ. -/
lemma iSup_subtype_eq_sup' {T : Finset A} (hT : T.Nonempty) (f : A → ℝ) :
    ⨆ (t : T), f t = T.sup' hT f := by
  haveI : Nonempty T := hT.to_subtype
  haveI : Fintype T := Finset.fintypeCoeSort T
  have h := Finset.sup'_univ_eq_ciSup (α := ℝ) (ι := T) (f ∘ Subtype.val)
  simp only [Function.comp_apply] at h
  rw [← h]
  apply le_antisymm
  · apply Finset.sup'_le
    intro ⟨t, ht⟩ _
    exact Finset.le_sup' f ht
  · apply Finset.sup'_le
    intro t ht
    exact Finset.le_sup' (f := fun (x : T) => f x) (Finset.mem_univ (⟨t, ht⟩ : T))

omit [PseudoMetricSpace A] in
/-- For a finite set with at least one non-negative value, biSup equals sup'.
    The hypothesis is needed because sSup ∅ = 0 for ℝ. -/
lemma biSup_eq_sup'_of_finset {T : Finset A} (hT : T.Nonempty) (f : A → ℝ)
    (h_nonneg : ∃ t ∈ T, 0 ≤ f t) :
    ⨆ t ∈ T, f t = T.sup' hT f := by
  have h_sSup : sSup (∅ : Set ℝ) = 0 := Real.sSup_empty
  have h_cond : ∃ x ∈ T, sSup ∅ ≤ f x := by
    obtain ⟨t, ht, hft⟩ := h_nonneg
    exact ⟨t, ht, h_sSup ▸ hft⟩
  have h_image_ne : (T.image f).Nonempty := hT.image f
  have h := Finset.ciSup_eq_max'_image f h_cond h_image_ne
  rw [h, Finset.max'_eq_sup', Finset.sup'_image]
  simp only [Function.comp_def, id]

/-- E[max_{t ∈ T} X_t] ≤ σ · diam(T) · √(2 log |T|) for centered sub-Gaussian processes. -/
theorem subGaussian_finite_max_bound {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ} (hσ : 0 < σ)
    (hX : IsSubGaussianProcess μ X σ)
    (T : Finset A) (hT : T.Nonempty) (hT_card : 2 ≤ T.card)
    (t₀ : A) (ht₀ : t₀ ∈ T) (hcenter : ∀ ω, X t₀ ω = 0)
    (hX_meas : ∀ t, Measurable (X t))
    -- Additional hypotheses for the MGF method
    (hX_int : ∀ t ∈ T, Integrable (X t) μ)
    (hX_int_exp : ∀ t ∈ T, ∀ l : ℝ, Integrable (fun ω => exp (l * X t ω)) μ)
    -- Non-degeneracy: diam > 0 (otherwise the bound is trivial but requires extra work)
    (hdiam_pos : 0 < Metric.diam (T : Set A)) :
    μ[fun ω => ⨆ t ∈ T, X t ω] ≤ σ * Metric.diam (T : Set A) * sqrt (2 * log T.card) := by
  have h_biSup_eq : ∀ ω, ⨆ t ∈ T, X t ω = T.sup' hT (fun t => X t ω) := fun ω =>
    biSup_eq_sup'_of_finset hT (fun t => X t ω) ⟨t₀, ht₀, le_of_eq (hcenter ω).symm⟩
  set σ' := σ * Metric.diam (T : Set A) with hσ'_def
  have hσ' : 0 < σ' := mul_pos hσ hdiam_pos
  have h_cgf_bound : ∀ t ∈ T, ∀ l, cgf (X t) μ l ≤ l^2 * σ'^2 / 2 := by
    intro t ht l
    unfold cgf mgf
    have h_mgf_bound : μ[fun ω => exp (l * X t ω)] ≤ exp (l^2 * σ'^2 / 2) := by
      have h1 : μ[fun ω => exp (l * X t ω)] = μ[fun ω => exp (l * (X t ω - X t₀ ω))] := by
        congr 1; ext ω; simp only [hcenter ω, sub_zero]
      rw [h1]
      calc μ[fun ω => exp (l * (X t ω - X t₀ ω))]
        _ ≤ exp (l^2 * σ^2 * (dist t t₀)^2 / 2) := hX t t₀ l
        _ ≤ exp (l^2 * σ'^2 / 2) := by
            apply exp_le_exp.mpr
            apply div_le_div_of_nonneg_right _ (by norm_num : (0 : ℝ) ≤ 2)
            have hdist : (dist t t₀)^2 ≤ (Metric.diam (T : Set A))^2 := by
              apply sq_le_sq'
              · calc -(Metric.diam (T : Set A))
                  _ ≤ 0 := neg_nonpos.mpr Metric.diam_nonneg
                  _ ≤ dist t t₀ := dist_nonneg
              · exact Metric.dist_le_diam_of_mem (Finset.finite_toSet T).isBounded ht ht₀
            calc l^2 * σ^2 * (dist t t₀)^2
              _ ≤ l^2 * σ^2 * (Metric.diam (T : Set A))^2 := by
                  apply mul_le_mul_of_nonneg_left hdist (mul_nonneg (sq_nonneg _) (sq_nonneg _))
              _ = l^2 * σ'^2 := by rw [hσ'_def, mul_pow]; ring
    have h_mgf_pos : 0 < μ[fun ω => exp (l * X t ω)] := integral_exp_pos (hX_int_exp t ht l)
    calc log (μ[fun ω => exp (l * X t ω)])
      _ ≤ log (exp (l^2 * σ'^2 / 2)) := log_le_log h_mgf_pos h_mgf_bound
      _ = l^2 * σ'^2 / 2 := log_exp _
  have h_result := expected_max_subGaussian (ι := A) (s := T) hσ' hT hT_card
    (fun t ht => hX_meas t)
    (fun t ht => hX_int t ht)
    (fun t ht l => h_cgf_bound t ht l)
    (fun t ht l => hX_int_exp t ht l)
  calc ∫ ω, ⨆ t ∈ T, X t ω ∂μ
    _ = ∫ ω, T.sup' hT (fun t => X t ω) ∂μ := by congr 1; ext ω; exact h_biSup_eq ω
    _ ≤ σ' * sqrt (2 * log T.card) := h_result

/-- Variant of `subGaussian_finite_max_bound` with diameter bound D and no fixed basepoint. -/
theorem subGaussian_finite_max_bound' {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ} (hσ : 0 < σ)
    (hX : IsSubGaussianProcess μ X σ)
    (T : Finset A) (hT : 2 ≤ T.card)
    (D : ℝ) (hD : 0 < D) (hdiam : Metric.diam (T : Set A) ≤ D)
    (hX_meas : ∀ t, Measurable (X t))
    (hX_int : ∀ t s : A, Integrable (fun ω => X t ω - X s ω) μ)
    (hX_int_exp : ∀ t s : A, ∀ l : ℝ, Integrable (fun ω => exp (l * (X t ω - X s ω))) μ) :
    ∃ C : ℝ, C > 0 ∧ C ≤ sqrt 2 ∧ ∀ t₀ ∈ T,
      μ[fun ω => ⨆ t ∈ T, (X t ω - X t₀ ω)] ≤ C * σ * D * sqrt (log T.card) := by
  use sqrt 2
  refine ⟨sqrt_pos.mpr (by norm_num), le_refl _, ?_⟩
  · intro t₀ ht₀
    set Y : A → Ω → ℝ := fun t ω => X t ω - X t₀ ω with hY_def
    have hT_ne : T.Nonempty := Finset.card_pos.mp (Nat.lt_of_lt_of_le (by norm_num : 0 < 2) hT)
    have hY_sg : IsSubGaussianProcess μ Y σ := by
      intro s t l
      simp only [hY_def]
      have h_eq : ∀ ω, (X s ω - X t₀ ω) - (X t ω - X t₀ ω) = X s ω - X t ω := fun ω => by ring
      calc μ[fun ω => exp (l * (Y s ω - Y t ω))]
        _ = μ[fun ω => exp (l * (X s ω - X t ω))] := by
            congr 1; ext ω; simp [hY_def, h_eq]
        _ ≤ exp (l^2 * σ^2 * (dist s t)^2 / 2) := hX s t l
    have hY_center : ∀ ω, Y t₀ ω = 0 := fun ω => by simp [hY_def]
    have hY_meas : ∀ t, Measurable (Y t) := fun t => (hX_meas t).sub (hX_meas t₀)
    have hY_int : ∀ t ∈ T, Integrable (Y t) μ := fun t _ => hX_int t t₀
    have hY_int_exp : ∀ t ∈ T, ∀ l : ℝ, Integrable (fun ω => exp (l * Y t ω)) μ := by
      intro t _ l
      convert hX_int_exp t t₀ l using 1
    by_cases hdiam_zero : Metric.diam (T : Set A) = 0
    · calc ∫ ω, ⨆ t ∈ T, (X t ω - X t₀ ω) ∂μ
        _ ≤ 0 := by
            have h_dist_zero : ∀ t ∈ T, dist t t₀ = 0 := fun t ht => by
              have h1 := Metric.dist_le_diam_of_mem (Finset.finite_toSet T).isBounded ht ht₀
              have h2 : 0 ≤ dist t t₀ := dist_nonneg
              linarith [hdiam_zero]
            have h_Y_zero_ae : ∀ t ∈ T, Y t =ᵐ[μ] (fun _ => 0) := fun t ht => by
              have h_mgf_le_one : ∀ l, μ[fun ω => exp (l * Y t ω)] ≤ 1 := fun l => by
                simp only [hY_def]
                calc μ[fun ω => exp (l * (X t ω - X t₀ ω))]
                  _ ≤ exp (l^2 * σ^2 * (dist t t₀)^2 / 2) := hX t t₀ l
                  _ = 1 := by simp [h_dist_zero t ht]
              have h_int_exp_pos : ∀ l : ℝ, 0 < l → Integrable (fun ω => exp (l * Y t ω)) μ :=
                fun l _ => hY_int_exp t ht l
              have h_int_exp_neg : ∀ l : ℝ, l < 0 → Integrable (fun ω => exp (l * Y t ω)) μ :=
                fun l _ => hY_int_exp t ht l
              exact ae_eq_zero_of_mgf_le_one h_mgf_le_one h_int_exp_pos h_int_exp_neg
            have h_all_ae : ∀ᵐ ω ∂μ, ∀ t ∈ T, Y t ω = 0 := by
              have h_ae_forall : ∀ t ∈ T, ∀ᵐ ω ∂μ, Y t ω = 0 := fun t ht => by
                filter_upwards [h_Y_zero_ae t ht] with ω hω
                exact hω
              exact T.eventually_all.mpr (fun t ht => h_ae_forall t ht)
            -- biSup = sup' for nonempty finite set
            have h_biSup : ∀ ω, ⨆ t ∈ T, (X t ω - X t₀ ω) = T.sup' hT_ne (fun t => X t ω - X t₀ ω) :=
              fun ω => biSup_eq_sup'_of_finset hT_ne _ ⟨t₀, ht₀, by simp only [sub_self, le_refl]⟩
            have h_sup_ae : (fun ω => ⨆ t ∈ T, (X t ω - X t₀ ω)) =ᵐ[μ] (fun _ => 0) := by
              filter_upwards [h_all_ae] with ω h_all
              rw [h_biSup]
              apply le_antisymm
              · apply Finset.sup'_le; intro t ht; simp [hY_def] at h_all; linarith [h_all t ht]
              · exact Finset.le_sup' _ ht₀ |>.trans' (by simp only [sub_self, le_refl])
            have h_eq_zero : ∫ ω, ⨆ t ∈ T, (X t ω - X t₀ ω) ∂μ = 0 := by
              calc ∫ ω, ⨆ t ∈ T, (X t ω - X t₀ ω) ∂μ
                _ = ∫ _, (0 : ℝ) ∂μ := integral_congr_ae h_sup_ae
                _ = 0 := by simp
            linarith
        _ ≤ sqrt 2 * σ * D * sqrt (log T.card) := by positivity
    · have hdiam_pos : 0 < Metric.diam (T : Set A) :=
        lt_of_le_of_ne Metric.diam_nonneg (fun h => hdiam_zero h.symm)
      have h_bound := subGaussian_finite_max_bound hσ hY_sg T hT_ne hT t₀ ht₀
        hY_center hY_meas hY_int hY_int_exp hdiam_pos
      calc ∫ ω, ⨆ t ∈ T, (X t ω - X t₀ ω) ∂μ
        _ = ∫ ω, ⨆ t ∈ T, Y t ω ∂μ := by simp only [hY_def]
        _ ≤ σ * Metric.diam (T : Set A) * sqrt (2 * log T.card) := h_bound
        _ ≤ σ * D * sqrt (2 * log T.card) := by
            apply mul_le_mul_of_nonneg_right _ (sqrt_nonneg _)
            apply mul_le_mul_of_nonneg_left hdiam (le_of_lt hσ)
        _ = sqrt 2 * σ * D * sqrt (log T.card) := by
            rw [sqrt_mul (by norm_num : (0 : ℝ) ≤ 2) (log T.card)]
            ring

/-!
## Helper lemmas for hypothesis elimination

These lemmas help derive integrability and centeredness from exponential integrability,
allowing us to eliminate redundant hypotheses in the Dudley theorem.
-/

/-- If `exp(l * Y)` is integrable for all `l : ℝ`, then `Y` is integrable.

This follows from the fact that when `integrableExpSet Y μ = univ`, we have
`0 ∈ interior(integrableExpSet Y μ)`, and Mathlib provides that `Y^p` is
integrable for any `p ≥ 0` in this case. -/
lemma integrable_of_integrable_exp_all {Ω : Type*} [MeasurableSpace Ω]
    {Y : Ω → ℝ} {μ : Measure Ω}
    (h : ∀ l : ℝ, Integrable (fun ω => exp (l * Y ω)) μ) :
    Integrable Y μ := by
  have h_set_eq : integrableExpSet Y μ = Set.univ := by
    ext t
    simp only [integrableExpSet, Set.mem_setOf_eq, Set.mem_univ, iff_true]
    exact h t
  have h_interior : (0 : ℝ) ∈ interior (integrableExpSet Y μ) := by
    rw [h_set_eq, interior_univ]
    exact Set.mem_univ _
  exact integrable_of_mem_interior_integrableExpSet h_interior

/-- If a sub-Gaussian process satisfies the MGF bound and has exponential integrability,
then the increment `X s - X t` has zero mean.

**Proof idea:** The MGF `M(l) = E[exp(l * (X s - X t))]` satisfies:
1. `M(l) ≤ exp(l² σ² d(s,t)² / 2)` for all `l` (sub-Gaussian bound)
2. At `l = 0`: `M(0) = 1` and RHS = 1
3. `M'(0) = E[X s - X t]` (by `deriv_mgf_zero`)
4. Since `M(l) ≤ f(l)` where `f(l) = exp(l² σ² d² / 2)`, and `f'(0) = 0`,
   we get `E[X s - X t] ≤ 0` by comparing derivatives at a touching point.
5. By symmetry (swapping s and t), `E[X t - X s] ≤ 0`, i.e., `E[X s - X t] ≥ 0`.
6. Therefore `E[X s - X t] = 0`. -/
lemma subGaussian_process_centered {Ω : Type*} [MeasurableSpace Ω]
    {A : Type*} [PseudoMetricSpace A] {μ : Measure Ω} [IsProbabilityMeasure μ]
    {X : A → Ω → ℝ} {σ : ℝ}
    (hX : IsSubGaussianProcess μ X σ) (s t : A)
    (hX_int_exp : ∀ l : ℝ, Integrable (fun ω => exp (l * (X s ω - X t ω))) μ) :
    ∫ ω, (X s ω - X t ω) ∂μ = 0 := by
  set Y := fun ω => X s ω - X t ω
  -- Establish that 0 is in interior of integrableExpSet
  have h_set_eq : integrableExpSet Y μ = Set.univ := by
    ext l
    simp only [integrableExpSet, Set.mem_setOf_eq, Set.mem_univ, iff_true]
    exact hX_int_exp l
  have h_interior : (0 : ℝ) ∈ interior (integrableExpSet Y μ) := by
    rw [h_set_eq, interior_univ]
    exact Set.mem_univ _
  -- The MGF is differentiable with derivative involving the integral
  have h_hasderiv : HasDerivAt (mgf Y μ) (∫ ω, Y ω * exp (0 * Y ω) ∂μ) 0 :=
    hasDerivAt_mgf h_interior
  -- Simplify: Y * exp(0 * Y) = Y * 1 = Y
  have h_deriv_simp : (∫ ω, Y ω * exp (0 * Y ω) ∂μ) = ∫ ω, Y ω ∂μ := by
    congr 1; ext ω; simp
  rw [h_deriv_simp] at h_hasderiv
  -- The MGF bound gives us: mgf Y μ l ≤ exp(l² σ² d² / 2) for all l
  have h_mgf_bound : ∀ l : ℝ, mgf Y μ l ≤ exp (l^2 * σ^2 * (dist s t)^2 / 2) := hX s t
  set c := σ^2 * (dist s t)^2 / 2
  -- The key: (mgf Y μ) - (fun l => exp(l² c)) has a LOCAL MAXIMUM at 0
  -- because mgf Y μ l ≤ exp(l² c) for all l, and both equal 1 at l = 0
  have h_mgf_zero : mgf Y μ 0 = 1 := mgf_zero
  -- Define g(l) = mgf Y μ l - exp(l² c)
  set g := fun l => mgf Y μ l - exp (l^2 * c) with hg_def
  -- g has a local max at 0 because g(l) ≤ 0 for all l and g(0) = 0
  have hg_nonpos : ∀ l, g l ≤ 0 := fun l => by
    simp only [hg_def]
    have h := h_mgf_bound l
    have hc_eq : l^2 * σ^2 * dist s t ^ 2 / 2 = l^2 * c := by ring
    rw [hc_eq] at h
    linarith
  have hg_zero : g 0 = 0 := by simp [hg_def, h_mgf_zero]
  have h_local_max : IsLocalMax g 0 := by
    rw [IsLocalMax, IsMaxFilter]
    filter_upwards with l
    rw [hg_zero]
    exact hg_nonpos l
  -- The bound function exp(l² c) has derivative 0 at l = 0
  have h_bound_deriv : HasDerivAt (fun l => exp (l^2 * c)) 0 0 := by
    -- d/dl[exp(l² c)] at l=0 = exp(0) · (2·0·c) = 1 · 0 = 0
    have hinner : HasDerivAt (fun l : ℝ => l^2 * c) 0 0 := by
      have h1 := hasDerivAt_pow 2 (0 : ℝ)
      have h1' : HasDerivAt (fun l : ℝ => l^2) 0 0 := by simpa using h1
      have h2 := h1'.mul_const c
      simpa using h2
    have hexp : HasDerivAt exp 1 0 := by simpa using Real.hasDerivAt_exp 0
    have hinner_at_zero : (fun l : ℝ => l^2 * c) 0 = 0 := by simp
    have h := HasDerivAt.scomp_of_eq (0 : ℝ) hexp hinner hinner_at_zero.symm
    simp only [smul_eq_mul, mul_one] at h
    exact h
  -- g has derivative (∫ Y) - 0 = ∫ Y at 0
  have h_g_deriv : HasDerivAt g (∫ ω, Y ω ∂μ) 0 := by
    have := h_hasderiv.sub h_bound_deriv
    simp only [sub_zero] at this
    exact this
  -- By local max at 0, g'(0) = 0, hence ∫ Y = 0
  exact IsLocalMax.hasDerivAt_eq_zero h_local_max h_g_deriv

end


