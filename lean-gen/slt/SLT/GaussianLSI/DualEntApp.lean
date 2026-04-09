/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianLSI.DualityEntropy
import Mathlib.Analysis.SpecialFunctions.Log.ENNRealLog

/-!
# Entropy Duality: T-Parameterization

This file proves the entropy duality formula in T-parameterization:

    Ent[Y; μ] = sup { E[Y(log T - log E[T])] | T ≥ 0, integrable, E[T] > 0 }

where `Ent[Y; μ] = E[Y log Y] - E[Y] · log(E[Y])` is the entropy of a **nonnegative**
random variable Y with E[Y log Y] < ∞.

## Main Definitions

* `logExtendedReal` : ℝ → EReal with log 0 = ⊥ (via ENNReal.log)
* `integralYLogT μ Y T` : E[Y(log T - log E[T])] as an EReal value
* `dualEntropySetT μ Y` : The set { E[Y(log T - log E[T])] | T ≥ 0, integrable, E[T] > 0 }

## Main Results

* `entropy_duality_T` : **Main theorem** Ent[Y; μ] = sSup (dualEntropySetT μ Y)
* `entropy_ge_integral_log` : integralYLogT μ Y T ≤ Ent[Y; μ] for any valid T
* `entropy_ge_integral_log_real` : Real-valued Gibbs inequality (requires T > 0 on {Y > 0})
* `T_value_in_dualEntropySet` : Correspondence with U-parameterized dualEntropySet

## Key Design Decisions

**No restriction on T beyond T ≥ 0, integrable, E[T] > 0:**
When T = 0 on a set where Y > 0, the value E[Y(log T - log E[T])] = -∞ in EReal
(since log 0 = -∞). The duality set is `Set EReal`, and the supremum correctly
ignores these ⊥ values.

**Technical note:** Mathlib uses `Real.log 0 = 0` as a junk value. For the correct
mathematical convention log 0 = -∞, we use `ENNReal.log` which satisfies `log 0 = ⊥`.

**Gibbs inequality caveat:** The real-valued bound `entropy_ge_integral_log_real`
requires `T > 0` a.e. on `{Y > 0}`. Without this, the inequality can FAIL due to
`Real.log 0 = 0`. (Counterexample: Y ≡ 1, T(0) = 0, T(1) = 2 on uniform {0,1}.)
-/

open MeasureTheory ProbabilityTheory Real Set Filter Classical
open scoped ENNReal NNReal EReal BigOperators

noncomputable section

namespace LogSobolev

variable {Ω : Type*} [MeasurableSpace Ω] {μ : Measure Ω}

/-! ## Extended Logarithm Infrastructure

We define an extended logarithm `logExtendedReal : ℝ → EReal` that correctly
handles log 0 = ⊥ (= -∞), using `ENNReal.log` under the hood.
-/

section ExtendedLog

/-- Extended logarithm: log x = ⊥ when x ≤ 0, (Real.log x : EReal) otherwise.
    This uses ENNReal.log which correctly satisfies log 0 = ⊥. -/
def logExtendedReal (x : ℝ) : EReal :=
  ENNReal.log (ENNReal.ofReal x)

@[simp]
lemma logExtendedReal_zero : logExtendedReal 0 = ⊥ := by
  simp only [logExtendedReal, ENNReal.ofReal_zero, ENNReal.log_zero]

lemma logExtendedReal_of_nonpos {x : ℝ} (hx : x ≤ 0) : logExtendedReal x = ⊥ := by
  simp only [logExtendedReal, ENNReal.ofReal_eq_zero.mpr hx, ENNReal.log_zero]

lemma logExtendedReal_of_pos {x : ℝ} (hx : 0 < x) : logExtendedReal x = (Real.log x : EReal) := by
  simp only [logExtendedReal]
  rw [ENNReal.log_ofReal_of_pos hx]

lemma logExtendedReal_measurable : Measurable logExtendedReal := by
  unfold logExtendedReal
  exact ENNReal.measurable_log.comp ENNReal.measurable_ofReal

end ExtendedLog

/-! ## EReal-Valued Integral for Y(log T - log E[T]) -/

section IntegralYLogT

