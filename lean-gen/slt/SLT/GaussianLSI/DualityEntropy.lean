/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianLSI.Entropy
import Mathlib.MeasureTheory.Measure.WithDensity
import Mathlib.MeasureTheory.Integral.Bochner.ContinuousLinearMap
import Mathlib.Analysis.SpecialFunctions.Log.ERealExp
import Mathlib.Data.EReal.Operations
import Mathlib.Analysis.SpecialFunctions.Log.ENNRealLogExp
import Mathlib.MeasureTheory.Function.L1Space.Integrable

/-!
# Duality Formula for Entropy

This file proves the variational (duality) formula for entropy:

    Ent[Y; μ] = sup { E[u · Y] | U : Ω → EReal, E[e^U] = 1 }

where `Ent[Y; μ] = E[Y log Y] - E[Y] · log(E[Y])` is the entropy of a **nonnegative**
random variable Y with E[Y log Y] < ∞ (defined in `LogSobolev.Entropy`).

## Main Definitions

* `expIntegralEReal μ U` : ∫⁻ ω, (U ω).exp ∂μ for U : Ω → EReal
* `optimalU Y mean` : The optimizer log(Y/mean) on {Y > 0}, ⊥ on {Y ≤ 0}
* `expMeasure μ U` : The tilted measure e^U · μ (for real-valued U)
* `expMeasureEReal μ U` : The tilted measure e^U · μ (for EReal-valued U)
* `dualEntropySet μ Y` : The set { E[u · Y] | E[e^U] = 1 } for EReal U

## Main Results

* `entropy_ge_integral_mul` : E[U · Y] ≤ Ent[Y; μ] for real U with E[e^U] = 1
* `entropy_nonneg_sub_integral_of_exp_constraint` : Core lemma Ent[Y; μ] - E[u · Y] ≥ 0
* `dualEntropySet_le_entropy` : All elements of dualEntropySet are ≤ Ent[Y; μ]
* `optimalU_in_dualEntropySet` : The supremum Ent[Y; μ] is attained
* `entropy_duality` : **Main theorem** Ent[Y; μ] = sSup (dualEntropySet μ Y)

## Proof Strategy

The key identity (proved in `entropy_sub_eq_entropy_expMeasure`) is:

    Ent[Y; μ] - E[U · Y] = Ent[Y · e^{-U}; e^U · μ]

Since entropy is nonnegative (`entropy_nonneg`), this gives Ent[Y; μ] ≥ E[U · Y].
Equality holds when U = log(Y/E[Y]) on {Y > 0} and U = -∞ on {Y = 0}.

**Convention:** U : Ω → EReal allows U = ⊥ (= -∞) on {Y = 0}, ensuring e^U = 0 there
and that {Y = 0} contributes nothing to E[U · Y] (since ⊥ · 0 = 0 in EReal).

-/

open MeasureTheory ProbabilityTheory Real Set Filter
open scoped ENNReal NNReal BigOperators

noncomputable section

namespace LogSobolev

variable {Ω : Type*} [MeasurableSpace Ω] {μ : Measure Ω}

/-!
## EReal Integration Infrastructure
-/

/-- Integral of e^U where U : Ω → EReal, using Lebesgue integral.
    This equals 0 when U = ⊥ (since exp(⊥) = 0) and ⊤ when U = ⊤. -/
def expIntegralEReal (μ : Measure Ω) (U : Ω → EReal) : ℝ≥0∞ :=
  ∫⁻ ω, (U ω).exp ∂μ

/-- The optimal U for entropy duality: log(Y/E[Y]) when Y > 0, ⊥ when Y ≤ 0.
    This ensures e^U = Y/E[Y] on {Y > 0} and e^U = 0 on {Y ≤ 0}. -/
def optimalU (Y : Ω → ℝ) (mean : ℝ) : Ω → EReal :=
  fun ω => if 0 < Y ω then ((log (Y ω) - log mean) : ℝ) else ⊥

/-- Measurability of optimalU -/
lemma optimalU_measurable (Y : Ω → ℝ) (hY_meas : Measurable Y) (mean : ℝ) :
    Measurable (optimalU Y mean) := by
  unfold optimalU
  apply Measurable.ite
  · exact measurableSet_lt measurable_const hY_meas
  · exact (hY_meas.log.sub measurable_const).coe_real_ereal
  · exact measurable_const

omit [MeasurableSpace Ω] in
/-- exp of optimalU: equals Y/mean when Y > 0, equals 0 when Y ≤ 0 -/
lemma exp_optimalU (Y : Ω → ℝ) (mean : ℝ) (hmean : 0 < mean) (ω : Ω) :
    (optimalU Y mean ω).exp = if 0 < Y ω then ENNReal.ofReal (Y ω / mean) else 0 := by
  unfold optimalU
  split_ifs with hY
  · -- Y ω > 0
    rw [EReal.exp_coe, exp_sub, exp_log hY, exp_log hmean, div_eq_mul_inv]
  · -- Y ω ≤ 0
    exact EReal.exp_bot

