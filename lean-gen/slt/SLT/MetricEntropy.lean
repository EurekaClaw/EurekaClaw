/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.CoveringNumber
import SLT.MeasureInfrastructure
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.MeasureTheory.Integral.IntervalIntegral.Basic

/-!
# Metric Entropy

Metric entropy (logarithm of covering number) and the entropy integral for Dudley's bound.

## Design Note
Two-level design: ENNReal `entropyIntegralENNReal` (canonical) with real wrapper `entropyIntegral`.

## Main definitions

* `metricEntropy` / `metricEntropyENNReal`: log N(ε, s)
* `dudleyIntegrand`: √log N(ε, s) as ENNReal
* `entropyIntegralENNReal`: ∫₀^D √log N(ε, s) dε (canonical)
* `entropyIntegral`: Real-valued wrapper via `.toReal`

## Main results

* Monotonicity lemmas for entropy and entropy integral
* Dyadic sum approximation: `dyadicRHS_le_four_times_entropyIntegral`

-/

open Set Metric Real MeasureTheory
open scoped BigOperators ENNReal

noncomputable section

variable {A : Type*} [PseudoMetricSpace A]

/-!
## Metric Entropy (Real-valued)
-/

/-- Helper to compute metric entropy given a natural number. -/
def metricEntropyOfNat (n : ℕ) : ℝ :=
  if n ≤ 1 then 0 else Real.log n

lemma metricEntropyOfNat_nonneg (n : ℕ) : 0 ≤ metricEntropyOfNat n := by
  unfold metricEntropyOfNat
  split_ifs with hn
  · exact le_rfl
  · push_neg at hn
    exact Real.log_nonneg (Nat.one_le_cast.mpr (Nat.one_le_of_lt hn))

lemma metricEntropyOfNat_mono {n m : ℕ} (h : n ≤ m) : metricEntropyOfNat n ≤ metricEntropyOfNat m := by
  unfold metricEntropyOfNat
  split_ifs with hn hm hm
  · exact le_rfl
  · push_neg at hm
    exact Real.log_nonneg (Nat.one_le_cast.mpr (Nat.one_le_of_lt hm))
  · push_neg at hn
    omega
  · push_neg at hn
    exact Real.log_le_log (Nat.cast_pos.mpr (by omega : 0 < n)) (Nat.cast_le.mpr h)

/-- Metric entropy: log of the covering number.
    Returns 0 if the covering number is infinite or ≤ 1 (to avoid log issues). -/
def metricEntropy (eps : ℝ) (s : Set A) : ℝ :=
  match _h : coveringNumber eps s with
  | ⊤ => 0
  | (n : ℕ) => metricEntropyOfNat n

/-- Metric entropy is non-negative. -/
lemma metricEntropy_nonneg (eps : ℝ) (s : Set A) : 0 ≤ metricEntropy eps s := by
  unfold metricEntropy
  split
  · exact le_rfl
  · exact metricEntropyOfNat_nonneg _

/-- Metric entropy of empty set is 0. -/
lemma metricEntropy_empty (eps : ℝ) : metricEntropy eps (∅ : Set A) = 0 := by
  unfold metricEntropy metricEntropyOfNat
  split
  · rfl
  · rename_i n hn
    rw [coveringNumber_empty] at hn
    have : n = 0 := WithTop.coe_injective hn.symm
    simp [this]

/-- Metric entropy is anti-monotone in ε. Requires `coveringNumber eps1 s < ⊤`. -/
lemma metricEntropy_anti_eps {eps1 eps2 : ℝ} {s : Set A}
    (heps : eps1 ≤ eps2)
    (hfin1 : coveringNumber eps1 s < ⊤) : metricEntropy eps2 s ≤ metricEntropy eps1 s := by
  unfold metricEntropy
  have hcov := coveringNumber_anti_eps heps (s := s)
  have hfin2 : coveringNumber eps2 s < ⊤ := lt_of_le_of_lt hcov hfin1
  split
  · rename_i h2
    rw [h2] at hfin2
    exact absurd rfl (ne_of_lt hfin2)
  · split
    · rename_i n2 h2 h1
      rw [h1] at hfin1
      exact absurd rfl (ne_of_lt hfin1)
    · rename_i n2 h2 n1 h1
      have hle : n2 ≤ n1 := by
        rw [h1, h2] at hcov
        exact WithTop.coe_le_coe.mp hcov
      exact metricEntropyOfNat_mono hle

/-- Metric entropy is anti-monotone in epsilon for totally bounded sets. -/
lemma metricEntropy_anti_eps_of_totallyBounded {eps1 eps2 : ℝ} {s : Set A}
    (heps1 : 0 < eps1) (heps : eps1 ≤ eps2)
    (hs : TotallyBounded s) : metricEntropy eps2 s ≤ metricEntropy eps1 s :=
  metricEntropy_anti_eps heps (coveringNumber_lt_top_of_totallyBounded heps1 hs)

/-- Metric entropy is monotone in the set: larger set means larger entropy.
    Note: This version assumes the superset has finite covering number. -/
lemma metricEntropy_mono_set {eps : ℝ} {s t : Set A}
    (h : s ⊆ t) (hfin : coveringNumber eps t < ⊤) : metricEntropy eps s ≤ metricEntropy eps t := by
  unfold metricEntropy
  have hcov := coveringNumber_mono_set h (eps := eps)
  have hfin_s : coveringNumber eps s < ⊤ := lt_of_le_of_lt hcov hfin
  split
  · rename_i hs
    rw [hs] at hfin_s
    exact absurd rfl (ne_of_lt hfin_s)
  · split
    · rename_i ns hs ht
      rw [ht] at hfin
      exact absurd rfl (ne_of_lt hfin)
    · rename_i ns hs nt ht
      have hle : ns ≤ nt := by
        rw [hs, ht] at hcov
        exact WithTop.coe_le_coe.mp hcov
      exact metricEntropyOfNat_mono hle

/-- Metric entropy is monotone in the set for totally bounded supersets. -/
lemma metricEntropy_mono_set_of_totallyBounded {eps : ℝ} {s t : Set A}
    (heps : 0 < eps) (h : s ⊆ t) (ht : TotallyBounded t) :
    metricEntropy eps s ≤ metricEntropy eps t :=
  metricEntropy_mono_set h (coveringNumber_lt_top_of_totallyBounded heps ht)

/-!
## Square Root of Entropy (Real-valued)
-/

/-- Square root of metric entropy: √log N(ε, s). -/
def sqrtEntropy (eps : ℝ) (s : Set A) : ℝ :=
  Real.sqrt (metricEntropy eps s)

/-- Square root entropy is non-negative. -/
lemma sqrtEntropy_nonneg (eps : ℝ) (s : Set A) : 0 ≤ sqrtEntropy eps s :=
  Real.sqrt_nonneg _

/-- Square root entropy of empty set is 0. -/
lemma sqrtEntropy_empty (eps : ℝ) : sqrtEntropy eps (∅ : Set A) = 0 := by
  simp only [sqrtEntropy, metricEntropy_empty, Real.sqrt_zero]

/-- Square root entropy is anti-monotone in epsilon (requires finite covering number). -/
lemma sqrtEntropy_anti_eps {eps1 eps2 : ℝ} {s : Set A}
    (heps : eps1 ≤ eps2) (hfin1 : coveringNumber eps1 s < ⊤) :
    sqrtEntropy eps2 s ≤ sqrtEntropy eps1 s :=
  Real.sqrt_le_sqrt (metricEntropy_anti_eps heps hfin1)

/-- Square root entropy is anti-monotone in epsilon for totally bounded sets. -/
lemma sqrtEntropy_anti_eps_of_totallyBounded {eps1 eps2 : ℝ} {s : Set A}
    (heps1 : 0 < eps1) (heps : eps1 ≤ eps2) (hs : TotallyBounded s) :
    sqrtEntropy eps2 s ≤ sqrtEntropy eps1 s :=
  sqrtEntropy_anti_eps heps (coveringNumber_lt_top_of_totallyBounded heps1 hs)


/-- For an optimal ε-net, √(log |net|) = sqrtEntropy(ε, s).
    This is the key lemma for Dudley's chaining bound. -/
lemma sqrtEntropy_eq_sqrt_log_card_of_optimal {eps : ℝ} {s : Set A} {t : Finset A}
    (heps : 0 < eps) (hs : TotallyBounded s)
    (hopt : (t.card : WithTop ℕ) = coveringNumber eps s) :
    sqrtEntropy eps s = Real.sqrt (Real.log t.card) := by
  unfold sqrtEntropy metricEntropy
  have hfin : coveringNumber eps s < ⊤ := coveringNumber_lt_top_of_totallyBounded heps hs
  -- The match on coveringNumber eps s
  split
  · -- Case: coveringNumber = ⊤ (contradicts hfin)
    rename_i h
    rw [h] at hfin
    exact absurd rfl (ne_of_lt hfin)
  · -- Case: coveringNumber = n
    rename_i n hn
    -- From hopt and hn, we have t.card = n
    have hcard : t.card = n := by
      rw [hn] at hopt
      exact WithTop.coe_injective hopt
    rw [hcard]
    -- metricEntropyOfNat n vs Real.log n
    unfold metricEntropyOfNat
    split_ifs with h1
    · -- Case n ≤ 1: metricEntropyOfNat = 0
      -- Real.log n ≤ 0 when n ≤ 1 for nat n, and sqrt 0 = 0
      cases n with
      | zero => simp
      | succ m =>
        simp only [Nat.succ_le_succ_iff, Nat.le_zero] at h1
        simp [h1]
    · -- Case n > 1: metricEntropyOfNat = Real.log n
      rfl

/-- For any ε-net, √(log |net|) ≥ sqrtEntropy(ε, s).
    Since coveringNumber ≤ |net|, we have √(log coveringNumber) ≤ √(log |net|). -/
lemma sqrtEntropy_le_sqrt_log_card {eps : ℝ} {s : Set A} {t : Finset A}
    (heps : 0 < eps) (hs : TotallyBounded s) (hnet : IsENet t eps s) :
    sqrtEntropy eps s ≤ Real.sqrt (Real.log t.card) := by
  -- Get optimal net
  obtain ⟨t_opt, hopt_net, hopt_card⟩ := exists_optimal_enet heps hs
  -- sqrtEntropy = √(log |t_opt|)
  have heq := sqrtEntropy_eq_sqrt_log_card_of_optimal heps hs hopt_card
  rw [heq]
  -- Need: √(log |t_opt|) ≤ √(log |t|)
  apply Real.sqrt_le_sqrt
  -- Need: log |t_opt| ≤ log |t|
  have hle : coveringNumber eps s ≤ (t.card : WithTop ℕ) := coveringNumber_le_card hnet
  rw [← hopt_card] at hle
  have hcard_le : t_opt.card ≤ t.card := WithTop.coe_le_coe.mp hle
  -- Cases for log monotonicity
  by_cases h_topt_le : t_opt.card ≤ 1
  · -- If |t_opt| ≤ 1, then log |t_opt| ≤ 0 ≤ log |t| (when |t| ≥ 1)
    have h_log_topt : Real.log (t_opt.card : ℝ) ≤ 0 := by
      interval_cases t_opt.card
      · simp
      · simp
    -- Need 0 ≤ log |t|
    by_cases ht_pos : t.card = 0
    · -- If |t| = 0, then |t_opt| = 0 too
      have : t_opt.card = 0 := Nat.eq_zero_of_le_zero (by omega : t_opt.card ≤ 0)
      simp [this, ht_pos]
    · push_neg at ht_pos
      have ht_ge1 : 1 ≤ t.card := Nat.one_le_iff_ne_zero.mpr ht_pos
      by_cases ht_ge2 : 2 ≤ t.card
      · have : (1 : ℝ) ≤ t.card := by exact_mod_cast ht_ge1
        have hlog_t : 0 ≤ Real.log (t.card : ℝ) := Real.log_nonneg this
        linarith
      · push_neg at ht_ge2
        have : t.card = 1 := by omega
        simp [this]
        exact h_log_topt
  · -- If |t_opt| > 1, use log monotonicity
    push_neg at h_topt_le
    have h_topt_pos : 0 < t_opt.card := by omega
    apply Real.log_le_log
    · exact Nat.cast_pos.mpr h_topt_pos
    · exact Nat.cast_le.mpr hcard_le