/-- The integral E[Y(log T - log E[T])] as an EReal value.

    When T > 0 a.e. on {Y > 0}, this equals the usual Bochner integral cast to EReal.
    When T = 0 on a set of positive measure where Y > 0, this is ⊥ (= -∞).

    This definition correctly captures the mathematical semantics where log 0 = -∞. -/
def integralYLogT (μ : Measure Ω) (Y T : Ω → ℝ) : EReal :=
  if ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω then
    ((∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ) : ℝ)
  else ⊥

/-- When T > 0 a.e. on {Y > 0}, the EReal integral equals the real integral. -/
lemma integralYLogT_of_pos_on_Y (Y T : Ω → ℝ)
    (hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω) :
    integralYLogT μ Y T =
      ((∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ) : ℝ) := by
  simp only [integralYLogT, if_pos hT_pos_on_Y]

/-- When T = 0 on a set of positive measure where Y > 0, the integral is ⊥. -/
lemma integralYLogT_eq_bot (Y T : Ω → ℝ)
    (hT_not_pos : ¬∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω) :
    integralYLogT μ Y T = ⊥ := by
  simp only [integralYLogT, if_neg hT_not_pos]

end IntegralYLogT

/-! ## T-Parameterized Duality Set -/

section DualitySetT

/-- The duality set for entropy, parameterized by nonnegative integrable T.

    For each T ≥ 0 integrable with E[T] > 0, we include the value E[Y(log T - log E[T])].
    This value is in EReal (can be ⊥ when T = 0 on {Y > 0}).

    **No additional restrictions** are placed on T, making this exactly consistent
    with the mathematical statement:

      Ent(Y) = sup_{T ≥ 0, integrable, E[T] > 0} E[Y(log T - log E[T])]  -/
def dualEntropySetT (μ : Measure Ω) (Y : Ω → ℝ) : Set EReal :=
  {x | ∃ T : Ω → ℝ,
        Measurable T ∧
        (0 ≤ᵐ[μ] T) ∧
        Integrable T μ ∧
        (0 < ∫ ω, T ω ∂μ) ∧
        x = integralYLogT μ Y T}

/-- The set dualEntropySetT contains ⊥ (when there exists T = 0 on {Y > 0}). -/
lemma bot_mem_dualEntropySetT_of_exists [IsProbabilityMeasure μ]
    (Y : Ω → ℝ)
    (h_exists : ∃ T : Ω → ℝ, Measurable T ∧ (0 ≤ᵐ[μ] T) ∧ Integrable T μ ∧
                (0 < ∫ ω, T ω ∂μ) ∧ ¬∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω) :
    ⊥ ∈ dualEntropySetT μ Y := by
  obtain ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, hT_not_pos⟩ := h_exists
  refine ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, ?_⟩
  rw [integralYLogT_eq_bot Y T hT_not_pos]

end DualitySetT

/-! ## Correspondence Between T and U Parameterizations -/

section Correspondence