/-- E[e^{optimalU}] = 1 when Y ≥ 0 a.e. and E[Y] > 0 -/
lemma expIntegralEReal_optimalU_eq_one [IsProbabilityMeasure μ]
    (Y : Ω → ℝ)
    (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_mean_pos : 0 < ∫ ω, Y ω ∂μ) :
    expIntegralEReal μ (optimalU Y (∫ ω, Y ω ∂μ)) = 1 := by
  unfold expIntegralEReal
  -- Compute the lintegral
  have h_exp : ∀ᵐ ω ∂μ, (optimalU Y (∫ ω', Y ω' ∂μ) ω).exp =
      ENNReal.ofReal (Y ω / ∫ ω', Y ω' ∂μ) := by
    filter_upwards [hY_nn] with ω hY_nn_ω
    rw [exp_optimalU Y _ hY_mean_pos]
    split_ifs with hY_pos
    · rfl
    · -- Y ω ≤ 0 but Y ω ≥ 0, so Y ω = 0
      have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
      simp [hY_zero]
  rw [lintegral_congr_ae h_exp]
  -- Now compute ∫⁻ ENNReal.ofReal (Y ω / E[Y])
  rw [← ENNReal.ofReal_one]
  -- ∫ Y / E[Y] = 1
  have h_div : ∫ ω, Y ω / ∫ ω', Y ω' ∂μ ∂μ = 1 := by
    have h_smul : ∫ ω, Y ω / (∫ ω', Y ω' ∂μ) ∂μ = (∫ ω, Y ω ∂μ) * (∫ ω', Y ω' ∂μ)⁻¹ := by
      simp_rw [div_eq_mul_inv]
      exact integral_mul_const_of_integrable hY_int
    rw [h_smul, mul_inv_cancel₀ (ne_of_gt hY_mean_pos)]
  rw [← h_div]
  -- Convert lintegral of ofReal to integral
  rw [← ofReal_integral_eq_lintegral_ofReal]
  · exact hY_int.div_const _
  · filter_upwards [hY_nn] with ω hω
    exact div_nonneg hω (le_of_lt hY_mean_pos)

/-!
## Product U * Y for EReal × ℝ

When U : Ω → EReal and Y : Ω → ℝ, we compute E[U * Y].
The key property is ⊥ * 0 = 0 in EReal, so the {Y = 0} part contributes nothing.
-/

omit [MeasurableSpace Ω] in
/-- The product (optimalU Y mean) * Y equals (log Y - log mean) * Y when Y > 0,
    and equals 0 when Y = 0. Note: When Y < 0, this equals ⊤, but we only use this
    lemma when Y ≥ 0 a.e. -/
lemma optimalU_mul_Y (Y : Ω → ℝ) (mean : ℝ) (hY_nn : 0 ≤ Y) (ω : Ω) :
    (optimalU Y mean ω) * (Y ω : EReal) =
    if 0 < Y ω then ((log (Y ω) - log mean) * Y ω : ℝ) else 0 := by
  unfold optimalU
  split_ifs with hY
  · -- Y ω > 0
    simp only [EReal.coe_mul]
  · -- Y ω ≤ 0 and Y ω ≥ 0 (from hY_nn), so Y ω = 0
    push_neg at hY
    have hY_zero : Y ω = 0 := le_antisymm hY (hY_nn ω)
    simp only [hY_zero, EReal.coe_zero, mul_zero]

omit [MeasurableSpace Ω] in
/-- Under Y ≥ 0, (optimalU * Y) takes real values -/
lemma optimalU_mul_Y_real (Y : Ω → ℝ) (hY_nn : 0 ≤ Y) (mean : ℝ) (ω : Ω) :
    ∃ r : ℝ, (optimalU Y mean ω) * (Y ω : EReal) = r := by
  rw [optimalU_mul_Y Y mean hY_nn ω]
  split_ifs with hY
  · exact ⟨_, rfl⟩
  · exact ⟨0, rfl⟩

/-- Under Y ≥ 0 a.e., (optimalU * Y) takes real values a.e. -/
lemma optimalU_mul_Y_real_ae (Y : Ω → ℝ) (hY_nn : 0 ≤ᵐ[μ] Y) (mean : ℝ) :
    ∀ᵐ ω ∂μ, ∃ r : ℝ, (optimalU Y mean ω) * (Y ω : EReal) = r := by
  filter_upwards [hY_nn] with ω hY_nn_ω
  -- Directly prove for this specific ω
  unfold optimalU
  split_ifs with hY
  · use (log (Y ω) - log mean) * Y ω
    rw [← EReal.coe_mul]
  · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY) hY_nn_ω
    simp only [hY_zero, EReal.coe_zero, mul_zero]
    exact ⟨0, rfl⟩

/-- The real value of (optimalU * Y) when Y ≥ 0 -/
def optimalU_mul_Y_toReal (Y : Ω → ℝ) (mean : ℝ) (ω : Ω) : ℝ :=
  if 0 < Y ω then (log (Y ω) - log mean) * Y ω else 0

omit [MeasurableSpace Ω] in
lemma optimalU_mul_Y_eq_toReal (Y : Ω → ℝ) (mean : ℝ) (hY_nn : 0 ≤ Y) (ω : Ω) :
    ((optimalU Y mean ω) * (Y ω : EReal)).toReal = optimalU_mul_Y_toReal Y mean ω := by
  unfold optimalU_mul_Y_toReal
  rw [optimalU_mul_Y Y mean hY_nn ω]
  split_ifs with hY
  · rfl
  · rfl

