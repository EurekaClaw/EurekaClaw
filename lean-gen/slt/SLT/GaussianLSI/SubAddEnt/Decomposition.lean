/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianLSI.SubAddEnt.Basic

/-!
# Entropy Decomposition (Chain Rule)

Proves the entropy decomposition: Ent(f) = E[Ent^{(i)}(f)] + Ent(E^{(i)}[f]).

## Main Definitions

* `integralCondExpMulLog`: The integral ∫ E^{(i)}[f] · log(E^{(i)}[f]) dμ.

## Main Results

* `entropy_decomposition`: Entropy chain rule decomposition.
* `entropy_telescoping_pointwise`: Pointwise telescoping identity for entropy.
-/

open MeasureTheory ProbabilityTheory Real Set Filter

open scoped ENNReal NNReal BigOperators

noncomputable section

namespace SubAddEnt

variable {n : ℕ} {Ω : Type*} [MeasurableSpace Ω]
variable {μs : Fin n → Measure Ω} [∀ i, IsProbabilityMeasure (μs i)]

-- Product measure notation
local notation "μˢ" => Measure.pi μs

/-! ## Key Identities -/

/-- The integral ∫ E^{(i)}[f] · log(E^{(i)}[f]) dμ. -/
def integralCondExpMulLog (i : Fin n) (f : (Fin n → Ω) → ℝ) : ℝ :=
  ∫ x, condExpExceptCoord (μs := μs) i f x * log (condExpExceptCoord (μs := μs) i f x) ∂μˢ

/-!
## Entropy Decomposition
-/

/-- ∫ Ent^{(i)}(f) dμ = ∫ f log f dμ - ∫ E^{(i)}[f] · log(E^{(i)}[f]) dμ. -/
theorem integral_condEntExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ)
    (hEf_log_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
                                        log (condExpExceptCoord (μs := μs) i f x)) μˢ) :
    ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ =
    ∫ x, f x * log (f x) ∂μˢ - integralCondExpMulLog (μs := μs) i f := by
  unfold condEntExceptCoord integralCondExpMulLog
  rw [integral_sub]
  · -- Apply tower property to the first integral
    rw [integral_condExpExceptCoord_mul_log i f hf_log_int]
  · -- E^{(i)}[f log f] is integrable
    exact condExpExceptCoord_integrable i (fun z => f z * log (f z)) hf_log_int
  · -- E^{(i)}[f] * log(E^{(i)}[f]) is integrable
    exact hEf_log_int

/-- Ent(E^{(i)}[f]) = ∫ E^{(i)}[f] · log(E^{(i)}[f]) dμ - (∫ f dμ) · log(∫ f dμ). -/
theorem entropy_condExpExceptCoord (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ) :
    LogSobolev.entropy μˢ (condExpExceptCoord (μs := μs) i f) =
    integralCondExpMulLog (μs := μs) i f - (∫ x, f x ∂μˢ) * log (∫ x, f x ∂μˢ) := by
  unfold LogSobolev.entropy integralCondExpMulLog
  -- Use tower property: ∫ E^{(i)}[f] dμˢ = ∫ f dμˢ
  rw [condExpExceptCoord_expectation i f hf_int]

/-- **Entropy Decomposition**: Ent(f) = E[Ent^{(i)}(f)] + Ent(E^{(i)}[f]). -/
theorem entropy_decomposition (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ)
    (hEf_log_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
                                        log (condExpExceptCoord (μs := μs) i f x)) μˢ) :
    LogSobolev.entropy μˢ f =
    ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ +
    LogSobolev.entropy μˢ (condExpExceptCoord (μs := μs) i f) := by
  -- LHS = ∫ f log f - (∫ f) * log(∫ f)
  -- RHS = (∫ f log f - ∫ E[f] log E[f]) + (∫ E[f] log E[f] - (∫ f) * log(∫ f))
  -- These are equal by cancellation
  rw [integral_condEntExceptCoord i f hf_log_int hEf_log_int]
  rw [entropy_condExpExceptCoord i f hf_int]
  unfold LogSobolev.entropy
  ring

/-!
## Corollaries
-/

/-- E[Ent^{(i)}(f)] = Ent(f) - Ent(E^{(i)}[f]). -/
theorem integral_condEntExceptCoord_eq_entropy_sub (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ)
    (hEf_log_int : Integrable (fun x => condExpExceptCoord (μs := μs) i f x *
                                        log (condExpExceptCoord (μs := μs) i f x)) μˢ) :
    ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ =
    LogSobolev.entropy μˢ f -
    LogSobolev.entropy μˢ (condExpExceptCoord (μs := μs) i f) := by
  have h := entropy_decomposition i f hf_int hf_log_int hEf_log_int
  linarith