/-- If a finset has cardinality ≤ coveringNumber(eps, s), then √(log card) ≤ sqrtEntropy.
    This is the key lemma for using GoodDyadicNets in the Dudley bound. -/
lemma sqrt_log_card_le_sqrtEntropy_of_card_le {eps : ℝ} {s : Set A} {n : ℕ}
    (heps : 0 < eps) (hs : TotallyBounded s)
    (hle : (n : WithTop ℕ) ≤ coveringNumber eps s) :
    Real.sqrt (Real.log n) ≤ sqrtEntropy eps s := by
  have hfin : coveringNumber eps s < ⊤ := coveringNumber_lt_top_of_totallyBounded heps hs
  have hne : coveringNumber eps s ≠ ⊤ := ne_top_of_lt hfin
  -- Get the natural number value of coveringNumber
  let m := (coveringNumber eps s).untop hne
  have hm : coveringNumber eps s = m := (WithTop.coe_untop _ hne).symm
  -- From hle and hm: n ≤ m
  rw [hm] at hle
  have hnm : n ≤ m := WithTop.coe_le_coe.mp hle
  -- sqrtEntropy eps s = √(metricEntropy eps s)
  unfold sqrtEntropy metricEntropy
  split
  · -- Case: coveringNumber = ⊤ (contradicts hfin)
    rename_i h; rw [h] at hfin; exact absurd rfl (ne_of_lt hfin)
  · -- Case: coveringNumber = some m'
    rename_i m' hm'
    -- From hm and hm': m = m'
    have hmm' : m = m' := by
      have h1 : (↑m : WithTop ℕ) = coveringNumber eps s := hm.symm
      have h2 : coveringNumber eps s = ↑m' := hm'
      have : (↑m : WithTop ℕ) = ↑m' := h1.trans h2
      exact WithTop.coe_injective this
    subst hmm'
    -- Need: √(log n) ≤ √(metricEntropyOfNat m)
    apply Real.sqrt_le_sqrt
    -- Need: log n ≤ metricEntropyOfNat m
    unfold metricEntropyOfNat
    split_ifs with h1
    · -- Case m ≤ 1: metricEntropyOfNat = 0
      -- n ≤ m ≤ 1, so log n ≤ 0
      have hn_le : n ≤ 1 := le_trans hnm h1
      interval_cases n
      · simp
      · simp
    · -- Case m > 1: metricEntropyOfNat = log m
      push_neg at h1
      by_cases hn1 : n ≤ 1
      · -- n ≤ 1: log n ≤ 0 ≤ log m
        have hlog_n : Real.log n ≤ 0 := by
          interval_cases n
          · simp
          · simp
        have hlog_m : 0 ≤ Real.log (m : ℝ) := Real.log_nonneg (Nat.one_le_cast.mpr (by omega : 1 ≤ m))
        linarith
      · -- n > 1: use log monotonicity
        push_neg at hn1
        apply Real.log_le_log
        · exact Nat.cast_pos.mpr (by omega : 0 < n)
        · exact Nat.cast_le.mpr hnm

/-- Helper: √(log (a * b)) ≤ √(log a) + √(log b) for a, b ≥ 1.
    Used for bounding edge cardinalities in the Dudley chaining argument. -/
lemma sqrt_log_mul_le {a b : ℕ} (ha : 1 ≤ a) (hb : 1 ≤ b) :
    Real.sqrt (Real.log (a * b)) ≤ Real.sqrt (Real.log a) + Real.sqrt (Real.log b) := by
  by_cases ha2 : a ≤ 1
  · have ha1 : a = 1 := le_antisymm ha2 ha
    simp [ha1]
  by_cases hb2 : b ≤ 1
  · have hb1 : b = 1 := le_antisymm hb2 hb
    simp [hb1]
  push_neg at ha2 hb2
  -- log(a*b) = log a + log b
  have hlog_mul : Real.log ((a : ℝ) * (b : ℝ)) = Real.log (a : ℝ) + Real.log (b : ℝ) := by
    apply Real.log_mul
    · exact Nat.cast_ne_zero.mpr (by omega : a ≠ 0)
    · exact Nat.cast_ne_zero.mpr (by omega : b ≠ 0)
  rw [hlog_mul]
  -- √(x + y) ≤ √x + √y for x, y ≥ 0 (this follows from squaring both sides)
  have hlog_a_nonneg : 0 ≤ Real.log (a : ℝ) := Real.log_nonneg (by norm_cast)
  have hlog_b_nonneg : 0 ≤ Real.log (b : ℝ) := Real.log_nonneg (by norm_cast)
  -- Use √(x + y) ≤ √x + √y which holds when x, y ≥ 0
  -- Proof: √(x + y)² = x + y ≤ x + 2√(xy) + y = (√x + √y)²
  have key : Real.log (a : ℝ) + Real.log (b : ℝ) ≤
      (Real.sqrt (Real.log a) + Real.sqrt (Real.log b))^2 := by
    have hsq_a : Real.sqrt (Real.log (a : ℝ))^2 = Real.log (a : ℝ) := Real.sq_sqrt hlog_a_nonneg
    have hsq_b : Real.sqrt (Real.log (b : ℝ))^2 = Real.log (b : ℝ) := Real.sq_sqrt hlog_b_nonneg
    have hsq : (Real.sqrt (Real.log (a : ℝ)) + Real.sqrt (Real.log (b : ℝ)))^2 =
        Real.log (a : ℝ) + 2 * Real.sqrt (Real.log (a : ℝ)) * Real.sqrt (Real.log (b : ℝ)) + Real.log (b : ℝ) := by
      ring_nf
      rw [hsq_a, hsq_b]
    rw [hsq]
    have h_cross_nonneg : 0 ≤ 2 * Real.sqrt (Real.log (a : ℝ)) * Real.sqrt (Real.log (b : ℝ)) := by positivity
    linarith
  calc Real.sqrt (Real.log (a : ℝ) + Real.log (b : ℝ))
    _ ≤ Real.sqrt ((Real.sqrt (Real.log a) + Real.sqrt (Real.log b))^2) := Real.sqrt_le_sqrt key
    _ = |Real.sqrt (Real.log a) + Real.sqrt (Real.log b)| := Real.sqrt_sq_eq_abs _
    _ = Real.sqrt (Real.log a) + Real.sqrt (Real.log b) := abs_of_nonneg (by positivity)

/-- Each f(j) for j ∈ [1, K+1] appears at most twice when summing f(k+1) + f(k+2). -/
lemma sum_shifted_le_two_sum {f : ℕ → ℝ} (hf : ∀ k, 0 ≤ f k) (K : ℕ) :
    ∑ k ∈ Finset.range K, (f (k + 1) + f (k + 2)) ≤
    2 * ∑ k ∈ Finset.range (K + 2), f k := by
  -- Split the sum: Σ (f(k+1) + f(k+2)) = Σ f(k+1) + Σ f(k+2)
  have hsplit : ∑ k ∈ Finset.range K, (f (k + 1) + f (k + 2)) =
      ∑ k ∈ Finset.range K, f (k + 1) + ∑ k ∈ Finset.range K, f (k + 2) :=
    Finset.sum_add_distrib
  rw [hsplit]
  -- Each shifted sum is a subset of the full range [0, K+2)
  have h1 : ∑ k ∈ Finset.range K, f (k + 1) ≤ ∑ k ∈ Finset.range (K + 2), f k := by
    -- Σ_{k<K} f(k+1) sums over f(1), f(2), ..., f(K)
    -- which is a subset of f(0), f(1), ..., f(K+1) = range (K+2)
    -- Reindex: the shifted range maps to {1, ..., K} ⊆ {0, ..., K+1}
    set s : Finset ℕ := Finset.map ⟨(· + 1), add_left_injective 1⟩ (Finset.range K) with hs_def
    have hbij : ∑ k ∈ Finset.range K, f (k + 1) = ∑ j ∈ s, f j := by
      rw [hs_def, Finset.sum_map]; rfl
    rw [hbij]
    have hsub : s ⊆ Finset.range (K + 2) := by
      intro x hx
      rw [hs_def] at hx
      simp only [Finset.mem_map, Finset.mem_range, Function.Embedding.coeFn_mk] at hx
      obtain ⟨y, hy, rfl⟩ := hx
      simp only [Finset.mem_range]; omega
    -- sum over subset ≤ sum over superset when extra terms are nonnegative
    have hdiff : ∑ j ∈ s, f j = ∑ j ∈ Finset.range (K + 2), f j -
        ∑ j ∈ (Finset.range (K + 2) \ s), f j := by
      rw [← Finset.sum_sdiff hsub]; ring
    rw [hdiff]
    have hnn : 0 ≤ ∑ j ∈ (Finset.range (K + 2) \ s), f j := Finset.sum_nonneg (fun i _ => hf i)
    linarith
  have h2 : ∑ k ∈ Finset.range K, f (k + 2) ≤ ∑ k ∈ Finset.range (K + 2), f k := by
    -- Σ_{k<K} f(k+2) sums over f(2), f(3), ..., f(K+1)
    -- which is a subset of f(0), f(1), ..., f(K+1) = range (K+2)
    set s : Finset ℕ := Finset.map ⟨(· + 2), add_left_injective 2⟩ (Finset.range K) with hs_def
    have hbij : ∑ k ∈ Finset.range K, f (k + 2) = ∑ j ∈ s, f j := by
      rw [hs_def, Finset.sum_map]; rfl
    rw [hbij]
    have hsub : s ⊆ Finset.range (K + 2) := by
      intro x hx
      rw [hs_def] at hx
      simp only [Finset.mem_map, Finset.mem_range, Function.Embedding.coeFn_mk] at hx
      obtain ⟨y, hy, rfl⟩ := hx
      simp only [Finset.mem_range]; omega
    have hdiff : ∑ j ∈ s, f j = ∑ j ∈ Finset.range (K + 2), f j -
        ∑ j ∈ (Finset.range (K + 2) \ s), f j := by
      rw [← Finset.sum_sdiff hsub]; ring
    rw [hdiff]
    have hnn : 0 ≤ ∑ j ∈ (Finset.range (K + 2) \ s), f j := Finset.sum_nonneg (fun i _ => hf i)
    linarith
  calc ∑ k ∈ Finset.range K, f (k + 1) + ∑ k ∈ Finset.range K, f (k + 2)
    _ ≤ ∑ k ∈ Finset.range (K + 2), f k + ∑ k ∈ Finset.range (K + 2), f k := add_le_add h1 h2
    _ = 2 * ∑ k ∈ Finset.range (K + 2), f k := by ring

/-!
## ENNReal Metric Entropy and Dudley Integrand
-/

/-- Metric entropy as ENNReal: max(0, log N(ε, s)).
    This is the non-negative part of the logarithm of the covering number. -/
def metricEntropyENNReal (eps : ℝ) (s : Set A) : ℝ≥0∞ :=
  ENNReal.ofReal (metricEntropy eps s)

/-- Dudley integrand: √(log N(ε, s)), as ENNReal.
    This is the integrand for Dudley's entropy integral. -/