/-- E[(optimalU Y mean) * Y] = Ent(Y) when Y ≥ 0 a.e. -/
lemma integral_optimalU_mul_Y_eq_entropy [IsProbabilityMeasure μ]
    (Y : Ω → ℝ)
    (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ) :
    ∫ ω, optimalU_mul_Y_toReal Y (∫ ω', Y ω' ∂μ) ω ∂μ = entropy μ Y := by
  unfold entropy optimalU_mul_Y_toReal
  -- We need to show:
  -- ∫ (if 0 < Y then (log Y - log E[Y]) * Y else 0) = ∫ Y log Y - E[Y] * log E[Y]
  have h_eq : ∀ᵐ ω ∂μ, (if 0 < Y ω then (log (Y ω) - log (∫ ω', Y ω' ∂μ)) * Y ω else 0) =
      Y ω * log (Y ω) - log (∫ ω', Y ω' ∂μ) * Y ω := by
    filter_upwards [hY_nn] with ω hY_nn_ω
    split_ifs with hY_pos
    · ring
    · -- Y ω = 0 (since Y ω ≥ 0 and not Y ω > 0)
      have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
      simp [hY_zero]
  rw [integral_congr_ae h_eq]
  have h_const_int : Integrable (fun ω => log (∫ ω', Y ω' ∂μ) * Y ω) μ :=
    hY_int.const_mul _
  rw [integral_sub hY_log_int h_const_int]
  -- ∫ log(E[Y]) * Y = log(E[Y]) * ∫ Y
  have h_const : ∫ ω, log (∫ ω', Y ω' ∂μ) * Y ω ∂μ = log (∫ ω', Y ω' ∂μ) * ∫ ω, Y ω ∂μ := by
    rw [← integral_const_mul]
  rw [h_const]
  ring

/-!
## Integral under Changed Measure (for lower bound)

Key lemmas for computing integrals when the measure is changed from μ to ν = (e^U)·μ.
This is used for the lower bound direction with real-valued U.
-/

/-- The changed measure e^U · μ as a withDensity measure (for real-valued U) -/
def expMeasure (μ : Measure Ω) (U : Ω → ℝ) : Measure Ω :=
  μ.withDensity (fun ω => ENNReal.ofReal (exp (U ω)))

/-- If ∫ e^U dμ = 1, then expMeasure μ U is a probability measure -/
lemma expMeasure_isProbabilityMeasure [IsProbabilityMeasure μ]
    (U : Ω → ℝ)
    (hU_int : ∫ ω, exp (U ω) ∂μ = 1)
    (hU_exp_integrable : Integrable (fun ω => exp (U ω)) μ) :
    IsProbabilityMeasure (expMeasure μ U) := by
  constructor
  simp only [expMeasure, withDensity_apply _ MeasurableSet.univ, Measure.restrict_univ]
  have h : ∫⁻ ω, ENNReal.ofReal (exp (U ω)) ∂μ = ENNReal.ofReal (∫ ω, exp (U ω) ∂μ) := by
    rw [ofReal_integral_eq_lintegral_ofReal]
    · exact hU_exp_integrable
    · exact Eventually.of_forall (fun ω => le_of_lt (exp_pos (U ω)))
  rw [h, hU_int, ENNReal.ofReal_one]

/-- Integral of f with respect to expMeasure equals integral of f * e^U with respect to μ -/
lemma integral_expMeasure (U f : Ω → ℝ) (hU_meas : Measurable U) :
    ∫ ω, f ω ∂(expMeasure μ U) = ∫ ω, f ω * exp (U ω) ∂μ := by
  simp only [expMeasure]
  have hf_meas : Measurable (fun ω => ENNReal.ofReal (exp (U ω))) :=
    hU_meas.exp.ennreal_ofReal
  have hf_lt_top : ∀ᵐ ω ∂μ, ENNReal.ofReal (exp (U ω)) < ⊤ := by
    filter_upwards with ω
    exact ENNReal.ofReal_lt_top
  rw [integral_withDensity_eq_integral_toReal_smul hf_meas hf_lt_top]
  congr 1
  ext ω
  simp only [smul_eq_mul]
  rw [ENNReal.toReal_ofReal (le_of_lt (exp_pos (U ω)))]
  ring

/-!
## Key Identity: Ent(Y) - E[UY] = Ent_{e^U·P}[Y·e^{-U}]

This identity is the heart of the duality proof (for real-valued U).
-/