/-- For T with proper positivity, the value is in dualEntropySet. -/
lemma T_value_in_dualEntropySet [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_nn : 0 ≤ᵐ[μ] Y)
    (T : Ω → ℝ) (hT_meas : Measurable T) (hT_nn : 0 ≤ᵐ[μ] T)
    (hT_int : Integrable T μ) (hT_mean_pos : 0 < ∫ ω, T ω ∂μ)
    (hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω)
    (hYlogT_int : Integrable (fun ω => Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ))) μ) :
    ∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ ∈ dualEntropySet μ Y := by
  -- Define U = log T - log E[T] on {T > 0}, ⊥ on {T = 0}
  let mean := ∫ ω, T ω ∂μ
  let U : Ω → EReal := fun ω => if 0 < T ω then ((Real.log (T ω) - Real.log mean) : ℝ) else ⊥
  -- Define the real-valued part
  let u : Ω → ℝ := fun ω => if 0 < T ω then Real.log (T ω) - Real.log mean else 0
  refine ⟨U, ?_, ?_, u, ?_, ?_, ?_, ?_⟩
  · -- U is measurable
    apply Measurable.ite
    · exact measurableSet_lt measurable_const hT_meas
    · exact (hT_meas.log.sub measurable_const).coe_real_ereal
    · exact measurable_const
  · -- E[e^U] = 1
    -- The key: e^U = T/mean on {T > 0}, 0 on {T = 0}
    unfold expIntegralEReal
    have h_exp : ∀ᵐ ω ∂μ, (U ω).exp = ENNReal.ofReal (T ω / mean) := by
      filter_upwards [hT_nn] with ω hT_nn_ω
      simp only [U]
      split_ifs with hT_pos
      · rw [EReal.exp_coe, Real.exp_sub, Real.exp_log hT_pos, Real.exp_log hT_mean_pos]
      · rw [EReal.exp_bot]
        have hT_zero : T ω = 0 := le_antisymm (le_of_not_gt hT_pos) hT_nn_ω
        simp [hT_zero]
    rw [lintegral_congr_ae h_exp]
    rw [← ENNReal.ofReal_one]
    have h_div : ∫ ω, T ω / mean ∂μ = 1 := by
      have : (∫ ω, T ω / mean ∂μ) = (∫ ω, mean⁻¹ * T ω ∂μ) := by
        apply integral_congr_ae
        filter_upwards with ω
        ring
      rw [this, integral_const_mul]
      simp only [mean]
      rw [mul_comm, mul_inv_cancel₀ (ne_of_gt hT_mean_pos)]
    rw [← h_div]
    rw [← ofReal_integral_eq_lintegral_ofReal]
    · exact hT_int.div_const _
    · filter_upwards [hT_nn] with ω hω
      exact div_nonneg hω (le_of_lt hT_mean_pos)
  · -- u is measurable
    apply Measurable.ite
    · exact measurableSet_lt measurable_const hT_meas
    · exact hT_meas.log.sub measurable_const
    · exact measurable_const
  · -- U = u on {Y > 0}
    filter_upwards [hT_pos_on_Y] with ω hT_pos_ω
    intro hY_pos
    simp only [U, u, if_pos (hT_pos_ω hY_pos)]
  · -- u * Y is integrable
    have h_eq : (fun ω => u ω * Y ω) =ᵐ[μ]
        (fun ω => Y ω * (Real.log (T ω) - Real.log mean)) := by
      filter_upwards [hT_nn, hY_nn, hT_pos_on_Y] with ω hT_nn_ω hY_nn_ω hT_pos_ω
      simp only [u]
      by_cases hY_pos : 0 < Y ω
      · rw [if_pos (hT_pos_ω hY_pos)]
        ring
      · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    exact Integrable.congr hYlogT_int h_eq.symm
  · -- x = ∫ u * Y
    have h_eq : (fun ω => u ω * Y ω) =ᵐ[μ]
        (fun ω => Y ω * (Real.log (T ω) - Real.log mean)) := by
      filter_upwards [hT_nn, hY_nn, hT_pos_on_Y] with ω hT_nn_ω hY_nn_ω hT_pos_ω
      simp only [u]
      by_cases hY_pos : 0 < Y ω
      · rw [if_pos (hT_pos_ω hY_pos)]
        ring
      · have hY_zero : Y ω = 0 := le_antisymm (le_of_not_gt hY_pos) hY_nn_ω
        simp [hY_zero]
    rw [integral_congr_ae h_eq]