/-- Nonnegativity of expected conditional entropy -/
theorem integral_condEntExceptCoord_nonneg (i : Fin n) (f : (Fin n → Ω) → ℝ)
    (hf_nn : 0 ≤ᵐ[μˢ] f)
    (hf_int : Integrable f μˢ)
    (hf_log_int : Integrable (fun x => f x * log (f x)) μˢ) :
    0 ≤ ∫ x, condEntExceptCoord (μs := μs) i f x ∂μˢ := by
  -- Get the slice hypotheses as a.e. statements
  have hnn_ae := ae_nonneg_slice_of_ae_nonneg i f hf_nn
  have hint_ae := integrable_update_slice i f hf_int
  have hlogint_ae := integrable_update_slice i (fun z => f z * log (f z)) hf_log_int
  -- Use integral_nonneg_of_ae with the a.e. bound from Jensen
  apply integral_nonneg_of_ae
  filter_upwards [hnn_ae, hint_ae, hlogint_ae] with x hnn hint hlogint
  -- At this point x, we have the slice hypotheses for this specific x
  -- The conditional entropy at x is nonnegative by Jensen
  show 0 ≤ condEntExceptCoord (μs := μs) i f x
  simp only [condEntExceptCoord]
  have h := condExpExceptCoord_mul_log_ge_at i f x hnn hint hlogint
  linarith

/-! ## Telescoping Entropy Decomposition -/

omit [∀ i, IsProbabilityMeasure (μs i)] in
/-- E_0[f] = ∫ f dμ (unconditional expectation). -/
lemma condExpFirstK_zero (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω) :
    condExpFirstK (μs := μs) 0 f x = ∫ z, f z ∂μˢ := by
  unfold condExpFirstK
  -- When k = 0, the condition j.val < 0 is false for all j, so we always pick y j
  -- Therefore f (fun j => if j.val < 0 then x j else y j) = f y
  have h : ∀ y : Fin n → Ω, f (fun j => if j.val < (0 : Fin (n + 1)).val then x j else y j) = f y := by
    intro y
    -- j.val < 0 is false for all j : Fin n, so if-then-else reduces to y j
    simp only [Fin.val_zero, Nat.not_lt_zero, ↓reduceIte]
  simp only [h]

/-- E_n[f] = f (identity). -/
lemma condExpFirstK_last (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω) :
    condExpFirstK (μs := μs) (Fin.last n) f x = f x := by
  unfold condExpFirstK
  -- When k = Fin.last n (value = n), the condition j.val < n is true for all j : Fin n
  have h : ∀ y : Fin n → Ω, f (fun j => if j.val < (Fin.last n).val then x j else y j) = f x := by
    intro y
    congr 1 with j
    simp only [Fin.val_last, j.isLt, ↓reduceIte]
  simp only [h, integral_const, probReal_univ, smul_eq_mul, one_mul]

/-- **Pointwise Telescoping**: f·(log f - log(∫f)) = Σᵢ f·(log E_{i+1}[f] - log Eᵢ[f]). -/
theorem entropy_telescoping_pointwise (f : (Fin n → Ω) → ℝ) (x : Fin n → Ω) :
    f x * (log (f x) - log (∫ z, f z ∂μˢ)) =
    ∑ i : Fin n, f x * (log (condExpFirstK (μs := μs) i.succ f x) -
                        log (condExpFirstK (μs := μs) i.castSucc f x)) := by
  -- Factor out f x from the sum
  rw [← Finset.mul_sum]
  congr 1
  -- Define g : ℕ → ℝ for the telescoping (extended with 0 outside [0, n])
  let g : ℕ → ℝ := fun k =>
    if h : k ≤ n then log (condExpFirstK (μs := μs) ⟨k, Nat.lt_succ_of_le h⟩ f x) else 0
  -- The sum ∑_{i=0}^{n-1} (g(i+1) - g(i)) = g(n) - g(0) by Finset.sum_range_sub
  have hg_tele : ∑ i ∈ Finset.range n, (g (i + 1) - g i) = g n - g 0 :=
    Finset.sum_range_sub g n
  -- Convert Fin sum to range sum
  have hsum_convert : ∑ i : Fin n, (log (condExpFirstK (μs := μs) i.succ f x) -
                                     log (condExpFirstK (μs := μs) i.castSucc f x)) =
      ∑ i ∈ Finset.range n, (g (i + 1) - g i) := by
    -- First show each term equals g (↑i + 1) - g ↑i
    have hterm : ∀ i : Fin n, log (condExpFirstK (μs := μs) i.succ f x) -
                               log (condExpFirstK (μs := μs) i.castSucc f x) =
                              g (↑i + 1) - g ↑i := by
      intro i
      simp only [g]
      have hi1 : ↑i + 1 ≤ n := i.isLt
      have hi0 : (i : ℕ) ≤ n := Nat.le_of_lt i.isLt
      simp only [hi1, hi0, dite_true]
      congr
    -- Rewrite using hterm, then apply Fin.sum_univ_eq_sum_range
    simp only [hterm]
    exact Fin.sum_univ_eq_sum_range (fun k => g (k + 1) - g k) n
  rw [hsum_convert, hg_tele]
  -- Simplify g(n) and g(0) using boundary lemmas
  simp only [g, le_refl, dite_true, Nat.zero_le]
  have hgn : log (condExpFirstK (μs := μs) ⟨n, Nat.lt_succ_self n⟩ f x) = log (f x) := by
    congr 1
    have : (⟨n, Nat.lt_succ_self n⟩ : Fin (n + 1)) = Fin.last n := rfl
    rw [this, condExpFirstK_last]
  have hg0 : log (condExpFirstK (μs := μs) ⟨0, Nat.zero_lt_succ n⟩ f x) = log (∫ z, f z ∂μˢ) := by
    congr 1
  rw [hgn, hg0]

end SubAddEnt

end