/-- The key identity relating entropy under original and changed measures. -/
lemma entropy_sub_eq_entropy_expMeasure [IsProbabilityMeasure μ]
    (U Y : Ω → ℝ) (hU_meas : Measurable U) (_hY_meas : Measurable Y)
    (_hU_exp_int : ∫ ω, exp (U ω) ∂μ = 1)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hUY_int : Integrable (fun ω => U ω * Y ω) μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ) :
    entropy μ Y - ∫ ω, U ω * Y ω ∂μ =
    entropy (expMeasure μ U) (fun ω => Y ω * exp (-U ω)) := by
  let ν := expMeasure μ U
  unfold entropy
  -- First compute ∫ g dν = ∫ Y dμ where g = Y * e^{-U}
  have h_int_g : ∫ ω, Y ω * exp (-U ω) ∂ν = ∫ ω, Y ω ∂μ := by
    rw [integral_expMeasure U (fun ω => Y ω * exp (-U ω)) hU_meas]
    congr 1
    ext ω
    rw [mul_assoc, ← exp_add, neg_add_cancel, exp_zero, mul_one]
  -- Next compute ∫ g log g dν
  have h_int_glogg : ∫ ω, (Y ω * exp (-U ω)) * log (Y ω * exp (-U ω)) ∂ν =
      ∫ ω, Y ω * log (Y ω) ∂μ - ∫ ω, U ω * Y ω ∂μ := by
    rw [integral_expMeasure U _ hU_meas]
    have h_eq : ∀ᵐ ω ∂μ, (Y ω * exp (-U ω)) * log (Y ω * exp (-U ω)) * exp (U ω) =
        Y ω * log (Y ω) - U ω * Y ω := by
      filter_upwards [hY_nn] with ω hY_nn_ω
      by_cases hY_zero : Y ω = 0
      · simp [hY_zero]
      · have hY_pos : 0 < Y ω := hY_nn_ω.lt_of_ne' hY_zero
        have hexp_cancel : exp (-U ω) * exp (U ω) = 1 := by
          rw [← exp_add, neg_add_cancel, exp_zero]
        rw [log_mul (ne_of_gt hY_pos) (ne_of_gt (exp_pos _)), log_exp]
        calc (Y ω * exp (-U ω)) * (log (Y ω) + -U ω) * exp (U ω)
            = Y ω * (exp (-U ω) * exp (U ω)) * (log (Y ω) - U ω) := by ring
          _ = Y ω * 1 * (log (Y ω) - U ω) := by rw [hexp_cancel]
          _ = Y ω * log (Y ω) - U ω * Y ω := by ring
    rw [integral_congr_ae h_eq, integral_sub hY_log_int hUY_int]
  rw [h_int_g, h_int_glogg]
  ring

/-!
## Lower Bound: Ent(Y) ≥ E[UY] (for real-valued U)
-/

/-- The fundamental lower bound: Ent(Y) ≥ E[UY] for any real-valued U with E[e^U] = 1. -/
theorem entropy_ge_integral_mul [IsProbabilityMeasure μ]
    (U Y : Ω → ℝ) (hU_meas : Measurable U) (hY_meas : Measurable Y)
    (hU_exp_int : ∫ ω, exp (U ω) ∂μ = 1)
    (hU_exp_integrable : Integrable (fun ω => exp (U ω)) μ)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hUY_int : Integrable (fun ω => U ω * Y ω) μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ)
    (hg_int : Integrable (fun ω => Y ω * exp (-U ω)) (expMeasure μ U))
    (hglogg_int : Integrable (fun ω => (Y ω * exp (-U ω)) * log (Y ω * exp (-U ω)))
        (expMeasure μ U)) :
    ∫ ω, U ω * Y ω ∂μ ≤ entropy μ Y := by
  have hν_prob : IsProbabilityMeasure (expMeasure μ U) :=
    expMeasure_isProbabilityMeasure U hU_exp_int hU_exp_integrable
  have h_eq := entropy_sub_eq_entropy_expMeasure U Y hU_meas hY_meas hU_exp_int
    hY_nn hUY_int hY_log_int
  have hg_nn : 0 ≤ᵐ[expMeasure μ U] (fun ω => Y ω * exp (-U ω)) := by
    simp only [expMeasure, EventuallyLE, Pi.zero_apply]
    rw [ae_withDensity_iff hU_meas.exp.ennreal_ofReal]
    filter_upwards [hY_nn] with ω hω _
    exact mul_nonneg hω (le_of_lt (exp_pos _))
  have h_nonneg := entropy_nonneg hg_nn hg_int hglogg_int
  linarith [h_eq, h_nonneg]

/-!
## The Duality Set and Main Theorem
-/

/-- The set of E[UY] values for U : Ω → EReal with E[e^U] = 1.
    We represent E[UY] as a real number when the integral makes sense. -/
def dualEntropySet (μ : Measure Ω) (Y : Ω → ℝ) : Set ℝ :=
  {x | ∃ U : Ω → EReal, Measurable U ∧
        expIntegralEReal μ U = 1 ∧
        -- The integral E[U * Y] is well-defined and equals x
        -- For simplicity, we require U to be real-valued a.e. where Y > 0
        (∃ u : Ω → ℝ, Measurable u ∧
          (∀ᵐ ω ∂μ, 0 < Y ω → U ω = (u ω : EReal)) ∧
          Integrable (fun ω => u ω * Y ω) μ ∧
          x = ∫ ω, u ω * Y ω ∂μ)}

/-- Alternative: simpler set using only real-valued U -/
def dualEntropySetReal (μ : Measure Ω) (Y : Ω → ℝ) : Set ℝ :=
  {x | ∃ U : Ω → ℝ, Measurable U ∧
        ∫ ω, exp (U ω) ∂μ = 1 ∧
        Integrable (fun ω => U ω * Y ω) μ ∧
        x = ∫ ω, U ω * Y ω ∂μ}