/-- The optimal T = Y gives value Ent(Y). -/
lemma entropy_mem_dualEntropySetT [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y) (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ) (hY_mean_pos : 0 < ∫ ω, Y ω ∂μ)
    (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ) :
    (entropy μ Y : EReal) ∈ dualEntropySetT μ Y := by
  -- Take T = Y
  refine ⟨Y, hY_meas, hY_nn, hY_int, hY_mean_pos, ?_⟩
  -- Y > 0 on {Y > 0} trivially
  have hY_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < Y ω := Eventually.of_forall (fun _ h => h)
  rw [integralYLogT_of_pos_on_Y Y Y hY_pos_on_Y]
  -- The integral equals entropy
  unfold entropy
  -- Show ∫ Y(log Y - log E[Y]) = ∫ Y log Y - E[Y] log E[Y]
  have h_eq : ∀ᵐ ω ∂μ, Y ω * (Real.log (Y ω) - Real.log (∫ ω', Y ω' ∂μ)) =
      Y ω * Real.log (Y ω) - Real.log (∫ ω', Y ω' ∂μ) * Y ω := by
    filter_upwards with ω
    ring
  have h_const_int : Integrable (fun ω => Real.log (∫ ω', Y ω' ∂μ) * Y ω) μ :=
    hY_int.const_mul _
  have h_integral : ∫ ω, Y ω * (Real.log (Y ω) - Real.log (∫ ω', Y ω' ∂μ)) ∂μ =
      ∫ ω, Y ω * Real.log (Y ω) ∂μ - (∫ ω, Y ω ∂μ) * Real.log (∫ ω', Y ω' ∂μ) := by
    rw [integral_congr_ae h_eq]
    rw [integral_sub hY_log_int h_const_int]
    have h_const : ∫ ω, Real.log (∫ ω', Y ω' ∂μ) * Y ω ∂μ = Real.log (∫ ω', Y ω' ∂μ) * ∫ ω, Y ω ∂μ := by
      rw [← integral_const_mul]
    rw [h_const]
    ring
  simp only [EReal.coe_sub, EReal.coe_mul]
  rw [h_integral]
  simp only [EReal.coe_sub, EReal.coe_mul]

end Correspondence

/-! ## EReal Supremum Lemmas -/

section EReal_sSup

/-- If S ⊆ EReal is nonempty and bounded above by a real value,
    then sSup S is at most that bound. -/
lemma sSup_le_of_forall_le {S : Set EReal} {b : ℝ} (hb : ∀ x ∈ S, x ≤ (b : EReal)) :
    sSup S ≤ (b : EReal) := by
  apply csSup_le'
  intro x hx
  exact hb x hx

/-- The real elements of dualEntropySetT are bounded above by entropy. -/
lemma dualEntropySetT_le_entropy [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y) (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ) (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ)
    (x : EReal) (hx : x ∈ dualEntropySetT μ Y) :
    x ≤ (entropy μ Y : EReal) := by
  obtain ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, hx_eq⟩ := hx
  by_cases hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω
  · -- T > 0 on {Y > 0}, so the value is a real integral
    rw [integralYLogT_of_pos_on_Y Y T hT_pos_on_Y] at hx_eq
    rw [hx_eq]
    -- Case split on integrability of the integrand
    let f := fun ω => Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ))
    by_cases hf_int : Integrable f μ
    · -- If integrable, use correspondence with dualEntropySet
      have h_in_set := T_value_in_dualEntropySet Y hY_nn T hT_meas hT_nn
        hT_int hT_mean_pos hT_pos_on_Y hf_int
      have h_le := dualEntropySet_le_entropy Y hY_meas hY_nn hY_int hY_log_int
        (∫ ω, f ω ∂μ) h_in_set
      exact EReal.coe_le_coe_iff.mpr h_le
    · -- If not integrable, Mathlib integral returns 0
      have h_int_zero : ∫ ω, f ω ∂μ = 0 := integral_undef hf_int
      rw [h_int_zero]
      simp only [EReal.coe_zero]
      -- 0 ≤ entropy by entropy_nonneg
      exact EReal.coe_nonneg.mpr (entropy_nonneg hY_nn hY_int hY_log_int)
  · -- T = 0 on some {Y > 0}, so value is ⊥
    rw [integralYLogT_eq_bot Y T hT_pos_on_Y] at hx_eq
    rw [hx_eq]
    exact bot_le

/-- dualEntropySetT is nonempty when E[Y] > 0 (contains entropy). -/
lemma dualEntropySetT_nonempty [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y) (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ) (hY_mean_pos : 0 < ∫ ω, Y ω ∂μ)
    (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ) :
    (dualEntropySetT μ Y).Nonempty :=
  ⟨(entropy μ Y : EReal), entropy_mem_dualEntropySetT Y hY_meas hY_nn hY_int hY_mean_pos hY_log_int⟩

/-- dualEntropySetT is bounded above by entropy. -/
lemma dualEntropySetT_bddAbove [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y) (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ) (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ) :
    BddAbove (dualEntropySetT μ Y) :=
  ⟨(entropy μ Y : EReal), fun _ hx =>
    dualEntropySetT_le_entropy Y hY_meas hY_nn hY_int hY_log_int _ hx⟩