def dudleyIntegrand (eps : ℝ) (s : Set A) : ℝ≥0∞ :=
  ENNReal.ofReal (sqrtEntropy eps s)

lemma dudleyIntegrand_eq_sqrt_metricEntropyENNReal (eps : ℝ) (s : Set A) :
    dudleyIntegrand eps s = ENNReal.ofReal (Real.sqrt (metricEntropy eps s)) := rfl

/-- Dudley integrand is monotone in epsilon (anti-monotone: larger eps → smaller value). -/
lemma dudleyIntegrand_anti_eps {eps1 eps2 : ℝ} {s : Set A}
    (heps : eps1 ≤ eps2) (hfin1 : coveringNumber eps1 s < ⊤) :
    dudleyIntegrand eps2 s ≤ dudleyIntegrand eps1 s :=
  ENNReal.ofReal_le_ofReal (sqrtEntropy_anti_eps heps hfin1)

/-- Dudley integrand is anti-monotone in epsilon for totally bounded sets. -/
lemma dudleyIntegrand_anti_eps_of_totallyBounded {eps1 eps2 : ℝ} {s : Set A}
    (heps1 : 0 < eps1) (heps : eps1 ≤ eps2) (hs : TotallyBounded s) :
    dudleyIntegrand eps2 s ≤ dudleyIntegrand eps1 s :=
  dudleyIntegrand_anti_eps heps (coveringNumber_lt_top_of_totallyBounded heps1 hs)

/-!
## Entropy Integral (ENNReal - Canonical)
-/

/-- Dudley's entropy integral as ENNReal:
    ∫_{(0,D]} √(log N(ε, s)) dε.
    This is the canonical definition; the real version is obtained via `.toReal`. -/
def entropyIntegralENNReal (s : Set A) (D : ℝ) : ℝ≥0∞ :=
  ∫⁻ eps in Set.Ioc (0 : ℝ) D, dudleyIntegrand eps s

/-- Entropy integral ENNReal is monotone in D. -/
lemma entropyIntegralENNReal_mono_D {s : Set A} {D₁ D₂ : ℝ}
    (hD : D₁ ≤ D₂) :
    entropyIntegralENNReal s D₁ ≤ entropyIntegralENNReal s D₂ := by
  unfold entropyIntegralENNReal
  apply lintegral_mono'
  · apply Measure.restrict_mono
    · intro x hx
      exact ⟨hx.1, le_trans hx.2 hD⟩
    · exact le_rfl
  · exact fun _ => le_rfl

/-- Dudley integrand is monotone in the set. -/
lemma dudleyIntegrand_mono_set {eps : ℝ} {s₁ s₂ : Set A}
    (hsub : s₁ ⊆ s₂) (hfin : coveringNumber eps s₂ < ⊤) :
    dudleyIntegrand eps s₁ ≤ dudleyIntegrand eps s₂ :=
  ENNReal.ofReal_le_ofReal (Real.sqrt_le_sqrt (metricEntropy_mono_set hsub hfin))

/-- Entropy integral ENNReal is monotone in the set. -/
lemma entropyIntegralENNReal_mono_set {s₁ s₂ : Set A} {D : ℝ}
    (hsub : s₁ ⊆ s₂)
    (hfin : ∀ eps, 0 < eps → eps ≤ D → coveringNumber eps s₂ < ⊤) :
    entropyIntegralENNReal s₁ D ≤ entropyIntegralENNReal s₂ D := by
  unfold entropyIntegralENNReal
  apply setLIntegral_mono' measurableSet_Ioc
  intro eps heps
  exact dudleyIntegrand_mono_set hsub (hfin eps heps.1 heps.2)

/-- Entropy integral ENNReal is monotone in the set for totally bounded sets. -/
lemma entropyIntegralENNReal_mono_set_of_totallyBounded {s₁ s₂ : Set A} {D : ℝ}
    (hsub : s₁ ⊆ s₂) (hs₂ : TotallyBounded s₂) :
    entropyIntegralENNReal s₁ D ≤ entropyIntegralENNReal s₂ D := by
  apply entropyIntegralENNReal_mono_set hsub
  intro eps heps _
  exact coveringNumber_lt_top_of_totallyBounded heps hs₂

/-!
## Entropy Integral (Real-valued - User-facing)

The real-valued entropy integral is the `.toReal` of the ENNReal version.
It requires a finiteness assumption to be meaningful.
-/

/-- Real-valued entropy integral, obtained from the extended integral via `toReal`.
    It is only meaningful (and useful) when `entropyIntegralENNReal s D < ∞`. -/
def entropyIntegral (s : Set A) (D : ℝ) : ℝ :=
  (entropyIntegralENNReal s D).toReal

/-- Entropy integral is non-negative. -/
lemma entropyIntegral_nonneg {s : Set A} {D : ℝ} :
    0 ≤ entropyIntegral s D :=
  ENNReal.toReal_nonneg

/-- Entropy integral of empty set is 0. -/
lemma entropyIntegral_empty (D : ℝ) : entropyIntegral (∅ : Set A) D = 0 := by
  unfold entropyIntegral entropyIntegralENNReal dudleyIntegrand sqrtEntropy
  simp only [metricEntropy_empty, Real.sqrt_zero, ENNReal.ofReal_zero, lintegral_zero,
    ENNReal.toReal_zero]

/-- Entropy integral is monotone in D (with finiteness assumptions). -/
lemma entropyIntegral_mono_D {s : Set A} {D₁ D₂ : ℝ}
    (hD : D₁ ≤ D₂)
    (hfinite₂ : entropyIntegralENNReal s D₂ ≠ ⊤) :
    entropyIntegral s D₁ ≤ entropyIntegral s D₂ := by
  unfold entropyIntegral
  have hfinite₁ : entropyIntegralENNReal s D₁ ≠ ⊤ :=
    ne_top_of_le_ne_top hfinite₂ (entropyIntegralENNReal_mono_D hD)
  rw [ENNReal.toReal_le_toReal hfinite₁ hfinite₂]
  exact entropyIntegralENNReal_mono_D hD

/-- Entropy integral is monotone in the set (with finiteness assumptions). -/
lemma entropyIntegral_mono_set {s₁ s₂ : Set A} {D : ℝ}
    (hsub : s₁ ⊆ s₂)
    (hfin : ∀ eps, 0 < eps → eps ≤ D → coveringNumber eps s₂ < ⊤)
    (hfinite₂ : entropyIntegralENNReal s₂ D ≠ ⊤) :
    entropyIntegral s₁ D ≤ entropyIntegral s₂ D := by
  unfold entropyIntegral
  have hfinite₁ : entropyIntegralENNReal s₁ D ≠ ⊤ :=
    ne_top_of_le_ne_top hfinite₂ (entropyIntegralENNReal_mono_set hsub hfin)
  rw [ENNReal.toReal_le_toReal hfinite₁ hfinite₂]
  exact entropyIntegralENNReal_mono_set hsub hfin

/-- Entropy integral is monotone in the set for totally bounded sets (with finiteness). -/
lemma entropyIntegral_mono_set_of_totallyBounded {s₁ s₂ : Set A} {D : ℝ}
    (hsub : s₁ ⊆ s₂) (hs₂ : TotallyBounded s₂)
    (hfinite₂ : entropyIntegralENNReal s₂ D ≠ ⊤) :
    entropyIntegral s₁ D ≤ entropyIntegral s₂ D := by
  apply entropyIntegral_mono_set hsub _ hfinite₂
  intro eps heps _
  exact coveringNumber_lt_top_of_totallyBounded heps hs₂

/-- Entropy integral is monotone in D for totally bounded sets (with finiteness). -/
lemma entropyIntegral_mono_D_of_totallyBounded {s : Set A} {D₁ D₂ : ℝ}
    (hD : D₁ ≤ D₂)
    (hfinite₂ : entropyIntegralENNReal s D₂ ≠ ⊤) :
    entropyIntegral s D₁ ≤ entropyIntegral s D₂ :=
  entropyIntegral_mono_D hD hfinite₂

/-!
## Integrability and Real-ENNReal Connection

For totally bounded sets, sqrtEntropy is integrable on [a, b] with a > 0.
-/

/-- For a totally bounded set, sqrtEntropy is bounded on [δ, D] for any δ > 0. -/
lemma sqrtEntropy_bounded_of_totallyBounded {s : Set A} (hs : TotallyBounded s)
    {δ D : ℝ} (hδ : 0 < δ) :
    ∃ M : ℝ, ∀ x ∈ Set.Icc δ D, sqrtEntropy x s ≤ M := by
  use sqrtEntropy δ s
  intro x hx
  apply sqrtEntropy_anti_eps_of_totallyBounded hδ hx.1 hs

/-- For totally bounded sets, sqrtEntropy is antitone on any interval [a, D] with a > 0. -/
lemma sqrtEntropy_antitoneOn_of_totallyBounded {s : Set A} (hs : TotallyBounded s)
    {a D : ℝ} (ha : 0 < a) :
    AntitoneOn (fun x => sqrtEntropy x s) (Set.Icc a D) := by
  intro x hx y hy hxy
  have hx_pos : 0 < x := lt_of_lt_of_le ha hx.1
  exact sqrtEntropy_anti_eps_of_totallyBounded hx_pos hxy hs

/-- sqrtEntropy is integrable on any interval [a, b] with 0 < min a b for totally bounded sets. -/
lemma sqrtEntropy_intervalIntegrable_of_totallyBounded {s : Set A} (hs : TotallyBounded s)
    {a b : ℝ} (ha : 0 < min a b) :
    IntervalIntegrable (fun x => sqrtEntropy x s) MeasureTheory.volume a b := by
  have ha_pos : 0 < a := lt_of_lt_of_le ha (min_le_left a b)
  have hb_pos : 0 < b := lt_of_lt_of_le ha (min_le_right a b)
  have h_anti : AntitoneOn (fun x => sqrtEntropy x s) (Set.uIcc a b) := by
    rw [Set.uIcc_eq_union]
    intro x hx y hy hxy
    have hx_pos : 0 < x := by
      cases hx with
      | inl hx => exact lt_of_lt_of_le ha_pos hx.1
      | inr hx => exact lt_of_lt_of_le hb_pos hx.1
    exact sqrtEntropy_anti_eps_of_totallyBounded hx_pos hxy hs
  have h_int : IntegrableOn (fun x => sqrtEntropy x s) (Set.uIcc a b) volume :=
    AntitoneOn.integrableOn_isCompact isCompact_uIcc h_anti
  exact h_int.intervalIntegrable

/-!
## Dyadic Sum Approximation

For the chaining proof, we relate the entropy integral to a dyadic sum.
-/

/-- Set lintegral over an interval is bounded by length times sup. -/
lemma setLIntegral_Ioc_le_length_mul_sup {f : ℝ → ℝ≥0∞} {a b : ℝ} {M : ℝ≥0∞}
    (hf : ∀ x ∈ Set.Ioc a b, f x ≤ M) :
    ∫⁻ x in Set.Ioc a b, f x ≤ ENNReal.ofReal (b - a) * M := by
  calc ∫⁻ x in Set.Ioc a b, f x
      ≤ ∫⁻ x in Set.Ioc a b, M := setLIntegral_mono' measurableSet_Ioc hf
    _ = M * volume (Set.Ioc a b) := by
          rw [lintegral_const, Measure.restrict_apply MeasurableSet.univ, Set.univ_inter]
    _ = M * ENNReal.ofReal (b - a) := by congr 1; rw [Real.volume_Ioc]
    _ = ENNReal.ofReal (b - a) * M := mul_comm _ _

/-!
## Truncated Entropy Integral