/-- The optimal U is in the EReal duality set (when E[Y] > 0) -/
lemma optimalU_in_dualEntropySet [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_mean_pos : 0 < ∫ ω, Y ω ∂μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ) :
    entropy μ Y ∈ dualEntropySet μ Y := by
  let mean := ∫ ω, Y ω ∂μ
  let U_opt := optimalU Y mean
  -- Define the real-valued part: u(ω) = log(Y ω) - log(mean) when Y > 0, and 0 otherwise
  let u : Ω → ℝ := fun ω => if 0 < Y ω then log (Y ω) - log mean else 0
  refine ⟨U_opt, optimalU_measurable Y hY_meas mean, ?_, u, ?_, ?_, ?_, ?_⟩
  · -- E[e^{U_opt}] = 1
    exact expIntegralEReal_optimalU_eq_one Y hY_nn hY_int hY_mean_pos
  · -- u is measurable
    apply Measurable.ite
    · exact measurableSet_lt measurable_const hY_meas
    · exact hY_meas.log.sub measurable_const
    · exact measurable_const
  · -- U_opt = u where Y > 0
    filter_upwards with ω
    intro hY_pos
    show optimalU Y mean ω = ((if 0 < Y ω then log (Y ω) - log mean else 0) : ℝ)
    simp only [optimalU, if_pos hY_pos]
  · -- u * Y is integrable
    have h_eq : (fun ω => u ω * Y ω) =ᵐ[μ] (optimalU_mul_Y_toReal Y mean) := by
      filter_upwards [hY_nn] with ω hY_nn_ω
      show (if 0 < Y ω then log (Y ω) - log mean else 0) * Y ω = optimalU_mul_Y_toReal Y mean ω
      simp only [optimalU_mul_Y_toReal]
      split_ifs with hY_pos
      · rfl
      · simp only [zero_mul]
    -- Show optimalU_mul_Y_toReal is integrable
    have h_eq2 : (fun ω => Y ω * log (Y ω) - log mean * Y ω) =ᵐ[μ] optimalU_mul_Y_toReal Y mean := by
      filter_upwards [hY_nn] with ω hY_nn_ω
      simp only [optimalU_mul_Y_toReal]
      split_ifs with hY_pos
      · ring
      · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    have h_int_toReal : Integrable (optimalU_mul_Y_toReal Y mean) μ :=
      Integrable.congr (hY_log_int.sub (hY_int.const_mul _)) h_eq2
    exact Integrable.congr h_int_toReal h_eq.symm
  · -- x = E[u * Y] = entropy
    have h_eq : ∀ᵐ ω ∂μ, u ω * Y ω = optimalU_mul_Y_toReal Y mean ω := by
      filter_upwards [hY_nn] with ω hY_nn_ω
      show (if 0 < Y ω then log (Y ω) - log mean else 0) * Y ω = optimalU_mul_Y_toReal Y mean ω
      simp only [optimalU_mul_Y_toReal]
      split_ifs with hY_pos
      · rfl
      · simp only [zero_mul]
    rw [integral_congr_ae h_eq]
    exact (integral_optimalU_mul_Y_eq_entropy Y hY_nn hY_int hY_log_int).symm

/-- When E[Y] = 0, entropy is 0 and the constant U = 0 achieves this -/
lemma entropy_eq_zero_of_mean_zero [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_mean_zero : ∫ ω, Y ω ∂μ = 0) :
    entropy μ Y = 0 := by
  -- When E[Y] = 0 and Y ≥ 0 a.e., we have Y = 0 a.e.
  have hY_zero : Y =ᵐ[μ] 0 := (integral_eq_zero_iff_of_nonneg_ae hY_nn hY_int).mp hY_mean_zero
  -- Entropy of 0 is 0
  calc entropy μ Y = entropy μ (fun _ => 0) := entropy_congr hY_zero
    _ = 0 := entropy_const μ 0

/-- When E[Y] = 0, the dualEntropySet contains 0 (achieved by U = 0) -/
lemma zero_in_dualEntropySet_of_mean_zero [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) :
    (0 : ℝ) ∈ dualEntropySet μ Y := by
  -- Use U = 0 (constant function)
  refine ⟨fun _ => (0 : ℝ), measurable_const.coe_real_ereal, ?_, fun _ => 0, measurable_const, ?_, ?_, ?_⟩
  · -- E[e^0] = E[1] = 1
    simp only [expIntegralEReal, lintegral_const, MeasureTheory.measure_univ]
    simp only [EReal.coe_zero, EReal.exp_zero, one_mul]
  · -- U = u = 0 everywhere
    filter_upwards with ω _
    rfl
  · -- 0 * Y is integrable
    simp only [zero_mul]
    exact integrable_zero _ _ _
  · -- x = ∫ 0 * Y = 0
    simp only [zero_mul, integral_zero]

/-- The tilted measure using EReal-valued U.
    This is the measure e^U · μ where EReal.exp : EReal → ENNReal. -/
def expMeasureEReal (μ : Measure Ω) (U : Ω → EReal) : Measure Ω :=
  μ.withDensity (fun ω => (U ω).exp)

/-- When expIntegralEReal μ U = 1, the tilted measure is a probability measure. -/
lemma expMeasureEReal_isProbabilityMeasure [IsProbabilityMeasure μ]
    (U : Ω → EReal) (_hU_meas : Measurable U)
    (hU_int : expIntegralEReal μ U = 1) :
    IsProbabilityMeasure (expMeasureEReal μ U) := by
  constructor
  simp only [expMeasureEReal, withDensity_apply _ MeasurableSet.univ, Measure.restrict_univ]
  exact hU_int