end EReal_sSup

/-! ## Main Theorem -/

section MainTheorem

/-- **Entropy Duality Formula (T-Parameterization)** -/
theorem entropy_duality_T [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ) :
    (entropy μ Y : EReal) = sSup (dualEntropySetT μ Y) := by
  by_cases hY_mean : ∫ ω, Y ω ∂μ = 0
  · -- Case E[Y] = 0: Y = 0 a.e., entropy = 0
    have hY_zero : Y =ᵐ[μ] 0 := (integral_eq_zero_iff_of_nonneg_ae hY_nn hY_int).mp hY_mean
    have h_ent_zero : entropy μ Y = 0 := entropy_eq_zero_of_mean_zero Y hY_nn hY_int hY_mean
    rw [h_ent_zero]
    simp only [EReal.coe_zero]
    apply le_antisymm
    · -- 0 ≤ sSup: show 0 is in the set
      apply le_csSup
      · -- Bounded above by 0
        use 0
        intro x hx
        obtain ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, hx_eq⟩ := hx
        by_cases hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω
        · rw [integralYLogT_of_pos_on_Y Y T hT_pos_on_Y] at hx_eq
          rw [hx_eq]
          -- When Y = 0 a.e., the integral is 0
          have h_int_zero : ∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ = 0 := by
            have h_ae : (fun ω => Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ))) =ᵐ[μ]
                        (fun _ => (0 : ℝ)) := by
              filter_upwards [hY_zero] with ω hω
              simp [hω]
            rw [integral_congr_ae h_ae, integral_const, smul_zero]
          simp [h_int_zero]
        · rw [integralYLogT_eq_bot Y T hT_pos_on_Y] at hx_eq
          rw [hx_eq]
          exact bot_le
      · -- 0 is in the set (take T = 1)
        refine ⟨fun _ => 1, measurable_const, Eventually.of_forall (fun _ => zero_le_one),
                integrable_const 1, ?_, ?_⟩
        · simp only [integral_const, probReal_univ, smul_eq_mul, mul_one, zero_lt_one]
        · have h1_int : ∫ ω, (1 : ℝ) ∂μ = 1 := by simp [integral_const, probReal_univ]
          have h1_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < (1 : ℝ) := Eventually.of_forall (fun _ _ => one_pos)
          rw [integralYLogT_of_pos_on_Y Y (fun _ => 1) h1_pos_on_Y]
          simp only [Real.log_one, h1_int, sub_self, mul_zero, integral_const, smul_zero]
          rfl
    · -- sSup ≤ 0: all elements ≤ 0
      apply csSup_le
      · -- Nonempty
        refine ⟨0, ?_⟩
        refine ⟨fun _ => 1, measurable_const, Eventually.of_forall (fun _ => zero_le_one),
                integrable_const 1, ?_, ?_⟩
        · simp only [integral_const, probReal_univ, smul_eq_mul, mul_one, zero_lt_one]
        · have h1_int : ∫ ω, (1 : ℝ) ∂μ = 1 := by simp [integral_const, probReal_univ]
          have h1_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < (1 : ℝ) := Eventually.of_forall (fun _ _ => one_pos)
          rw [integralYLogT_of_pos_on_Y Y (fun _ => 1) h1_pos_on_Y]
          simp only [Real.log_one, h1_int, sub_self, mul_zero, integral_const, smul_zero]
          rfl
      · -- All elements ≤ 0
        intro x hx
        obtain ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, hx_eq⟩ := hx
        by_cases hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω
        · rw [integralYLogT_of_pos_on_Y Y T hT_pos_on_Y] at hx_eq
          rw [hx_eq]
          have h_int_zero : ∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ = 0 := by
            have h_ae : (fun ω => Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ))) =ᵐ[μ]
                        (fun _ => (0 : ℝ)) := by
              filter_upwards [hY_zero] with ω hω
              simp [hω]
            rw [integral_congr_ae h_ae, integral_const, smul_zero]
          simp [h_int_zero]
        · rw [integralYLogT_eq_bot Y T hT_pos_on_Y] at hx_eq
          rw [hx_eq]
          exact bot_le
  · -- Case E[Y] > 0
    have hY_mean_pos : 0 < ∫ ω, Y ω ∂μ := by
      apply (integral_nonneg_of_ae hY_nn).lt_of_ne'
      exact hY_mean
    apply le_antisymm
    · -- entropy ≤ sSup: entropy is in the set
      have h_mem := entropy_mem_dualEntropySetT Y hY_meas hY_nn hY_int hY_mean_pos hY_log_int
      exact le_csSup (dualEntropySetT_bddAbove Y hY_meas hY_nn hY_int hY_log_int) h_mem
    · -- sSup ≤ entropy: all elements ≤ entropy
      apply csSup_le (dualEntropySetT_nonempty Y hY_meas hY_nn hY_int hY_mean_pos hY_log_int)
      intro x hx
      exact dualEntropySetT_le_entropy Y hY_meas hY_nn hY_int hY_log_int x hx