For the dyadic bound, we use truncated integrals over (δ, D] where δ > 0.
This avoids the potential divergence at 0 and is always finite.
-/

/-- Truncated Dudley entropy integral over (δ, D].
    Always finite when δ > 0 because `dudleyIntegrand` is bounded on [δ, D]. -/
def entropyIntegralENNRealTrunc (s : Set A) (δ D : ℝ) : ℝ≥0∞ :=
  ∫⁻ eps in Set.Ioc δ D, dudleyIntegrand eps s

/-- The truncated entropy integral is finite when δ > 0. -/
lemma entropyIntegralENNRealTrunc_lt_top {s : Set A} {δ D : ℝ}
    (hδ : 0 < δ) (hs : TotallyBounded s) :
    entropyIntegralENNRealTrunc s δ D < ⊤ := by
  unfold entropyIntegralENNRealTrunc
  -- dudleyIntegrand is bounded by dudleyIntegrand δ s on (δ, D]
  have hbound : ∀ x ∈ Set.Ioc δ D, dudleyIntegrand x s ≤ dudleyIntegrand δ s := by
    intro x hx
    exact dudleyIntegrand_anti_eps_of_totallyBounded hδ (le_of_lt hx.1) hs
  calc ∫⁻ eps in Set.Ioc δ D, dudleyIntegrand eps s
      ≤ ENNReal.ofReal (D - δ) * dudleyIntegrand δ s :=
        setLIntegral_Ioc_le_length_mul_sup hbound
    _ < ⊤ := by
        apply ENNReal.mul_lt_top
        · exact ENNReal.ofReal_lt_top
        · unfold dudleyIntegrand
          exact ENNReal.ofReal_lt_top

/-- ENNReal dyadic RHS used in the dyadic bound for entropy integral. -/
def dyadicRHS_ENNReal (s : Set A) (D : ℝ) (K : ℕ) : ℝ≥0∞ :=
  ENNReal.ofReal D *
    ∑ k ∈ Finset.range K,
      ENNReal.ofReal ((2 : ℝ)^(-((k : ℤ) + 1))) *
        dudleyIntegrand (D * (2 : ℝ)^(-((k : ℤ) + 1))) s
  + ENNReal.ofReal (D * (2 : ℝ)^(-(K : ℤ))) *
      dudleyIntegrand (D * (2 : ℝ)^(-(K : ℤ))) s

/-- Public dyadic RHS for ENNReal inequality, total in `K`.
    For `K = 0`, we return `⊤` (trivial bound). For `K ≥ 1`, we use the concrete dyadic RHS. -/
def dyadicRHS_ENNReal_total (s : Set A) (D : ℝ) (K : ℕ) : ℝ≥0∞ :=
  if K = 0 then ⊤ else dyadicRHS_ENNReal s D K

/-- Real-valued dyadic RHS used in the real dyadic bound, valid for `K ≥ 1`. -/
def dyadicRHS_real (s : Set A) (D : ℝ) (K : ℕ) : ℝ :=
  D * ∑ k ∈ Finset.range K,
    (2 : ℝ)^(-((k : ℤ) + 1)) *
      sqrtEntropy (D * (2 : ℝ)^(-((k : ℤ) + 1))) s
  + D * (2 : ℝ)^(-(K : ℤ)) *
      sqrtEntropy (D * (2 : ℝ)^(-(K : ℤ))) s

/-- The dyadic RHS is non-negative when D > 0. -/
lemma dyadicRHS_real_nonneg {s : Set A} {D : ℝ} (hD : 0 < D) (K : ℕ) :
    0 ≤ dyadicRHS_real s D K := by
  unfold dyadicRHS_real
  apply add_nonneg
  · apply mul_nonneg (le_of_lt hD)
    apply Finset.sum_nonneg
    intro k _
    apply mul_nonneg (zpow_nonneg (by norm_num : (0:ℝ) ≤ 2) _) (sqrtEntropy_nonneg _ _)
  · apply mul_nonneg
    · apply mul_nonneg (le_of_lt hD) (zpow_nonneg (by norm_num : (0:ℝ) ≤ 2) _)
    · exact sqrtEntropy_nonneg _ _

/-- The ENNReal and real dyadic RHS are related by toReal when the ENNReal version is finite. -/
lemma dyadicRHS_ENNReal_toReal {s : Set A} {D : ℝ} {K : ℕ}
    (hD : 0 < D) :
    (dyadicRHS_ENNReal s D K).toReal = dyadicRHS_real s D K := by
  unfold dyadicRHS_ENNReal dyadicRHS_real dudleyIntegrand
  -- All terms are finite ENNReal.ofReal values, so we can convert to real.
  -- The key lemmas are ENNReal.toReal_add, ENNReal.toReal_mul, ENNReal.toReal_sum.
  have h_sum_finite : ENNReal.ofReal D *
      ∑ k ∈ Finset.range K, ENNReal.ofReal (2 ^ (-((k : ℤ) + 1))) *
        ENNReal.ofReal (sqrtEntropy (D * 2 ^ (-((k : ℤ) + 1))) s) ≠ ⊤ := by
    apply ENNReal.mul_ne_top ENNReal.ofReal_ne_top
    apply ne_top_of_lt
    rw [ENNReal.sum_lt_top]
    intro k _
    exact ENNReal.mul_lt_top ENNReal.ofReal_lt_top ENNReal.ofReal_lt_top
  have h_tail_finite : ENNReal.ofReal (D * 2 ^ (-(K : ℤ))) *
      ENNReal.ofReal (sqrtEntropy (D * 2 ^ (-(K : ℤ))) s) ≠ ⊤ :=
    ENNReal.mul_ne_top ENNReal.ofReal_ne_top ENNReal.ofReal_ne_top
  rw [ENNReal.toReal_add h_sum_finite h_tail_finite]
  congr 1
  · -- Sum part
    rw [ENNReal.toReal_mul, ENNReal.toReal_ofReal (le_of_lt hD)]
    congr 1
    have h_terms_finite : ∀ k ∈ Finset.range K,
        ENNReal.ofReal (2 ^ (-((k : ℤ) + 1))) *
          ENNReal.ofReal (sqrtEntropy (D * 2 ^ (-((k : ℤ) + 1))) s) ≠ ⊤ := fun k _ =>
      ENNReal.mul_ne_top ENNReal.ofReal_ne_top ENNReal.ofReal_ne_top
    rw [ENNReal.toReal_sum h_terms_finite]
    apply Finset.sum_congr rfl
    intro k _
    rw [ENNReal.toReal_mul,
        ENNReal.toReal_ofReal (by positivity : 0 ≤ (2 : ℝ) ^ (-((k : ℤ) + 1))),
        ENNReal.toReal_ofReal (sqrtEntropy_nonneg _ _)]
  · -- Tail part
    rw [ENNReal.toReal_mul,
        ENNReal.toReal_ofReal (by positivity : 0 ≤ D * 2 ^ (-(K : ℤ))),
        ENNReal.toReal_ofReal (sqrtEntropy_nonneg _ _)]

/-- Splitting lemma for truncated integrals: (δ, D] = (δ, c] ∪ (c, D] when δ ≤ c ≤ D. -/
lemma entropyIntegralENNRealTrunc_split {s : Set A} {δ c D : ℝ}
    (hδc : δ ≤ c) (hcD : c ≤ D) :
    entropyIntegralENNRealTrunc s δ D =
      entropyIntegralENNRealTrunc s δ c + entropyIntegralENNRealTrunc s c D := by
  unfold entropyIntegralENNRealTrunc
  have h_union : Set.Ioc δ D = Set.Ioc δ c ∪ Set.Ioc c D := (Set.Ioc_union_Ioc_eq_Ioc hδc hcD).symm
  have h_disj : Disjoint (Set.Ioc δ c) (Set.Ioc c D) := Set.Ioc_disjoint_Ioc_of_le le_rfl
  rw [h_union]
  rw [lintegral_union measurableSet_Ioc h_disj]

