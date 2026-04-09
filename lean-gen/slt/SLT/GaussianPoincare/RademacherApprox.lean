/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.MeasureTheory.Measure.ProbabilityMeasure
import Mathlib.Probability.Distributions.Gaussian.Real
import Mathlib.Probability.IdentDistrib
import Mathlib.Probability.Independence.Basic
import Mathlib.Probability.Independence.Integration
import Mathlib.Probability.Notation
import Mathlib.Probability.Moments.Variance

/-!
# Approximation of Standard Gaussian via Rademacher Sums

This file formalizes the approximation of the standard Gaussian distribution using
normalized sums of Rademacher random variables via the Central Limit Theorem.

## Main definitions

* `rademacherMeasure`: The probability measure on `ℝ` that assigns probability 1/2 to both -1 and 1.
* `rademacherSum`: The normalized Rademacher sum `S_n = n^{-1/2} * ∑_{j=1}^n ε_j`.

## Main results

* `rademacher_expectation_zero`: The expectation of a Rademacher random variable is 0.
* `rademacher_variance_one`: The variance of a Rademacher random variable is 1.
* `rademacherSum_expectation_zero`: `E[S_n] = 0`.
* `rademacherSum_variance_one`: `Var(S_n) = 1`.

-/

noncomputable section

open MeasureTheory ProbabilityTheory Real Filter
open scoped ENNReal Topology

namespace RademacherApprox

/-! ### Rademacher Measure -/

/-- The Rademacher measure: probability measure on ℝ assigning probability 1/2 to both -1 and 1. -/
def rademacherMeasure : Measure ℝ :=
  (1/2 : ℝ≥0∞) • Measure.dirac (-1 : ℝ) + (1/2 : ℝ≥0∞) • Measure.dirac (1 : ℝ)

instance isProbabilityMeasure_rademacherMeasure : IsProbabilityMeasure rademacherMeasure := by
  constructor
  simp only [rademacherMeasure, Measure.coe_add, Measure.coe_smul, Pi.add_apply, Pi.smul_apply,
    smul_eq_mul]
  simp only [Measure.dirac_apply_of_mem (Set.mem_univ _)]
  simp only [one_div, mul_one]
  exact ENNReal.inv_two_add_inv_two

/-- The Rademacher measure as a probability measure. -/
def rademacherProbMeasure : ProbabilityMeasure ℝ :=
  ⟨rademacherMeasure, inferInstance⟩

/-! ### Basic Properties of Rademacher Random Variables -/

/-- Integrability of identity on the Rademacher measure. -/
lemma integrable_id_rademacherMeasure : Integrable id rademacherMeasure := by
  simp only [rademacherMeasure]
  apply Integrable.add_measure
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp

/-- Integrability of square on the Rademacher measure. -/
lemma integrable_sq_rademacherMeasure : Integrable (fun x => x^2) rademacherMeasure := by
  simp only [rademacherMeasure]
  apply Integrable.add_measure
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp

/-- The expectation of a Rademacher random variable is 0. -/
theorem rademacher_expectation_zero : ∫ x, x ∂rademacherMeasure = 0 := by
  simp only [rademacherMeasure]
  rw [integral_add_measure, integral_smul_measure, integral_smul_measure]
  · rw [integral_dirac' (fun x => x) (-1) stronglyMeasurable_id,
        integral_dirac' (fun x => x) (1) stronglyMeasurable_id]
    norm_num
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp

/-- The second moment of a Rademacher random variable is 1. -/
theorem rademacher_second_moment : ∫ x, x^2 ∂rademacherMeasure = 1 := by
  simp only [rademacherMeasure]
  rw [integral_add_measure, integral_smul_measure, integral_smul_measure]
  · rw [integral_dirac' (fun x => x^2) (-1) (stronglyMeasurable_id.pow _),
        integral_dirac' (fun x => x^2) (1) (stronglyMeasurable_id.pow _)]
    norm_num
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp
  · apply Integrable.smul_measure _ (by simp)
    apply integrable_dirac
    simp

/-- The variance of a Rademacher random variable is 1. -/
theorem rademacher_variance_one : ∫ x, x^2 ∂rademacherMeasure - (∫ x, x ∂rademacherMeasure)^2 = 1 := by
  rw [rademacher_expectation_zero, rademacher_second_moment]
  ring

/-! ### Rademacher Random Variables on a Probability Space -/

variable {Ω : Type*} [MeasurableSpace Ω]

/-- A random variable `ε : Ω → ℝ` is Rademacher if its law is the Rademacher measure. -/
def IsRademacher (P : Measure Ω) (ε : Ω → ℝ) : Prop :=
  P.map ε = rademacherMeasure

/-- The expectation of a Rademacher random variable is 0. -/
theorem IsRademacher.expectation_zero {P : Measure Ω} [IsProbabilityMeasure P]
    {ε : Ω → ℝ} (hε : Measurable ε) (h : IsRademacher P ε) : ∫ x, ε x ∂P = 0 := by
  have : ∫ x, x ∂(P.map ε) = ∫ x, ε x ∂P := integral_map hε.aemeasurable aestronglyMeasurable_id
  rw [← this, h]
  exact rademacher_expectation_zero

/-- The second moment of a Rademacher random variable is 1. -/
theorem IsRademacher.second_moment {P : Measure Ω} [IsProbabilityMeasure P]
    {ε : Ω → ℝ} (hε : Measurable ε) (h : IsRademacher P ε) : ∫ x, (ε x) ^ 2 ∂P = 1 := by
  have : ∫ x, x ^ 2 ∂(P.map ε) = ∫ x, (ε x) ^ 2 ∂P :=
    integral_map hε.aemeasurable (aestronglyMeasurable_id.pow _)
  rw [← this, h]
  exact rademacher_second_moment

/-! ### Independent Rademacher Sequence -/

variable (Ω : Type*) [MeasurableSpace Ω]

/-- A sequence of independent Rademacher random variables. -/
structure IndepRademacherSeq (P : ProbabilityMeasure Ω) where
  /-- The sequence of Rademacher random variables -/
  ε : ℕ → Ω → ℝ
  /-- Each ε_i is measurable -/
  measurable : ∀ i, Measurable (ε i)
  /-- Each ε_i is Rademacher -/
  isRademacher : ∀ i, IsRademacher (↑P) (ε i)
  /-- The ε_i are independent -/
  indep : iIndepFun ε (↑P)
  /-- The ε_i are identically distributed -/
  ident : ∀ i, IdentDistrib (ε i) (ε 0) (↑P) (↑P)

/-! ### Rademacher Sum -/

variable {Ω}

/-- The normalized Rademacher sum: `S_n = n^{-1/2} * ∑_{j=0}^{n-1} ε_j`. -/
def rademacherSum (ε : ℕ → Ω → ℝ) (n : ℕ) (ω : Ω) : ℝ :=
  (√n)⁻¹ * ∑ i : Fin n, ε i ω

/-! ### Main Properties of Rademacher Sum -/

variable {P : ProbabilityMeasure Ω}

/-- Rademacher random variables are bounded (taking values in {-1, 1}), hence integrable. -/
lemma IndepRademacherSeq.integrable (seq : IndepRademacherSeq Ω P) (i : ℕ) :
    Integrable (seq.ε i) (↑P) := by
  -- Use the fact that P.map ε_i = rademacherMeasure and id is integrable on rademacherMeasure
  have h := seq.isRademacher i
  have him := integrable_map_measure (μ := ↑P) aestronglyMeasurable_id (seq.measurable i).aemeasurable
  rw [h] at him
  exact him.mp integrable_id_rademacherMeasure

/-- Rademacher random variables are bounded by 1 almost everywhere. -/
lemma IndepRademacherSeq.norm_le_one (seq : IndepRademacherSeq Ω P) (i : ℕ) :
    ∀ᵐ ω ∂(↑P : Measure Ω), ‖seq.ε i ω‖ ≤ 1 := by
  -- The law of ε_i is the Rademacher measure, which is supported on {-1, 1}
  have h := seq.isRademacher i
  -- Show that ‖x‖ ≤ 1 for all x in the support of rademacherMeasure
  have hae : ∀ᵐ x ∂rademacherMeasure, ‖x‖ ≤ 1 := by
    simp only [rademacherMeasure]
    rw [ae_add_measure_iff]
    have hmeas : MeasurableSet {x : ℝ | ‖x‖ ≤ 1} := by measurability
    constructor <;> {
      rw [Measure.ae_smul_measure_iff (by norm_num : (1/2 : ℝ≥0∞) ≠ 0)]
      rw [ae_dirac_iff hmeas]
      simp
    }
  rw [← h] at hae
  exact ae_of_ae_map (seq.measurable i).aemeasurable hae

/-- The product of two Rademacher random variables is integrable. -/
lemma IndepRademacherSeq.integrable_mul (seq : IndepRademacherSeq Ω P) (i j : ℕ) :
    Integrable (fun ω => seq.ε i ω * seq.ε j ω) (↑P) :=
  Integrable.bdd_mul (seq.integrable j) (seq.integrable i).aestronglyMeasurable (seq.norm_le_one i)

/-- **Expectation of Rademacher Sum is Zero**
`E[S_n] = n^{-1/2} * ∑_{j=1}^{n} E[ε_j] = 0` -/
theorem rademacherSum_expectation_zero (seq : IndepRademacherSeq Ω P) (n : ℕ) :
    ∫ ω, rademacherSum seq.ε n ω ∂(↑P) = 0 := by
  unfold rademacherSum
  rw [MeasureTheory.integral_const_mul]
  -- Each ε_i has expectation 0, so the sum has expectation 0
  have h_sum_zero : ∫ ω, (∑ i : Fin n, seq.ε i ω) ∂(↑P) = 0 := by
    rw [integral_finset_sum Finset.univ]
    · apply Finset.sum_eq_zero
      intro i _
      exact (seq.isRademacher i).expectation_zero (seq.measurable i)
    · intro i _
      exact seq.integrable i
  rw [h_sum_zero, mul_zero]

/-- **Variance of Rademacher Sum is One**
`Var(S_n) = n^{-1} * ∑_{j=1}^{n} Var(ε_j) = n^{-1} * n = 1` -/
theorem rademacherSum_variance_one (seq : IndepRademacherSeq Ω P) (n : ℕ) (hn : n ≠ 0) :
    ∫ ω, (rademacherSum seq.ε n ω) ^ 2 ∂(↑P) - (∫ ω, rademacherSum seq.ε n ω ∂(↑P)) ^ 2 = 1 := by
  rw [rademacherSum_expectation_zero seq n]
  simp only [ne_eq, OfNat.ofNat_ne_zero, not_false_eq_true, zero_pow, sub_zero]
  -- Need to show E[S_n^2] = 1
  unfold rademacherSum
  simp only [mul_pow, inv_pow]
  -- (√n ^ 2)⁻¹ = n⁻¹ when n ≥ 0
  have hsqrt : (√(n : ℝ)) ^ 2 = n := Real.sq_sqrt (Nat.cast_nonneg n)
  rw [hsqrt]
  rw [integral_const_mul]
  -- Goal: (n : ℝ)⁻¹ * E[(∑ i, ε_i)^2] = 1
  have hn' : (n : ℝ) ≠ 0 := Nat.cast_ne_zero.mpr hn
  rw [inv_mul_eq_one₀ hn']
  -- Goal: E[(∑ i, ε_i)^2] = n
  -- Use sq to express power 2, then expand as double sum
  simp only [sq, Finset.sum_mul_sum]
  rw [integral_finset_sum Finset.univ]
  · -- Split into diagonal (i=j) and off-diagonal (i≠j) terms
    -- Off-diagonal terms vanish by independence
    have h_diag : ∀ i : Fin n, ∫ ω, (seq.ε i ω) * (seq.ε i ω) ∂(↑P) = 1 := by
      intro i
      simp_rw [← sq]
      exact (seq.isRademacher i).second_moment (seq.measurable i)
    have h_off : ∀ i j : Fin n, i ≠ j → ∫ ω, (seq.ε i ω) * (seq.ε j ω) ∂(↑P) = 0 := by
      intro i j hij
      have hij' : (i : ℕ) ≠ (j : ℕ) := Fin.val_ne_of_ne hij
      have hindep : IndepFun (seq.ε i) (seq.ε j) (↑P) := seq.indep.indepFun hij'
      have := hindep.integral_fun_mul_eq_mul_integral
        (seq.integrable i).aestronglyMeasurable (seq.integrable j).aestronglyMeasurable
      rw [this]
      rw [(seq.isRademacher i).expectation_zero (seq.measurable i),
          (seq.isRademacher j).expectation_zero (seq.measurable j)]
      ring
    -- Sum over all pairs: ∑ᵢ ∑ⱼ ε_i * ε_j = ∑ᵢ ε_i² + ∑ᵢ ∑ⱼ≠ᵢ ε_i * ε_j
    -- Compute ∑ᵢ ∫ (∑ⱼ ε_i * ε_j)
    have h_sum : ∑ i : Fin n, ∫ ω, ∑ j : Fin n, seq.ε i ω * seq.ε j ω ∂(↑P) = n := by
      calc ∑ i : Fin n, ∫ ω, ∑ j : Fin n, seq.ε i ω * seq.ε j ω ∂(↑P)
          = ∑ i : Fin n, ∑ j : Fin n, ∫ ω, seq.ε i ω * seq.ε j ω ∂(↑P) := by
              congr 1
              ext i
              rw [integral_finset_sum Finset.univ]
              intro j _
              exact seq.integrable_mul i j
        _ = ∑ i : Fin n, (∫ ω, seq.ε i ω * seq.ε i ω ∂(↑P) +
              ∑ j ∈ Finset.univ.filter (· ≠ i), ∫ ω, seq.ε i ω * seq.ε j ω ∂(↑P)) := by
              congr 1
              ext i
              rw [← Finset.add_sum_erase Finset.univ _ (Finset.mem_univ i)]
              congr 1
              apply Finset.sum_congr
              · ext j; simp [Finset.mem_erase, Finset.mem_filter]
              · intros; rfl
        _ = ∑ i : Fin n, (1 + ∑ j ∈ Finset.univ.filter (· ≠ i), 0) := by
              congr 1
              ext i
              congr 1
              · exact h_diag i
              · apply Finset.sum_congr rfl
                intro j hj
                simp only [Finset.mem_filter, Finset.mem_univ, true_and] at hj
                exact h_off i j (Ne.symm hj)
        _ = ∑ _i : Fin n, 1 := by simp
        _ = n := by simp
    exact h_sum.symm
  · intro i _
    apply integrable_finset_sum Finset.univ
    intro j _
    exact seq.integrable_mul i j

end RademacherApprox

end
