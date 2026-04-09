/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianPoincare.RademacherApprox
import SLT.EfronStein
import Mathlib.Analysis.Calculus.ContDiff.Basic
import Mathlib.Topology.Algebra.Support
import Mathlib.Analysis.Normed.Group.Bounded

/-!
# Efron-Stein Inequality Applied to Rademacher Sums

This file formalizes the application of Efron-Stein's inequality to derive variance bounds
for smooth compactly supported functions composed with normalized Rademacher sums.

## Main results

### Part 1: Square Integrability
* `compactlySupported_continuous_bounded`: A continuous compactly supported function is bounded.
* `compactlySupported_smooth_integrable_sq`: For `f ∈ C_c²(ℝ)` and any random variable `X`,
  `E[f(X)²] < ∞`.

### Part 2: Efron-Stein Application to Rademacher Sums
* `variance_rademacherSum_efronStein`: For `f ∈ C_c²(ℝ)` and `S_n = n^{-1/2} ∑ε_j`:
  ```
  Var(f(S_n)) ≤ (n/4) * E[(f(S_n + (1-ε₁)/√n) - f(S_n - (1+ε₁)/√n))²]
  ```

-/

noncomputable section

open MeasureTheory ProbabilityTheory Real Filter
open scoped ENNReal Topology

namespace EfronSteinApp

/-! ### Part 1: Square Integrability of Compactly Supported Smooth Functions -/

section SquareIntegrability

variable {Ω : Type*}

/-- Predicate for a function being `C²` with compact support. -/
def CompactlySupportedSmooth (f : ℝ → ℝ) : Prop :=
  ContDiff ℝ 2 f ∧ HasCompactSupport f