/-- **Entropy Upper Bound (Corollary of T-Parameterized Duality)**

    For **any** nonnegative integrable random variable T with E[T] > 0:

      Ent(Y) ≥ E[Y(log T - log E[T])]

    where the right-hand side is in EReal (extended reals).

    This is an immediate consequence of `entropy_duality_T`: since entropy equals
    the supremum over all such T, it must be at least any particular value. -/
theorem entropy_ge_integral_log [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ)
    (T : Ω → ℝ) (hT_meas : Measurable T)
    (hT_nn : 0 ≤ᵐ[μ] T)
    (hT_int : Integrable T μ)
    (hT_mean_pos : 0 < ∫ ω, T ω ∂μ) :
    integralYLogT μ Y T ≤ (entropy μ Y : EReal) :=
  dualEntropySetT_le_entropy Y hY_meas hY_nn hY_int hY_log_int
    (integralYLogT μ Y T) ⟨T, hT_meas, hT_nn, hT_int, hT_mean_pos, rfl⟩

/-- **Real-Valued Entropy Upper Bound (Gibbs Inequality)**

    For nonnegative integrable T with E[T] > 0 and T > 0 a.e. on {Y > 0}:

      ∫ Y(log T - log E[T]) dμ ≤ Ent(Y)

    as a real-valued inequality.

    **Important:** The condition `hT_pos_on_Y` (T > 0 where Y > 0) is essential.
    Without it, the inequality can FAIL due to Mathlib's convention `Real.log 0 = 0`.

    Counterexample: Y ≡ 1, T(0) = 0, T(1) = 2 on uniform {0,1}.
    Then Ent(Y) = 0 but ∫ Y log T = (0 + log 2)/2 ≈ 0.347 > 0.

    **For conditional expectations:** If T = E[f | F] for some σ-algebra F,
    then T > 0 on {f > 0} automatically (conditional expectation preserves
    positivity on fibers). So this version applies to entropy subadditivity proofs. -/
theorem entropy_ge_integral_log_real [IsProbabilityMeasure μ]
    (Y : Ω → ℝ) (hY_meas : Measurable Y)
    (hY_nn : 0 ≤ᵐ[μ] Y)
    (hY_int : Integrable Y μ)
    (hY_log_int : Integrable (fun ω => Y ω * Real.log (Y ω)) μ)
    (T : Ω → ℝ) (hT_meas : Measurable T)
    (hT_nn : 0 ≤ᵐ[μ] T)
    (hT_int : Integrable T μ)
    (hT_mean_pos : 0 < ∫ ω, T ω ∂μ)
    (hT_pos_on_Y : ∀ᵐ ω ∂μ, 0 < Y ω → 0 < T ω) :
    (∫ ω, Y ω * (Real.log (T ω) - Real.log (∫ ω', T ω' ∂μ)) ∂μ) ≤ entropy μ Y := by
  -- When T > 0 on {Y > 0}, integralYLogT equals the Bochner integral
  have h_eq := integralYLogT_of_pos_on_Y Y T hT_pos_on_Y
  have h_le := entropy_ge_integral_log Y hY_meas hY_nn hY_int hY_log_int T hT_meas hT_nn hT_int hT_mean_pos
  rw [h_eq] at h_le
  exact EReal.coe_le_coe_iff.mp h_le

end MainTheorem

end LogSobolev

end