/-- The density (U ω).exp is a.e. finite when ∫⁻ (U ω).exp dμ < ∞ -/
lemma exp_density_ae_lt_top {U : Ω → EReal} (hU_meas : Measurable U)
    (hU_exp_int : expIntegralEReal μ U ≠ ⊤) :
    ∀ᵐ ω ∂μ, (U ω).exp < ⊤ := by
  have h_meas : Measurable fun ω => (U ω).exp := Measurable.ereal_exp hU_meas
  exact ae_lt_top h_meas hU_exp_int

/-- Auxiliary lemma: The entropy bound from the tilted measure identity.
    This is the core technical lemma establishing Ent(Y) - E[uY] ≥ 0
    when U : Ω → EReal satisfies E[e^U] = 1 and U = u on {Y > 0}.

    Mathematical proof: Ent(Y) - E[uY] = Ent_{e^U·P}[Y·e^{-u}] ≥ 0 -/
lemma entropy_nonneg_sub_integral_of_exp_constraint [IsProbabilityMeasure μ]
    {Y : Ω → ℝ}
    (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ)
    {U : Ω → EReal} (hU_meas : Measurable U)
    (hU_exp_int : expIntegralEReal μ U = 1)
    {u : Ω → ℝ} (_hu_meas : Measurable u)
    (hU_eq_u : ∀ᵐ ω ∂μ, 0 < Y ω → U ω = (u ω : EReal))
    (hUY_int : Integrable (fun ω => u ω * Y ω) μ) :
    0 ≤ entropy μ Y - ∫ ω, u ω * Y ω ∂μ := by
  -- The tilted measure ν = e^U · μ is a probability measure
  have hν_prob : IsProbabilityMeasure (expMeasureEReal μ U) :=
    expMeasureEReal_isProbabilityMeasure U hU_meas hU_exp_int

  -- Define g = Y · e^{-u} on {Y > 0}, 0 elsewhere
  let g : Ω → ℝ := fun ω => if 0 < Y ω then Y ω * exp (-u ω) else 0

  -- The density (U ω).exp is a.e. finite
  have hU_exp_ne_top : expIntegralEReal μ U ≠ ⊤ := by simp [hU_exp_int]
  have h_density_ae_fin : ∀ᵐ ω ∂μ, (U ω).exp < ⊤ := exp_density_ae_lt_top hU_meas hU_exp_ne_top
  have h_density_meas : Measurable (fun ω => (U ω).exp) := Measurable.ereal_exp hU_meas

  -- Step 1: g ≥ 0 a.e. under ν
  have hg_nn : 0 ≤ᵐ[expMeasureEReal μ U] g := by
    simp only [expMeasureEReal, EventuallyLE, Pi.zero_apply]
    rw [ae_withDensity_iff h_density_meas]
    filter_upwards with ω _
    simp only [g]
    split_ifs with hY_pos
    · exact mul_nonneg (le_of_lt hY_pos) (le_of_lt (exp_pos _))
    · exact le_refl 0

  -- Step 2: Compute E_ν[g] = E_μ[Y]
  -- We use: ∫ g dν = ∫ g · (U ω).exp.toReal dμ
  have h_int_g : ∫ ω, g ω ∂(expMeasureEReal μ U) = ∫ ω, Y ω ∂μ := by
    simp only [expMeasureEReal]
    rw [integral_withDensity_eq_integral_toReal_smul h_density_meas h_density_ae_fin]
    apply integral_congr_ae
    filter_upwards [hY_nn, hU_eq_u] with ω hY_nn_ω hU_eq_ω
    simp only [g, smul_eq_mul]
    split_ifs with hY_pos
    · -- Y ω > 0: g = Y * e^{-u}, density.toReal = e^u
      have hU_eq : U ω = (u ω : EReal) := hU_eq_ω hY_pos
      have h_exp_eq : (U ω).exp = ENNReal.ofReal (exp (u ω)) := by
        rw [hU_eq, EReal.exp_coe]
      rw [h_exp_eq, ENNReal.toReal_ofReal (le_of_lt (exp_pos _))]
      have h_cancel : exp (-u ω) * exp (u ω) = 1 := by
        rw [← exp_add, neg_add_cancel, exp_zero]
      calc exp (u ω) * (Y ω * exp (-u ω))
          = Y ω * (exp (-u ω) * exp (u ω)) := by ring
        _ = Y ω * 1 := by rw [h_cancel]
        _ = Y ω := by ring
    · -- Y ω ≤ 0: since Y ω ≥ 0, Y ω = 0
      have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
      simp [hY_zero]

  -- Step 3: Compute E_ν[g log g] = E_μ[Y log Y] - E_μ[uY]
  have h_int_glogg : ∫ ω, g ω * log (g ω) ∂(expMeasureEReal μ U) =
      ∫ ω, Y ω * log (Y ω) ∂μ - ∫ ω, u ω * Y ω ∂μ := by
    simp only [expMeasureEReal]
    rw [integral_withDensity_eq_integral_toReal_smul h_density_meas h_density_ae_fin]
    have h_eq : ∀ᵐ ω ∂μ, (U ω).exp.toReal • (g ω * log (g ω)) =
        Y ω * log (Y ω) - u ω * Y ω := by
      filter_upwards [hY_nn, hU_eq_u] with ω hY_nn_ω hU_eq_ω
      simp only [g, smul_eq_mul]
      split_ifs with hY_pos
      · -- Y ω > 0: g = Y * e^{-u}, log g = log Y - u
        have hU_eq : U ω = (u ω : EReal) := hU_eq_ω hY_pos
        have h_exp_eq : (U ω).exp = ENNReal.ofReal (exp (u ω)) := by
          rw [hU_eq, EReal.exp_coe]
        rw [h_exp_eq, ENNReal.toReal_ofReal (le_of_lt (exp_pos _))]
        have hlog_g : log (Y ω * exp (-u ω)) = log (Y ω) + log (exp (-u ω)) :=
          log_mul (ne_of_gt hY_pos) (ne_of_gt (exp_pos _))
        rw [hlog_g, log_exp]
        have h_cancel : exp (-u ω) * exp (u ω) = 1 := by
          rw [← exp_add, neg_add_cancel, exp_zero]
        calc exp (u ω) * (Y ω * exp (-u ω) * (log (Y ω) + -u ω))
            = Y ω * (exp (-u ω) * exp (u ω)) * (log (Y ω) - u ω) := by ring
          _ = Y ω * 1 * (log (Y ω) - u ω) := by rw [h_cancel]
          _ = Y ω * log (Y ω) - u ω * Y ω := by ring
      · -- Y ω ≤ 0: Y ω = 0
        have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    rw [integral_congr_ae h_eq, integral_sub hY_log_int hUY_int]

  -- Step 4: Show entropy of g under ν equals Ent(Y) - E[uY]
  have h_ent_eq : entropy (expMeasureEReal μ U) g = entropy μ Y - ∫ ω, u ω * Y ω ∂μ := by
    unfold entropy
    rw [h_int_g, h_int_glogg]
    ring

  -- Step 5: g is integrable under ν
  have hg_int : Integrable g (expMeasureEReal μ U) := by
    simp only [expMeasureEReal]
    rw [integrable_withDensity_iff_integrable_smul₀' h_density_meas.aemeasurable h_density_ae_fin]
    have h_eq : (fun ω => (U ω).exp.toReal • g ω) =ᵐ[μ] Y := by
      filter_upwards [hY_nn, hU_eq_u] with ω hY_nn_ω hU_eq_ω
      simp only [g, smul_eq_mul]
      split_ifs with hY_pos
      · have hU_eq : U ω = (u ω : EReal) := hU_eq_ω hY_pos
        have h_exp_eq : (U ω).exp = ENNReal.ofReal (exp (u ω)) := by
          rw [hU_eq, EReal.exp_coe]
        rw [h_exp_eq, ENNReal.toReal_ofReal (le_of_lt (exp_pos _))]
        have h_cancel : exp (-u ω) * exp (u ω) = 1 := by
          rw [← exp_add, neg_add_cancel, exp_zero]
        calc exp (u ω) * (Y ω * exp (-u ω))
            = Y ω * (exp (-u ω) * exp (u ω)) := by ring
          _ = Y ω * 1 := by rw [h_cancel]
          _ = Y ω := by ring
      · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    exact Integrable.congr hY_int h_eq.symm

  -- Step 6: g log g is integrable under ν
  have hglogg_int : Integrable (fun ω => g ω * log (g ω)) (expMeasureEReal μ U) := by
    simp only [expMeasureEReal]
    rw [integrable_withDensity_iff_integrable_smul₀' h_density_meas.aemeasurable h_density_ae_fin]
    have h_eq : (fun ω => (U ω).exp.toReal • (g ω * log (g ω))) =ᵐ[μ]
        (fun ω => Y ω * log (Y ω) - u ω * Y ω) := by
      filter_upwards [hY_nn, hU_eq_u] with ω hY_nn_ω hU_eq_ω
      simp only [g, smul_eq_mul]
      split_ifs with hY_pos
      · have hU_eq : U ω = (u ω : EReal) := hU_eq_ω hY_pos
        have h_exp_eq : (U ω).exp = ENNReal.ofReal (exp (u ω)) := by
          rw [hU_eq, EReal.exp_coe]
        rw [h_exp_eq, ENNReal.toReal_ofReal (le_of_lt (exp_pos _))]
        have hlog_g : log (Y ω * exp (-u ω)) = log (Y ω) + log (exp (-u ω)) :=
          log_mul (ne_of_gt hY_pos) (ne_of_gt (exp_pos _))
        rw [hlog_g, log_exp]
        have h_cancel : exp (-u ω) * exp (u ω) = 1 := by
          rw [← exp_add, neg_add_cancel, exp_zero]
        calc exp (u ω) * (Y ω * exp (-u ω) * (log (Y ω) + -u ω))
            = Y ω * (exp (-u ω) * exp (u ω)) * (log (Y ω) - u ω) := by ring
          _ = Y ω * 1 * (log (Y ω) - u ω) := by rw [h_cancel]
          _ = Y ω * log (Y ω) - u ω * Y ω := by ring
      · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    exact Integrable.congr (hY_log_int.sub hUY_int) h_eq.symm

  -- Step 7: Apply entropy_nonneg to get Ent_ν[g] ≥ 0
  have h_nonneg := @entropy_nonneg _ _ (expMeasureEReal μ U) hν_prob g hg_nn hg_int hglogg_int

  -- Conclude: Ent_μ[Y] - E_μ[uY] = Ent_ν[g] ≥ 0
  linarith [h_nonneg, h_ent_eq]

/-- Key lemma: Every element of dualEntropySet is bounded above by entropy.
    This follows from the identity Ent(Y) - E[UY] = Ent_{e^U·P}[Y·e^{-U}] ≥ 0.

    The mathematical proof uses the key identity:
    - Define tilted measure ν = e^U · μ (probability measure since E[e^U] = 1)
    - Define g = Y · e^{-u} on {Y > 0}, g = 0 on {Y = 0}
    - Then E_ν[g] = E_μ[Y] and E_ν[g log g] = E_μ[Y log Y] - E_μ[uY]
    - Hence Ent_ν[g] = Ent_μ[Y] - E_μ[uY]
    - By entropy_nonneg, Ent_ν[g] ≥ 0, giving E_μ[uY] ≤ Ent_μ[Y]
-/
lemma dualEntropySet_le_entropy [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (_hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y) (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ)
    (x : ℝ) (hx : x ∈ dualEntropySet μ Y) :
    x ≤ entropy μ Y := by
  obtain ⟨_U, _hU_meas, _hU_exp_int, u, _hu_meas, _hU_eq_u, _hUY_int, hx_eq⟩ := hx
  rw [hx_eq]

  -- The bound follows from the entropy duality identity.
  -- The key steps are:
  -- 1. E[e^U] = 1 where U = u on {Y > 0}
  -- 2. Ent(Y) - E[uY] = Ent_ν[g] ≥ 0 (entropy under tilted measure)

  have h_key : entropy μ Y - ∫ ω, u ω * Y ω ∂μ ≥ 0 := by
    by_cases hY_zero : ∫ ω, Y ω ∂μ = 0
    · -- If E[Y] = 0, then Y = 0 a.e., so both entropy and ∫ uY are 0
      have hY_ae_zero : Y =ᵐ[μ] 0 := (integral_eq_zero_iff_of_nonneg_ae hY_nn hY_int).mp hY_zero
      have h_ent_zero : entropy μ Y = 0 := entropy_eq_zero_of_mean_zero Y hY_nn hY_int hY_zero
      have h_uY_zero : ∫ ω, u ω * Y ω ∂μ = 0 := by
        apply integral_eq_zero_of_ae
        filter_upwards [hY_ae_zero] with ω hω
        simp [hω]
      simp [h_ent_zero, h_uY_zero]
    · -- If E[Y] > 0, use the variational bound
      exact entropy_nonneg_sub_integral_of_exp_constraint hY_nn hY_int hY_log_int
        _hU_meas _hU_exp_int _hu_meas _hU_eq_u _hUY_int

  linarith

/-- The duality formula for entropy -/
theorem entropy_duality [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * log (Y ω)) μ) :
    entropy μ Y = sSup (dualEntropySet μ Y) := by
  -- Case split on whether E[Y] = 0 or E[Y] > 0
  by_cases hY_mean : ∫ ω, Y ω ∂μ = 0
  · -- Case E[Y] = 0: both sides equal 0
    have h_ent_zero := entropy_eq_zero_of_mean_zero Y hY_nn hY_int hY_mean
    have h_zero_mem := zero_in_dualEntropySet_of_mean_zero (μ := μ) Y
    rw [h_ent_zero]
    apply le_antisymm
    · -- 0 ≤ sSup: 0 is in the set
      apply le_csSup _ h_zero_mem
      use 0
      intro x hx
      have := dualEntropySet_le_entropy Y hY_meas hY_nn hY_int hY_log_int x hx
      rw [h_ent_zero] at this
      exact this
    · -- sSup ≤ 0: all elements ≤ 0 (which is entropy)
      apply csSup_le ⟨0, h_zero_mem⟩
      intro x hx
      have := dualEntropySet_le_entropy Y hY_meas hY_nn hY_int hY_log_int x hx
      rw [h_ent_zero] at this
      exact this
  · -- Case E[Y] > 0
    have hY_mean_pos : 0 < ∫ ω, Y ω ∂μ := by
      apply (integral_nonneg_of_ae hY_nn).lt_of_ne'
      exact hY_mean
    apply le_antisymm
    · -- entropy ≤ sSup: entropy is in the set, and set is bounded above
      have h_mem := optimalU_in_dualEntropySet Y hY_meas hY_nn hY_int hY_mean_pos hY_log_int
      apply le_csSup _ h_mem
      -- Show the set is bounded above by entropy
      use entropy μ Y
      intro x hx
      exact dualEntropySet_le_entropy Y hY_meas hY_nn hY_int hY_log_int x hx
    · -- sSup ≤ entropy: all elements ≤ entropy
      apply csSup_le
      · -- Set is nonempty (entropy is in it)
        exact ⟨entropy μ Y, optimalU_in_dualEntropySet Y hY_meas hY_nn hY_int hY_mean_pos hY_log_int⟩
      · -- All elements ≤ entropy
        intro x hx
        exact dualEntropySet_le_entropy Y hY_meas hY_nn hY_int hY_log_int x hx

end LogSobolev

end