/-- A `C²` compactly supported function is continuous. -/
lemma CompactlySupportedSmooth.continuous {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    Continuous f :=
  hf.1.continuous

/-- A continuous compactly supported function is bounded.
This follows from the Extreme Value Theorem: continuous functions on compact sets attain
their maximum. -/
theorem compactlySupported_continuous_bounded {f : ℝ → ℝ}
    (hcont : Continuous f) (hsupp : HasCompactSupport f) :
    ∃ C : ℝ, ∀ x : ℝ, ‖f x‖ ≤ C :=
  hsupp.exists_bound_of_continuous hcont

/-- A compactly supported smooth function is bounded. -/
theorem CompactlySupportedSmooth.bounded {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f) :
    ∃ C : ℝ, ∀ x : ℝ, ‖f x‖ ≤ C :=
  compactlySupported_continuous_bounded hf.continuous hf.2

/-- The composition of a bounded measurable function with any random variable is bounded. -/
lemma bounded_comp_bounded {f : ℝ → ℝ} {X : Ω → ℝ} {C : ℝ}
    (hbdd : ∀ x : ℝ, ‖f x‖ ≤ C) :
    ∀ ω : Ω, ‖f (X ω)‖ ≤ C := fun ω => hbdd (X ω)

variable [MeasurableSpace Ω]

/-- A compactly supported smooth function composed with any random variable is bounded a.e. -/
lemma CompactlySupportedSmooth.ae_bounded {f : ℝ → ℝ} (hf : CompactlySupportedSmooth f)
    {P : Measure Ω} {X : Ω → ℝ} :
    ∃ C : ℝ, ∀ᵐ ω ∂P, ‖f (X ω)‖ ≤ C := by
  obtain ⟨C, hC⟩ := hf.bounded
  exact ⟨C, ae_of_all P (bounded_comp_bounded hC)⟩

/-- A bounded function is square-integrable on any finite measure. -/
lemma integrable_sq_of_bounded {P : Measure Ω} [IsFiniteMeasure P]
    {g : Ω → ℝ} (hg : AEStronglyMeasurable g P) {C : ℝ} (hC : 0 ≤ C)
    (hbdd : ∀ᵐ ω ∂P, ‖g ω‖ ≤ C) :
    Integrable (fun ω => (g ω)^2) P := by
  apply Integrable.of_bound (hg.pow 2) (C^2)
  filter_upwards [hbdd] with ω hω
  simp only [Pi.pow_apply, Real.norm_eq_abs]
  rw [abs_pow]
  calc |g ω|^2 ≤ ‖g ω‖^2 := by rw [Real.norm_eq_abs]
    _ ≤ C^2 := by
        apply sq_le_sq'
        · calc -C ≤ 0 := neg_nonpos.mpr hC
            _ ≤ ‖g ω‖ := norm_nonneg _
        · exact hω

/-- **Part 1 Main Result**: For `f ∈ C_c²(ℝ)` and any random variable `X`,
the expectation `E[f(X)²]` is finite. -/
theorem compactlySupported_smooth_integrable_sq {f : ℝ → ℝ}
    (hf : CompactlySupportedSmooth f)
    {P : Measure Ω} [IsProbabilityMeasure P]
    {X : Ω → ℝ} (hX : AEStronglyMeasurable X P) :
    Integrable (fun ω => (f (X ω))^2) P := by
  obtain ⟨C, hC⟩ := hf.bounded
  apply integrable_sq_of_bounded (C := max 0 C)
  · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable hX.aemeasurable
  · exact le_max_left 0 C
  · exact ae_of_all P (fun ω => (hC (X ω)).trans (le_max_right 0 C))

/-- The composition of a compactly supported smooth function with any random variable
is integrable. -/
theorem compactlySupported_smooth_integrable {f : ℝ → ℝ}
    (hf : CompactlySupportedSmooth f)
    {P : Measure Ω} [IsProbabilityMeasure P]
    {X : Ω → ℝ} (hX : AEStronglyMeasurable X P) :
    Integrable (fun ω => f (X ω)) P := by
  obtain ⟨C, hC⟩ := hf.bounded
  apply Integrable.of_bound
    (hf.continuous.aestronglyMeasurable.comp_aemeasurable hX.aemeasurable)
    C (ae_of_all P (bounded_comp_bounded hC))

/-- The composition is in MemLp 2. -/
theorem compactlySupported_smooth_memLp2 {f : ℝ → ℝ}
    (hf : CompactlySupportedSmooth f)
    {P : Measure Ω} [IsProbabilityMeasure P]
    {X : Ω → ℝ} (hX : AEStronglyMeasurable X P) :
    MemLp (fun ω => f (X ω)) 2 P := by
  have haesm : AEStronglyMeasurable (fun ω => f (X ω)) P :=
    hf.continuous.aestronglyMeasurable.comp_aemeasurable hX.aemeasurable
  rw [memLp_two_iff_integrable_sq haesm]
  exact compactlySupported_smooth_integrable_sq hf hX

end SquareIntegrability

/-! ### Part 2: Efron-Stein Application to Rademacher Sums -/

section EfronSteinRademacher

open RademacherApprox

variable {Ω : Type*} {n : ℕ}

/-- The Rademacher sum with coordinate i flipped:
`S_n^{(i)} = S_n - 2εᵢ/√n` -/
def rademacherSumFlipped (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) : ℝ :=
  rademacherSum ε n ω - 2 * ε i ω / Real.sqrt n

/-- S_n^{(i)} equals S_n with εᵢ replaced by -εᵢ. -/
lemma rademacherSumFlipped_eq (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) :
    rademacherSumFlipped ε i ω =
    (√n)⁻¹ * (∑ j : Fin n, if j = i then -ε i ω else ε j ω) := by
  unfold rademacherSumFlipped rademacherSum
  -- S_n - 2εᵢ/√n = (√n)⁻¹ * (∑ε_j - 2εᵢ) = (√n)⁻¹ * ∑(if j=i then -εᵢ else εⱼ)
  have hsum : ∑ j : Fin n, (if j = i then -ε i ω else ε j ω) =
              (∑ j : Fin n, ε j ω) - 2 * ε i ω := by
    rw [Finset.sum_ite, Finset.filter_eq', Finset.filter_ne']
    simp only [Finset.mem_univ, ↓reduceIte, Finset.sum_singleton]
    have herase : (Finset.univ.erase i).sum (fun j : Fin n => ε j ω) + ε i ω =
                  (Finset.univ : Finset (Fin n)).sum (fun j => ε j ω) :=
      Finset.sum_erase_add Finset.univ (fun j : Fin n => ε j ω) (Finset.mem_univ i)
    linarith [herase]
  rw [hsum]
  ring

/-- The `a⁺` term: `S_n + (1-εᵢ)/√n` -/
def aPlus (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) : ℝ :=
  rademacherSum ε n ω + (1 - ε i ω) / Real.sqrt n

/-- The `a⁻` term: `S_n - (1+εᵢ)/√n` -/
def aMinus (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) : ℝ :=
  rademacherSum ε n ω - (1 + ε i ω) / Real.sqrt n

/-- When εᵢ = 1: a⁺ = Sₙ and a⁻ = Sₙ - 2/√n -/
lemma aPlus_aMinus_eps_pos (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) (h : ε i ω = 1) :
    aPlus ε i ω = rademacherSum ε n ω ∧
    aMinus ε i ω = rademacherSum ε n ω - 2 / Real.sqrt n := by
  unfold aPlus aMinus
  simp only [h, sub_self, zero_div, add_zero]
  constructor
  · trivial
  · norm_num

/-- When εᵢ = -1: a⁺ = Sₙ + 2/√n and a⁻ = Sₙ -/
lemma aPlus_aMinus_eps_neg (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) (h : ε i ω = -1) :
    aPlus ε i ω = rademacherSum ε n ω + 2 / Real.sqrt n ∧
    aMinus ε i ω = rademacherSum ε n ω := by
  unfold aPlus aMinus
  simp only [h, sub_neg_eq_add, add_neg_cancel, zero_div, sub_zero]
  constructor
  · norm_num
  · trivial

/-- Key identity: (f(Sₙ) - f(Sₙ^{(i)}))² = (f(a⁺) - f(a⁻))²
This holds because:
- When εᵢ = 1: f(Sₙ) - f(Sₙ^{(i)}) = f(Sₙ) - f(Sₙ - 2/√n) = f(a⁺) - f(a⁻)
- When εᵢ = -1: f(Sₙ) - f(Sₙ^{(i)}) = -(f(a⁺) - f(a⁻)), but squaring gives the same result
-/
lemma sq_diff_eq_sq_diff_aPlus_aMinus (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ)
    (i : Fin n) (ω : Ω) (hε : ε i ω = 1 ∨ ε i ω = -1) :
    (f (rademacherSum ε n ω) - f (rademacherSumFlipped ε i ω))^2 =
    (f (aPlus ε i ω) - f (aMinus ε i ω))^2 := by
  rcases hε with h | h
  · -- Case εᵢ = 1
    obtain ⟨haplus, haminus⟩ := aPlus_aMinus_eps_pos ε i ω h
    have hflip : rademacherSumFlipped ε i ω = rademacherSum ε n ω - 2 / Real.sqrt n := by
      unfold rademacherSumFlipped
      simp only [h, mul_one]
    rw [haplus, haminus, hflip]
  · -- Case εᵢ = -1
    obtain ⟨haplus, haminus⟩ := aPlus_aMinus_eps_neg ε i ω h
    have hflip : rademacherSumFlipped ε i ω = rademacherSum ε n ω + 2 / Real.sqrt n := by
      unfold rademacherSumFlipped
      simp only [h, mul_neg_one, neg_div, sub_neg_eq_add]
    rw [haplus, haminus, hflip]
    ring_nf

/-- The value Z⁺ when εᵢ is set to +1 (keeping other coordinates fixed). -/
def ZPlus (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) : ℝ :=
  f ((√n)⁻¹ * (1 + ∑ j ∈ Finset.univ.erase i, ε j ω))

/-- The value Z⁻ when εᵢ is set to -1 (keeping other coordinates fixed). -/
def ZMinus (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) : ℝ :=
  f ((√n)⁻¹ * (-1 + ∑ j ∈ Finset.univ.erase i, ε j ω))

/-- The conditional expectation E^{(i)}[Z] = (Z⁺ + Z⁻)/2 -/
lemma condExp_eq_average_ZPlus_ZMinus (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω) :
    (ZPlus f ε i ω + ZMinus f ε i ω) / 2 =
    (1/2) * ZPlus f ε i ω + (1/2) * ZMinus f ε i ω := by ring

/-- When εᵢ = +1, Z = Z⁺ and Z - E^{(i)}[Z] = (Z⁺ - Z⁻)/2 -/
lemma Z_minus_condExp_eps_pos (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω)
    (h : ε i ω = 1) :
    f (rademacherSum ε n ω) = ZPlus f ε i ω := by
  unfold ZPlus rademacherSum
  congr 1
  rw [← Finset.sum_erase_add Finset.univ _ (Finset.mem_univ i)]
  simp [h]

/-- When εᵢ = -1, Z = Z⁻ -/
lemma Z_minus_condExp_eps_neg (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n) (ω : Ω)
    (h : ε i ω = -1) :
    f (rademacherSum ε n ω) = ZMinus f ε i ω := by
  unfold ZMinus rademacherSum
  congr 1
  rw [← Finset.sum_erase_add Finset.univ _ (Finset.mem_univ i)]
  simp [h]

/-- Key identity: (Z - E^{(i)}[Z])² = (1/4)(Z⁺ - Z⁻)²
This is because:
- When εᵢ = +1: Z = Z⁺, so Z - E^{(i)}[Z] = Z⁺ - (Z⁺+Z⁻)/2 = (Z⁺-Z⁻)/2
- When εᵢ = -1: Z = Z⁻, so Z - E^{(i)}[Z] = Z⁻ - (Z⁺+Z⁻)/2 = -(Z⁺-Z⁻)/2
In both cases, the square is (1/4)(Z⁺-Z⁻)² -/
lemma sq_diff_condExp_eq_quarter_sq_diff (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n)
    (ω : Ω) (hε : ε i ω = 1 ∨ ε i ω = -1) :
    (f (rademacherSum ε n ω) - (ZPlus f ε i ω + ZMinus f ε i ω) / 2)^2 =
    (1/4) * (ZPlus f ε i ω - ZMinus f ε i ω)^2 := by
  rcases hε with h | h
  · -- εᵢ = +1: Z = Z⁺
    rw [Z_minus_condExp_eps_pos f ε i ω h]
    ring
  · -- εᵢ = -1: Z = Z⁻
    rw [Z_minus_condExp_eps_neg f ε i ω h]
    ring

/-- The squared difference (Z - Z^{(i)})² equals (Z⁺ - Z⁻)² -/
lemma sq_diff_flipped_eq_sq_ZPlus_ZMinus (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n)
    (ω : Ω) (hε : ε i ω = 1 ∨ ε i ω = -1) :
    (f (rademacherSum ε n ω) - f (rademacherSumFlipped ε i ω))^2 =
    (ZPlus f ε i ω - ZMinus f ε i ω)^2 := by
  rcases hε with h | h
  · -- εᵢ = +1: Z = Z⁺, Z^{(i)} = Z⁻
    rw [Z_minus_condExp_eps_pos f ε i ω h]
    have : f (rademacherSumFlipped ε i ω) = ZMinus f ε i ω := by
      unfold ZMinus rademacherSumFlipped rademacherSum
      congr 1
      have herase : (Finset.univ.erase i).sum (fun j : Fin n => ε j ω) + ε i ω =
                    (Finset.univ : Finset (Fin n)).sum (fun j => ε j ω) :=
        Finset.sum_erase_add Finset.univ (fun j : Fin n => ε j ω) (Finset.mem_univ i)
      have hsum : ∑ j : Fin n, ε j ω = ∑ j ∈ Finset.univ.erase i, ε j ω + ε i ω := herase.symm
      simp only [h] at hsum ⊢
      -- Goal: (√n)⁻¹ * (s + 1) - 2/√n = (√n)⁻¹ * (-1 + s)  where s = ∑_{j≠i} ε_j
      have hsumFin : ∑ j : Fin n, ε (↑j) ω = ∑ j ∈ Finset.univ.erase i, ε (↑j) ω + 1 := hsum
      calc (√↑n)⁻¹ * ∑ j : Fin n, ε (↑j) ω - 2 * 1 / √↑n
          = (√↑n)⁻¹ * (∑ j ∈ Finset.univ.erase i, ε (↑j) ω + 1) - 2 / √↑n := by rw [hsumFin]; ring
        _ = (√↑n)⁻¹ * (-1 + ∑ j ∈ Finset.univ.erase i, ε (↑j) ω) := by ring
    rw [this]
  · -- εᵢ = -1: Z = Z⁻, Z^{(i)} = Z⁺
    rw [Z_minus_condExp_eps_neg f ε i ω h]
    have : f (rademacherSumFlipped ε i ω) = ZPlus f ε i ω := by
      unfold ZPlus rademacherSumFlipped rademacherSum
      congr 1
      have herase : (Finset.univ.erase i).sum (fun j : Fin n => ε j ω) + ε i ω =
                    (Finset.univ : Finset (Fin n)).sum (fun j => ε j ω) :=
        Finset.sum_erase_add Finset.univ (fun j : Fin n => ε j ω) (Finset.mem_univ i)
      have hsum : ∑ j : Fin n, ε j ω = ∑ j ∈ Finset.univ.erase i, ε j ω + ε i ω := herase.symm
      simp only [h] at hsum ⊢
      -- Goal: (√n)⁻¹ * (s - 1) + 2/√n = (√n)⁻¹ * (1 + s)  where s = ∑_{j≠i} ε_j
      have hsumFin : ∑ j : Fin n, ε (↑j) ω = ∑ j ∈ Finset.univ.erase i, ε (↑j) ω + -1 := hsum
      calc (√↑n)⁻¹ * ∑ j : Fin n, ε (↑j) ω - 2 * -1 / √↑n
          = (√↑n)⁻¹ * (∑ j ∈ Finset.univ.erase i, ε (↑j) ω + -1) + 2 / √↑n := by rw [hsumFin]; ring
        _ = (√↑n)⁻¹ * (1 + ∑ j ∈ Finset.univ.erase i, ε (↑j) ω) := by ring
    rw [this]
    ring

/-- **Key Lemma**: The squared conditional deviation equals 1/4 times the squared flipped difference.
(Z - E^{(i)}[Z])² = (1/4)(Z - Z^{(i)})² -/
theorem sq_condExp_deviation_eq_quarter_sq_flip (f : ℝ → ℝ) (ε : ℕ → Ω → ℝ) (i : Fin n)
    (ω : Ω) (hε : ε i ω = 1 ∨ ε i ω = -1) :
    (f (rademacherSum ε n ω) - (ZPlus f ε i ω + ZMinus f ε i ω) / 2)^2 =
    (1/4) * (f (rademacherSum ε n ω) - f (rademacherSumFlipped ε i ω))^2 := by
  rw [sq_diff_condExp_eq_quarter_sq_diff f ε i ω hε,
      sq_diff_flipped_eq_sq_ZPlus_ZMinus f ε i ω hε]

end EfronSteinRademacher

/-! ### Part 2 Main Theorem Setup -/

section MainTheorem

open RademacherApprox

/-- Rademacher random variables take values in {-1, 1} almost surely. -/
lemma rademacher_values_ae {Ω : Type*} [MeasurableSpace Ω]
    {P : Measure Ω} {ε : Ω → ℝ} (hε : IsRademacher P ε) :
    ∀ᵐ ω ∂P, ε ω = 1 ∨ ε ω = -1 := by
  unfold IsRademacher at hε
  -- rademacherMeasure is supported on {-1, 1}
  have hsupp : ∀ᵐ x ∂rademacherMeasure, x = 1 ∨ x = -1 := by
    simp only [rademacherMeasure]
    rw [ae_add_measure_iff]
    have hmeas : MeasurableSet {x : ℝ | x = 1 ∨ x = -1} := by measurability
    constructor <;> {
      rw [Measure.ae_smul_measure_iff (by norm_num : (1/2 : ℝ≥0∞) ≠ 0)]
      rw [ae_dirac_iff hmeas]
      simp
    }
  rw [← hε] at hsupp
  -- ε is measurable since map ε P = rademacherMeasure ≠ 0
  have hmeas' : AEMeasurable ε P := by
    apply AEMeasurable.of_map_ne_zero
    rw [hε]
    exact IsProbabilityMeasure.ne_zero rademacherMeasure
  exact ae_of_ae_map hmeas' hsupp

variable (n : ℕ)

/-- The product space for n independent Rademacher variables. -/
abbrev RademacherSpace (n : ℕ) := Fin n → ℝ

/-- Product measure for n copies of rademacherMeasure. -/
def rademacherProductMeasure (n : ℕ) : Measure (RademacherSpace n) :=
  Measure.pi (fun _ : Fin n => rademacherMeasure)

instance isProbabilityMeasure_rademacherProduct (n : ℕ) :
    IsProbabilityMeasure (rademacherProductMeasure n) :=
  Measure.pi.instIsProbabilityMeasure _

/-- Coordinate projection is measurable. -/
lemma measurable_coord (i : Fin n) : Measurable (fun x : RademacherSpace n => x i) :=
  measurable_pi_apply i

/-- Coordinate projection is a Rademacher random variable. -/
lemma coord_isRademacher (i : Fin n) :
    IsRademacher (rademacherProductMeasure n) (fun x : RademacherSpace n => x i) := by
  unfold IsRademacher rademacherProductMeasure
  -- Use that Measure.map (eval i) (Measure.pi μ) = (∏ j ≠ i, μ j univ) • μ i
  -- For probability measures, this simplifies to μ i
  have h := MeasureTheory.Measure.pi_map_eval (fun _ : Fin n => rademacherMeasure) i
  simp only [Finset.prod_eq_one (fun j _ => measure_univ), one_smul] at h
  exact h

/-- Coordinate projections are independent. -/
lemma coord_indep : iIndepFun (fun i : Fin n => (fun x : RademacherSpace n => x i))
    (rademacherProductMeasure n) := by
  unfold rademacherProductMeasure
  -- Apply iIndepFun_pi with identity functions
  have h := ProbabilityTheory.iIndepFun_pi (𝓧 := fun _ => ℝ) (Ω := fun _ => ℝ)
    (μ := fun _ : Fin n => rademacherMeasure) (X := fun _ => id)
    (fun _ => aemeasurable_id)
  simp only [id_eq] at h
  exact h

/-- The Rademacher sum on the product space. -/
def rademacherSumProd (x : RademacherSpace n) : ℝ :=
  (√n)⁻¹ * ∑ i : Fin n, x i

/-- The Rademacher sum is measurable. -/
lemma measurable_rademacherSumProd : Measurable (rademacherSumProd n) := by
  unfold rademacherSumProd
  apply Measurable.const_mul
  apply Finset.measurable_sum
  intro i _
  exact measurable_pi_apply i

/-- The Rademacher sum is AEStronglyMeasurable. -/
lemma aestronglyMeasurable_rademacherSumProd :
    AEStronglyMeasurable (rademacherSumProd n) (rademacherProductMeasure n) :=
  (measurable_rademacherSumProd n).aestronglyMeasurable

/-- All coordinates are ±1 almost surely on the product space. -/
lemma coord_values_ae (i : Fin n) :
    ∀ᵐ x ∂(rademacherProductMeasure n), x i = 1 ∨ x i = -1 :=
  rademacher_values_ae (coord_isRademacher n i)

/-- The `a⁺` function on the product space. -/
def aPlusProd (i : Fin n) (x : RademacherSpace n) : ℝ :=
  rademacherSumProd n x + (1 - x i) / Real.sqrt n

/-- The `a⁻` function on the product space. -/
def aMinusProd (i : Fin n) (x : RademacherSpace n) : ℝ :=
  rademacherSumProd n x - (1 + x i) / Real.sqrt n

variable [NeZero n]

/-- **Part 2 Main Theorem**: Variance bound for f(S_n) using Efron-Stein.

For `f ∈ C_c²(ℝ)` and the normalized Rademacher sum `S_n`:
  `Var(f(S_n)) ≤ (n/4) * E[(f(S_n + (1-ε₁)/√n) - f(S_n - (1+ε₁)/√n))²]`

-/
theorem variance_rademacherSum_efronStein (f : ℝ → ℝ) (hf : CompactlySupportedSmooth f) :
    variance (fun x : RademacherSpace n => f (rademacherSumProd n x)) (rademacherProductMeasure n) ≤
    (n : ℝ) / 4 * ∫ x, (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2 ∂(rademacherProductMeasure n) := by
  -- For n = 0, we have a contradiction with NeZero n
  by_cases hn0 : n = 0
  · exact absurd hn0 (NeZero.ne n)
  -- Setup: the composition f ∘ S_n is in MemLp 2
  have hmemLp : MemLp (fun x => f (rademacherSumProd n x)) 2 (rademacherProductMeasure n) :=
    compactlySupported_smooth_memLp2 hf (aestronglyMeasurable_rademacherSumProd n)
  -- Get boundedness of f
  obtain ⟨C, hC⟩ := hf.bounded
  -- Apply Efron-Stein inequality
  have hES := @efronStein n ℝ _ (fun _ => rademacherMeasure)
    (fun _ => isProbabilityMeasure_rademacherMeasure)
    (fun x => f (rademacherSumProd n x))
  -- Need to show that the composition is MemLp 2 on the product measure
  have hμeq : Measure.pi (fun _ : Fin n => rademacherMeasure) = rademacherProductMeasure n := rfl
  rw [hμeq] at hES
  specialize hES hmemLp
  -- The Efron-Stein bound is:
  -- Var(f(S_n)) ≤ ∑ᵢ E[(f(S_n) - E^{(i)}[f(S_n)])²]
  -- We need to relate this to E[(f(a⁺) - f(a⁻))²]
  -- Key: (f(S_n) - E^{(i)}[f(S_n)])² = (1/4)(f(a⁺) - f(a⁻))² a.s.
  calc variance (fun x => f (rademacherSumProd n x)) (rademacherProductMeasure n)
      ≤ ∑ i : Fin n, ∫ x, (f (rademacherSumProd n x) -
          condExpExceptCoord (μs := fun _ => rademacherMeasure) i
            (fun x => f (rademacherSumProd n x)) x)^2 ∂(rademacherProductMeasure n) := hES
    _ ≤ ∑ i : Fin n, (1/4 : ℝ) * ∫ x, (f (aPlusProd n i x) - f (aMinusProd n i x))^2
          ∂(rademacherProductMeasure n) := by
        apply Finset.sum_le_sum
        intro i _
        -- The key bound: using the fact that (Z - E^{(i)}Z)² ≤ (1/4)(f(a⁺) - f(a⁻))² a.s.
        -- This requires relating condExpExceptCoord to our ZPlus/ZMinus
        have hint1 : Integrable (fun x => (f (rademacherSumProd n x) -
            condExpExceptCoord (μs := fun _ => rademacherMeasure) i
              (fun x => f (rademacherSumProd n x)) x)^2) (rademacherProductMeasure n) := by
          -- The difference is bounded by 2C (both f(S_n) and E^{(i)}f(S_n) are bounded by C)
          -- so the square is bounded by 4C²
          apply integrable_sq_of_bounded (C := 2 * C)
          · apply AEStronglyMeasurable.sub
            · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
                (measurable_rademacherSumProd n).aemeasurable
            · -- The condExpExceptCoord is measurable because rademacherMeasure is discrete
              -- condExpExceptCoord i g x = (1/2) g(update x i 1) + (1/2) g(update x i (-1))
              have hmeas1 : AEStronglyMeasurable
                  (fun x => f (rademacherSumProd n (Function.update x i 1)))
                  (rademacherProductMeasure n) :=
                hf.continuous.aestronglyMeasurable.comp_aemeasurable
                  ((measurable_rademacherSumProd n).comp (measurable_update_left)).aemeasurable
              have hmeas2 : AEStronglyMeasurable
                  (fun x => f (rademacherSumProd n (Function.update x i (-1))))
                  (rademacherProductMeasure n) :=
                hf.continuous.aestronglyMeasurable.comp_aemeasurable
                  ((measurable_rademacherSumProd n).comp (measurable_update_left)).aemeasurable
              -- The integral equals (1/2) * f(update x i 1) + (1/2) * f(update x i (-1))
              -- which is a linear combination of measurable functions
              have hmeas_sum : AEStronglyMeasurable
                  (fun x => (1/2 : ℝ) • f (rademacherSumProd n (Function.update x i 1)) +
                            (1/2 : ℝ) • f (rademacherSumProd n (Function.update x i (-1))))
                  (rademacherProductMeasure n) :=
                AEStronglyMeasurable.add (hmeas1.const_smul (1/2 : ℝ)) (hmeas2.const_smul (1/2 : ℝ))
              apply hmeas_sum.congr
              filter_upwards with x
              unfold condExpExceptCoord rademacherMeasure
              rw [integral_add_measure, integral_smul_measure, integral_smul_measure,
                  integral_dirac, integral_dirac]
              · simp only [smul_eq_mul, one_div, ENNReal.toReal_inv, ENNReal.toReal_ofNat]
                ring
              · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)
              · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)
          · linarith [hC 0, norm_nonneg (f 0)]
          · filter_upwards with x
            calc ‖f (rademacherSumProd n x) -
                   condExpExceptCoord (μs := fun _ => rademacherMeasure) i
                     (fun x => f (rademacherSumProd n x)) x‖
                ≤ ‖f (rademacherSumProd n x)‖ +
                  ‖condExpExceptCoord (μs := fun _ => rademacherMeasure) i
                     (fun x => f (rademacherSumProd n x)) x‖ := norm_sub_le _ _
              _ ≤ C + C := by
                  apply add_le_add (hC _)
                  unfold condExpExceptCoord
                  rw [Real.norm_eq_abs]
                  -- Need: |∫ f(S_n(update x i y)) dμ(y)| ≤ C
                  calc |∫ y, f (rademacherSumProd n (Function.update x i y)) ∂rademacherMeasure|
                      ≤ ∫ y, |f (rademacherSumProd n (Function.update x i y))| ∂rademacherMeasure :=
                        abs_integral_le_integral_abs
                    _ ≤ ∫ _y, C ∂rademacherMeasure := by
                        apply integral_mono_of_nonneg
                        · filter_upwards with y; exact abs_nonneg _
                        · exact integrable_const C
                        · filter_upwards with y
                          exact (Real.norm_eq_abs _).symm ▸ hC _
                    _ = C := by simp [integral_const]
              _ = 2 * C := by ring
        have hint2 : Integrable (fun x => (f (aPlusProd n i x) - f (aMinusProd n i x))^2)
            (rademacherProductMeasure n) := by
          -- Both f(a⁺) and f(a⁻) are bounded by C, so their difference is bounded by 2C
          apply integrable_sq_of_bounded (C := 2 * C)
          · apply AEStronglyMeasurable.sub
            · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
                ((measurable_rademacherSumProd n).add
                  ((measurable_const.sub (measurable_pi_apply i)).div measurable_const)).aemeasurable
            · exact hf.continuous.aestronglyMeasurable.comp_aemeasurable
                ((measurable_rademacherSumProd n).sub
                  ((measurable_const.add (measurable_pi_apply i)).div measurable_const)).aemeasurable
          · linarith [hC 0, norm_nonneg (f 0)]
          · filter_upwards with x
            calc ‖f (aPlusProd n i x) - f (aMinusProd n i x)‖
                ≤ ‖f (aPlusProd n i x)‖ + ‖f (aMinusProd n i x)‖ := norm_sub_le _ _
              _ ≤ C + C := add_le_add (hC _) (hC _)
              _ = 2 * C := by ring
        rw [← MeasureTheory.integral_const_mul]
        apply integral_mono_ae hint1 (hint2.const_mul (1/4 : ℝ))
        -- Show pointwise bound a.s.
        filter_upwards [coord_values_ae n i] with x hx
        -- Compute condExpExceptCoord
        have hcond : condExpExceptCoord (μs := fun _ => rademacherMeasure) i
            (fun x => f (rademacherSumProd n x)) x =
            (1/2) * f (rademacherSumProd n (Function.update x i 1)) +
            (1/2) * f (rademacherSumProd n (Function.update x i (-1))) := by
          unfold condExpExceptCoord rademacherMeasure
          rw [integral_add_measure, integral_smul_measure, integral_smul_measure]
          · rw [integral_dirac, integral_dirac]
            simp only [smul_eq_mul, ENNReal.toReal_inv, ENNReal.toReal_ofNat, one_div]
            ring
          · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)
          · exact Integrable.smul_measure (integrable_dirac (by simp : ‖_‖ₑ < ⊤)) (by simp)
        -- The key: relate S_n(update x i y) to a⁺, a⁻
        have hupdate_1 : rademacherSumProd n (Function.update x i 1) =
            rademacherSumProd n x + (1 - x i) / Real.sqrt n := by
          unfold rademacherSumProd
          rw [Finset.sum_update_of_mem (Finset.mem_univ i)]
          have hsum : ∑ x_1 ∈ Finset.univ \ {i}, x x_1 = (∑ j, x j) - x i := by
            simp only [Finset.sdiff_singleton_eq_erase]
            exact Finset.sum_erase_eq_sub (f := x) (Finset.mem_univ i)
          rw [hsum]
          field_simp
          ring
        have hupdate_neg1 : rademacherSumProd n (Function.update x i (-1)) =
            rademacherSumProd n x - (1 + x i) / Real.sqrt n := by
          unfold rademacherSumProd
          rw [Finset.sum_update_of_mem (Finset.mem_univ i)]
          have hsum : ∑ x_1 ∈ Finset.univ \ {i}, x x_1 = (∑ j, x j) - x i := by
            simp only [Finset.sdiff_singleton_eq_erase]
            exact Finset.sum_erase_eq_sub (f := x) (Finset.mem_univ i)
          rw [hsum]
          field_simp
          ring
        -- So f(update x i 1) = f(a⁺) and f(update x i (-1)) = f(a⁻)
        have hf1 : f (rademacherSumProd n (Function.update x i 1)) = f (aPlusProd n i x) := by
          unfold aPlusProd; rw [hupdate_1]
        have hfneg1 : f (rademacherSumProd n (Function.update x i (-1))) = f (aMinusProd n i x) := by
          unfold aMinusProd; rw [hupdate_neg1]
        rw [hcond, hf1, hfneg1]
        -- Now the computation depends on whether x i = 1 or x i = -1
        -- The key identity: (a - (1/2 * b + 1/2 * c))² = 1/4 * (b - c)² when a = b or a = c
        rcases hx with hpos | hneg
        · -- x i = 1: f(S_n) = f(a⁺) (since a⁺ = S_n when x i = 1)
          have ha_eq : f (aPlusProd n i x) = f (rademacherSumProd n x) := by
            congr 1; unfold aPlusProd; simp [hpos]
          rw [ha_eq]
          -- LHS = (f(S_n) - (1/2 * f(S_n) + 1/2 * f(a⁻)))² = (1/2 * (f(S_n) - f(a⁻)))² = 1/4 * (f(S_n) - f(a⁻))²
          ring_nf
          exact le_refl _
        · -- x i = -1: f(S_n) = f(a⁻) (since a⁻ = S_n when x i = -1)
          have ha_eq : f (aMinusProd n i x) = f (rademacherSumProd n x) := by
            congr 1; unfold aMinusProd; simp [hneg]
          rw [ha_eq]
          -- LHS = (f(S_n) - (1/2 * f(a⁺) + 1/2 * f(S_n)))² = (1/2 * (f(S_n) - f(a⁺)))² = 1/4 * (f(a⁺) - f(S_n))²
          ring_nf
          exact le_refl _
    _ = (n : ℝ) / 4 * ∫ x, (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2
          ∂(rademacherProductMeasure n) := by
        -- By symmetry, all n terms are equal since the Rademacher variables are i.i.d.
        -- ∑ᵢ (1/4) * E[...] = n * (1/4) * E[term at i=0] = (n/4) * E[...]
        -- The integral ∫ (f(a⁺ᵢ(x)) - f(a⁻ᵢ(x)))² dμ(x) is the same for all i
        have hall_eq : ∀ i ∈ Finset.univ, (1/4 : ℝ) * ∫ x, (f (aPlusProd n i x) - f (aMinusProd n i x))^2
            ∂(rademacherProductMeasure n) =
          (1/4 : ℝ) * ∫ x, (f (aPlusProd n 0 x) - f (aMinusProd n 0 x))^2
            ∂(rademacherProductMeasure n) := by
          intro i _
          -- By exchangeability of i.i.d. Rademacher variables
          -- The swap permutation σ swaps coordinates 0 and i
          let σ : Equiv.Perm (Fin n) := Equiv.swap 0 i
          -- The coordinate swap using MeasurableEquiv.piCongrLeft
          let swapEquiv := MeasurableEquiv.piCongrLeft (fun _ : Fin n => ℝ) σ
          -- Key lemma: σ.symm = σ (swap is self-inverse)
          have hσ_symm : σ.symm = σ := Equiv.symm_swap 0 i
          -- Key lemma: σ i = 0
          have hσ_i : σ i = 0 := Equiv.swap_apply_right 0 i
          -- Key: rademacherSumProd is invariant under coordinate permutation
          have hsum_inv : ∀ x, rademacherSumProd n (swapEquiv x) = rademacherSumProd n x := by
            intro x
            unfold rademacherSumProd
            rw [MeasurableEquiv.coe_piCongrLeft]
            simp only [Equiv.piCongrLeft_apply_eq_cast, hσ_symm, cast_eq]
            rw [← Finset.sum_equiv σ (g := fun j => x j)]
            · simp only [Finset.mem_univ, implies_true]
            · intro j _; rfl
          -- Key: (swapEquiv x) i = x 0 (since σ.symm i = σ i = 0)
          have hswap_i : ∀ x, (swapEquiv x) i = x 0 := by
            intro x
            show (Equiv.piCongrLeft (fun _ => ℝ) σ) x i = x 0
            simp only [Equiv.piCongrLeft_apply_eq_cast, cast_eq, hσ_symm, hσ_i]
          -- Therefore: aPlusProd n i (swapEquiv x) = aPlusProd n 0 x
          have haPlus : ∀ x, aPlusProd n i (swapEquiv x) = aPlusProd n 0 x := by
            intro x
            unfold aPlusProd
            rw [hsum_inv, hswap_i]
          -- Similarly: aMinusProd n i (swapEquiv x) = aMinusProd n 0 x
          have haMinus : ∀ x, aMinusProd n i (swapEquiv x) = aMinusProd n 0 x := by
            intro x
            unfold aMinusProd
            rw [hsum_inv, hswap_i]
          -- The product measure is preserved under swapEquiv (same marginals)
          have hpreserves : MeasurePreserving swapEquiv (rademacherProductMeasure n)
              (rademacherProductMeasure n) := by
            unfold rademacherProductMeasure
            exact measurePreserving_piCongrLeft (fun _ => rademacherMeasure) σ
          -- Use measure preservation to equate integrals
          congr 1
          rw [← hpreserves.integral_comp']
          congr 1
          ext x
          rw [haPlus, haMinus]
        rw [Finset.sum_eq_card_nsmul hall_eq]
        simp only [Finset.card_univ, Fintype.card_fin]
        simp only [nsmul_eq_mul]
        ring

end MainTheorem

end EfronSteinApp

end
