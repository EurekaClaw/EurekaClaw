/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.MeasureTheory.Measure.ProbabilityMeasure
import Mathlib.MeasureTheory.Measure.Prod
import Mathlib.MeasureTheory.Measure.Count
import Mathlib.Probability.ProbabilityMassFunction.Basic
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Analysis.SpecialFunctions.BinaryEntropy
import Mathlib.Analysis.Complex.ExponentialBounds
import Mathlib.Logic.Function.Basic
import SLT.GaussianLSI.Entropy
import SLT.GaussianLSI.TwoPoint
import SLT.GaussianPoincare.Limit

/-!
# Bernoulli Log-Sobolev Inequality

This file proves the Bernoulli log-Sobolev inequality on the hypercube {±1}^n.

## Main definitions

* `flipCoord j ε`: Flip the j-th coordinate of ε, replacing ε_j with -ε_j
* `bernoulliUniform n`: The uniform measure on {±1}^n (balanced Bernoulli product)
* `signValue`: Maps Bool to ±1 ∈ ℝ

## Main results

* `han_inequality`: Han's subadditivity for entropy on the hypercube:
  Ent_μ(h²) ≤ Σⱼ E_μ[Ent^(j)(h²)] where Ent^(j) is the conditional two-point entropy
* `bernoulli_logSobolev`: For any h : {±1}^n → ℝ,
  Ent_μ(h²) ≤ (1/2) · E_μ[Σⱼ (h(ε) - h(flip_j ε))²]
* `bernoulli_logSobolev_app`: Application to compactly supported smooth functions f:
  Ent_{S_n}(f²) ≤ (1/2) · Σᵢ E[(f(S_n) - f(S_n with coord i flipped))²]

## Proof approach (Rothaus-based)

We prove this by induction on n:
- Base case (n = 0): Both sides are 0
- Inductive step: Use the conditional entropy decomposition and the Rothaus lemma
  (two-point inequality) for the last coordinate
-/

open MeasureTheory ProbabilityTheory Real Set Filter Function
open scoped ENNReal NNReal BigOperators Topology

noncomputable section

namespace BernoulliLSI

/-!
## Part 1: Sign values and coordinate flips
-/

/-- Map Bool to ±1 ∈ ℝ: True ↦ +1, False ↦ -1 -/
def signValue (b : Bool) : ℝ := if b then 1 else -1

@[simp] theorem signValue_true : signValue true = 1 := rfl
@[simp] theorem signValue_false : signValue false = -1 := rfl

/-- Sign values are ±1, so their square is 1 -/
@[simp] theorem signValue_sq (b : Bool) : (signValue b)^2 = 1 := by
  cases b <;> simp [signValue]

/-- The sign of the negated value -/
@[simp] theorem signValue_not (b : Bool) : signValue (!b) = -signValue b := by
  cases b <;> simp [signValue]

variable {n : ℕ}

/-- Flip the j-th coordinate: ε^(j) has ε_j replaced by ¬ε_j -/
def flipCoord (j : Fin n) (ε : Fin n → Bool) : Fin n → Bool :=
  update ε j (!ε j)

/-- Flipping the same coordinate twice returns the original -/
theorem flipCoord_involutive (j : Fin n) : flipCoord j ∘ flipCoord j = id := by
  ext ε i
  simp only [comp_apply, id_eq, flipCoord]
  by_cases h : i = j
  · subst h; simp only [update_self, Bool.not_not]
  · rw [update_of_ne h, update_of_ne h]

/-- The j-th coordinate after flip -/
@[simp] theorem flipCoord_same (j : Fin n) (ε : Fin n → Bool) :
    (flipCoord j ε) j = !ε j := by
  simp [flipCoord]

/-- Other coordinates are unchanged after flip -/
theorem flipCoord_noteq (j i : Fin n) (ε : Fin n → Bool) (h : i ≠ j) :
    (flipCoord j ε) i = ε i := by
  simp only [flipCoord, update_of_ne h]

/-!
## Part 2: Bernoulli measure on the hypercube

The uniform measure on {±1}^n is the counting measure normalized by 2^n.
-/

/-- The uniform measure on Fin n → Bool (representing {±1}^n).
    Each point has probability 1/2^n. -/
def bernoulliUniform (n : ℕ) : Measure (Fin n → Bool) :=
  ((Finset.univ : Finset (Fin n → Bool)).card : ℝ≥0∞)⁻¹ • Measure.count

/-- The number of elements in Fin n → Bool is 2^n -/
theorem card_fin_bool (n : ℕ) : Finset.card (Finset.univ : Finset (Fin n → Bool)) = 2^n := by
  simp only [Finset.card_univ, Fintype.card_fun, Fintype.card_fin, Fintype.card_bool]

/-- The Bernoulli uniform measure is a probability measure -/
instance (n : ℕ) : IsProbabilityMeasure (bernoulliUniform n) := by
  constructor
  unfold bernoulliUniform
  simp only [Measure.smul_apply, smul_eq_mul]
  rw [Measure.count_apply_finite Set.univ Set.finite_univ]
  simp only [Set.Finite.toFinset_univ, Finset.card_univ, Fintype.card_fun, Fintype.card_fin,
    Fintype.card_bool, Nat.cast_pow, Nat.cast_ofNat]
  rw [ENNReal.inv_mul_cancel]
  · -- 2^n ≠ 0
    apply pow_ne_zero
    norm_num
  · -- 2^n ≠ ⊤
    exact ENNReal.pow_ne_top (by norm_num : (2 : ℝ≥0∞) ≠ ⊤)