/-- Dyadic bound consistency: dyadicRHS(D/2, K) + (D/2)·f(D/2) = dyadicRHS(D, K+1). -/
lemma dyadicRHS_ENNReal_half_step {s : Set A} {D : ℝ} {K : ℕ}
    (hD : 0 < D) :
    dyadicRHS_ENNReal s (D / 2) K + ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s ≤
    dyadicRHS_ENNReal s D (K + 1) := by
  -- Key: (D/2) * 2^{-(k+1)} = D * 2^{-(k+2)} allows reindexing
  apply le_of_eq
  unfold dyadicRHS_ENNReal

  have h2ne : (2 : ℝ) ≠ 0 := by norm_num

  have h_half_tail : (D / 2) * (2 : ℝ) ^ (-(K : ℤ)) = D * (2 : ℝ) ^ (-((K : ℤ) + 1)) := by
    rw [show -((K : ℤ) + 1) = -(K : ℤ) + (-1) by ring]
    rw [zpow_add₀ h2ne, zpow_neg_one]
    ring

  -- Split RHS sum: range (K+1) = {0} ∪ {1, ..., K}
  rw [Finset.sum_range_succ']
  simp only [Nat.cast_zero]

  -- Rewrite LHS tail and extra terms
  have h_tail_eq : ENNReal.ofReal ((D / 2) * (2 : ℝ) ^ (-(K : ℤ))) *
      dudleyIntegrand ((D / 2) * (2 : ℝ) ^ (-(K : ℤ))) s =
      ENNReal.ofReal (D * (2 : ℝ) ^ (-((K : ℤ) + 1))) *
      dudleyIntegrand (D * (2 : ℝ) ^ (-((K : ℤ) + 1))) s := by
    rw [h_half_tail]

  have h_extra_eq : ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s =
      ENNReal.ofReal D * (ENNReal.ofReal ((2 : ℝ) ^ (-(1 : ℤ))) *
        dudleyIntegrand (D * (2 : ℝ) ^ (-(1 : ℤ))) s) := by
    rw [zpow_neg_one]
    have hD2 : D / 2 = D * 2⁻¹ := by ring
    rw [hD2]
    rw [ENNReal.ofReal_mul (le_of_lt hD)]
    ring

  -- Rewrite LHS sum via (D/2) * 2^{-(k+1)} = D * 2^{-(k+2)}
  have h_sum_transform :
      ENNReal.ofReal (D / 2) * ∑ k ∈ Finset.range K,
        ENNReal.ofReal ((2 : ℝ) ^ (-((k : ℤ) + 1))) *
          dudleyIntegrand ((D / 2) * (2 : ℝ) ^ (-((k : ℤ) + 1))) s =
      ENNReal.ofReal D * ∑ k ∈ Finset.range K,
        ENNReal.ofReal ((2 : ℝ) ^ (-(((k : ℤ) + 1) + 1))) *
          dudleyIntegrand (D * (2 : ℝ) ^ (-(((k : ℤ) + 1) + 1))) s := by
    -- Factor out D/2 = D * 2^{-1}
    have hD2 : D / 2 = D * 2⁻¹ := by ring
    rw [hD2, ENNReal.ofReal_mul (le_of_lt hD)]
    rw [Finset.mul_sum, Finset.mul_sum]
    apply Finset.sum_congr rfl
    intro k _
    -- Key identities
    have harg_eq : D * 2⁻¹ * (2 : ℝ) ^ (-((k : ℤ) + 1)) = D * (2 : ℝ) ^ (-((k : ℤ) + 1 + 1)) := by
      have h1 : -((k : ℤ) + 1 + 1) = -((k : ℤ) + 1) + (-1) := by ring
      rw [h1, zpow_add₀ h2ne, zpow_neg_one]
      ring
    have hcoef_eq : (2 : ℝ)⁻¹ * (2 : ℝ) ^ (-((k : ℤ) + 1)) = (2 : ℝ) ^ (-((k : ℤ) + 1 + 1)) := by
      have h1 : -((k : ℤ) + 1 + 1) = -((k : ℤ) + 1) + (-1) := by ring
      rw [h1, zpow_add₀ h2ne, zpow_neg_one, mul_comm]
    -- Transform via algebraic identities
    rw [harg_eq]
    rw [mul_assoc (ENNReal.ofReal D) (ENNReal.ofReal 2⁻¹) _]
    congr 1
    rw [← mul_assoc]
    congr 1
    rw [← ENNReal.ofReal_mul (by norm_num : (0 : ℝ) ≤ 2⁻¹), hcoef_eq]

  -- Now combine everything
  rw [h_sum_transform, h_tail_eq, h_extra_eq]

  -- Rearrange terms using associativity and commutativity
  rw [mul_add, add_assoc, add_assoc]
  congr 1
  rw [add_comm]
  simp only [zero_add, Int.reduceNeg, Nat.cast_add, Nat.cast_one]

/-- Strong dyadic bound for the **truncated** ENNReal entropy integral.

    Let δ_K := D * 2^{-K}. Then for K ≥ 1 and D > 0:
        ∫_{(δ_K, D]} f(ε)dε  ≤  dyadicRHS_ENNReal s D K.

    This statement is always true with no finiteness assumptions,
    because the truncated integral is automatically finite. -/
lemma entropyIntegralENNRealTrunc_le_dyadic_sum_strong
    (s : Set A) (hs : TotallyBounded s) :
    ∀ (K : ℕ), 1 ≤ K →
      ∀ (D : ℝ), 0 < D →
        let δ := D * (2 : ℝ)^(-(K : ℤ))
        entropyIntegralENNRealTrunc s δ D ≤ dyadicRHS_ENNReal s D K := by
  intro K hK
  -- We use strong induction on K starting from K = 1
  induction K with
  | zero => omega
  | succ n IH =>
    cases n with
    | zero =>
      -- Base case: K = 1
      intro D hD
      simp only [Nat.zero_add, Nat.cast_one, zpow_neg_one]
      -- δ = D / 2
      have hδ_eq : D * (2 : ℝ)⁻¹ = D / 2 := by ring
      -- The integrand on (D/2, D] is bounded by f(D/2) (antitonicity)
      have hδ_pos : 0 < D / 2 := by linarith
      have hδ_le_D : D / 2 ≤ D := by linarith
      unfold entropyIntegralENNRealTrunc
      have hbound : ∀ x ∈ Set.Ioc (D / 2) D, dudleyIntegrand x s ≤ dudleyIntegrand (D / 2) s := by
        intro x hx
        exact dudleyIntegrand_anti_eps_of_totallyBounded hδ_pos (le_of_lt hx.1) hs
      calc ∫⁻ eps in Set.Ioc (D * (2 : ℝ)⁻¹) D, dudleyIntegrand eps s
          = ∫⁻ eps in Set.Ioc (D / 2) D, dudleyIntegrand eps s := by rw [hδ_eq]
        _ ≤ ENNReal.ofReal (D - D / 2) * dudleyIntegrand (D / 2) s :=
            setLIntegral_Ioc_le_length_mul_sup hbound
        _ = ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s := by
            congr 1
            · congr 1; ring
        _ ≤ ENNReal.ofReal D * (ENNReal.ofReal ((2 : ℝ)⁻¹) * dudleyIntegrand (D / 2) s) +
              ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s := by
            -- The sum part: D * 2^{-1} * f(D/2) = D/2 * f(D/2)
            -- So LHS ≤ D/2 * f(D/2) + D/2 * f(D/2)
            have h1 : ENNReal.ofReal D * (ENNReal.ofReal ((2 : ℝ)⁻¹) * dudleyIntegrand (D / 2) s)
                = ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s := by
              rw [← mul_assoc, ← ENNReal.ofReal_mul (le_of_lt hD)]
              simp only [mul_comm D 2⁻¹, inv_mul_eq_div]
            rw [h1]
            exact le_add_self
        _ = dyadicRHS_ENNReal s D 1 := by
            -- Unfold dyadicRHS_ENNReal for K = 1
            unfold dyadicRHS_ENNReal
            simp only [Finset.range_one, Finset.sum_singleton, Nat.cast_zero,
              zpow_neg_one, Nat.cast_one]
            ring_nf
    | succ n' =>
      -- Inductive step: K' = n' + 1
      intro D hD
      let K' := n' + 1
      have hK'_ge_1 : 1 ≤ K' := Nat.one_le_of_lt (Nat.lt_add_of_pos_right Nat.zero_lt_one)
      have hK_eq : n' + 2 = K' + 1 := rfl
      have hδ_eq : D * (2 : ℝ) ^ (-((n' + 2 : ℕ) : ℤ)) =
          (D / 2) * (2 : ℝ) ^ (-(K' : ℤ)) := by
        simp only [K', Nat.cast_add, Nat.cast_one, Nat.cast_ofNat]
        have h2ne : (2 : ℝ) ≠ 0 := by norm_num
        rw [show (-(↑n' + 2) : ℤ) = -(↑n' + 1) + (-1) by ring]
        rw [zpow_add₀ h2ne]
        ring
      let δ := D * (2 : ℝ) ^ (-((n' + 2 : ℕ) : ℤ))
      have hδ_pos : 0 < δ := by positivity
      have hδ_le_half : δ ≤ D / 2 := by
        simp only [δ]
        have h1 : (2 : ℝ) ^ (-((n' + 2 : ℕ) : ℤ)) ≤ (2 : ℝ) ^ (-(1 : ℤ)) := by
          apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2 : ℝ))
          simp only [neg_le_neg_iff, Nat.cast_add, Nat.cast_ofNat]
          have : (1 : ℤ) ≤ (n' : ℤ) + 2 := by omega
          exact this
        calc D * (2 : ℝ) ^ (-((n' + 2 : ℕ) : ℤ))
            ≤ D * (2 : ℝ) ^ (-(1 : ℤ)) := by apply mul_le_mul_of_nonneg_left h1 (le_of_lt hD)
          _ = D * 2⁻¹ := by simp only [zpow_neg_one]
          _ = D / 2 := by ring
      have hδ_le_D : δ ≤ D := le_trans hδ_le_half (by linarith)
      have hhalf_le_D : D / 2 ≤ D := by linarith
      have hhalf_pos : 0 < D / 2 := by linarith
      -- Split the integral
      -- Note: goal has `let δ := D * 2 ^ (-↑(n' + 1 + 1))` which equals our local δ = D * 2 ^ (-↑(n' + 2))
      -- n' + 1 + 1 = n' + 2 definitionally, so we can just intro and use the split directly
      intro δ'
      have hδ'_eq : δ' = δ := rfl
      rw [hδ'_eq]
      have hsplit := entropyIntegralENNRealTrunc_split hδ_le_half hhalf_le_D (s := s)
      rw [hsplit]
      -- Bound each part separately
      -- Part 1: (D/2, D] ≤ (D/2) * f(D/2) (this becomes the k=0 term after reindexing)
      have hbound_upper : ∀ x ∈ Set.Ioc (D / 2) D,
          dudleyIntegrand x s ≤ dudleyIntegrand (D / 2) s := by
        intro x hx
        exact dudleyIntegrand_anti_eps_of_totallyBounded hhalf_pos (le_of_lt hx.1) hs
      have h_upper : entropyIntegralENNRealTrunc s (D / 2) D ≤
          ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s := by
        unfold entropyIntegralENNRealTrunc
        calc ∫⁻ eps in Set.Ioc (D / 2) D, dudleyIntegrand eps s
            ≤ ENNReal.ofReal (D - D / 2) * dudleyIntegrand (D / 2) s :=
              setLIntegral_Ioc_le_length_mul_sup hbound_upper
          _ = ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s := by
              congr 1; congr 1; ring
      -- Part 2: (δ, D/2] = ∫ at scale D/2 with K' steps
      -- By IH: entropyIntegralENNRealTrunc s ((D/2) * 2^{-K'}) (D/2) ≤ dyadicRHS_ENNReal s (D/2) K'
      -- Note: δ = (D/2) * 2^{-K'} by hδ_eq
      have h_lower_setup : entropyIntegralENNRealTrunc s δ (D / 2) =
          entropyIntegralENNRealTrunc s ((D / 2) * (2 : ℝ) ^ (-(K' : ℤ))) (D / 2) := by
        congr 1
      have h_IH := IH hK'_ge_1 (D / 2) hhalf_pos
      have h_lower : entropyIntegralENNRealTrunc s δ (D / 2) ≤ dyadicRHS_ENNReal s (D / 2) K' := by
        rw [h_lower_setup]
        exact h_IH
      -- Now combine: LHS ≤ h_lower + h_upper ≤ dyadicRHS at scale D
      calc entropyIntegralENNRealTrunc s δ (D / 2) + entropyIntegralENNRealTrunc s (D / 2) D
          ≤ dyadicRHS_ENNReal s (D / 2) K' + ENNReal.ofReal (D / 2) * dudleyIntegrand (D / 2) s :=
            add_le_add h_lower h_upper
        _ ≤ dyadicRHS_ENNReal s D (K' + 1) :=
            dyadicRHS_ENNReal_half_step hD
        _ = dyadicRHS_ENNReal s D (n' + 2) := rfl

/-- Public dyadic upper bound for the truncated entropy integral. -/
theorem entropyIntegralENNRealTrunc_le_dyadic_sum
    {s : Set A} (hs : TotallyBounded s)
    {D : ℝ} (hD : 0 < D)
    {K : ℕ} (hK : 1 ≤ K) :
    let δ := D * (2 : ℝ)^(-(K : ℤ))
    entropyIntegralENNRealTrunc s δ D ≤ dyadicRHS_ENNReal s D K :=
  entropyIntegralENNRealTrunc_le_dyadic_sum_strong s hs K hK D hD

/-- Real-valued truncated entropy integral over (δ, D]. -/
def entropyIntegralTrunc (s : Set A) (δ D : ℝ) : ℝ :=
  (entropyIntegralENNRealTrunc s δ D).toReal

/-- Real-valued dyadic bound for truncated integrals. -/
theorem entropyIntegralTrunc_le_dyadic_sum_real
    {s : Set A} (hs : TotallyBounded s)
    {D : ℝ} (hD : 0 < D)
    {K : ℕ} (hK : 1 ≤ K) :
    let δ := D * (2 : ℝ)^(-(K : ℤ))
    entropyIntegralTrunc s δ D ≤ dyadicRHS_real s D K := by
  intro δ
  -- Get the ENNReal inequality
  have h_ENNReal := entropyIntegralENNRealTrunc_le_dyadic_sum hs hD hK
  -- Both sides are finite
  have hδ_pos : 0 < δ := by positivity
  have h_lhs_finite : entropyIntegralENNRealTrunc s δ D ≠ ⊤ :=
    ne_top_of_lt (entropyIntegralENNRealTrunc_lt_top hδ_pos hs)
  have h_rhs_finite : dyadicRHS_ENNReal s D K ≠ ⊤ := by
    -- The RHS is a sum of products of ENNReal.ofReal terms, which are finite
    unfold dyadicRHS_ENNReal
    apply ne_top_of_lt
    apply ENNReal.add_lt_top.mpr
    constructor
    · apply ENNReal.mul_lt_top ENNReal.ofReal_lt_top
      rw [ENNReal.sum_lt_top]
      intro k _
      apply ENNReal.mul_lt_top ENNReal.ofReal_lt_top
      unfold dudleyIntegrand
      exact ENNReal.ofReal_lt_top
    · apply ENNReal.mul_lt_top ENNReal.ofReal_lt_top
      unfold dudleyIntegrand
      exact ENNReal.ofReal_lt_top
  -- Convert to real
  have h_toReal := (ENNReal.toReal_le_toReal h_lhs_finite h_rhs_finite).mpr h_ENNReal
  unfold entropyIntegralTrunc
  calc (entropyIntegralENNRealTrunc s δ D).toReal
      ≤ (dyadicRHS_ENNReal s D K).toReal := h_toReal
    _ = dyadicRHS_real s D K := dyadicRHS_ENNReal_toReal hD

/-- Dyadic RHS bounded by twice truncated integral plus tail.

For antitone f ≥ 0 and dyadic points εⱼ = D · 2^{-j}:
  εⱼ · f(εⱼ) ≤ 2 · ∫_{ε_{j+1}}^{εⱼ} f(t) dt

Summing: dyadicRHS ≤ 2 · entropyIntegralTrunc + 2δf(δ). -/
lemma dyadicRHS_le_twice_entropyIntegralTrunc_add_tail
    {s : Set A} (hs : TotallyBounded s)
    {D : ℝ} (hD : 0 < D)
    {K : ℕ} (hK : 1 ≤ K) :
    let δ := D * (2 : ℝ)^(-(K : ℤ))
    dyadicRHS_real s D K ≤ 2 * entropyIntegralTrunc s δ D + 2 * δ * sqrtEntropy δ s := by
  intro δ
  have hδ_pos : 0 < δ := by positivity
  have hδ_le_D : δ ≤ D := by
    simp only [δ]
    have h1 : (2 : ℝ) ^ (-(K : ℤ)) ≤ 1 := zpow_le_one_of_nonpos₀ (by norm_num) (by simp)
    calc D * (2 : ℝ) ^ (-(K : ℤ)) ≤ D * 1 := mul_le_mul_of_nonneg_left h1 (le_of_lt hD)
      _ = D := mul_one D
  have h_trunc_nonneg : 0 ≤ entropyIntegralTrunc s δ D := ENNReal.toReal_nonneg
  have h_sqrtE_nonneg : 0 ≤ sqrtEntropy δ s := sqrtEntropy_nonneg _ _

  -- Case K = 1: dyadicRHS = 2δf(δ), and 2*entropyIntegralTrunc ≥ 0
  -- So dyadicRHS = 2δf(δ) ≤ 2*entropyIntegralTrunc + 2δf(δ) ✓
  by_cases hK1 : K = 1
  · subst hK1
    simp only [] at *
    unfold dyadicRHS_real
    simp only [Finset.range_one, Finset.sum_singleton, Nat.cast_zero,
      neg_add_rev]
    -- Normalize the exponent expressions
    have h_exp_eq1 : (2 : ℝ) ^ ((-1 : ℤ) + (-0 : ℤ)) = 2⁻¹ := by norm_num
    have h_exp_eq2 : (2 : ℝ) ^ (-(1 : ℕ) : ℤ) = 2⁻¹ := by norm_num
    simp only [h_exp_eq1, h_exp_eq2]
    -- dyadicRHS_real s D 1 = D * 2⁻¹ * sqrtE(D/2) + D * 2⁻¹ * sqrtE(D/2) = 2 * (D/2) * sqrtE(D/2)
    have h_eq : D * (2⁻¹ * sqrtEntropy (D * 2⁻¹) s) + D * 2⁻¹ * sqrtEntropy (D * 2⁻¹) s =
        2 * (D * 2⁻¹) * sqrtEntropy (D * 2⁻¹) s := by ring
    rw [h_eq]
    -- Need: 2 * δ * sqrtE(δ) ≤ 2 * entropyIntegralTrunc + 2 * δ * sqrtE(δ)
    -- Note: δ = D * 2⁻¹ since 2 ^ (-↑1) = 2⁻¹
    have h_delta_eq : δ = D * 2⁻¹ := by
      simp only [δ, h_exp_eq2]
    rw [h_delta_eq]
    rw [h_delta_eq] at h_trunc_nonneg
    linarith

  · -- Case K ≥ 2: Use the Riemann sum bound for antitone functions
    have hK_ge_2 : 2 ≤ K := by omega

    have h_trunc_finite : entropyIntegralENNRealTrunc s δ D < ⊤ :=
      entropyIntegralENNRealTrunc_lt_top hδ_pos hs

    -- ε(j) = D * 2^{-j}
    let ε := fun j : ℕ => D * (2 : ℝ)^(-(j : ℤ))

    -- Basic facts about ε
    have hε_pos : ∀ j : ℕ, 0 < ε j := fun j => by positivity
    have hε_K_eq_δ : ε K = δ := rfl

    -- Key algebraic identity: D * 2^{-(k+1)} = ε(k+1)
    have h_term_eq : ∀ k : ℕ,
        D * (2 : ℝ)^(-((k : ℤ) + 1)) * sqrtEntropy (D * (2 : ℝ)^(-((k : ℤ) + 1))) s
        = ε (k + 1) * sqrtEntropy (ε (k + 1)) s := by
      intro k
      simp only [ε]
      congr 2

    -- Rewrite the sum using ε notation
    have h_sum_eq : D * ∑ k ∈ Finset.range K,
        (2 : ℝ)^(-((k : ℤ) + 1)) * sqrtEntropy (D * (2 : ℝ)^(-((k : ℤ) + 1))) s
        = ∑ k ∈ Finset.range K, ε (k + 1) * sqrtEntropy (ε (k + 1)) s := by
      rw [Finset.mul_sum]
      apply Finset.sum_congr rfl
      intro k _
      -- D * (2^{-(k+1)} * sqrtE(D*2^{-(k+1)})) = D*2^{-(k+1)} * sqrtE(D*2^{-(k+1)})
      -- = ε(k+1) * sqrtE(ε(k+1))
      have : D * ((2 : ℝ)^(-((k : ℤ) + 1)) * sqrtEntropy (D * (2 : ℝ)^(-((k : ℤ) + 1))) s) =
          D * (2 : ℝ)^(-((k : ℤ) + 1)) * sqrtEntropy (D * (2 : ℝ)^(-((k : ℤ) + 1))) s := by ring
      rw [this]
      exact h_term_eq k

    -- dyadicRHS_real = Σ_{k<K} ε(k+1) * f(ε(k+1)) + δ * f(δ)
    have h_dyadic_decomp : dyadicRHS_real s D K =
        ∑ k ∈ Finset.range K, ε (k + 1) * sqrtEntropy (ε (k + 1)) s + δ * sqrtEntropy δ s := by
      unfold dyadicRHS_real
      rw [h_sum_eq]

    -- The sum Σ_{k<K} ε(k+1) f(ε(k+1)) = Σ_{j∈{1,...,K}} ε(j) f(ε(j))
    -- Split off the last term (j = K):
    -- = Σ_{j∈{1,...,K-1}} ε(j) f(ε(j)) + ε(K) f(ε(K))
    have h_range_succ : Finset.range K = Finset.range (K - 1) ∪ {K - 1} := by
      ext k
      simp only [Finset.mem_range, Finset.mem_union, Finset.mem_singleton]
      omega

    have h_disjoint : Disjoint (Finset.range (K - 1)) {K - 1} := by
      simp [Finset.disjoint_singleton_right, Finset.mem_range]

    have h_sum_split : ∑ k ∈ Finset.range K, ε (k + 1) * sqrtEntropy (ε (k + 1)) s =
        ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s +
        ε K * sqrtEntropy (ε K) s := by
      rw [h_range_succ, Finset.sum_union h_disjoint]
      simp only [Finset.sum_singleton]
      congr 1
      have : K - 1 + 1 = K := by omega
      rw [this]

    -- Now: dyadicRHS_real = (main sum) + ε(K)*f(ε(K)) + δ*f(δ) = (main sum) + 2δ*f(δ)
    have h_dyadic_eq_main_plus_tail : dyadicRHS_real s D K =
        ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s +
        2 * δ * sqrtEntropy δ s := by
      rw [h_dyadic_decomp, h_sum_split, ← hε_K_eq_δ]
      ring

    -- For totally bounded sets, sqrtEntropy is antitone
    have h_anti : ∀ a b : ℝ, 0 < a → a ≤ b → sqrtEntropy b s ≤ sqrtEntropy a s := by
      intro a b ha hab
      exact sqrtEntropy_anti_eps_of_totallyBounded ha hab hs

    -- Each ε(j+1) = ε(j) / 2, so the interval [ε(j+1), ε(j)] has width ε(j)/2
    have hε_half : ∀ j : ℕ, ε (j + 1) = ε j / 2 := by
      intro j
      simp only [ε]
      rw [show (-(j + 1 : ℕ) : ℤ) = -↑j - 1 by push_cast; ring]
      rw [zpow_sub₀ (by norm_num : (2 : ℝ) ≠ 0), zpow_one]
      ring

    -- Key lemma for each term: ε(j) * f(ε(j)) ≤ 2 * ∫_{Ioc(ε(j+1), ε(j))} (dudleyIntegrand · s)
    have h_term_bound : ∀ j : ℕ, 1 ≤ j →
        ε j * sqrtEntropy (ε j) s ≤
        2 * (∫⁻ t in Set.Ioc (ε (j + 1)) (ε j), dudleyIntegrand t s).toReal := by
      intro j hj
      have hεj_pos : 0 < ε j := hε_pos j
      have hεj1_pos : 0 < ε (j + 1) := hε_pos (j + 1)
      have hεj1_lt_εj : ε (j + 1) < ε j := by
        rw [hε_half j]
        linarith
      have h_width : ε j - ε (j + 1) = ε j / 2 := by
        rw [hε_half j]
        ring
      -- sqrtEntropy is antitone on [ε(j+1), ε(j)]
      have h_anti_interval : ∀ t ∈ Set.Ioc (ε (j + 1)) (ε j),
          sqrtEntropy (ε j) s ≤ sqrtEntropy t s := by
        intro t ht
        exact h_anti t (ε j) (lt_of_le_of_lt (le_of_lt hεj1_pos) ht.1) ht.2
      -- The integral is at least (width) * f(ε(j))
      have h_const_integral : (ε j - ε (j + 1)) * sqrtEntropy (ε j) s =
          (∫⁻ _ in Set.Ioc (ε (j + 1)) (ε j),
            ENNReal.ofReal (sqrtEntropy (ε j) s)).toReal := by
        rw [MeasureTheory.setLIntegral_const, Real.volume_Ioc]
        rw [ENNReal.toReal_mul]
        rw [ENNReal.toReal_ofReal (le_of_lt (by linarith : 0 < ε j - ε (j + 1)))]
        rw [ENNReal.toReal_ofReal (sqrtEntropy_nonneg _ _)]
        ring
      -- The constant integral ≤ the function integral (antitone bound)
      have h_const_le : (∫⁻ _ in Set.Ioc (ε (j + 1)) (ε j), ENNReal.ofReal (sqrtEntropy (ε j) s)) ≤
          (∫⁻ t in Set.Ioc (ε (j + 1)) (ε j), dudleyIntegrand t s) := by
        apply setLIntegral_mono' measurableSet_Ioc
        intro t ht
        unfold dudleyIntegrand
        exact ENNReal.ofReal_le_ofReal (h_anti_interval t ht)
      -- Combine
      calc ε j * sqrtEntropy (ε j) s
          = 2 * ((ε j - ε (j + 1)) * sqrtEntropy (ε j) s) := by rw [h_width]; ring
        _ = 2 * (∫⁻ _ in Set.Ioc (ε (j + 1)) (ε j),
              ENNReal.ofReal (sqrtEntropy (ε j) s)).toReal := by rw [h_const_integral]
        _ ≤ 2 * (∫⁻ t in Set.Ioc (ε (j + 1)) (ε j), dudleyIntegrand t s).toReal := by
            apply mul_le_mul_of_nonneg_left _ (by norm_num : (0 : ℝ) ≤ 2)
            apply ENNReal.toReal_mono _ h_const_le
            -- Finiteness: the integral over a finite interval with bounded integrand is finite
            apply ne_top_of_lt
            calc ∫⁻ t in Set.Ioc (ε (j + 1)) (ε j), dudleyIntegrand t s
                ≤ ∫⁻ t in Set.Ioc (ε (j + 1)) (ε j), dudleyIntegrand (ε (j + 1)) s := by
                  apply setLIntegral_mono' measurableSet_Ioc
                  intro t ht
                  apply dudleyIntegrand_anti_eps_of_totallyBounded hεj1_pos (le_of_lt ht.1) hs
              _ = ENNReal.ofReal (ε j - ε (j + 1)) * dudleyIntegrand (ε (j + 1)) s := by
                  rw [setLIntegral_const, Real.volume_Ioc, mul_comm]
              _ < ⊤ := by
                  apply ENNReal.mul_lt_top
                  · exact ENNReal.ofReal_lt_top
                  · unfold dudleyIntegrand; exact ENNReal.ofReal_lt_top

    have h_main_sum_bound : ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s ≤
        2 * entropyIntegralTrunc s δ D := by
      -- Sum the term bounds
      have h_sum_term_bounds : ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s ≤
          ∑ k ∈ Finset.range (K - 1),
            2 * (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal := by
        apply Finset.sum_le_sum
        intro k hk
        -- k ∈ range (K-1) means k < K-1, so k+1 ≤ K-1, so 1 ≤ k+1
        have h1 : 1 ≤ k + 1 := Nat.le_add_left 1 k
        exact h_term_bound (k + 1) h1

      -- Pull out the factor of 2
      have h_factor_2 : ∑ k ∈ Finset.range (K - 1),
          2 * (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal =
          2 * ∑ k ∈ Finset.range (K - 1),
            (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal := by
        rw [Finset.mul_sum]

      have h_union_bound : ∑ k ∈ Finset.range (K - 1),
          (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal ≤
          entropyIntegralTrunc s δ D := by

        -- First show the ENNReal sum is finite
        have h_each_finite : ∀ k ∈ Finset.range (K - 1),
            (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s) < ⊤ := by
          intro k _
          have hεk2_pos : 0 < ε (k + 2) := hε_pos (k + 2)
          calc ∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s
              ≤ ∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand (ε (k + 2)) s := by
                apply setLIntegral_mono' measurableSet_Ioc
                intro t ht
                apply dudleyIntegrand_anti_eps_of_totallyBounded hεk2_pos (le_of_lt ht.1) hs
            _ = ENNReal.ofReal (ε (k + 1) - ε (k + 2)) * dudleyIntegrand (ε (k + 2)) s := by
                rw [setLIntegral_const, Real.volume_Ioc, mul_comm]
            _ < ⊤ := by
                apply ENNReal.mul_lt_top
                · exact ENNReal.ofReal_lt_top
                · unfold dudleyIntegrand; exact ENNReal.ofReal_lt_top

        -- Each interval Ioc(ε(k+2), ε(k+1)) ⊆ Ioc(δ, D)
        have h_interval_subset : ∀ k ∈ Finset.range (K - 1),
            Set.Ioc (ε (k + 2)) (ε (k + 1)) ⊆ Set.Ioc δ D := by
          intro k hk
          have hk_lt : k < K - 1 := Finset.mem_range.mp hk
          intro t ht
          constructor
          · -- δ = ε(K) ≤ ε(k+2) < t
            calc δ = ε K := rfl
              _ ≤ ε (k + 2) := by
                simp only [ε]
                apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
                apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2 : ℝ))
                simp only [neg_le_neg_iff, Int.ofNat_le]
                omega
              _ < t := ht.1
          · -- t ≤ ε(k+1) ≤ ε(1) = D/2 ≤ D
            calc t ≤ ε (k + 1) := ht.2
              _ ≤ ε 1 := by
                simp only [ε]
                apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
                apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2 : ℝ))
                simp only [neg_le_neg_iff, Int.ofNat_le]
                omega
              _ = D / 2 := by simp only [ε]; ring
              _ ≤ D := by linarith

        -- First, prove intervals are pairwise disjoint
        have h_disjoint_intervals : Set.PairwiseDisjoint (Finset.range (K - 1))
            (fun k => Set.Ioc (ε (k + 2)) (ε (k + 1))) := by
          intro i hi j hj hij
          simp only [Set.disjoint_iff]
          intro x hx
          simp only [Set.mem_Ioc, Set.mem_inter_iff, Set.mem_empty_iff_false] at hx ⊢
          obtain ⟨⟨hi1, hi2⟩, ⟨hj1, hj2⟩⟩ := hx
          by_cases h : i < j
          · have : i + 2 ≤ j + 1 := by omega
            have hε_le : ε (j + 1) ≤ ε (i + 2) := by
              simp only [ε]
              apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
              apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2 : ℝ))
              simp only [neg_le_neg_iff, Int.ofNat_le]
              exact this
            linarith
          · have hji : j < i := lt_of_le_of_ne (le_of_not_gt h) (Ne.symm hij)
            have : j + 2 ≤ i + 1 := by omega
            have hε_le : ε (i + 1) ≤ ε (j + 2) := by
              simp only [ε]
              apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
              apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2 : ℝ))
              simp only [neg_le_neg_iff, Int.ofNat_le]
              exact this
            linarith

        -- Union of intervals is contained in Ioc δ D
        have h_union_subset : ⋃ k ∈ Finset.range (K - 1),
            Set.Ioc (ε (k + 2)) (ε (k + 1)) ⊆ Set.Ioc δ D := by
          intro x hx
          simp only [Set.mem_iUnion, Finset.mem_range] at hx
          obtain ⟨k, hk, hxk⟩ := hx
          exact h_interval_subset k (Finset.mem_range.mpr hk) hxk

        -- The ENNReal sum of the integrals via disjoint union
        have h_ennreal_sum : ∑ k ∈ Finset.range (K - 1),
            (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s) ≤
            entropyIntegralENNRealTrunc s δ D := by
          -- Sum = integral over disjoint union ≤ integral over Ioc δ D
          calc ∑ k ∈ Finset.range (K - 1),
              (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s)
              = ∫⁻ t in ⋃ k ∈ Finset.range (K - 1), Set.Ioc (ε (k + 2)) (ε (k + 1)),
                  dudleyIntegrand t s := by
                symm
                apply MeasureTheory.lintegral_biUnion_finset
                · exact h_disjoint_intervals
                · intro k _; exact measurableSet_Ioc
            _ ≤ ∫⁻ t in Set.Ioc δ D, dudleyIntegrand t s := by
                apply MeasureTheory.lintegral_mono'
                · exact Measure.restrict_mono h_union_subset le_rfl
                · exact fun _ => le_rfl
            _ = entropyIntegralENNRealTrunc s δ D := rfl

        -- Now convert to real: ∑ (f k).toReal = (∑ f k).toReal ≤ entropyIntegralTrunc
        have h_sum_finite : ∑ k ∈ Finset.range (K - 1),
            (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s) < ⊤ :=
          lt_of_le_of_lt h_ennreal_sum h_trunc_finite
        -- Convert sum of toReal to toReal of sum
        have h_toReal_sum : ∑ k ∈ Finset.range (K - 1),
            (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal =
            (∑ k ∈ Finset.range (K - 1),
              ∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal := by
          symm
          apply ENNReal.toReal_sum
          intro k hk
          exact ne_top_of_lt (h_each_finite k hk)
        rw [h_toReal_sum]
        unfold entropyIntegralTrunc
        exact (ENNReal.toReal_le_toReal (ne_top_of_lt h_sum_finite)
          (ne_top_of_lt h_trunc_finite)).mpr h_ennreal_sum

      calc ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s
          ≤ ∑ k ∈ Finset.range (K - 1),
              2 * (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal :=
            h_sum_term_bounds
        _ = 2 * ∑ k ∈ Finset.range (K - 1),
              (∫⁻ t in Set.Ioc (ε (k + 2)) (ε (k + 1)), dudleyIntegrand t s).toReal :=
            h_factor_2
        _ ≤ 2 * entropyIntegralTrunc s δ D :=
            mul_le_mul_of_nonneg_left h_union_bound (by norm_num : (0 : ℝ) ≤ 2)

    -- Final step: combine the decomposition with the main sum bound
    calc dyadicRHS_real s D K
        = ∑ k ∈ Finset.range (K - 1), ε (k + 1) * sqrtEntropy (ε (k + 1)) s +
          2 * δ * sqrtEntropy δ s := h_dyadic_eq_main_plus_tail
      _ ≤ 2 * entropyIntegralTrunc s δ D + 2 * δ * sqrtEntropy δ s := by
          linarith [h_main_sum_bound]

/-!
## Real-Valued Entropy Integral Identification

Under finiteness, the ENNReal entropy integral equals a real Lebesgue integral.
-/

/-- The truncated ENNReal entropy integral is monotone in K (larger K means smaller δ_K). -/
lemma entropyIntegralENNRealTrunc_mono_K
    {s : Set A} {D : ℝ} (hD : 0 < D) :
    Monotone (fun K : ℕ => entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D) := by
  intro K₁ K₂ hK
  unfold entropyIntegralENNRealTrunc
  apply lintegral_mono'
  · apply Measure.restrict_mono
    · -- Ioc δ_{K₁} D ⊆ Ioc δ_{K₂} D when K₁ ≤ K₂ (δ_{K₂} ≤ δ_{K₁})
      intro x hx
      constructor
      · -- δ_{K₂} < x
        calc D * 2 ^ (-(K₂ : ℤ)) ≤ D * 2 ^ (-(K₁ : ℤ)) := by
              apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
              apply zpow_le_zpow_right₀ (by norm_num : 1 ≤ (2:ℝ))
              simp only [neg_le_neg_iff, Int.ofNat_le]
              exact hK
          _ < x := hx.1
      · exact hx.2
    · exact le_rfl
  · exact fun _ => le_rfl

/-- The truncated ENNReal entropy integral is bounded by the full integral. -/
lemma entropyIntegralENNRealTrunc_le
    {s : Set A} {D : ℝ} (hD : 0 < D) (K : ℕ) :
    entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D ≤ entropyIntegralENNReal s D := by
  unfold entropyIntegralENNRealTrunc entropyIntegralENNReal
  apply lintegral_mono'
  · apply Measure.restrict_mono
    · intro x hx
      exact ⟨lt_of_le_of_lt (by positivity) hx.1, hx.2⟩
    · exact le_rfl
  · exact fun _ => le_rfl

/-- The supremum of truncated ENNReal entropy integrals equals the full integral.
    This follows from the fact that ⋃_K Ioc(δ_K, D] = Ioc(0, D] as K → ∞. -/
lemma iSup_entropyIntegralENNRealTrunc_eq
    {s : Set A} {D : ℝ} (hD : 0 < D) :
    ⨆ K : ℕ, entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D = entropyIntegralENNReal s D := by
  unfold entropyIntegralENNRealTrunc entropyIntegralENNReal
  apply le_antisymm
  · -- ⨆ K, ∫⁻ on Ioc(δ_K, D] ≤ ∫⁻ on Ioc(0, D]
    apply iSup_le
    intro K
    apply lintegral_mono'
    · apply Measure.restrict_mono
      · intro x hx
        exact ⟨lt_of_le_of_lt (by positivity) hx.1, hx.2⟩
      · exact le_rfl
    · exact fun _ => le_rfl
  · -- Monotone convergence: Ioc(D*2^{-K}, D] increasing with union Ioc(0, D]
    -- δ_K = D * 2^{-K} is decreasing
    have h_delta_anti : StrictAnti (fun K : ℕ => D * (2 : ℝ)^(-(K:ℤ))) := by
      intro K L hKL
      apply mul_lt_mul_of_pos_left _ hD
      -- Need: 2^{-L} < 2^{-K}
      simp only [zpow_neg, zpow_natCast]
      rw [inv_eq_one_div, inv_eq_one_div]
      apply one_div_lt_one_div_of_lt (by positivity)
      have h_nat : (2 : ℕ) ^ K < (2 : ℕ) ^ L := Nat.pow_lt_pow_right (by norm_num) hKL
      exact_mod_cast h_nat

    -- The sets Ioc(D * 2^{-K}, D) are increasing (directed by monotone)
    have h_sets_mono : Monotone (fun K : ℕ => Set.Ioc (D * 2^(-(K:ℤ))) D) := by
      intro K L hKL
      apply Set.Ioc_subset_Ioc_left
      rcases eq_or_lt_of_le hKL with rfl | hKL
      · exact le_refl _
      · exact le_of_lt (h_delta_anti hKL)

    -- The union of Ioc(D * 2^{-K}, D) equals Ioc(0, D)
    have h_union : ⋃ K : ℕ, Set.Ioc (D * 2^(-(K:ℤ))) D = Set.Ioc 0 D := by
      ext x
      constructor
      · intro hx
        simp only [Set.mem_iUnion, Set.mem_Ioc] at hx
        obtain ⟨K, hK⟩ := hx
        exact ⟨lt_of_le_of_lt (by positivity) hK.1, hK.2⟩
      · intro hx
        simp only [Set.mem_iUnion, Set.mem_Ioc] at *
        have h_tends : Filter.Tendsto (fun K : ℕ => D * 2^(-(K:ℤ))) Filter.atTop (nhds 0) := by
          have h1 : Filter.Tendsto (fun K : ℕ => (2 : ℝ)^(-(K:ℤ))) Filter.atTop (nhds 0) := by
            simp only [zpow_neg, zpow_natCast]
            -- (2^K)⁻¹ = (1/2)^K
            have h_eq : ∀ K : ℕ, ((2 : ℝ) ^ K)⁻¹ = (1/2 : ℝ) ^ K := by
              intro K
              rw [one_div, inv_pow]
            simp only [h_eq]
            exact tendsto_pow_atTop_nhds_zero_of_lt_one (by norm_num : (0 : ℝ) ≤ 1/2)
              (by norm_num : (1 : ℝ) / 2 < 1)
          convert Filter.Tendsto.const_mul D h1 using 1
          simp only [mul_zero]
        -- Find K such that D * 2^{-K} < x
        have h_ev := (Metric.tendsto_atTop.mp h_tends (x / 2) (by linarith))
        obtain ⟨K, hK⟩ := h_ev
        use K
        specialize hK K (le_refl K)
        simp only [Real.dist_eq, sub_zero, abs_of_nonneg (by positivity : 0 ≤ D * 2^(-(K:ℤ)))] at hK
        constructor
        · linarith
        · exact hx.2

    -- Apply setLIntegral_iUnion_of_directed
    rw [← h_union]
    have h_directed : Directed (· ⊆ ·) (fun K : ℕ => Set.Ioc (D * 2^(-(K:ℤ))) D) :=
      h_sets_mono.directed_le
    rw [MeasureTheory.setLIntegral_iUnion_of_directed (dudleyIntegrand · s) h_directed]

/-- Truncated entropy integral converges to full entropy integral as K → ∞. -/
lemma entropyIntegralTrunc_tendsto_entropyIntegral
    {s : Set A} {D : ℝ}
    (hD : 0 < D)
    (hfinite : entropyIntegralENNReal s D ≠ ⊤) :
    Filter.Tendsto (fun K : ℕ => entropyIntegralTrunc s (D * 2^(-(K:ℤ))) D)
      Filter.atTop (nhds (entropyIntegral s D)) := by
  unfold entropyIntegralTrunc entropyIntegral
  have h_ennreal_mono : Monotone (fun K : ℕ => entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D) :=
    entropyIntegralENNRealTrunc_mono_K hD
  have h_tendsto_ennreal : Filter.Tendsto
      (fun K : ℕ => entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D)
      Filter.atTop (nhds (entropyIntegralENNReal s D)) := by
    rw [← iSup_entropyIntegralENNRealTrunc_eq hD]
    exact tendsto_atTop_iSup h_ennreal_mono
  -- Each truncated integral is bounded by the full integral, hence finite
  have h_trunc_finite : ∀ K : ℕ, entropyIntegralENNRealTrunc s (D * 2^(-(K:ℤ))) D ≠ ⊤ := by
    intro K
    exact ne_top_of_le_ne_top hfinite (entropyIntegralENNRealTrunc_le hD K)
  rw [ENNReal.tendsto_toReal_iff h_trunc_finite hfinite]
  exact h_tendsto_ennreal

/-!
## Key Upstream Lemmas for Dudley's Theorem
-/

/-- Truncated entropy integral ≤ full entropy integral (real-valued). -/
lemma entropyIntegralTrunc_le_entropyIntegral
    {s : Set A} {D : ℝ} (hD : 0 < D) (K : ℕ)
    (hfinite : entropyIntegralENNReal s D ≠ ⊤) :
    entropyIntegralTrunc s (D * 2^(-(K:ℤ))) D ≤ entropyIntegral s D := by
  unfold entropyIntegralTrunc entropyIntegral
  apply ENNReal.toReal_mono hfinite
  exact entropyIntegralENNRealTrunc_le hD K

/-- For antitone f ≥ 0: δ·f(δ) ≤ ∫_0^δ f ≤ entropyIntegral. Key for dyadicRHS bound. -/
lemma delta_sqrtEntropy_le_entropyIntegral
    {s : Set A} (hs : TotallyBounded s)
    {D : ℝ} {δ : ℝ} (hδ_pos : 0 < δ) (hδ_le_D : δ ≤ D)
    (hfinite : entropyIntegralENNReal s D ≠ ⊤) :
    δ * sqrtEntropy δ s ≤ entropyIntegral s D := by
  -- sqrtEntropy is antitone: for t ≤ δ, sqrtEntropy t s ≥ sqrtEntropy δ s
  have h_anti : ∀ t ∈ Set.Ioc 0 δ, sqrtEntropy δ s ≤ sqrtEntropy t s := by
    intro t ht
    exact sqrtEntropy_anti_eps_of_totallyBounded ht.1 ht.2 hs
  have h_sqrtEntropy_nonneg : 0 ≤ sqrtEntropy δ s := sqrtEntropy_nonneg δ s
  -- Key insight: δ * f(δ) = ∫_{(0,δ]} f(δ) dt ≤ ∫_{(0,δ]} f(t) dt ≤ ∫_{(0,D]} f(t) dt
  -- Step 1: δ * sqrtEntropy δ s as an integral of constant over (0, δ]
  have h_const_integral : δ * sqrtEntropy δ s =
      (∫⁻ _ in Set.Ioc 0 δ, ENNReal.ofReal (sqrtEntropy δ s)).toReal := by
    rw [MeasureTheory.setLIntegral_const, Real.volume_Ioc, sub_zero]
    rw [ENNReal.toReal_mul, ENNReal.toReal_ofReal (le_of_lt hδ_pos),
        ENNReal.toReal_ofReal h_sqrtEntropy_nonneg]
    ring
  -- Step 2: Ioc 0 δ ⊆ Ioc 0 D
  have h_subset : Set.Ioc 0 δ ⊆ Set.Ioc 0 D := fun x hx => ⟨hx.1, le_trans hx.2 hδ_le_D⟩
  -- Step 3: Integral over (0, δ] ≤ integral over (0, D]
  have h_int_mono : (∫⁻ t in Set.Ioc 0 δ, dudleyIntegrand t s) ≤
      (∫⁻ t in Set.Ioc 0 D, dudleyIntegrand t s) := by
    apply lintegral_mono'
    · exact Measure.restrict_mono h_subset le_rfl
    · exact fun _ => le_rfl
  -- Step 4: Finiteness of the restricted integral
  have h_finite_subset : (∫⁻ t in Set.Ioc 0 δ, dudleyIntegrand t s) ≠ ⊤ :=
    ne_top_of_le_ne_top hfinite h_int_mono
  -- Step 5: ∫ (constant f(δ)) ≤ ∫ f(t) on (0, δ]
  have h_const_le_func : (∫⁻ _ in Set.Ioc 0 δ, ENNReal.ofReal (sqrtEntropy δ s)) ≤
      (∫⁻ t in Set.Ioc 0 δ, dudleyIntegrand t s) := by
    apply setLIntegral_mono' measurableSet_Ioc
    intro t ht
    unfold dudleyIntegrand
    exact ENNReal.ofReal_le_ofReal (h_anti t ht)
  -- Step 6: Combine
  calc δ * sqrtEntropy δ s
      = (∫⁻ _ in Set.Ioc 0 δ, ENNReal.ofReal (sqrtEntropy δ s)).toReal := h_const_integral
    _ ≤ (∫⁻ t in Set.Ioc 0 δ, dudleyIntegrand t s).toReal := by
        apply ENNReal.toReal_mono h_finite_subset h_const_le_func
    _ ≤ (∫⁻ t in Set.Ioc 0 D, dudleyIntegrand t s).toReal := by
        apply ENNReal.toReal_mono hfinite h_int_mono
    _ = entropyIntegral s D := rfl

/-- dyadicRHS ≤ 4 · entropyIntegral. Combines dyadic bound with integral monotonicity. -/
lemma dyadicRHS_le_four_times_entropyIntegral
    {s : Set A} (hs : TotallyBounded s)
    {D : ℝ} (hD : 0 < D)
    {K : ℕ} (hK : 1 ≤ K)
    (hfinite : entropyIntegralENNReal s D ≠ ⊤) :
    dyadicRHS_real s D K ≤ 4 * entropyIntegral s D := by
  -- δ = D * 2^{-K}
  let δ := D * (2 : ℝ)^(-(K : ℤ))
  have hδ_pos : 0 < δ := by positivity
  have hδ_le_D : δ ≤ D := by
    simp only [δ]
    have h1 : (2 : ℝ) ^ (-(K : ℤ)) ≤ 1 := zpow_le_one_of_nonpos₀ (by norm_num) (by simp)
    calc D * (2 : ℝ) ^ (-(K : ℤ)) ≤ D * 1 := mul_le_mul_of_nonneg_left h1 (le_of_lt hD)
      _ = D := mul_one D
  -- Step 1: dyadicRHS ≤ 2 * entropyIntegralTrunc + 2 * δ * sqrtEntropy δ s
  have h_dyadic_upper := dyadicRHS_le_twice_entropyIntegralTrunc_add_tail hs hD hK
  -- Step 2: entropyIntegralTrunc ≤ entropyIntegral
  have h_trunc_le := entropyIntegralTrunc_le_entropyIntegral hD K hfinite
  -- Step 3: δ * sqrtEntropy δ s ≤ entropyIntegral
  have h_tail_le := delta_sqrtEntropy_le_entropyIntegral hs hδ_pos hδ_le_D hfinite
  -- Combine
  calc dyadicRHS_real s D K
      ≤ 2 * entropyIntegralTrunc s δ D + 2 * δ * sqrtEntropy δ s := h_dyadic_upper
    _ ≤ 2 * entropyIntegral s D + 2 * entropyIntegral s D := by linarith
    _ = 4 * entropyIntegral s D := by ring


end