/-- The measure is invariant under coordinate flips -/
theorem bernoulli_flip_invariance (j : Fin n) :
    (bernoulliUniform n).map (flipCoord j) = bernoulliUniform n := by
  -- flipCoord j is a bijection (involutive) and count is invariant under bijections
  unfold bernoulliUniform
  have hinv : (flipCoord j).Involutive := fun ε => by
    simp only [flipCoord]
    ext i
    by_cases h : i = j
    · subst h; simp only [update_self, Bool.not_not]
    · rw [update_of_ne h, update_of_ne h]
  rw [Measure.map_smul]
  congr 1
  -- Show count measure is invariant under bijection
  ext s hs
  have hmeas : Measurable (flipCoord j) := measurable_of_finite _
  rw [Measure.map_apply hmeas hs]
  have hs1 : (flipCoord j ⁻¹' s).Finite := Set.toFinite _
  have hs2 : s.Finite := Set.toFinite _
  rw [Measure.count_apply_finite _ hs1]
  rw [Measure.count_apply_finite _ hs2]
  -- Need: hs1.toFinset.card = hs2.toFinset.card
  -- This follows from bijection: preimage of s under bijection has same cardinality
  have h_eq : hs1.toFinset = hs2.toFinset.image (flipCoord j) := by
    ext x
    simp only [Set.Finite.mem_toFinset, Set.mem_preimage, Finset.mem_image]
    constructor
    · intro hx
      exact ⟨flipCoord j x, hx, hinv x⟩
    · rintro ⟨y, hy, rfl⟩
      convert hy using 1
      exact hinv y
  rw [h_eq, Finset.card_image_of_injective _ hinv.injective]

/-- Integral over bernoulliUniform equals sum divided by 2^n.
    This is the fundamental property of the uniform measure on finite types. -/
theorem bernoulli_integral_eq_sum {n : ℕ} (f : (Fin n → Bool) → ℝ) :
    ∫ ε, f ε ∂(bernoulliUniform n) = (∑ ε : Fin n → Bool, f ε) / 2^n := by
  unfold bernoulliUniform
  rw [integral_smul_measure]
  rw [integral_fintype _ (Integrable.of_finite)]
  rw [card_fin_bool n]
  simp only [Nat.cast_pow, Nat.cast_ofNat, smul_eq_mul, count_real_singleton, one_mul]
  rw [ENNReal.toReal_inv, ENNReal.toReal_pow, ENNReal.toReal_ofNat]
  ring

/-- Sum over Fin (n+1) → Bool decomposes as sum over slices by the last coordinate. -/
theorem sum_fin_succ_bool_eq_sum_snoc {n : ℕ} (f : (Fin (n+1) → Bool) → ℝ) :
    ∑ ε : Fin (n+1) → Bool, f ε =
    ∑ ε' : Fin n → Bool, (f (Fin.snoc ε' true) + f (Fin.snoc ε' false)) := by
  -- Use Fin.snocEquiv: (Fin (n+1) → α) ≃ α × (Fin n → α) at last position
  -- But we need (Fin n → α) × α, so use Prod.swap
  let h_equiv : (Fin (n+1) → Bool) ≃ (Fin n → Bool) × Bool :=
    (Fin.snocEquiv (fun _ => Bool)).symm.trans (Equiv.prodComm _ _)
  calc ∑ ε : Fin (n+1) → Bool, f ε
      = ∑ p : (Fin n → Bool) × Bool, f (h_equiv.symm p) := by
          rw [Fintype.sum_equiv h_equiv.symm]
          simp
    _ = ∑ ε' : Fin n → Bool, ∑ b : Bool, f (h_equiv.symm (ε', b)) := by
          rw [Fintype.sum_prod_type]
    _ = ∑ ε' : Fin n → Bool, (f (h_equiv.symm (ε', true)) + f (h_equiv.symm (ε', false))) := by
          congr 1
          ext ε'
          simp only [Fintype.sum_bool]
    _ = ∑ ε' : Fin n → Bool, (f (Fin.snoc ε' true) + f (Fin.snoc ε' false)) := by
          congr 1

/-- Integral over bernoulliUniform (n+1) splits into average over slices.
    This expresses that summing over (Fin (n+1) → Bool) equals summing over
    pairs (ε', b) with ε' : Fin n → Bool and b : Bool, weighted by 1/2 each. -/
theorem bernoulli_integral_succ_split {n : ℕ} (f : (Fin (n+1) → Bool) → ℝ) :
    ∫ ε, f ε ∂(bernoulliUniform (n+1)) =
    ∫ ε', (f (Fin.snoc ε' true) + f (Fin.snoc ε' false)) / 2 ∂(bernoulliUniform n) := by
  rw [bernoulli_integral_eq_sum, bernoulli_integral_eq_sum]
  rw [sum_fin_succ_bool_eq_sum_snoc]
  rw [pow_succ]
  rw [Finset.sum_div]
  -- Goal: ∑ i, (f true + f false) / (2^n * 2) = (∑ i, (f true + f false) / 2) / 2^n
  -- Rewrite RHS: (∑ (x/2)) / 2^n = ∑ (x / (2 * 2^n)) = ∑ (x / (2^n * 2))
  rw [Finset.sum_div]
  congr 1
  ext i
  ring

/-! ## Part 3: Entropy on the hypercube -/

/-- The sum over all coordinate differences -/
def gradientNormSq (n : ℕ) (h : (Fin n → Bool) → ℝ) (ε : Fin n → Bool) : ℝ :=
  ∑ j : Fin n, (h ε - h (flipCoord j ε))^2

/-!
## Part 4: The two-point (conditional) entropy lemma

For the inductive step, we need to analyze the entropy when conditioning
on all but one coordinate. This uses the Rothaus lemma from TwoPoint.lean.
-/

/-- Given a function h and fixed values for coordinates except the last,
    the Rothaus lemma gives the two-point log-Sobolev bound. -/
theorem two_point_rothaus_bound {n : ℕ} (h : (Fin (n + 1) → Bool) → ℝ)
    (hh_nn : ∀ ε, 0 ≤ h ε)
    (ε' : Fin n → Bool) :
    let a := (h (Fin.snoc ε' true))^2
    let b := (h (Fin.snoc ε' false))^2
    -- Two-point log-Sobolev (Rothaus lemma): entropy ≤ gradient term
    (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2) ≤
      (h (Fin.snoc ε' true) - h (Fin.snoc ε' false))^2 / 2 := by
  set a := (h (Fin.snoc ε' true))^2 with ha_def
  set b := (h (Fin.snoc ε' false))^2 with hb_def
  have ha_nn : 0 ≤ a := sq_nonneg _
  have hb_nn : 0 ≤ b := sq_nonneg _
  have h_diff_sq_nn : 0 ≤ (h (Fin.snoc ε' true) - h (Fin.snoc ε' false))^2 / 2 :=
    div_nonneg (sq_nonneg _) (by norm_num : (0 : ℝ) ≤ 2)
  -- Helper for log 2 ≤ 1
  have hlog2_le : log 2 ≤ 1 := by
    have h1 : (2 : ℝ) < exp 1 := by
      have : (2.7182818283 : ℝ) < exp 1 := Real.exp_one_gt_d9
      linarith
    have h2 : log 2 < log (exp 1) := log_lt_log (by norm_num) h1
    simp at h2
    linarith
  by_cases ha_pos : 0 < a
  · by_cases hb_pos : 0 < b
    · -- Both positive: apply Rothaus lemma and simplify
      have hrothaus := LogSobolev.rothaus_lemma ha_pos hb_pos
      -- Need to show (√a - √b)² = (h(+) - h(-))² when h ≥ 0
      have hsqrt_a : sqrt a = h (Fin.snoc ε' true) := by
        rw [ha_def]
        exact sqrt_sq (hh_nn _)
      have hsqrt_b : sqrt b = h (Fin.snoc ε' false) := by
        rw [hb_def]
        exact sqrt_sq (hh_nn _)
      calc (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2)
          ≤ (sqrt a - sqrt b)^2 / 2 := hrothaus
        _ = (h (Fin.snoc ε' true) - h (Fin.snoc ε' false))^2 / 2 := by rw [hsqrt_a, hsqrt_b]
    · -- b = 0: a > 0, b = 0
      have hb_zero : b = 0 := le_antisymm (not_lt.mp hb_pos) hb_nn
      simp only [hb_zero, add_zero, mul_zero, log_zero]
      by_cases ha_zero : a = 0
      · -- a = 0 and b = 0: contradiction with ha_pos
        exact absurd (ha_zero ▸ ha_pos) (lt_irrefl 0)
      · -- LHS = a * log a / 2 - a / 2 * log (a / 2)
        --     = a/2 * (log a - log (a/2)) = a/2 * log 2
        -- RHS = (h(true) - 0)^2 / 2 = a / 2
        have h_lhs : a * log a / 2 - a / 2 * log (a / 2) = a / 2 * log 2 := by
          rw [log_div ha_zero (by norm_num : (2 : ℝ) ≠ 0)]
          ring
        rw [h_lhs]
        -- h(false)^2 = 0 means h(false) = 0 since h ≥ 0
        have h_false_zero : h (Fin.snoc ε' false) = 0 := sq_eq_zero_iff.mp hb_zero
        rw [h_false_zero, sub_zero, sq]
        -- Need: a/2 * log 2 ≤ a / 2, i.e., log 2 ≤ 1
        calc a / 2 * log 2 ≤ a / 2 * 1 := by nlinarith [hlog2_le, ha_nn]
          _ = a / 2 := by ring
          _ = h (Fin.snoc ε' true) * h (Fin.snoc ε' true) / 2 := by rw [ha_def]; ring
  · -- a = 0
    have ha_zero : a = 0 := le_antisymm (not_lt.mp ha_pos) ha_nn
    simp only [ha_zero, zero_add, zero_mul, log_zero]
    by_cases hb_zero : b = 0
    · -- a = 0 and b = 0: both h values are 0, so LHS = RHS = 0
      simp only [hb_zero, mul_zero, log_zero, zero_div, sub_zero]
      exact h_diff_sq_nn
    · -- a = 0, b > 0
      have h_lhs : b * log b / 2 - b / 2 * log (b / 2) = b / 2 * log 2 := by
        rw [log_div hb_zero (by norm_num : (2 : ℝ) ≠ 0)]
        ring
      rw [h_lhs]
      have h_true_zero : h (Fin.snoc ε' true) = 0 := sq_eq_zero_iff.mp ha_zero
      rw [h_true_zero, zero_sub]
      -- (0 - h(false))² = h(false)² = b
      have hsq_neg : (-h (Fin.snoc ε' false))^2 = b := by
        rw [neg_sq, hb_def]
      rw [hsq_neg]
      linarith [mul_le_of_le_one_right (div_nonneg hb_nn (by norm_num : (0 : ℝ) ≤ 2)) hlog2_le]

/-!
## Part 5: Decomposition lemmas for the induction
-/

/-- The sum over coordinates decomposes: first n coordinates plus the last one -/
theorem gradientNormSq_succ_decomposition {n : ℕ} (h : (Fin (n + 1) → Bool) → ℝ)
    (ε : Fin (n + 1) → Bool) :
    gradientNormSq (n + 1) h ε =
    (∑ j : Fin n, (h ε - h (flipCoord (Fin.castSucc j) ε))^2) +
    (h ε - h (flipCoord (Fin.last n) ε))^2 := by
  simp only [gradientNormSq]
  rw [Fin.sum_univ_castSucc]

/-- For any ε : Fin (n+1) → Bool, we can write it as snoc ε' b -/
theorem fin_succ_eq_snoc {n : ℕ} (ε : Fin (n + 1) → Bool) :
    ε = Fin.snoc (fun i => ε (Fin.castSucc i)) (ε (Fin.last n)) := by
  ext i
  by_cases h : i = Fin.last n
  · simp [h, Fin.snoc]
  · have hi : i.val < n := by
      have hlt := i.isLt
      have hne : i.val ≠ n := by
        intro heq
        apply h
        ext
        simp [Fin.last, heq]
      omega
    simp only [Fin.snoc, hi, ↓reduceDIte]
    congr

/-- Flipping the last coordinate swaps true/false -/
theorem flipCoord_last_snoc {n : ℕ} (ε' : Fin n → Bool) (b : Bool) :
    flipCoord (Fin.last n) (Fin.snoc ε' b) = Fin.snoc ε' (!b) := by
  ext i
  by_cases h : i = Fin.last n
  · simp only [h, flipCoord_same, Fin.snoc_last]
  · have hi : i.val < n := by
      have hlt := i.isLt
      have hne : i.val ≠ n := by
        intro heq
        apply h; ext; simp [Fin.last, heq]
      omega
    have hne' : i ≠ Fin.last n := fun heq => h heq
    rw [flipCoord_noteq (Fin.last n) i _ hne']
    simp only [Fin.snoc, hi, ↓reduceDIte]

/-- Flipping a coordinate in the first n doesn't affect the last coordinate -/
theorem flipCoord_castSucc_snoc {n : ℕ} (j : Fin n) (ε' : Fin n → Bool) (b : Bool) :
    flipCoord (Fin.castSucc j) (Fin.snoc ε' b) = Fin.snoc (flipCoord j ε') b := by
  ext i
  by_cases hi_last : i = Fin.last n
  · -- i is the last index
    simp only [hi_last, Fin.snoc_last]
    have hne : Fin.last n ≠ Fin.castSucc j := by
      intro heq
      have hval : (Fin.last n).val = (Fin.castSucc j).val := congrArg Fin.val heq
      simp only [Fin.last, Fin.val_castSucc] at hval
      omega
    rw [flipCoord_noteq (Fin.castSucc j) (Fin.last n) _ hne]
    simp [Fin.snoc]
  · -- i is not the last index
    have hi : i.val < n := by
      have hlt := i.isLt
      have hne : i.val ≠ n := by
        intro heq
        apply hi_last; ext; simp [Fin.last, heq]
      omega
    by_cases hj : i = Fin.castSucc j
    · -- i = castSucc j
      subst hj
      simp only [flipCoord_same, Fin.snoc]
      have hi' : (Fin.castSucc j).val < n := by simp [Fin.val_castSucc]
      simp only [hi', ↓reduceDIte]
      -- Need to show !ε'(castLT (castSucc j)) = flipCoord j ε' (castLT (castSucc j))
      have hcast_eq : Fin.castLT (Fin.castSucc j) hi' = j := by
        ext; simp [Fin.castLT, Fin.castSucc]
      simp only [hcast_eq, flipCoord_same, cast_eq]
    · -- i ≠ castSucc j
      have hne' : i ≠ Fin.castSucc j := hj
      rw [flipCoord_noteq (Fin.castSucc j) i _ hne']
      simp only [Fin.snoc, hi, ↓reduceDIte]
      have hj' : Fin.castLT i hi ≠ j := by
        intro heq
        apply hj
        ext
        simp only [Fin.val_castSucc]
        exact congrArg Fin.val heq
      rw [flipCoord_noteq j (Fin.castLT i hi) _ hj']

/-- Key bound: The gradient contribution from the last coordinate equals the difference squared -/
theorem last_coord_gradient_bound {n : ℕ} (h : (Fin (n + 1) → Bool) → ℝ)
    (ε' : Fin n → Bool) (b : Bool) :
    (h (Fin.snoc ε' b) - h (flipCoord (Fin.last n) (Fin.snoc ε' b)))^2 =
    (h (Fin.snoc ε' b) - h (Fin.snoc ε' (!b)))^2 := by
  rw [flipCoord_last_snoc]

/-- Entropy equals ∫ f log f - (∫ f) log(∫ f) by definition -/
theorem entropy_def' {α : Type*} [MeasurableSpace α] (μ : Measure α) (f : α → ℝ) :
    LogSobolev.entropy μ f = ∫ ω, f ω * log (f ω) ∂μ - (∫ ω, f ω ∂μ) * log (∫ ω, f ω ∂μ) := rfl

/-- For the Bernoulli uniform measure, integral is a weighted sum -/
theorem bernoulli_integral {n : ℕ} (f : (Fin n → Bool) → ℝ) :
    ∫ ε, f ε ∂(bernoulliUniform n) =
    (2^n : ℝ)⁻¹ * ∑ ε : Fin n → Bool, f ε := by
  unfold bernoulliUniform
  rw [integral_smul_measure, card_fin_bool]
  simp only [Nat.cast_pow, Nat.cast_ofNat, smul_eq_mul]
  rw [ENNReal.toReal_inv]
  congr 1
  rw [integral_count]

/-- The gradient sum splits into individual coordinate contributions -/
theorem integral_gradientNormSq_eq_sum {n : ℕ} (h : (Fin n → Bool) → ℝ) :
    ∫ ε, gradientNormSq n h ε ∂(bernoulliUniform n) =
    ∑ j : Fin n, ∫ ε, (h ε - h (flipCoord j ε))^2 ∂(bernoulliUniform n) := by
  simp only [gradientNormSq]
  rw [integral_finset_sum]
  intro j _
  apply Integrable.of_finite

/-- Each coordinate gradient term is symmetric: the average over ε_j of (h(ε) - h(flip_j ε))²
    equals (h(ε_{-j}, true) - h(ε_{-j}, false))² regardless of which ε_j value we pick -/
theorem gradient_term_symmetric {n : ℕ} (j : Fin n) (h : (Fin n → Bool) → ℝ) :
    ∫ ε, (h ε - h (flipCoord j ε))^2 ∂(bernoulliUniform n) =
    ∫ ε, (h ε - h (flipCoord j ε))^2 ∂(bernoulliUniform n) := rfl

/-- The two-point entropy for coordinate j given all other coordinates.
    This is the entropy of the function (h(ε_{-j}, true)², h(ε_{-j}, false)²)
    under the uniform distribution on {true, false}. -/
def twoPointEntropyCoord {n : ℕ} (j : Fin n) (h : (Fin n → Bool) → ℝ)
    (ε : Fin n → Bool) : ℝ :=
  let a := (h ε)^2
  let b := (h (flipCoord j ε))^2
  (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2)

/-- The two-point entropy is bounded by the squared difference via Rothaus -/
theorem twoPointEntropyCoord_le_gradientTerm {n : ℕ} (j : Fin n)
    (h : (Fin n → Bool) → ℝ) (ε : Fin n → Bool) :
    twoPointEntropyCoord j h ε ≤ (h ε - h (flipCoord j ε))^2 / 2 := by
  unfold twoPointEntropyCoord
  set a := (h ε)^2 with ha_def
  set b := (h (flipCoord j ε))^2 with hb_def
  have ha_nn : 0 ≤ a := sq_nonneg _
  have hb_nn : 0 ≤ b := sq_nonneg _
  by_cases ha_pos : 0 < a
  · by_cases hb_pos : 0 < b
    · -- Both positive: apply Rothaus lemma
      have hrothaus := LogSobolev.rothaus_lemma ha_pos hb_pos
      -- √a = |h(ε)| and √b = |h(flip ε)| (using sqrt_sq_eq_abs, no nonnegativity needed)
      have hsqrt_a : sqrt a = |h ε| := sqrt_sq_eq_abs (h ε)
      have hsqrt_b : sqrt b = |h (flipCoord j ε)| := sqrt_sq_eq_abs (h (flipCoord j ε))
      -- Use reverse triangle inequality: ||x| - |y|| ≤ |x - y|, then square both sides
      have h_rev_tri : (|h ε| - |h (flipCoord j ε)|)^2 ≤ (h ε - h (flipCoord j ε))^2 := by
        rw [sq_le_sq]
        exact abs_abs_sub_abs_le_abs_sub (h ε) (h (flipCoord j ε))
      calc (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2)
          ≤ (sqrt a - sqrt b)^2 / 2 := hrothaus
        _ = (|h ε| - |h (flipCoord j ε)|)^2 / 2 := by rw [hsqrt_a, hsqrt_b]
        _ ≤ (h ε - h (flipCoord j ε))^2 / 2 := by linarith [h_rev_tri]
    · -- b = 0
      have hb_zero : b = 0 := le_antisymm (not_lt.mp hb_pos) hb_nn
      simp only [hb_zero, add_zero, mul_zero, log_zero]
      by_cases ha_zero : a = 0
      · simp [ha_zero]; positivity
      · have h_lhs : a * log a / 2 - a / 2 * log (a / 2) = a / 2 * log 2 := by
          rw [log_div ha_zero (by norm_num : (2 : ℝ) ≠ 0)]
          ring
        rw [h_lhs]
        have h_flip_zero : h (flipCoord j ε) = 0 := sq_eq_zero_iff.mp hb_zero
        rw [h_flip_zero, sub_zero, sq]
        have hlog2_le : log 2 ≤ 1 := by
          have h1 : (2 : ℝ) < exp 1 := by
            have : (2.7182818283 : ℝ) < exp 1 := Real.exp_one_gt_d9
            linarith
          have h2 : log 2 < log (exp 1) := log_lt_log (by norm_num : (0 : ℝ) < 2) h1
          simp only [log_exp] at h2
          linarith
        calc a / 2 * log 2 ≤ a / 2 * 1 := by nlinarith [hlog2_le, ha_nn]
          _ = a / 2 := by ring
          _ = h ε * h ε / 2 := by rw [ha_def]; ring_nf
  · -- a = 0
    have ha_zero : a = 0 := le_antisymm (not_lt.mp ha_pos) ha_nn
    simp only [ha_zero, zero_add, zero_mul, log_zero]
    by_cases hb_zero : b = 0
    · simp [hb_zero]; positivity
    · have h_lhs : b * log b / 2 - b / 2 * log (b / 2) = b / 2 * log 2 := by
        rw [log_div hb_zero (by norm_num : (2 : ℝ) ≠ 0)]
        ring
      rw [h_lhs]
      have h_ε_zero : h ε = 0 := sq_eq_zero_iff.mp ha_zero
      rw [h_ε_zero, zero_sub, neg_sq]
      have hlog2_le : log 2 ≤ 1 := by
        have h1 : (2 : ℝ) < exp 1 := by
          have : (2.7182818283 : ℝ) < exp 1 := Real.exp_one_gt_d9
          linarith
        have h2 : log 2 < log (exp 1) := log_lt_log (by norm_num : (0 : ℝ) < 2) h1
        simp only [log_exp] at h2
        linarith
      calc b / 2 * log 2 ≤ b / 2 * 1 := by nlinarith [hlog2_le, hb_nn]
        _ = b / 2 := by ring
        _ = h (flipCoord j ε) ^ 2 / 2 := by rw [hb_def]

/-- φ(x) = x log x is convex on [0, ∞), so φ((a+b)/2) ≤ (φ(a) + φ(b))/2 -/
theorem phi_convex_avg (a b : ℝ) (ha : 0 ≤ a) (hb : 0 ≤ b) :
    (a + b) / 2 * log ((a + b) / 2) ≤ (a * log a + b * log b) / 2 := by
  by_cases hab : a + b = 0
  · -- If a + b = 0, then a = b = 0
    have ha0 : a = 0 := by linarith
    have hb0 : b = 0 := by linarith
    simp [ha0, hb0]
  · -- Otherwise, use convexity of x log x
    have hconv := Real.convexOn_mul_log
    have ha_mem : a ∈ Set.Ici (0 : ℝ) := Set.mem_Ici.mpr ha
    have hb_mem : b ∈ Set.Ici (0 : ℝ) := Set.mem_Ici.mpr hb
    have h12 : (0 : ℝ) ≤ 1/2 := by norm_num
    have h12' : (1/2 : ℝ) + 1/2 = 1 := by norm_num
    have hkey := hconv.2 ha_mem hb_mem h12 h12 h12'
    simp only [smul_eq_mul] at hkey
    have hmid_eq : (1/2 : ℝ) * a + (1/2) * b = (a + b) / 2 := by ring
    rw [hmid_eq] at hkey
    calc (a + b) / 2 * log ((a + b) / 2)
        ≤ (1/2) * (a * log a) + (1/2) * (b * log b) := hkey
      _ = (a * log a + b * log b) / 2 := by ring

/-- The two-point entropy is always nonnegative (consequence of Jensen) -/
theorem twoPointEntropyCoord_nonneg {n : ℕ} (j : Fin n) (h : (Fin n → Bool) → ℝ)
    (ε : Fin n → Bool) :
    0 ≤ twoPointEntropyCoord j h ε := by
  unfold twoPointEntropyCoord
  set a := (h ε)^2
  set b := (h (flipCoord j ε))^2
  have ha_nn : 0 ≤ a := sq_nonneg _
  have hb_nn : 0 ≤ b := sq_nonneg _
  -- By Jensen: (a+b)/2 * log((a+b)/2) ≤ (a log a + b log b)/2
  have hconv := phi_convex_avg a b ha_nn hb_nn
  linarith

/-- The average two-point entropy over all ε is bounded by the average gradient term -/
theorem avg_twoPointEntropyCoord_le {n : ℕ} (j : Fin n)
    (h : (Fin n → Bool) → ℝ) :
    ∫ ε, twoPointEntropyCoord j h ε ∂(bernoulliUniform n) ≤
    ∫ ε, (h ε - h (flipCoord j ε))^2 / 2 ∂(bernoulliUniform n) := by
  apply integral_mono_of_nonneg
  · -- The two-point entropy is nonneg (a.e.)
    filter_upwards with ε
    exact twoPointEntropyCoord_nonneg j h ε
  · -- The RHS is integrable
    apply Integrable.of_finite
  · -- Pointwise bound
    apply Eventually.of_forall
    intro ε
    exact twoPointEntropyCoord_le_gradientTerm j h ε

/-- The total two-point entropy summed over all coordinates -/
def totalTwoPointEntropy {n : ℕ} (h : (Fin n → Bool) → ℝ) (ε : Fin n → Bool) : ℝ :=
  ∑ j : Fin n, twoPointEntropyCoord j h ε

/-- The conditional mean given all but the last coordinate -/
def condMeanLast {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ) (ε' : Fin n → Bool) : ℝ :=
  (f (Fin.snoc ε' true) + f (Fin.snoc ε' false)) / 2

/-- Two-point entropy for the last coordinate, given ε' -/
def twoPointEntropyLast {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ) (ε' : Fin n → Bool) : ℝ :=
  let a := f (Fin.snoc ε' true)
  let b := f (Fin.snoc ε' false)
  (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2)

/-- The two-point entropy using twoPointEntropyCoord at the last coordinate -/
theorem twoPointEntropyLast_eq_coord {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ)
    (ε' : Fin n → Bool) (b : Bool) :
    twoPointEntropyLast f ε' =
    let ε := Fin.snoc ε' b
    let a := f ε
    let c := f (flipCoord (Fin.last n) ε)
    (a * log a + c * log c) / 2 - (a + c) / 2 * log ((a + c) / 2) := by
  simp only [twoPointEntropyLast]
  cases b <;> simp [flipCoord_last_snoc, add_comm]

/-- Integral over n+1 dimensional cube equals integral of condMeanLast over n -/
theorem integral_eq_integral_condMeanLast {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ) :
    ∫ ε, f ε ∂(bernoulliUniform (n+1)) = ∫ ε', condMeanLast f ε' ∂(bernoulliUniform n) := by
  rw [bernoulli_integral_succ_split]
  congr 1

/-- f log f integral decomposition over the last coordinate -/
theorem integral_flogf_decomp {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ) :
    ∫ ε, f ε * log (f ε) ∂(bernoulliUniform (n+1)) =
    ∫ ε', (f (Fin.snoc ε' true) * log (f (Fin.snoc ε' true)) +
           f (Fin.snoc ε' false) * log (f (Fin.snoc ε' false))) / 2 ∂(bernoulliUniform n) := by
  rw [bernoulli_integral_succ_split]

theorem entropy_chain_rule_succ {n : ℕ} (f : (Fin (n + 1) → Bool) → ℝ) :
    LogSobolev.entropy (bernoulliUniform (n + 1)) f =
    ∫ ε', twoPointEntropyLast f ε' ∂(bernoulliUniform n) +
    LogSobolev.entropy (bernoulliUniform n) (condMeanLast f) := by
  -- Unfold entropy on both sides
  unfold LogSobolev.entropy
  -- Use the integral decomposition lemmas
  rw [integral_flogf_decomp, integral_eq_integral_condMeanLast]
  -- The key is to combine the twoPointEntropyLast and entropy of condMeanLast correctly
  -- Algebraic manipulation
  have key : ∀ ε' : Fin n → Bool,
      (f (Fin.snoc ε' true) * log (f (Fin.snoc ε' true)) +
       f (Fin.snoc ε' false) * log (f (Fin.snoc ε' false))) / 2 =
      twoPointEntropyLast f ε' + condMeanLast f ε' * log (condMeanLast f ε') := by
    intro ε'
    unfold twoPointEntropyLast condMeanLast
    ring
  rw [show (fun ε' => (f (Fin.snoc ε' true) * log (f (Fin.snoc ε' true)) +
           f (Fin.snoc ε' false) * log (f (Fin.snoc ε' false))) / 2) =
      (fun ε' => twoPointEntropyLast f ε' + condMeanLast f ε' * log (condMeanLast f ε'))
    from funext key]
  rw [integral_add Integrable.of_finite Integrable.of_finite]
  ring

/-- The two-point entropy function -/
def twoPointEnt (a b : ℝ) : ℝ :=
  (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2)

/-- Two-point entropy is nonnegative for nonnegative inputs (Jensen) -/
theorem twoPointEnt_nonneg (a b : ℝ) (ha : 0 ≤ a) (hb : 0 ≤ b) : 0 ≤ twoPointEnt a b := by
  unfold twoPointEnt
  have := phi_convex_avg a b ha hb
  linarith

/-- Two-point entropy at equal arguments is zero -/
theorem twoPointEnt_self (a : ℝ) : twoPointEnt a a = 0 := by
  unfold twoPointEnt
  have h1 : (a + a) / 2 = a := by ring
  have h2 : (a * log a + a * log a) / 2 = a * log a := by ring
  simp only [h1, h2, sub_self]

/-- Two-point entropy is symmetric -/
theorem twoPointEnt_comm (a b : ℝ) : twoPointEnt a b = twoPointEnt b a := by
  unfold twoPointEnt
  have h1 : a + b = b + a := by ring
  have h2 : a * log a + b * log b = b * log b + a * log a := by ring
  simp only [h1, h2]

/-- The Jensen gap δ_φ(x,y) = (φ(x)+φ(y))/2 - φ((x+y)/2) for φ(x) = x log x -/
def jensenGap (x y : ℝ) : ℝ :=
  (x * log x + y * log y) / 2 - (x + y) / 2 * log ((x + y) / 2)

/-- Jensen gap is nonnegative (convexity of x log x) -/
theorem jensenGap_nonneg (x y : ℝ) (hx : 0 ≤ x) (hy : 0 ≤ y) : 0 ≤ jensenGap x y := by
  unfold jensenGap
  have := phi_convex_avg x y hx hy
  linarith

/-- twoPointEnt expressed in terms of Jensen gap -/
theorem twoPointEnt_eq_jensenGap (a b : ℝ) : twoPointEnt a b = jensenGap a b := by
  unfold twoPointEnt jensenGap
  ring

/-!
### Helper Lemmas for Joint Convexity of Jensen Gap

The proof of joint convexity uses the fact that jensenGap can be written as:
  jensenGap(x, y) = ((x+y)/2) * D(x/(x+y))
where D(p) = log 2 - binEntropy(p) is convex (since binEntropy is concave).
-/

/-- The binary KL divergence from (p, 1-p) to (1/2, 1/2).
    This equals log 2 - binEntropy(p), where binEntropy is the binary Shannon entropy. -/
def binaryKLfromUniform (p : ℝ) : ℝ := Real.log 2 - Real.binEntropy p

/-- binaryKLfromUniform is convex on [0, 1] since binEntropy is concave. -/
theorem binaryKLfromUniform_convexOn :
    ConvexOn ℝ (Set.Icc (0 : ℝ) 1) binaryKLfromUniform := by
  have hconc := Real.strictConcave_binEntropy.concaveOn
  -- -binEntropy is convex, so log 2 - binEntropy is also convex
  have h1 : ConvexOn ℝ (Set.Icc (0 : ℝ) 1) (fun p => -Real.binEntropy p) := hconc.neg
  have h2 : ConvexOn ℝ (Set.Icc (0 : ℝ) 1) (fun _ => Real.log 2) :=
    convexOn_const _ (convex_Icc (0 : ℝ) 1)
  have h3 : ConvexOn ℝ (Set.Icc (0 : ℝ) 1) (fun p => Real.log 2 + (-Real.binEntropy p)) :=
    h2.add h1
  convert h3 using 1

/-- The midpoint inequality for binaryKLfromUniform -/
theorem binaryKLfromUniform_midpoint_le {p₀ p₁ : ℝ}
    (hp₀ : p₀ ∈ Set.Icc (0 : ℝ) 1) (hp₁ : p₁ ∈ Set.Icc (0 : ℝ) 1) :
    binaryKLfromUniform ((p₀ + p₁) / 2) ≤
    (binaryKLfromUniform p₀ + binaryKLfromUniform p₁) / 2 := by
  have hconv := binaryKLfromUniform_convexOn
  have h12 : (0 : ℝ) ≤ 1/2 := by norm_num
  have h12' : (1/2 : ℝ) + 1/2 = 1 := by norm_num
  have hmid_eq : (1/2 : ℝ) * p₀ + 1/2 * p₁ = (p₀ + p₁) / 2 := by ring
  have hkey := hconv.2 hp₀ hp₁ h12 h12 h12'
  simp only [smul_eq_mul, hmid_eq] at hkey
  calc binaryKLfromUniform ((p₀ + p₁) / 2)
      ≤ (1/2) * binaryKLfromUniform p₀ + (1/2) * binaryKLfromUniform p₁ := hkey
    _ = (binaryKLfromUniform p₀ + binaryKLfromUniform p₁) / 2 := by ring

/-- Weighted convexity of binaryKLfromUniform: D(w₀p₀ + w₁p₁) ≤ w₀D(p₀) + w₁D(p₁) -/
theorem binaryKLfromUniform_weighted_le {p₀ p₁ w₀ w₁ : ℝ}
    (hp₀ : p₀ ∈ Set.Icc (0 : ℝ) 1) (hp₁ : p₁ ∈ Set.Icc (0 : ℝ) 1)
    (hw₀ : 0 ≤ w₀) (hw₁ : 0 ≤ w₁) (hw_sum : w₀ + w₁ = 1) :
    binaryKLfromUniform (w₀ * p₀ + w₁ * p₁) ≤
    w₀ * binaryKLfromUniform p₀ + w₁ * binaryKLfromUniform p₁ := by
  have hconv := binaryKLfromUniform_convexOn
  have hkey := hconv.2 hp₀ hp₁ hw₀ hw₁ hw_sum
  simp only [smul_eq_mul] at hkey
  exact hkey

/-- jensenGap expressed in terms of binaryKLfromUniform when x + y > 0. -/
theorem jensenGap_eq_scaled_binaryKL {x y : ℝ} (hx : 0 ≤ x) (hy : 0 ≤ y) (hxy : 0 < x + y) :
    jensenGap x y = ((x + y) / 2) * binaryKLfromUniform (x / (x + y)) := by
  have hxy_ne : x + y ≠ 0 := ne_of_gt hxy
  -- Expand and simplify
  by_cases hx_zero : x = 0
  · -- Case x = 0: jensenGap(0, y) = (y/2) * binaryKL(0) = (y/2) * log 2
    subst hx_zero
    simp only [zero_add] at hxy_ne hxy ⊢
    simp only [binaryKLfromUniform, zero_div, Real.binEntropy_zero, sub_zero]
    simp only [jensenGap, zero_mul, Real.log_zero, zero_add]
    -- Need: y * log y / 2 - (y/2) * log(y/2) = (y/2) * log 2
    have hy_pos : 0 < y := hxy
    have hlog_half : Real.log (y / 2) = Real.log y - Real.log 2 := by
      rw [Real.log_div (ne_of_gt hy_pos) (by norm_num : (2 : ℝ) ≠ 0)]
    rw [hlog_half]
    ring
  by_cases hy_zero : y = 0
  · -- Case y = 0: jensenGap(x, 0) = (x/2) * binaryKL(1) = (x/2) * log 2
    subst hy_zero
    simp only [add_zero] at hxy_ne hxy ⊢
    simp only [binaryKLfromUniform, div_self hxy_ne, Real.binEntropy_one, sub_zero]
    simp only [jensenGap, mul_zero, Real.log_zero, add_zero]
    -- Need: x * log x / 2 - (x/2) * log(x/2) = (x/2) * log 2
    have hx_pos : 0 < x := hxy
    have hlog_half : Real.log (x / 2) = Real.log x - Real.log 2 := by
      rw [Real.log_div (ne_of_gt hx_pos) (by norm_num : (2 : ℝ) ≠ 0)]
    rw [hlog_half]
    ring
  -- General case: x > 0 and y > 0
  have hx_pos : 0 < x := hx.lt_of_ne' hx_zero
  have hy_pos : 0 < y := hy.lt_of_ne' hy_zero
  have hyd_eq : y / (x + y) = 1 - x / (x + y) := by field_simp; ring
  -- Expand using binEntropy definition
  simp only [binaryKLfromUniform, jensenGap]
  rw [Real.binEntropy_eq_negMulLog_add_negMulLog_one_sub]
  simp only [Real.negMulLog]
  rw [← hyd_eq]
  have hlog_half : Real.log ((x + y) / 2) = Real.log (x + y) - Real.log 2 := by
    rw [Real.log_div (ne_of_gt hxy) (by norm_num : (2 : ℝ) ≠ 0)]
  have hlog_x : Real.log (x / (x + y)) = Real.log x - Real.log (x + y) := by
    rw [Real.log_div (ne_of_gt hx_pos) hxy_ne]
  have hlog_y : Real.log (y / (x + y)) = Real.log y - Real.log (x + y) := by
    rw [Real.log_div (ne_of_gt hy_pos) hxy_ne]
  rw [hlog_half, hlog_x, hlog_y]
  field_simp
  ring

/-- Jensen gap vanishes when both arguments are equal -/
@[simp]
theorem jensenGap_self (x : ℝ) : jensenGap x x = 0 := by
  unfold jensenGap
  have h1 : (x + x) / 2 = x := by ring
  have h2 : (x * log x + x * log x) / 2 = x * log x := by ring
  simp only [h1, h2, sub_self]

/-- Key: Joint convexity of the Jensen gap function. -/
theorem jensenGap_joint_convex (x₀ x₁ y₀ y₁ : ℝ)
    (hx₀ : 0 ≤ x₀) (hx₁ : 0 ≤ x₁) (hy₀ : 0 ≤ y₀) (hy₁ : 0 ≤ y₁) :
    2 * jensenGap ((x₀ + x₁) / 2) ((y₀ + y₁) / 2) ≤ jensenGap x₀ y₀ + jensenGap x₁ y₁ := by

  set s₀ := x₀ + y₀ with hs₀
  set s₁ := x₁ + y₁ with hs₁
  set xbar := (x₀ + x₁) / 2 with hxbar
  set ybar := (y₀ + y₁) / 2 with hybar
  set sbar := xbar + ybar with hsbar

  have hsbar_eq : sbar = (s₀ + s₁) / 2 := by simp only [hsbar, hxbar, hybar, hs₀, hs₁]; ring

  -- Handle degenerate cases
  by_cases hs₀_zero : s₀ = 0
  · -- If s₀ = 0, then x₀ = y₀ = 0, so jensenGap(x₀, y₀) = 0
    have hx₀_zero : x₀ = 0 := by linarith
    have hy₀_zero : y₀ = 0 := by linarith
    rw [hx₀_zero, hy₀_zero]
    simp only [zero_add, jensenGap_self]
    -- Unfold xbar, ybar to get explicit expressions
    simp only [hxbar, hybar, hx₀_zero, hy₀_zero, zero_add]
    -- Now goal is: 2 * jensenGap (x₁/2) (y₁/2) ≤ jensenGap x₁ y₁
    by_cases hs₁_zero : s₁ = 0
    · have hx₁_zero : x₁ = 0 := by linarith
      have hy₁_zero : y₁ = 0 := by linarith
      simp [hx₁_zero, hy₁_zero, jensenGap_self]
    · -- s₁ > 0, so we can use the KL representation
      have hs₁_pos : 0 < s₁ := by
        rcases hx₁.lt_or_eq with h | h
        · linarith
        · -- h : 0 = x₁, so x₁ = 0
          have hx₁_eq : x₁ = 0 := h.symm
          -- s₁ = x₁ + y₁ = 0 + y₁ = y₁, but s₁ ≠ 0, so y₁ > 0
          simp only [hs₁, hx₁_eq, zero_add] at hs₁_zero
          linarith [hy₁.lt_of_ne' hs₁_zero]
      -- jensenGap(x₁/2, y₁/2) = (s₁/4) * D(p₁) and jensenGap(x₁, y₁) = (s₁/2) * D(p₁)
      have hsum_half_pos : 0 < x₁/2 + y₁/2 := by linarith
      rw [jensenGap_eq_scaled_binaryKL (by linarith : 0 ≤ x₁/2) (by linarith : 0 ≤ y₁/2) hsum_half_pos]
      rw [jensenGap_eq_scaled_binaryKL hx₁ hy₁ hs₁_pos]
      -- Goal: 2 * ((x₁/2 + y₁/2) / 2 * D(...)) ≤ (x₁ + y₁) / 2 * D(x₁/(x₁+y₁))
      -- Note: (x₁/2 + y₁/2) / 2 = (x₁ + y₁) / 4 and (x₁/2)/(x₁/2 + y₁/2) = x₁/(x₁+y₁)
      have hp₁_eq' : x₁ / 2 / (x₁ / 2 + y₁ / 2) = x₁ / (x₁ + y₁) := by field_simp
      rw [hp₁_eq']
      -- Now: 2 * ((x₁/2 + y₁/2) / 2 * D(x₁/(x₁+y₁))) ≤ (x₁+y₁) / 2 * D(x₁/(x₁+y₁))
      have hsimp : (x₁ / 2 + y₁ / 2) / 2 = (x₁ + y₁) / 4 := by ring
      rw [hsimp]
      -- Now: 2 * ((x₁+y₁)/4 * D(...)) ≤ (x₁+y₁)/2 * D(...)
      linarith

  by_cases hs₁_zero : s₁ = 0
  · -- If s₁ = 0, then x₁ = y₁ = 0, so jensenGap(x₁, y₁) = 0
    have hx₁_zero : x₁ = 0 := by linarith
    have hy₁_zero : y₁ = 0 := by linarith
    rw [hx₁_zero, hy₁_zero]
    simp only [add_zero, jensenGap_self]
    -- Unfold xbar, ybar to get explicit expressions
    simp only [hxbar, hybar, hx₁_zero, hy₁_zero, add_zero]
    -- Now goal is: 2 * jensenGap (x₀/2) (y₀/2) ≤ jensenGap x₀ y₀
    have hs₀_pos : 0 < s₀ := by
      rcases hx₀.lt_or_eq with h | h
      · linarith
      · -- h : 0 = x₀, so x₀ = 0
        have hx₀_eq : x₀ = 0 := h.symm
        simp only [hs₀, hx₀_eq, zero_add] at hs₀_zero
        linarith [hy₀.lt_of_ne' hs₀_zero]
    have hsum_half_pos₀ : 0 < x₀/2 + y₀/2 := by linarith
    rw [jensenGap_eq_scaled_binaryKL (by linarith : 0 ≤ x₀/2) (by linarith : 0 ≤ y₀/2) hsum_half_pos₀]
    rw [jensenGap_eq_scaled_binaryKL hx₀ hy₀ hs₀_pos]
    -- Similar simplification as the s₁ case
    have hp₀_eq' : x₀ / 2 / (x₀ / 2 + y₀ / 2) = x₀ / (x₀ + y₀) := by field_simp
    rw [hp₀_eq']
    have hsimp₀ : (x₀ / 2 + y₀ / 2) / 2 = (x₀ + y₀) / 4 := by ring
    rw [hsimp₀]
    linarith

  -- Main case: s₀ > 0 and s₁ > 0
  have hs₀_pos : 0 < s₀ := by
    rcases hx₀.lt_or_eq with h | h
    · linarith
    · have hx₀_eq : x₀ = 0 := h.symm
      simp only [hs₀, hx₀_eq, zero_add] at hs₀_zero
      linarith [hy₀.lt_of_ne' hs₀_zero]
  have hs₁_pos : 0 < s₁ := by
    rcases hx₁.lt_or_eq with h | h
    · linarith
    · have hx₁_eq : x₁ = 0 := h.symm
      simp only [hs₁, hx₁_eq, zero_add] at hs₁_zero
      linarith [hy₁.lt_of_ne' hs₁_zero]
  have hsbar_pos : 0 < sbar := by rw [hsbar_eq]; linarith

  -- Define the probabilities
  set p₀ := x₀ / s₀ with hp₀_def
  set p₁ := x₁ / s₁ with hp₁_def
  set pbar := xbar / sbar with hpbar_def

  -- p₀, p₁ ∈ [0, 1]
  have hp₀_mem : p₀ ∈ Set.Icc (0 : ℝ) 1 := by
    constructor
    · exact div_nonneg hx₀ (le_of_lt hs₀_pos)
    · rw [div_le_one hs₀_pos]; linarith
  have hp₁_mem : p₁ ∈ Set.Icc (0 : ℝ) 1 := by
    constructor
    · exact div_nonneg hx₁ (le_of_lt hs₁_pos)
    · rw [div_le_one hs₁_pos]; linarith

  -- Define the weights
  set w₀ := s₀ / (s₀ + s₁) with hw₀_def
  set w₁ := s₁ / (s₀ + s₁) with hw₁_def

  have hw₀_nonneg : 0 ≤ w₀ := div_nonneg (le_of_lt hs₀_pos) (by linarith)
  have hw₁_nonneg : 0 ≤ w₁ := div_nonneg (le_of_lt hs₁_pos) (by linarith)
  have hs_sum_ne : s₀ + s₁ ≠ 0 := by linarith
  have hw_sum : w₀ + w₁ = 1 := by
    simp only [hw₀_def, hw₁_def]
    rw [← add_div, div_self hs_sum_ne]

  -- Key: pbar is a weighted average of p₀ and p₁
  have hs₀_ne : s₀ ≠ 0 := ne_of_gt hs₀_pos
  have hs₁_ne : s₁ ≠ 0 := ne_of_gt hs₁_pos
  have hpbar_eq : pbar = w₀ * p₀ + w₁ * p₁ := by
    have hLHS : pbar = (x₀ + x₁) / (s₀ + s₁) := by
      simp only [hpbar_def, hxbar, hsbar_eq]
      field_simp [hs_sum_ne]
    have hw₀p₀ : w₀ * p₀ = x₀ / (s₀ + s₁) := by
      simp only [hw₀_def, hp₀_def]
      field_simp [hs₀_ne, hs_sum_ne]
    have hw₁p₁ : w₁ * p₁ = x₁ / (s₀ + s₁) := by
      simp only [hw₁_def, hp₁_def]
      field_simp [hs₁_ne, hs_sum_ne]
    rw [hLHS, hw₀p₀, hw₁p₁, ← add_div]

  -- Express jensenGaps using binaryKLfromUniform
  have hxbar_nonneg : 0 ≤ xbar := by simp only [hxbar]; linarith
  have hybar_nonneg : 0 ≤ ybar := by simp only [hybar]; linarith

  rw [jensenGap_eq_scaled_binaryKL hxbar_nonneg hybar_nonneg hsbar_pos]
  rw [jensenGap_eq_scaled_binaryKL hx₀ hy₀ hs₀_pos]
  rw [jensenGap_eq_scaled_binaryKL hx₁ hy₁ hs₁_pos]

  -- Simplify sbar and pbar
  have hsbar_simp : sbar = (s₀ + s₁) / 2 := hsbar_eq
  have hpbar_simp : xbar / sbar = pbar := by
    simp only [hpbar_def, hxbar, hsbar_eq, hs₀, hs₁]

  -- First replace xbar + ybar with sbar, then apply simplifications
  simp only [← hsbar]
  rw [hpbar_simp, hsbar_simp]

  -- Now we have: 2 * ((s₀+s₁)/2 / 2) * D(pbar) ≤ (s₀/2) * D(p₀) + (s₁/2) * D(p₁)
  -- Which simplifies to: ((s₀+s₁)/2) * D(pbar) ≤ (s₀/2) * D(p₀) + (s₁/2) * D(p₁)

  have hLHS_simp : 2 * ((s₀ + s₁) / 2 / 2 * binaryKLfromUniform pbar) =
                   ((s₀ + s₁) / 2) * binaryKLfromUniform pbar := by ring
  rw [hLHS_simp]

  -- Apply convexity: D(pbar) ≤ w₀ * D(p₀) + w₁ * D(p₁)
  have hconv := binaryKLfromUniform_weighted_le hp₀_mem hp₁_mem hw₀_nonneg hw₁_nonneg hw_sum
  rw [← hpbar_eq] at hconv

  -- Multiply by ((s₀ + s₁) / 2)
  have hscale : ((s₀ + s₁) / 2) * binaryKLfromUniform pbar ≤
                ((s₀ + s₁) / 2) * (w₀ * binaryKLfromUniform p₀ + w₁ * binaryKLfromUniform p₁) := by
    apply mul_le_mul_of_nonneg_left hconv
    linarith

  calc ((s₀ + s₁) / 2) * binaryKLfromUniform pbar
      ≤ ((s₀ + s₁) / 2) * (w₀ * binaryKLfromUniform p₀ + w₁ * binaryKLfromUniform p₁) := hscale
    _ = ((s₀ + s₁) / 2) * w₀ * binaryKLfromUniform p₀ +
        ((s₀ + s₁) / 2) * w₁ * binaryKLfromUniform p₁ := by ring
    _ = (s₀ / 2) * binaryKLfromUniform p₀ + (s₁ / 2) * binaryKLfromUniform p₁ := by
        simp only [hw₀_def, hw₁_def]; field_simp

/-- Two-point entropy is jointly convex: the midpoint inequality.

This is the key lemma for Han's inequality. For nonnegative a₀, a₁, b₀, b₁:
  twoPointEnt((a₀+a₁)/2, (b₀+b₁)/2) ≤ (twoPointEnt(a₀,b₀) + twoPointEnt(a₁,b₁))/2 -/
theorem twoPointEnt_midpoint_convex (a₀ a₁ b₀ b₁ : ℝ)
    (ha₀ : 0 ≤ a₀) (ha₁ : 0 ≤ a₁) (hb₀ : 0 ≤ b₀) (hb₁ : 0 ≤ b₁) :
    twoPointEnt ((a₀ + a₁) / 2) ((b₀ + b₁) / 2) ≤
    (twoPointEnt a₀ b₀ + twoPointEnt a₁ b₁) / 2 := by
  -- Rewrite in terms of Jensen gap
  rw [twoPointEnt_eq_jensenGap, twoPointEnt_eq_jensenGap, twoPointEnt_eq_jensenGap]
  -- Apply the joint convexity of Jensen gap
  have h := jensenGap_joint_convex a₀ a₁ b₀ b₁ ha₀ ha₁ hb₀ hb₁
  -- h: 2 * jensenGap ((a₀+a₁)/2) ((b₀+b₁)/2) ≤ jensenGap a₀ b₀ + jensenGap a₁ b₁
  linarith

/-- Sum of two-point entropies is nonnegative -/
theorem sum_twoPointEntropyCoord_nonneg {n : ℕ} (h : (Fin n → Bool) → ℝ)
    (ε : Fin n → Bool) :
    0 ≤ ∑ j : Fin n, twoPointEntropyCoord j h ε := by
  apply Finset.sum_nonneg
  intro j _
  exact twoPointEntropyCoord_nonneg j h ε

/-!
### Helper Lemmas for Han's Inequality

These lemmas establish the key relationships for the inductive step.
-/

/-- twoPointEntropyLast of h² equals twoPointEnt of the squared values -/
theorem twoPointEntropyLast_hsq_eq {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) :
    twoPointEntropyLast (fun ε => (h ε)^2) ε' =
    twoPointEnt ((h (Fin.snoc ε' true))^2) ((h (Fin.snoc ε' false))^2) := by
  simp only [twoPointEntropyLast, twoPointEnt]

/-- twoPointEntropyCoord at last coordinate equals twoPointEntropyLast -/
theorem twoPointEntropyCoord_last_eq_twoPointEntropyLast {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ)
    (ε' : Fin n → Bool) (b : Bool) :
    twoPointEntropyCoord (Fin.last n) h (Fin.snoc ε' b) =
    twoPointEnt ((h (Fin.snoc ε' true))^2) ((h (Fin.snoc ε' false))^2) := by
  simp only [twoPointEntropyCoord, twoPointEnt]
  cases b <;> simp only [flipCoord_last_snoc, Bool.not_true, Bool.not_false]
  -- Both goals are equal by commutativity of + (order of true/false swapped)
  all_goals simp only [add_comm (h (Fin.snoc ε' true) ^ 2 * _), add_comm (h (Fin.snoc ε' true) ^ 2)]

/-- Average of twoPointEntropyCoord at last coordinate over b equals E[twoPointEntropyLast (h²)] -/
theorem avg_twoPointEntropyCoord_last {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) :
    (twoPointEntropyCoord (Fin.last n) h (Fin.snoc ε' true) +
     twoPointEntropyCoord (Fin.last n) h (Fin.snoc ε' false)) / 2 =
    twoPointEntropyLast (fun ε => (h ε)^2) ε' := by
  rw [twoPointEntropyCoord_last_eq_twoPointEntropyLast h ε' true]
  rw [twoPointEntropyCoord_last_eq_twoPointEntropyLast h ε' false]
  rw [twoPointEntropyLast_hsq_eq]
  ring

/-- Slice function: h restricted to last coordinate being true -/
def sliceTrue {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) : (Fin n → Bool) → ℝ :=
  fun ε' => h (Fin.snoc ε' true)

/-- Slice function: h restricted to last coordinate being false -/
def sliceFalse {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) : (Fin n → Bool) → ℝ :=
  fun ε' => h (Fin.snoc ε' false)

/-- twoPointEntropyCoord at castSucc j equals the coord for the slice -/
theorem twoPointEntropyCoord_castSucc_eq_slice {n : ℕ} (j : Fin n)
    (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) (b : Bool) :
    twoPointEntropyCoord (Fin.castSucc j) h (Fin.snoc ε' b) =
    twoPointEntropyCoord j (if b then sliceTrue h else sliceFalse h) ε' := by
  cases b
  · -- false case: if false = true then ... else ... becomes sliceFalse
    simp only [twoPointEntropyCoord, flipCoord_castSucc_snoc, sliceFalse,
               Bool.false_eq_true, if_false]
  · -- true case: if true = true then ... else ... becomes sliceTrue
    simp only [twoPointEntropyCoord, flipCoord_castSucc_snoc, sliceTrue, if_true]

/-- Average of twoPointEntropyCoord at castSucc j equals average of slices -/
theorem avg_twoPointEntropyCoord_castSucc {n : ℕ} (j : Fin n)
    (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) :
    (twoPointEntropyCoord (Fin.castSucc j) h (Fin.snoc ε' true) +
     twoPointEntropyCoord (Fin.castSucc j) h (Fin.snoc ε' false)) / 2 =
    (twoPointEntropyCoord j (sliceTrue h) ε' + twoPointEntropyCoord j (sliceFalse h) ε') / 2 := by
  rw [twoPointEntropyCoord_castSucc_eq_slice j h ε' true]
  rw [twoPointEntropyCoord_castSucc_eq_slice j h ε' false]
  simp only [if_true, Bool.false_eq_true, if_false]

/-- The conditional mean sqrt function: g such that g² = condMeanLast h² -/
def condMeanSqrt {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) : (Fin n → Bool) → ℝ :=
  fun ε' => sqrt ((h (Fin.snoc ε' true))^2 + (h (Fin.snoc ε' false))^2) / sqrt 2

/-- condMeanSqrt is always nonnegative (it's a ratio of square roots) -/
theorem condMeanSqrt_nonneg {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ)
    (ε' : Fin n → Bool) : 0 ≤ condMeanSqrt h ε' := by
  unfold condMeanSqrt
  apply div_nonneg (sqrt_nonneg _) (sqrt_nonneg _)

/-- Key: condMeanLast h² = (condMeanSqrt h)² -/
theorem condMeanLast_eq_condMeanSqrt_sq {n : ℕ} (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) :
    condMeanLast (fun ε => (h ε)^2) ε' = (condMeanSqrt h ε')^2 := by
  unfold condMeanLast condMeanSqrt
  simp only [div_pow, sq_sqrt (by positivity : (0:ℝ) ≤ 2)]
  have hsum_nn : 0 ≤ (h (Fin.snoc ε' true))^2 + (h (Fin.snoc ε' false))^2 := by positivity
  rw [sq_sqrt hsum_nn]

/-- Joint convexity bound for twoPointEntropyCoord applied to condMeanSqrt -/
theorem twoPointEntropyCoord_condMeanSqrt_le {n : ℕ} (j : Fin n)
    (h : (Fin (n+1) → Bool) → ℝ) (ε' : Fin n → Bool) :
    twoPointEntropyCoord j (condMeanSqrt h) ε' ≤
    (twoPointEntropyCoord j (sliceTrue h) ε' + twoPointEntropyCoord j (sliceFalse h) ε') / 2 := by
  -- Use joint convexity of twoPointEnt
  unfold twoPointEntropyCoord
  set a₀ := (sliceTrue h ε')^2 with ha₀
  set a₁ := (sliceTrue h (flipCoord j ε'))^2 with ha₁
  set b₀ := (sliceFalse h ε')^2 with hb₀
  set b₁ := (sliceFalse h (flipCoord j ε'))^2 with hb₁
  have ha₀_nn : 0 ≤ a₀ := sq_nonneg _
  have ha₁_nn : 0 ≤ a₁ := sq_nonneg _
  have hb₀_nn : 0 ≤ b₀ := sq_nonneg _
  have hb₁_nn : 0 ≤ b₁ := sq_nonneg _
  -- condMeanSqrt h ε' squared equals (a₀ + b₀)/2
  have hcond_sq : (condMeanSqrt h ε')^2 = (a₀ + b₀) / 2 := by
    unfold condMeanSqrt
    simp only [div_pow, sq_sqrt (by positivity : (0:ℝ) ≤ 2)]
    have hsum_nn : 0 ≤ (h (Fin.snoc ε' true))^2 + (h (Fin.snoc ε' false))^2 := by positivity
    rw [sq_sqrt hsum_nn]
    simp only [sliceTrue, sliceFalse] at ha₀ hb₀
    rw [← ha₀, ← hb₀]
  have hcond_flip_sq : (condMeanSqrt h (flipCoord j ε'))^2 = (a₁ + b₁) / 2 := by
    unfold condMeanSqrt
    simp only [div_pow, sq_sqrt (by positivity : (0:ℝ) ≤ 2)]
    have hsum_nn : 0 ≤ (h (Fin.snoc (flipCoord j ε') true))^2 +
                       (h (Fin.snoc (flipCoord j ε') false))^2 := by positivity
    rw [sq_sqrt hsum_nn]
    simp only [sliceTrue, sliceFalse] at ha₁ hb₁
    rw [← ha₁, ← hb₁]
  rw [hcond_sq, hcond_flip_sq]
  -- Now apply twoPointEnt_midpoint_convex
  have h_conv := twoPointEnt_midpoint_convex a₀ b₀ a₁ b₁ ha₀_nn hb₀_nn ha₁_nn hb₁_nn
  -- h_conv: twoPointEnt ((a₀+b₀)/2) ((a₁+b₁)/2) ≤ (twoPointEnt a₀ a₁ + twoPointEnt b₀ b₁) / 2
  convert h_conv using 2

/-- Han's inequality for the hypercube: entropy is bounded by sum of conditional entropies.

This is the key subadditivity result. For independent coordinates with product measure:
  Ent(f) ≤ Σᵢ E[Ent^(i)(f)]

For f = h² on the hypercube, Ent^(i)(f) = twoPointEntropyCoord i h.

The proof uses the chain rule for entropy and the data processing inequality. -/
theorem han_inequality {n : ℕ} (h : (Fin n → Bool) → ℝ) :
    LogSobolev.entropy (bernoulliUniform n) (fun ε => (h ε)^2) ≤
    ∑ j : Fin n, ∫ ε, twoPointEntropyCoord j h ε ∂(bernoulliUniform n) := by
  -- Proof by induction on n
  induction n with
  | zero =>
    -- For n = 0, both sides are 0
    simp only [Finset.univ_eq_empty, Finset.sum_empty]
    -- LHS: entropy of constant function = 0
    have hconst : ∀ ε₁ ε₂ : Fin 0 → Bool, ε₁ = ε₂ := fun ε₁ ε₂ => by
      ext i; exact Fin.elim0 i
    have hval : ∃ c, ∀ ε, (h ε)^2 = c := ⟨(h default)^2, fun ε => by rw [hconst ε default]⟩
    obtain ⟨c, hc⟩ := hval
    simp only [hc]
    exact le_of_eq (LogSobolev.entropy_const (bernoulliUniform 0) c)
  | succ n ih =>
    -- For n+1, use chain rule decomposition
    -- Ent_{n+1}(h²) = E[twoPointEntropyLast (h²)] + Ent_n(condMeanLast (h²))

    -- Define the squared function
    set f := fun ε => (h ε)^2

    -- Step 1: Apply chain rule
    have hchain := entropy_chain_rule_succ f

    -- Step 2: Relate first term to twoPointEntropyCoord at last
    -- E[twoPointEntropyLast f] = E[twoPointEntropyCoord (last n) h]
    have hfirst : ∫ ε', twoPointEntropyLast f ε' ∂(bernoulliUniform n) =
        ∫ ε, twoPointEntropyCoord (Fin.last n) h ε ∂(bernoulliUniform (n+1)) := by
      rw [bernoulli_integral_succ_split]
      congr 1
      ext ε'
      rw [← avg_twoPointEntropyCoord_last h ε']

    -- Step 3: Relate condMeanLast f to (condMeanSqrt h)²
    have hcond_eq : condMeanLast f = fun ε' => (condMeanSqrt h ε')^2 := by
      ext ε'
      exact condMeanLast_eq_condMeanSqrt_sq h ε'

    -- Step 4: Apply IH to condMeanSqrt h (no nonnegativity hypothesis needed)
    have hih := ih (condMeanSqrt h)

    -- Step 5: Use convexity bound
    -- twoPointEntropyCoord j (condMeanSqrt h) ≤ (twoPointEntropyCoord j hT + ... hF)/2
    have hconv_bound : ∀ j : Fin n,
        ∫ ε', twoPointEntropyCoord j (condMeanSqrt h) ε' ∂(bernoulliUniform n) ≤
        ∫ ε, twoPointEntropyCoord (Fin.castSucc j) h ε ∂(bernoulliUniform (n+1)) := by
      intro j
      -- Pointwise bound from joint convexity
      have hpw : ∀ ε', twoPointEntropyCoord j (condMeanSqrt h) ε' ≤
          (twoPointEntropyCoord j (sliceTrue h) ε' +
           twoPointEntropyCoord j (sliceFalse h) ε') / 2 :=
        twoPointEntropyCoord_condMeanSqrt_le j h
      -- Integrate
      calc ∫ ε', twoPointEntropyCoord j (condMeanSqrt h) ε' ∂(bernoulliUniform n)
          ≤ ∫ ε', (twoPointEntropyCoord j (sliceTrue h) ε' +
                   twoPointEntropyCoord j (sliceFalse h) ε') / 2 ∂(bernoulliUniform n) := by
            apply integral_mono_of_nonneg
            · apply Eventually.of_forall; intro ε'
              exact twoPointEntropyCoord_nonneg j (condMeanSqrt h) ε'
            · exact Integrable.of_finite
            · exact Eventually.of_forall hpw
        _ = (∫ ε', twoPointEntropyCoord j (sliceTrue h) ε' ∂(bernoulliUniform n) +
             ∫ ε', twoPointEntropyCoord j (sliceFalse h) ε' ∂(bernoulliUniform n)) / 2 := by
            rw [integral_div, integral_add (Integrable.of_finite) (Integrable.of_finite)]
        _ = ∫ ε, twoPointEntropyCoord (Fin.castSucc j) h ε ∂(bernoulliUniform (n+1)) := by
            rw [bernoulli_integral_succ_split]
            -- Goal: (∫ sliceTrue + ∫ sliceFalse) / 2 = ∫ (castSucc true + castSucc false) / 2
            -- First simplify LHS
            have h_sliceTrue : ∫ ε', twoPointEntropyCoord j (sliceTrue h) ε' ∂(bernoulliUniform n) =
                ∫ ε', twoPointEntropyCoord (Fin.castSucc j) h (Fin.snoc ε' true) ∂(bernoulliUniform n) := by
              apply integral_congr_ae
              filter_upwards with ε'
              rw [twoPointEntropyCoord_castSucc_eq_slice j h ε' true]
              simp only [ite_true]
            have h_sliceFalse : ∫ ε', twoPointEntropyCoord j (sliceFalse h) ε' ∂(bernoulliUniform n) =
                ∫ ε', twoPointEntropyCoord (Fin.castSucc j) h (Fin.snoc ε' false) ∂(bernoulliUniform n) := by
              apply integral_congr_ae
              filter_upwards with ε'
              rw [twoPointEntropyCoord_castSucc_eq_slice j h ε' false]
              simp only [Bool.false_eq_true, ↓reduceIte]
            rw [h_sliceTrue, h_sliceFalse]
            rw [← integral_add Integrable.of_finite Integrable.of_finite]
            rw [integral_div]

    -- Step 6: Sum over j < n
    have hsum_bound : ∑ j : Fin n, ∫ ε', twoPointEntropyCoord j (condMeanSqrt h) ε' ∂(bernoulliUniform n) ≤
        ∑ j : Fin n, ∫ ε, twoPointEntropyCoord (Fin.castSucc j) h ε ∂(bernoulliUniform (n+1)) := by
      apply Finset.sum_le_sum
      intro j _
      exact hconv_bound j

    -- Step 7: Combine everything
    calc LogSobolev.entropy (bernoulliUniform (n + 1)) f
        = ∫ ε', twoPointEntropyLast f ε' ∂(bernoulliUniform n) +
          LogSobolev.entropy (bernoulliUniform n) (condMeanLast f) := hchain
      _ = ∫ ε, twoPointEntropyCoord (Fin.last n) h ε ∂(bernoulliUniform (n+1)) +
          LogSobolev.entropy (bernoulliUniform n) (fun ε' => (condMeanSqrt h ε')^2) := by
          rw [hfirst, hcond_eq]
      _ ≤ ∫ ε, twoPointEntropyCoord (Fin.last n) h ε ∂(bernoulliUniform (n+1)) +
          ∑ j : Fin n, ∫ ε', twoPointEntropyCoord j (condMeanSqrt h) ε' ∂(bernoulliUniform n) := by
          exact add_le_add_right hih _
      _ ≤ ∫ ε, twoPointEntropyCoord (Fin.last n) h ε ∂(bernoulliUniform (n+1)) +
          ∑ j : Fin n, ∫ ε, twoPointEntropyCoord (Fin.castSucc j) h ε ∂(bernoulliUniform (n+1)) := by
          exact add_le_add_right hsum_bound _
      _ = ∑ j : Fin (n+1), ∫ ε, twoPointEntropyCoord j h ε ∂(bernoulliUniform (n+1)) := by
          -- Split sum over Fin (n+1) into castSucc terms plus last term
          rw [Fin.sum_univ_castSucc]
          ring

/-- The main subadditivity bound combining Han's inequality with Rothaus -/
theorem entropy_le_half_gradient {n : ℕ} (h : (Fin n → Bool) → ℝ) :
    LogSobolev.entropy (bernoulliUniform n) (fun ε => (h ε)^2) ≤
    (1/2) * ∫ ε, gradientNormSq n h ε ∂(bernoulliUniform n) := by
  calc LogSobolev.entropy (bernoulliUniform n) (fun ε => (h ε)^2)
      ≤ ∑ j : Fin n, ∫ ε, twoPointEntropyCoord j h ε ∂(bernoulliUniform n) := by
        exact han_inequality h
    _ ≤ ∑ j : Fin n, ∫ ε, (h ε - h (flipCoord j ε))^2 / 2 ∂(bernoulliUniform n) := by
        apply Finset.sum_le_sum
        intro j _
        exact avg_twoPointEntropyCoord_le j h
    _ = ∫ ε, ∑ j : Fin n, (h ε - h (flipCoord j ε))^2 / 2 ∂(bernoulliUniform n) := by
        rw [← integral_finset_sum]
        intro j _
        exact Integrable.of_finite
    _ = ∫ ε, (∑ j : Fin n, (h ε - h (flipCoord j ε))^2) / 2 ∂(bernoulliUniform n) := by
        congr 1
        ext ε
        rw [Finset.sum_div]
    _ = (1/2) * ∫ ε, ∑ j : Fin n, (h ε - h (flipCoord j ε))^2 ∂(bernoulliUniform n) := by
        rw [← integral_const_mul]
        congr 1
        ext ε
        ring
    _ = (1/2) * ∫ ε, gradientNormSq n h ε ∂(bernoulliUniform n) := by
        rfl

/-!
## Part 6: Main Theorem - Bernoulli Log-Sobolev Inequality
-/

/-- The Bernoulli log-Sobolev inequality (Theorem 5.1).

For any function h : {±1}^n → ℝ,
  Ent_μ(h²) ≤ (1/2) · E_μ[Σⱼ (h(ε) - h(flip_j ε))²]

where μ is the uniform measure on the hypercube.

Note: The nonnegativity hypothesis was removed using the reverse triangle inequality
to show that (|h(ε)| - |h(flip_j ε)|)² ≤ (h(ε) - h(flip_j ε))². -/
theorem bernoulli_logSobolev (n : ℕ) (h : (Fin n → Bool) → ℝ) :
    LogSobolev.entropy (bernoulliUniform n) (fun ε => (h ε)^2) ≤
    (1/2) * ∫ ε, gradientNormSq n h ε ∂(bernoulliUniform n) :=
  -- Direct application of entropy_le_half_gradient
  entropy_le_half_gradient h

/-!
## Part 7: Application to Compactly Supported Smooth Functions

This section connects the Bernoulli log-Sobolev inequality on the Boolean hypercube
to compactly supported smooth functions via the Rademacher sum formulation.
-/

open EfronSteinApp GaussianPoincare

/-- Map from Boolean hypercube to Rademacher space: True ↦ 1, False ↦ -1. -/
def toRademacher {n : ℕ} (ε : Fin n → Bool) : RademacherSpace n :=
  fun i => signValue (ε i)

/-- The inverse map: 1 ↦ True, -1 ↦ False (partial, defined on support). -/
def fromRademacher {n : ℕ} (x : RademacherSpace n)
    (_hx : ∀ i, x i = 1 ∨ x i = -1) : Fin n → Bool :=
  fun i => (x i = 1)

/-- toRademacher is injective -/
theorem toRademacher_injective (n : ℕ) : Function.Injective (toRademacher (n := n)) := by
  intro ε₁ ε₂ h
  ext i
  have hi : signValue (ε₁ i) = signValue (ε₂ i) := congrFun h i
  cases hb₁ : ε₁ i <;> cases hb₂ : ε₂ i <;> simp_all [signValue]
  · norm_num at hi
  · norm_num at hi

/-- Flipping coordinate j on Bool corresponds to negating coordinate j on Rademacher space -/
theorem toRademacher_flipCoord {n : ℕ} (j : Fin n) (ε : Fin n → Bool) :
    toRademacher (flipCoord j ε) = Function.update (toRademacher ε) j (-(toRademacher ε j)) := by
  ext i
  simp only [toRademacher, Function.update]
  by_cases h : i = j
  · subst h
    simp only [flipCoord_same, signValue_not, dif_pos]
  · simp only [dif_neg h]
    rw [flipCoord_noteq j i ε h]

/-- The Rademacher sum after coordinate flip equals the shifted sum -/
theorem rademacherSumProd_flip_eq_shifted {n : ℕ} [NeZero n] (j : Fin n)
    (x : RademacherSpace n) (_hx : x j = 1 ∨ x j = -1) :
    rademacherSumProd n (Function.update x j (-x j)) = rademacherSumShifted n j x := by
  unfold rademacherSumProd rademacherSumShifted
  have hsum : ∑ i : Fin n, Function.update x j (-x j) i =
      (∑ i : Fin n, x i) - 2 * x j := by
    have h1 : Function.update x j (-x j) j = -x j := Function.update_self j (-x j) x
    have h2 : ∀ i ∈ Finset.univ, i ≠ j → Function.update x j (-x j) i = x i :=
      fun i _ hi => Function.update_of_ne hi (-x j) x
    calc ∑ i : Fin n, Function.update x j (-x j) i
        = Function.update x j (-x j) j +
            ∑ i ∈ Finset.univ.erase j, Function.update x j (-x j) i := by
          rw [Finset.sum_eq_sum_diff_singleton_add (Finset.mem_univ j)]
          simp only [Finset.sdiff_singleton_eq_erase]
          ring
      _ = -x j + ∑ i ∈ Finset.univ.erase j, x i := by
          rw [h1]
          congr 1
          apply Finset.sum_congr rfl
          intro i hi
          exact h2 i (Finset.mem_of_mem_erase hi) (Finset.ne_of_mem_erase hi)
      _ = -x j + (∑ i : Fin n, x i - x j) := by
          rw [Finset.sum_eq_sum_diff_singleton_add (Finset.mem_univ j)]
          simp only [Finset.sdiff_singleton_eq_erase, add_sub_cancel_right]
      _ = (∑ i : Fin n, x i) - 2 * x j := by ring
  rw [hsum]
  unfold rademacherSumProd
  ring

/-- toRademacher is measurable since Fin n → Bool is finite -/
theorem measurable_toRademacher {n : ℕ} : Measurable (toRademacher (n := n)) :=
  measurable_of_finite _

/-- rademacherSumProd is continuous since it's a linear combination of coordinate functions. -/
theorem continuous_rademacherSumProd (n : ℕ) : Continuous (rademacherSumProd n) := by
  unfold rademacherSumProd
  have hsum : Continuous (fun x : RademacherSpace n => ∑ i : Fin n, x i) := by
    apply continuous_finset_sum
    intro i _
    exact continuous_apply i
  exact hsum.const_smul ((√n)⁻¹)

/-- Key lemma: The bernoulliUniform measure pushes forward to rademacherProductMeasure via toRademacher. -/
theorem bernoulliUniform_map_toRademacher {n : ℕ} :
    (bernoulliUniform n).map toRademacher = rademacherProductMeasure n := by
  -- Both measures are probability measures supported on {±1}^n with equal weights
  -- We prove equality by showing they agree on all measurable rectangles
  ext s hs
  -- Use induction on n via product measure structure
  induction n with
  | zero =>
    -- For n = 0, both spaces are singletons
    simp only [bernoulliUniform, rademacherProductMeasure, Measure.map_apply measurable_toRademacher hs]
    -- Simplify LHS: (1⁻¹ • count) = count since 1⁻¹ = 1 in ENNReal
    simp only [Finset.card_univ, Fintype.card_fun, Fintype.card_fin, Fintype.card_bool,
      pow_zero, Nat.cast_one, inv_one, one_smul]
    -- For n = 0, Measure.pi of empty gives Dirac at the unique point
    rw [Measure.pi_of_empty (fun _ : Fin 0 => RademacherApprox.rademacherMeasure)]
    -- Now: count (toRademacher⁻¹' s) = dirac (fun _ => 1) s
    -- The unique element of Fin 0 → Bool maps to fun _ => 1 under toRademacher
    have huniq : ∀ ε : Fin 0 → Bool, toRademacher ε = fun _ : Fin 0 => (1 : ℝ) := by
      intro ε; ext i; exact Fin.elim0 i
    -- The unique element of Fin 0 → ℝ
    have helem : (fun _ : Fin 0 => (1 : ℝ)) = (fun a : Fin 0 => isEmptyElim a) := by
      ext i; exact Fin.elim0 i
    by_cases h : (fun _ : Fin 0 => (1 : ℝ)) ∈ s
    · have hpre : toRademacher⁻¹' s = Set.univ := by
        ext ε; simp only [Set.mem_preimage, Set.mem_univ, huniq ε, h]
      rw [hpre]
      simp only [Measure.count_univ]
      rw [Measure.dirac_apply' _ hs]
      have hmem : (fun a : Fin 0 => isEmptyElim a) ∈ s := by rw [← helem]; exact h
      rw [Set.indicator_of_mem hmem, Pi.one_apply]
      simp only [ENat.card_eq_coe_fintype_card, Fintype.card_fun, Fintype.card_fin,
        Fintype.card_bool, pow_zero, Nat.cast_one]
      norm_cast
    · have hpre : toRademacher⁻¹' s = ∅ := by
        ext ε; simp only [Set.mem_preimage, Set.mem_empty_iff_false, huniq ε, h]
      rw [hpre, measure_empty]
      rw [Measure.dirac_apply' _ hs]
      have hnotmem : (fun a : Fin 0 => isEmptyElim a) ∉ s := by rw [← helem]; exact h
      simp only [Set.indicator_of_notMem hnotmem]
  | succ n ih =>
    -- Both measures are discrete probability measures with equal weights on {±1}^{n+1}
    -- Expand the LHS using map_apply
    simp only [Measure.map_apply measurable_toRademacher hs]
    -- Now: bernoulliUniform (n+1) (toRademacher⁻¹' s) = rademacherProductMeasure (n+1) s
    unfold bernoulliUniform
    simp only [Finset.card_univ, Fintype.card_fun, Fintype.card_fin, Fintype.card_bool,
      Measure.smul_apply, smul_eq_mul]
    -- Rewrite using count on finite preimage
    rw [Measure.count_apply (measurable_toRademacher hs)]
    -- Step 1: Show (rademacherProductMeasure (n+1)) {toRademacher ε} = 2^{-(n+1)} for each ε
    have hsingleton : ∀ ε : Fin (n+1) → Bool,
        (rademacherProductMeasure (n+1)) {toRademacher ε} = ((2 : ℝ≥0∞)^(n+1))⁻¹ := by
      intro ε
      rw [← Set.univ_pi_singleton (toRademacher ε)]
      unfold rademacherProductMeasure
      rw [Measure.pi_pi (fun _ => RademacherApprox.rademacherMeasure)]
      -- Each factor is rademacherMeasure {toRademacher ε i} = 1/2
      have h_each : ∀ i : Fin (n+1), RademacherApprox.rademacherMeasure {toRademacher ε i} = 1/2 := by
        intro i
        unfold toRademacher signValue RademacherApprox.rademacherMeasure
        simp only [Measure.coe_add, Measure.coe_smul, Pi.add_apply, Pi.smul_apply, smul_eq_mul]
        rw [Measure.dirac_apply' _ (measurableSet_singleton _)]
        rw [Measure.dirac_apply' _ (measurableSet_singleton _)]
        simp only [Set.indicator_apply, Set.mem_singleton_iff]
        by_cases hb : ε i
        · -- Case ε i = true, so value is 1
          simp only [hb]
          norm_num
        · -- Case ε i = false, so value is -1
          simp only [hb]
          norm_num
      simp_rw [h_each]
      simp only [Finset.prod_const, Finset.card_univ, Fintype.card_fin]
      -- (1/2)^(n+1) = (2^{n+1})⁻¹
      simp only [one_div, ENNReal.inv_pow]
    -- Key: Show that toRademacher is a bijection onto the support of rademacherProductMeasure
    -- and both measures assign weight 2^{-(n+1)} to each point
    have hrange_char : ∀ x : RademacherSpace (n+1),
        x ∈ Set.range toRademacher ↔ ∀ i, x i = 1 ∨ x i = -1 := by
      intro x
      constructor
      · rintro ⟨ε, rfl⟩ i
        unfold toRademacher signValue
        by_cases h : ε i <;> simp [h]
      · intro hx
        -- Construct the preimage
        use fun i => x i = 1
        ext i
        unfold toRademacher signValue
        simp only []
        cases hx i with
        | inl h => simp [h]
        | inr h => simp only [h, decide_eq_false (by linarith : ¬(-1 : ℝ) = 1)]; rfl
    -- The measure is concentrated on the range
    have hsupp : (rademacherProductMeasure (n+1)) (Set.range toRademacher)ᶜ = 0 := by
      -- Every coordinate is ±1 a.e., so a.e. x is in range
      have hae : ∀ᵐ x ∂(rademacherProductMeasure (n+1)), x ∈ Set.range toRademacher := by
        -- Use hrange_char: x ∈ range ↔ ∀ i, x i = 1 ∨ x i = -1
        simp only [hrange_char]
        -- Need to show: ∀ᵐ x, ∀ i, x i = 1 ∨ x i = -1
        rw [ae_all_iff]
        intro i
        exact coord_values_ae (n+1) i
      -- If a.e. x ∈ S, then μ(Sᶜ) = 0
      exact mem_ae_iff.mp hae
    have hsum : (rademacherProductMeasure (n+1)) s =
        ∑ ε : Fin (n+1) → Bool, (rademacherProductMeasure (n+1)) (s ∩ {toRademacher ε}) := by
      -- μ s = μ (s ∩ range) = ∑_{ε} μ (s ∩ {toRademacher ε})
      have heq : (rademacherProductMeasure (n+1)) s =
          (rademacherProductMeasure (n+1)) (s ∩ Set.range toRademacher) := by
        rw [← measure_inter_add_diff s (Set.finite_range toRademacher).measurableSet]
        have h0 : (rademacherProductMeasure (n+1)) (s \ Set.range toRademacher) = 0 := by
          apply measure_mono_null (Set.diff_subset_compl _ _) hsupp
        rw [h0, add_zero]
      rw [heq]
      -- range toRademacher = ⋃ ε, {toRademacher ε}
      have hrange_eq : Set.range toRademacher =
          ⋃ ε : Fin (n+1) → Bool, {toRademacher ε} := by
        ext x; simp only [Set.mem_range, Set.mem_iUnion, Set.mem_singleton_iff, eq_comm]
      rw [hrange_eq, Set.inter_iUnion]
      rw [measure_iUnion]
      · exact tsum_fintype _
      · -- Disjoint singletons
        intro i j hij
        simp only [Set.disjoint_iff]
        intro x ⟨h1, h2⟩
        simp only [Set.mem_inter_iff, Set.mem_singleton_iff] at h1 h2
        have heq : toRademacher i = toRademacher j := h1.2.symm.trans h2.2
        exact hij (toRademacher_injective (n+1) heq)
      · -- Measurable singletons
        intro i
        exact hs.inter (measurableSet_singleton _)
    -- Now compute each term: μ(s ∩ {toRademacher ε}) = indicator(toRademacher ε ∈ s) * 2^{-(n+1)}
    have hterm : ∀ ε : Fin (n+1) → Bool, (rademacherProductMeasure (n+1)) (s ∩ {toRademacher ε}) =
        Set.indicator s (fun _ => ((2 : ℝ≥0∞)^(n+1))⁻¹) (toRademacher ε) := by
      intro ε
      by_cases h : toRademacher ε ∈ s
      · have heq : s ∩ {toRademacher ε} = {toRademacher ε} := by
          ext x; simp only [Set.mem_inter_iff, Set.mem_singleton_iff]
          constructor
          · exact And.right
          · intro hx; exact ⟨hx ▸ h, hx⟩
        rw [heq, hsingleton, Set.indicator_of_mem h]
      · have heq : s ∩ {toRademacher ε} = ∅ := by
          ext x; simp only [Set.mem_inter_iff, Set.mem_singleton_iff, Set.mem_empty_iff_false,
            iff_false, not_and]
          intro hx hxs; exact h (hxs ▸ hx)
        rw [heq, measure_empty, Set.indicator_of_notMem h]
    simp_rw [hsum, hterm]
    -- ∑ ε, indicator s _ (toRademacher ε) = 2^{-(n+1)} * |toRademacher⁻¹' s|
    haveI : DecidablePred fun i => toRademacher i ∈ s := Classical.decPred _
    rw [Finset.sum_indicator_eq_sum_filter, Finset.sum_const]
    -- Convert nsmul to mul and relate cardinalities
    rw [nsmul_eq_mul, mul_comm]
    congr 1
    -- Show (toRademacher ⁻¹' s).encard = ↑(filter card)
    · -- The filter is equivalent to the preimage
      have hfinite : (toRademacher ⁻¹' s).Finite := Set.toFinite _
      have heq_card : (Finset.filter (fun i => toRademacher i ∈ s) Finset.univ).card =
          hfinite.toFinset.card := by
        congr 1
        ext ε
        simp only [Finset.mem_filter, Finset.mem_univ, true_and, Set.Finite.mem_toFinset,
          Set.mem_preimage]
      rw [heq_card, hfinite.encard_eq_coe_toFinset_card]
      simp only [ENat.toENNReal_coe]
    -- Show (↑(2 ^ (n + 1)))⁻¹ = (2 ^ (n + 1))⁻¹
    · simp only [Nat.cast_pow, Nat.cast_ofNat, ENNReal.inv_pow]

/-- Key lemma: The integral of f(S_n(toRademacher ε)) over bernoulliUniform equals
    the integral of f(S_n(x)) over rademacherProductMeasure. -/
theorem bernoulli_integral_eq_rademacher_integral {n : ℕ} [NeZero n]
    {f : ℝ → ℝ} (hf : Continuous f) :
    ∫ ε, f (rademacherSumProd n (toRademacher ε)) ∂(bernoulliUniform n) =
    ∫ x, f (rademacherSumProd n x) ∂(rademacherProductMeasure n) := by
  -- Use the measure equality and integral_map
  rw [← bernoulliUniform_map_toRademacher]
  rw [integral_map measurable_toRademacher.aemeasurable]
  -- f ∘ rademacherSumProd is continuous hence AEStronglyMeasurable
  exact (hf.comp (continuous_rademacherSumProd n)).aestronglyMeasurable

/-- Key lemma: Entropy is preserved under the measure isomorphism. -/
theorem entropy_bernoulli_eq_rademacher {n : ℕ} [NeZero n]
    {g : RademacherSpace n → ℝ} (hg : Continuous g) :
    LogSobolev.entropy (bernoulliUniform n) (fun ε => (g (toRademacher ε))^2) =
    LogSobolev.entropy (rademacherProductMeasure n) (fun x => (g x)^2) := by
  -- Use the measure isomorphism: bernoulliUniform.map toRademacher = rademacherProductMeasure
  unfold LogSobolev.entropy
  -- The function g² is continuous, hence strongly measurable
  have hgsq : Continuous (fun x => (g x)^2) := hg.pow 2
  have hglog : Continuous (fun x => (g x)^2 * log ((g x)^2)) := hgsq.mul_log
  -- We show each integral part is equal using integral_map
  have h1 : ∫ x, (g x)^2 * log ((g x)^2) ∂(rademacherProductMeasure n) =
            ∫ ε, (g (toRademacher ε))^2 * log ((g (toRademacher ε))^2) ∂(bernoulliUniform n) := by
    rw [← bernoulliUniform_map_toRademacher]
    rw [integral_map measurable_toRademacher.aemeasurable hglog.aestronglyMeasurable]
  have h2 : ∫ x, (g x)^2 ∂(rademacherProductMeasure n) =
            ∫ ε, (g (toRademacher ε))^2 ∂(bernoulliUniform n) := by
    rw [← bernoulliUniform_map_toRademacher]
    rw [integral_map measurable_toRademacher.aemeasurable hgsq.aestronglyMeasurable]
  rw [h1, h2]

/-- Key lemma: The gradient term transforms correctly. -/
theorem gradient_eq_sum_shifted {n : ℕ} [NeZero n] {f : ℝ → ℝ} (hf : Continuous f) :
    ∫ ε, gradientNormSq n (fun ε' => f (rademacherSumProd n (toRademacher ε'))) ε
      ∂(bernoulliUniform n) =
    ∑ j : Fin n, ∫ x, (f (rademacherSumProd n x) - f (rademacherSumShifted n j x))^2
      ∂(rademacherProductMeasure n) := by
  -- Step 1: Expand gradientNormSq
  simp only [gradientNormSq]
  -- Step 2: Exchange integral and sum (integral of sum = sum of integrals for finite sums)
  rw [integral_finset_sum Finset.univ (fun j _ => Integrable.of_finite)]
  -- Step 3: For each term, show the integrand is the same after using flip-to-shifted correspondence
  congr 1
  ext j
  have hflip : ∀ ε, rademacherSumProd n (toRademacher (flipCoord j ε)) =
                   rademacherSumShifted n j (toRademacher ε) := by
    intro ε
    rw [toRademacher_flipCoord]
    apply rademacherSumProd_flip_eq_shifted
    -- Need to show toRademacher ε j = 1 ∨ toRademacher ε j = -1
    unfold toRademacher signValue
    simp only [ite_eq_left_iff, ite_eq_right_iff]
    by_cases h : ε j
    · left; simp [h]
    · right; simp [h]
  -- Rewrite the integrand
  have heq : ∀ ε, (f (rademacherSumProd n (toRademacher ε)) -
                  f (rademacherSumProd n (toRademacher (flipCoord j ε))))^2 =
                 (f (rademacherSumProd n (toRademacher ε)) -
                  f (rademacherSumShifted n j (toRademacher ε)))^2 := by
    intro ε; rw [hflip]
  simp_rw [heq]
  -- Step 4: Transfer integral from bernoulliUniform to rademacherProductMeasure
  -- Use bernoulliUniform_map_toRademacher and integral_map (in symmetric form)
  symm
  rw [← bernoulliUniform_map_toRademacher]
  -- The integrand is continuous, hence AEStronglyMeasurable
  have hcont_sum : Continuous (rademacherSumProd n) := continuous_rademacherSumProd n
  have hcont_shifted : Continuous (rademacherSumShifted n j) := by
    unfold rademacherSumShifted
    apply Continuous.sub hcont_sum
    apply Continuous.div_const
    exact continuous_const.mul (continuous_apply j)
  have hcont_integrand : Continuous (fun x => (f (rademacherSumProd n x) -
                                               f (rademacherSumShifted n j x))^2) := by
    apply Continuous.pow
    apply Continuous.sub (hf.comp hcont_sum) (hf.comp hcont_shifted)
  rw [integral_map measurable_toRademacher.aemeasurable hcont_integrand.aestronglyMeasurable]

/-- Key lemma: Entropy under pushforward for continuous functions. -/
theorem entropy_map_eq {n : ℕ} [NeZero n] {f : ℝ → ℝ} (hf : Continuous f) :
    LogSobolev.entropy (rademacherLaw n).toMeasure (fun x => (f x)^2) =
    LogSobolev.entropy (rademacherProductMeasure n) (fun x => (f (rademacherSumProd n x))^2) := by
  -- The law of S_n is the pushforward of the product measure
  -- Entropy(μ.map g)(φ) = Entropy(μ)(φ ∘ g) by the pushforward property
  unfold rademacherLaw LogSobolev.entropy
  simp only [ProbabilityMeasure.coe_mk]
  have hmeas : Measurable (rademacherSumProd n) := measurable_rademacherSumProd n
  have haem : AEMeasurable (rademacherSumProd n) (rademacherProductMeasure n) := hmeas.aemeasurable
  -- For the integrands, we need AEStronglyMeasurable
  have hfsq : Continuous (fun x => (f x)^2) := hf.pow 2
  have hlog : Continuous (fun x => (f x)^2 * Real.log ((f x)^2)) :=
    hfsq.mul_log
  -- Both integrals are over finite measures, so use integral_map
  congr 1
  · -- The f*log(f) integral
    rw [integral_map haem hlog.aestronglyMeasurable]
  · -- The mean integral
    congr 1
    · rw [integral_map haem hfsq.aestronglyMeasurable]
    · rw [integral_map haem hfsq.aestronglyMeasurable]

/-- **Application of Bernoulli Log-Sobolev to Compactly Supported Smooth Functions**

For f ∈ C_c²(ℝ) (compactly supported, twice continuously differentiable), the entropy
of f² under the law of the Rademacher sum S_{n+1} is bounded by half the expected
sum of squared differences:

  Ent_{S_{n+1}}(f²) ≤ (1/2) · ∑ᵢ E[(f(S_{n+1}) - f(S_{n+1} with coord i flipped))²]

This is the continuous-function version of the Bernoulli log-Sobolev inequality,
which serves as a key intermediate step toward the Gaussian log-Sobolev inequality
via the central limit theorem. -/
theorem bernoulli_logSobolev_app {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) (n : ℕ) :
    LogSobolev.entropy (rademacherLaw (n + 1)).toMeasure (fun x => (f x)^2) ≤
    (1/2) * ∑ i : Fin (n + 1), ∫ x,
        (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) i x))^2
          ∂rademacherProductMeasure (n + 1) := by
  -- Step 1: Transfer entropy from rademacherLaw to rademacherProductMeasure
  rw [entropy_map_eq hf.continuous]
  -- Step 2: Transfer from rademacherProductMeasure to bernoulliUniform via toRademacher
  have hg_cont : Continuous (fun x => f (rademacherSumProd (n + 1) x)) :=
    hf.continuous.comp (continuous_rademacherSumProd (n + 1))
  rw [← entropy_bernoulli_eq_rademacher hg_cont]
  -- Step 3: Apply the discrete Bernoulli log-Sobolev inequality
  have hbound := bernoulli_logSobolev (n + 1)
    (fun ε => f (rademacherSumProd (n + 1) (toRademacher ε)))
  -- Step 4: Transform the RHS to the sum of squared differences
  calc LogSobolev.entropy (bernoulliUniform (n + 1))
        (fun ε => (f (rademacherSumProd (n + 1) (toRademacher ε)))^2)
      ≤ (1/2) * ∫ ε, gradientNormSq (n + 1)
          (fun ε' => f (rademacherSumProd (n + 1) (toRademacher ε'))) ε
          ∂(bernoulliUniform (n + 1)) := hbound
    _ = (1/2) * ∑ i : Fin (n + 1), ∫ x,
          (f (rademacherSumProd (n + 1) x) - f (rademacherSumShifted (n + 1) i x))^2
            ∂rademacherProductMeasure (n + 1) := by
        rw [gradient_eq_sum_shifted hf.continuous]

end BernoulliLSI

end
