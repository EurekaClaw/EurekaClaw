/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.Analysis.SpecialFunctions.Log.Basic
import Mathlib.Analysis.SpecialFunctions.Log.NegMulLog
import Mathlib.Analysis.SpecialFunctions.Log.Deriv
import Mathlib.Analysis.SpecialFunctions.Sqrt
import Mathlib.Analysis.Calculus.MeanValue
import Mathlib.Analysis.Calculus.Deriv.Pow
import Mathlib.Analysis.Calculus.Deriv.Add
import Mathlib.Analysis.Calculus.Deriv.Mul
import Mathlib.Analysis.Calculus.Deriv.Comp

/-!
# Two-Point Inequality and Rothaus Lemma

This file proves two-sided bounds on the entropy of a two-point distribution,
which are key ingredients for the Bernoulli and Gaussian log-Sobolev inequalities.

## Main results

* `two_point_inequality`: For a, b > 0, the midpoint entropy exceeds the average
  entropy by at most (√a - √b)²/2:
  `(a+b)/2 * log((a+b)/2) - (a*log(a) + b*log(b))/2 ≤ (√a - √b)²/2`.

* `two_point_entropy_lower_bound`: Equivalent lower bound form of `two_point_inequality`.

* `rothaus_lemma`: For a, b > 0, the average entropy exceeds the midpoint entropy
  by at most (√a - √b)²/2:
  `(a*log(a) + b*log(b))/2 - (a+b)/2 * log((a+b)/2) ≤ (√a - √b)²/2`.

-/

open Real Set Filter
open scoped BigOperators Topology

noncomputable section

namespace LogSobolev

/-!
## Part 1: Basic helper functions and their properties
-/

/-- g₊(t) = (1 + t) * log(1 + t) for t > -1 -/
def gPlus (t : ℝ) : ℝ := (1 + t) * log (1 + t)

/-- g₋(t) = (1 - t) * log(1 - t) for t < 1 -/
def gMinus (t : ℝ) : ℝ := (1 - t) * log (1 - t)

/-- The auxiliary function φ(t) = (1+t)log(1+t) + (1-t)log(1-t) for t ∈ (-1, 1). -/
def phi (t : ℝ) : ℝ := gPlus t + gMinus t

/-!
## Part 2: Values at zero
-/

@[simp] theorem gPlus_zero : gPlus 0 = 0 := by simp [gPlus]

@[simp] theorem gMinus_zero : gMinus 0 = 0 := by simp [gMinus]

@[simp] theorem phi_zero : phi 0 = 0 := by simp [phi]

/-!
## Part 3: Symmetry
-/

theorem phi_neg (t : ℝ) : phi (-t) = phi t := by
  simp only [phi, gPlus, gMinus]
  ring_nf

/-!
## Part 4: Differentiability of components
-/

theorem differentiableAt_gPlus {t : ℝ} (ht : -1 < t) : DifferentiableAt ℝ gPlus t := by
  unfold gPlus
  have h : 0 < 1 + t := by linarith
  have h1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
  have h2 : DifferentiableAt ℝ (fun s => log (1 + s)) t :=
    (differentiableAt_log h.ne').comp t h1
  exact h1.mul h2

theorem differentiableAt_gMinus {t : ℝ} (ht : t < 1) : DifferentiableAt ℝ gMinus t := by
  unfold gMinus
  have h : 0 < 1 - t := by linarith
  have h1 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
  have h2 : DifferentiableAt ℝ (fun s => log (1 - s)) t :=
    (differentiableAt_log h.ne').comp t h1
  exact h1.mul h2

theorem differentiableAt_phi {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) : DifferentiableAt ℝ phi t := by
  unfold phi
  exact (differentiableAt_gPlus ht.1).add (differentiableAt_gMinus ht.2)

/-!
## Part 5: First derivatives
-/

theorem deriv_gPlus {t : ℝ} (ht : -1 < t) : deriv gPlus t = log (1 + t) + 1 := by
  unfold gPlus
  have h : 0 < 1 + t := by linarith
  have h1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
  have h2 : DifferentiableAt ℝ (fun s => log (1 + s)) t :=
    (differentiableAt_log h.ne').comp t h1
  -- Apply deriv_mul with explicit equality
  have h_deriv : deriv (fun t => (1 + t) * log (1 + t)) t =
      deriv (fun s => 1 + s) t * log (1 + t) + (1 + t) * deriv (fun s => log (1 + s)) t :=
    deriv_mul h1 h2
  rw [h_deriv]
  -- Derivative of (1 + s) is 1
  have d1 : deriv (fun s => 1 + s) t = 1 := by
    have hd : HasDerivAt (fun s => 1 + s) 1 t := by
      convert (hasDerivAt_id t).const_add (1 : ℝ) using 2
    exact hd.deriv
  -- Derivative of log(1 + s) using chain rule
  have d2 : deriv (fun s => log (1 + s)) t = 1 / (1 + t) := by
    rw [deriv.log h1 h.ne', d1]
  rw [d1, d2]
  field_simp

theorem deriv_gMinus {t : ℝ} (ht : t < 1) : deriv gMinus t = -log (1 - t) - 1 := by
  unfold gMinus
  have h : 0 < 1 - t := by linarith
  have h1 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
  have h2 : DifferentiableAt ℝ (fun s => log (1 - s)) t :=
    (differentiableAt_log h.ne').comp t h1
  -- Apply deriv_mul with explicit equality
  have h_deriv : deriv (fun t => (1 - t) * log (1 - t)) t =
      deriv (fun s => 1 - s) t * log (1 - t) + (1 - t) * deriv (fun s => log (1 - s)) t :=
    deriv_mul h1 h2
  rw [h_deriv]
  -- Derivative of (1 - s) is -1
  have d1 : deriv (fun s => 1 - s) t = -1 := by
    have hd : HasDerivAt (fun s => 1 - s) (-1) t := by
      convert (hasDerivAt_id t).const_sub (1 : ℝ) using 2
    exact hd.deriv
  -- Derivative of log(1 - s) using chain rule
  have d2 : deriv (fun s => log (1 - s)) t = -1 / (1 - t) := by
    rw [deriv.log h1 h.ne', d1]
  rw [d1, d2]
  field_simp
  ring

theorem deriv_phi {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    deriv phi t = log (1 + t) - log (1 - t) := by
  unfold phi
  have h_deriv : deriv (fun t => gPlus t + gMinus t) t =
      deriv gPlus t + deriv gMinus t :=
    deriv_add (differentiableAt_gPlus ht.1) (differentiableAt_gMinus ht.2)
  rw [h_deriv, deriv_gPlus ht.1, deriv_gMinus ht.2]
  ring

theorem deriv_phi_zero : deriv phi 0 = 0 := by
  have h : (0 : ℝ) ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith, by linarith⟩
  rw [deriv_phi h]
  simp

/-!
## Part 6: Second derivatives
-/

theorem deriv_deriv_gPlus {t : ℝ} (ht : -1 < t) : deriv (deriv gPlus) t = 1 / (1 + t) := by
  have h : 0 < 1 + t := by linarith
  have hdiff : (fun s => deriv gPlus s) =ᶠ[𝓝 t] (fun s => log (1 + s) + 1) := by
    have hopen : Ioi (-1 : ℝ) ∈ 𝓝 t := Ioi_mem_nhds ht
    filter_upwards [hopen] with s hs
    exact deriv_gPlus hs
  rw [Filter.EventuallyEq.deriv_eq hdiff]
  have h1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
  have hlog_diff : DifferentiableAt ℝ (fun s => log (1 + s)) t := (differentiableAt_log h.ne').comp t h1
  have h_deriv_add : deriv (fun s => log (1 + s) + 1) t =
      deriv (fun s => log (1 + s)) t + deriv (fun _ => (1 : ℝ)) t :=
    deriv_add hlog_diff (differentiableAt_const 1)
  rw [h_deriv_add]
  simp only [deriv_const, add_zero]
  rw [deriv.log h1 h.ne']
  have d1 : deriv (fun s => 1 + s) t = 1 := by
    have hd : HasDerivAt (fun s => 1 + s) 1 t := by
      convert (hasDerivAt_id t).const_add (1 : ℝ) using 2
    exact hd.deriv
  rw [d1]

theorem deriv_deriv_gMinus {t : ℝ} (ht : t < 1) : deriv (deriv gMinus) t = 1 / (1 - t) := by
  have h : 0 < 1 - t := by linarith
  have hdiff : (fun s => deriv gMinus s) =ᶠ[𝓝 t] (fun s => -log (1 - s) - 1) := by
    have hopen : Iio (1 : ℝ) ∈ 𝓝 t := Iio_mem_nhds ht
    filter_upwards [hopen] with s hs
    exact deriv_gMinus hs
  rw [Filter.EventuallyEq.deriv_eq hdiff]
  have h1 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
  have hlog_diff : DifferentiableAt ℝ (fun s => log (1 - s)) t := (differentiableAt_log h.ne').comp t h1
  have h_deriv_sub : deriv (fun s => -log (1 - s) - 1) t =
      deriv (fun y => -log (1 - y)) t - deriv (fun _ => (1 : ℝ)) t :=
    deriv_sub hlog_diff.neg (differentiableAt_const 1)
  rw [h_deriv_sub]
  simp only [deriv_const, sub_zero]
  have hd_neg : deriv (fun y => -log (1 - y)) t = -deriv (fun s => log (1 - s)) t :=
    hlog_diff.hasDerivAt.neg.deriv
  rw [hd_neg, deriv.log h1 h.ne']
  have d1 : deriv (fun s => 1 - s) t = -1 := by
    have hd : HasDerivAt (fun s => 1 - s) (-1) t := by
      convert (hasDerivAt_id t).const_sub (1 : ℝ) using 2
    exact hd.deriv
  rw [d1]
  ring

theorem deriv2_phi {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    deriv (deriv phi) t = 2 / (1 - t^2) := by
  have h1 : 0 < 1 + t := by linarith [ht.1]
  have h2 : 0 < 1 - t := by linarith [ht.2]
  have hdiff : (fun s => deriv phi s) =ᶠ[𝓝 t] (fun s => log (1 + s) - log (1 - s)) := by
    have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
    filter_upwards [hopen] with s hs
    exact deriv_phi hs
  rw [Filter.EventuallyEq.deriv_eq hdiff]
  have hd1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
  have hd2 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
  have hlog1_diff : DifferentiableAt ℝ (fun s => log (1 + s)) t := (differentiableAt_log h1.ne').comp t hd1
  have hlog2_diff : DifferentiableAt ℝ (fun s => log (1 - s)) t := (differentiableAt_log h2.ne').comp t hd2
  have h_deriv_sub : deriv (fun s => log (1 + s) - log (1 - s)) t =
      deriv (fun s => log (1 + s)) t - deriv (fun s => log (1 - s)) t :=
    deriv_sub hlog1_diff hlog2_diff
  rw [h_deriv_sub, deriv.log hd1 h1.ne', deriv.log hd2 h2.ne']
  have dd1 : deriv (fun s => 1 + s) t = 1 := by
    have hd : HasDerivAt (fun s => 1 + s) 1 t := by
      convert (hasDerivAt_id t).const_add (1 : ℝ) using 2
    exact hd.deriv
  have dd2 : deriv (fun s => 1 - s) t = -1 := by
    have hd : HasDerivAt (fun s => 1 - s) (-1) t := by
      convert (hasDerivAt_id t).const_sub (1 : ℝ) using 2
    exact hd.deriv
  rw [dd1, dd2]
  have h3 : (1 : ℝ) - t ^ 2 = (1 + t) * (1 - t) := by ring
  rw [h3]
  field_simp [h1.ne', h2.ne']
  ring

/-!
## Part 7: Key bound on second derivative
-/

theorem deriv2_phi_ge_two {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    2 ≤ deriv (deriv phi) t := by
  rw [deriv2_phi ht]
  have h : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  have h' : 1 - t^2 ≤ 1 := by nlinarith [sq_nonneg t]
  have h1 : 1 ≤ 1 / (1 - t^2) := one_le_div h |>.mpr h'
  calc 2 = 2 * 1 := by ring
    _ ≤ 2 * (1 / (1 - t^2)) := by nlinarith
    _ = 2 / (1 - t^2) := by ring

/-!
## Part 8: Nonnegativity of φ
-/

/-- φ(t) ≥ 0 for t ∈ (-1, 1).
    Proof: φ is strictly convex with minimum at 0 where φ(0) = 0. -/
theorem phi_nonneg {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) : 0 ≤ phi t := by
  -- φ(t) ≥ 0 follows from strict convexity: φ''(t) > 0, φ(0) = 0, φ'(0) = 0
  -- The minimum of a strictly convex function is where the derivative vanishes
  -- Since φ'(0) = 0, t = 0 is the minimum, and φ(0) = 0, so φ(t) ≥ 0
  by_cases ht0 : t = 0
  · simp [ht0]
  -- For t ≠ 0, use that φ is strictly increasing for t > 0 and strictly decreasing for t < 0
  -- (since φ'(t) = log(1+t) - log(1-t) which is positive for t > 0 and negative for t < 0)
  rcases lt_trichotomy t 0 with ht_neg | ht_zero | ht_pos
  · -- Case t < 0: φ'(t) < 0, so φ is decreasing. Since t < 0 and φ(0) = 0, we have φ(t) > φ(0) = 0
    -- Use MVT: φ(0) - φ(t) = φ'(ξ) * (0 - t) for some ξ ∈ (t, 0)
    have hcont : ContinuousOn phi (Icc t 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_phi hx_mem).continuousAt.continuousWithinAt
    have hdiff : DifferentiableOn ℝ phi (Ioo t 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_phi hx_mem).differentiableWithinAt
    obtain ⟨ξ, hξ_mem, hξ_eq⟩ := exists_deriv_eq_slope phi (by linarith : t < 0) hcont hdiff
    rw [phi_zero] at hξ_eq
    have hξ_in : ξ ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hξ_mem.1], by linarith [hξ_mem.2]⟩
    have hderiv_ξ : deriv phi ξ < 0 := by
      rw [deriv_phi hξ_in]
      have h1' : 0 < 1 + ξ := by linarith [hξ_in.1]
      have hξ_neg : ξ < 0 := hξ_mem.2
      have : log (1 + ξ) < log (1 - ξ) := by
        apply log_lt_log h1'
        linarith
      linarith
    have ht_ne : t ≠ 0 := by linarith
    have hphi_eq : phi t = deriv phi ξ * t := by
      have h := hξ_eq
      field_simp [ht_ne] at h
      -- h : deriv phi ξ * t = phi t
      linarith
    rw [hphi_eq]
    -- deriv phi ξ < 0 and t < 0, so their product is positive
    exact le_of_lt (mul_pos_of_neg_of_neg hderiv_ξ ht_neg)
  · exact absurd ht_zero ht0
  · -- Case t > 0: φ'(t) > 0, so φ is increasing. Use MVT similarly.
    have hcont : ContinuousOn phi (Icc 0 t) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hx.2]⟩
      exact (differentiableAt_phi hx_mem).continuousAt.continuousWithinAt
    have hdiff : DifferentiableOn ℝ phi (Ioo 0 t) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hx.2]⟩
      exact (differentiableAt_phi hx_mem).differentiableWithinAt
    obtain ⟨ξ, hξ_mem, hξ_eq⟩ := exists_deriv_eq_slope phi ht_pos hcont hdiff
    rw [phi_zero] at hξ_eq
    have hξ_in : ξ ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hξ_mem.1], by linarith [ht.2, hξ_mem.2]⟩
    have hderiv_ξ : 0 < deriv phi ξ := by
      rw [deriv_phi hξ_in]
      have h2' : 0 < 1 - ξ := by linarith [hξ_in.2]
      have hξ_pos : 0 < ξ := hξ_mem.1
      have : log (1 - ξ) < log (1 + ξ) := by
        apply log_lt_log h2'
        linarith
      linarith
    -- From hξ_eq: deriv phi ξ = (phi t - 0) / (t - 0)
    -- Multiply both sides by t to get: deriv phi ξ * t = phi t
    have ht_ne : t ≠ 0 := by linarith
    have hphi_eq : phi t = deriv phi ξ * t := by
      have h := hξ_eq
      field_simp [ht_ne] at h
      -- h : deriv phi ξ * t = phi t
      linarith
    rw [hphi_eq]
    exact le_of_lt (mul_pos hderiv_ξ ht_pos)

/-!
## Part 9: Main Two-Point Inequality
-/

/-- The two-point inequality:
    For a, b > 0, the midpoint entropy excess is bounded by the squared root difference.

    (a+b)/2 * log((a+b)/2) - (a*log(a) + b*log(b))/2 ≤ (√a - √b)²/2 -/
theorem two_point_inequality {a b : ℝ} (ha : 0 < a) (hb : 0 < b) :
    (a + b) / 2 * log ((a + b) / 2) - (a * log a + b * log b) / 2
    ≤ (sqrt a - sqrt b) ^ 2 / 2 := by
  have hLHS_le_zero : (a + b) / 2 * log ((a + b) / 2) - (a * log a + b * log b) / 2 ≤ 0 := by
    -- Use convexity of x*log(x) on [0, ∞)
    have hconv := Real.convexOn_mul_log
    -- For the midpoint with weights 1/2 and 1/2
    have ha_mem : a ∈ Set.Ici (0 : ℝ) := le_of_lt ha
    have hb_mem : b ∈ Set.Ici (0 : ℝ) := le_of_lt hb
    have hw1 : (0 : ℝ) ≤ 1/2 := by norm_num
    have hw2 : (0 : ℝ) ≤ 1/2 := by norm_num
    have hsum : (1/2 : ℝ) + 1/2 = 1 := by norm_num
    -- Apply convexity definition
    have hconvex := hconv.2 ha_mem hb_mem hw1 hw2 hsum
    simp only [smul_eq_mul] at hconvex
    -- hconvex : (1/2 * a + 1/2 * b) * log(1/2 * a + 1/2 * b) ≤ 1/2 * (a * log a) + 1/2 * (b * log b)
    have hmid' : 1/2 * a + 1/2 * b = (a + b) / 2 := by ring
    rw [hmid'] at hconvex
    have hrhs : 1/2 * (a * log a) + 1/2 * (b * log b) = (a * log a + b * log b) / 2 := by ring
    rw [hrhs] at hconvex
    linarith
  have hRHS_ge_zero : 0 ≤ (sqrt a - sqrt b) ^ 2 / 2 := by
    apply div_nonneg
    · exact sq_nonneg _
    · norm_num
  linarith

/-- Equivalent form: entropy of the two-point distribution is bounded below. -/
theorem two_point_entropy_lower_bound {a b : ℝ} (ha : 0 < a) (hb : 0 < b) :
    -(sqrt a - sqrt b)^2 / 2 ≤
    (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2) := by
  have h := two_point_inequality ha hb
  linarith

/-!
## Part 10: The Rothaus Lemma
-/

/-- The RHS term in Rothaus: 2 - 2√(1-t²) = (√(1+t) - √(1-t))² -/
theorem sqrt_diff_sq_eq {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    (sqrt (1 + t) - sqrt (1 - t))^2 = 2 - 2 * sqrt (1 - t^2) := by
  have h1 : 0 ≤ 1 + t := by linarith [ht.1]
  have h2 : 0 ≤ 1 - t := by linarith [ht.2]
  rw [sub_sq, sq_sqrt h1, sq_sqrt h2]
  -- Goal: 1 + t - 2 * √(1+t) * √(1-t) + (1 - t) = 2 - 2 * √(1 - t²)
  have hsqrt_mul : sqrt (1 + t) * sqrt (1 - t) = sqrt ((1 + t) * (1 - t)) :=
    (sqrt_mul h1 (1 - t)).symm
  have hmul : (1 + t) * (1 - t) = 1 - t^2 := by ring
  calc 1 + t - 2 * sqrt (1 + t) * sqrt (1 - t) + (1 - t)
      = 2 - 2 * (sqrt (1 + t) * sqrt (1 - t)) := by ring
    _ = 2 - 2 * sqrt ((1 + t) * (1 - t)) := by rw [hsqrt_mul]
    _ = 2 - 2 * sqrt (1 - t^2) := by rw [hmul]

/-- Key function: g(t) = 2 - 2√(1-t²) - φ(t). The Rothaus lemma says g ≥ 0. -/
def rothausDefect (t : ℝ) : ℝ := 2 - 2 * sqrt (1 - t^2) - phi t

@[simp] theorem rothausDefect_zero : rothausDefect 0 = 0 := by
  simp only [rothausDefect, sq, mul_zero, sub_zero, sqrt_one, mul_one, sub_self, phi_zero]

/-- The sqrt term in rothausDefect: s(t) = 2 - 2√(1-t²) -/
def sqrtTerm (t : ℝ) : ℝ := 2 - 2 * sqrt (1 - t^2)

@[simp] theorem sqrtTerm_zero : sqrtTerm 0 = 0 := by
  simp [sqrtTerm]

/-- First derivative of sqrtTerm -/
theorem deriv_sqrtTerm {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    deriv sqrtTerm t = 2 * t / sqrt (1 - t^2) := by
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  unfold sqrtTerm
  have hd1 : DifferentiableAt ℝ (fun s => 1 - s^2) t := by
    apply DifferentiableAt.sub
    · exact differentiableAt_const 1
    · exact differentiableAt_pow 2
  have hd2 : DifferentiableAt ℝ (fun s => sqrt (1 - s^2)) t :=
    hd1.sqrt h1.ne'
  -- Compute the derivative using the chain rule
  have h_deriv : deriv (fun s => 2 - 2 * sqrt (1 - s^2)) t =
      deriv (fun _ => (2 : ℝ)) t - deriv (fun s => 2 * sqrt (1 - s^2)) t := by
    have hd_const : DifferentiableAt ℝ (fun _ : ℝ => (2 : ℝ)) t := differentiableAt_const 2
    have hd_mul : DifferentiableAt ℝ (fun s => 2 * sqrt (1 - s^2)) t := hd2.const_mul 2
    exact deriv_sub hd_const hd_mul
  -- Explicitly compute deriv (fun s => 1 - s^2) t
  have hd_inner_val : deriv (fun s => 1 - s^2) t = -2 * t := by
    have hd_const : DifferentiableAt ℝ (fun _ : ℝ => (1 : ℝ)) t := differentiableAt_const 1
    have hd_pow : DifferentiableAt ℝ (fun s => s^2) t := differentiableAt_pow 2
    have h_sub_deriv : deriv (fun s => 1 - s^2) t = deriv (fun _ => (1 : ℝ)) t - deriv (fun s => s^2) t :=
      deriv_sub hd_const hd_pow
    -- Compute deriv (fun s => s^2) t explicitly using HasDerivAt
    have hd_sq : deriv (fun s : ℝ => s^2) t = 2 * t := by
      have h := hasDerivAt_pow 2 t
      rw [h.deriv]
      ring
    rw [h_sub_deriv, deriv_const, hd_sq]
    ring
  rw [h_deriv, deriv_const, deriv_const_mul _ hd2, deriv_sqrt hd1 h1.ne', hd_inner_val]
  field_simp [(sqrt_pos.mpr h1).ne']
  ring

/-- sqrtTerm is nonnegative for all reals (minimum value 0 at t = 0) -/
theorem sqrtTerm_ge_zero (t : ℝ) : 0 ≤ sqrtTerm t := by
  unfold sqrtTerm
  have h' : sqrt (1 - t^2) ≤ 1 := by
    rw [sqrt_le_one]
    nlinarith [sq_nonneg t]
  linarith

/-- The derivative of sqrtTerm at 0 is 0 -/
theorem deriv_sqrtTerm_zero : deriv sqrtTerm 0 = 0 := by
  have h0 : (0 : ℝ) ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith, by linarith⟩
  rw [deriv_sqrtTerm h0]
  simp

/-- Differentiability of rothausDefect on (-1, 1) -/
theorem differentiableAt_rothausDefect {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    DifferentiableAt ℝ rothausDefect t := by
  unfold rothausDefect
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  have hd1 : DifferentiableAt ℝ (fun s => 2 - 2 * sqrt (1 - s^2)) t := by
    have h' : DifferentiableAt ℝ (fun s => 1 - s^2) t :=
      differentiableAt_const 1 |>.sub (differentiableAt_pow 2)
    exact (differentiableAt_const 2).sub (h'.sqrt h1.ne' |>.const_mul 2)
  exact hd1.sub (differentiableAt_phi ht)

/-- The derivative of rothausDefect -/
theorem deriv_rothausDefect {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    deriv rothausDefect t = 2 * t / sqrt (1 - t^2) - (log (1 + t) - log (1 - t)) := by
  unfold rothausDefect
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  have hd1 : DifferentiableAt ℝ (fun s => 2 - 2 * sqrt (1 - s^2)) t := by
    have h' : DifferentiableAt ℝ (fun s => 1 - s^2) t :=
      differentiableAt_const 1 |>.sub (differentiableAt_pow 2)
    exact (differentiableAt_const 2).sub (h'.sqrt h1.ne' |>.const_mul 2)
  -- Compute the derivative as difference of derivatives
  have h_deriv : deriv (fun s => 2 - 2 * sqrt (1 - s^2) - phi s) t =
      deriv (fun s => 2 - 2 * sqrt (1 - s^2)) t - deriv phi t :=
    deriv_sub hd1 (differentiableAt_phi ht)
  rw [h_deriv]
  -- deriv sqrtTerm = 2t/√(1-t²) and deriv phi = log(1+t) - log(1-t)
  have h_sqrtTerm_eq : deriv (fun s => 2 - 2 * sqrt (1 - s^2)) t = deriv sqrtTerm t := by
    have : (fun s => 2 - 2 * sqrt (1 - s^2)) = sqrtTerm := by ext s; simp only [sqrtTerm]
    rw [this]
  rw [h_sqrtTerm_eq, deriv_sqrtTerm ht, deriv_phi ht]

/-- The derivative of rothausDefect at 0 is 0 -/
theorem deriv_rothausDefect_zero : deriv rothausDefect 0 = 0 := by
  have h0 : (0 : ℝ) ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith, by linarith⟩
  rw [deriv_rothausDefect h0]
  simp

/-- Second derivative of sqrtTerm: d²/dt²[2 - 2√(1-t²)] = 2/(1-t²)^(3/2) -/
theorem deriv2_sqrtTerm {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    deriv (deriv sqrtTerm) t = 2 / (1 - t^2) * (1 / sqrt (1 - t^2)) := by
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  -- First, establish that deriv sqrtTerm is 2s/√(1-s²) in a neighborhood
  have hdiff : (fun s => deriv sqrtTerm s) =ᶠ[𝓝 t] (fun s => 2 * s / sqrt (1 - s^2)) := by
    have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
    filter_upwards [hopen] with s hs
    exact deriv_sqrtTerm hs
  -- Use the filter equality to compute the second derivative
  have hderiv_eq : deriv (deriv sqrtTerm) t = deriv (fun s => 2 * s / sqrt (1 - s^2)) t :=
    Filter.EventuallyEq.deriv_eq hdiff
  -- Compute d/ds[2s/√(1-s²)]
  have hd_inner : DifferentiableAt ℝ (fun s => 1 - s^2) t :=
    differentiableAt_const 1 |>.sub (differentiableAt_pow 2)
  have hd_sqrt : DifferentiableAt ℝ (fun s => sqrt (1 - s^2)) t := hd_inner.sqrt h1.ne'
  have hd_num : DifferentiableAt ℝ (fun s => (2 : ℝ) * s) t :=
    differentiableAt_const (2 : ℝ) |>.mul differentiableAt_id
  -- Apply deriv_div with explicit equality
  have h_deriv_div : deriv (fun s => 2 * s / sqrt (1 - s^2)) t =
      (deriv (fun s => (2 : ℝ) * s) t * sqrt (1 - t^2) -
       (2 : ℝ) * t * deriv (fun s => sqrt (1 - s^2)) t) / (sqrt (1 - t^2))^2 :=
    deriv_div hd_num hd_sqrt (sqrt_ne_zero'.mpr h1)
  rw [hderiv_eq, h_deriv_div]
  -- Simplify the derivatives
  have d_num : deriv (fun s => (2 : ℝ) * s) t = 2 := by
    have : deriv (fun s => (2 : ℝ) * s) t = 2 * deriv id t := deriv_const_mul 2 differentiableAt_id
    simp [this]
  have d_inner : deriv (fun s => 1 - s^2) t = -2 * t := by
    have hd_const : DifferentiableAt ℝ (fun _ : ℝ => (1 : ℝ)) t := differentiableAt_const 1
    have hd_pow : DifferentiableAt ℝ (fun s => s^2) t := differentiableAt_pow 2
    have h_sub_deriv : deriv (fun s => 1 - s^2) t = deriv (fun _ => (1 : ℝ)) t - deriv (fun s => s^2) t :=
      deriv_sub hd_const hd_pow
    have hd_sq : deriv (fun s : ℝ => s^2) t = 2 * t := by
      have h := hasDerivAt_pow 2 t
      rw [h.deriv]
      ring
    rw [h_sub_deriv, deriv_const, hd_sq]
    ring
  have d_sqrt : deriv (fun s => sqrt (1 - s^2)) t = -t / sqrt (1 - t^2) := by
    rw [deriv_sqrt hd_inner h1.ne', d_inner]
    field_simp [(sqrt_pos.mpr h1).ne']
  rw [d_num, d_sqrt]
  field_simp [(sqrt_pos.mpr h1).ne']
  -- Goal: (1 - t ^ 2) * (√(1 - t ^ 2) ^ 2 - -t ^ 2) = √(1 - t ^ 2) ^ 2
  -- Using √(1 - t ^ 2) ^ 2 = 1 - t ^ 2 since h1 : 0 < 1 - t^2
  have hsq : sqrt (1 - t^2) ^ 2 = 1 - t^2 := sq_sqrt h1.le
  rw [hsq]
  ring

/-- The second derivative of rothausDefect is nonnegative:
    g''(t) = 2/(1-t²)^(3/2) - 2/(1-t²) = 2/(1-t²) · (1/√(1-t²) - 1) ≥ 0 -/
theorem deriv2_rothausDefect_nonneg {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    0 ≤ deriv (deriv rothausDefect) t := by
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  have hsqrt_pos : 0 < sqrt (1 - t^2) := sqrt_pos.mpr h1
  have hsqrt_le_one : sqrt (1 - t^2) ≤ 1 := by
    rw [sqrt_le_one]
    nlinarith [sq_nonneg t]
  -- Compute deriv (deriv rothausDefect) = deriv (deriv sqrtTerm) - deriv (deriv phi)
  have heq : (fun s => deriv rothausDefect s) =ᶠ[𝓝 t]
      (fun s => deriv sqrtTerm s - deriv phi s) := by
    have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
    filter_upwards [hopen] with s hs
    rw [deriv_rothausDefect hs, deriv_sqrtTerm hs, deriv_phi hs]
  -- Use the filter equality to compute the second derivative
  have hderiv_eq : deriv (deriv rothausDefect) t =
      deriv (fun s => deriv sqrtTerm s - deriv phi s) t :=
    Filter.EventuallyEq.deriv_eq heq
  -- Need differentiability of deriv sqrtTerm and deriv phi
  have hd_sqrtTerm' : DifferentiableAt ℝ (deriv sqrtTerm) t := by
    have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
    have heq2 : (fun s => deriv sqrtTerm s) =ᶠ[𝓝 t] (fun s => 2 * s / sqrt (1 - s^2)) := by
      filter_upwards [hopen] with s hs; exact deriv_sqrtTerm hs
    have hd_num : DifferentiableAt ℝ (fun s => (2 : ℝ) * s) t :=
      differentiableAt_const (2 : ℝ) |>.mul differentiableAt_id
    have hd_inner : DifferentiableAt ℝ (fun s => 1 - s^2) t :=
      differentiableAt_const 1 |>.sub (differentiableAt_pow 2)
    have hdiff_rhs : DifferentiableAt ℝ (fun s => 2 * s / sqrt (1 - s^2)) t :=
      hd_num.div (hd_inner.sqrt h1.ne') (sqrt_ne_zero'.mpr h1)
    exact hdiff_rhs.congr_of_eventuallyEq heq2
  have hd_phi' : DifferentiableAt ℝ (deriv phi) t := by
    have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
    have heq2 : (fun s => deriv phi s) =ᶠ[𝓝 t] (fun s => log (1 + s) - log (1 - s)) := by
      filter_upwards [hopen] with s hs; exact deriv_phi hs
    have h1p : 0 < 1 + t := by linarith [ht.1]
    have h1m : 0 < 1 - t := by linarith [ht.2]
    have hd1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
    have hd2 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
    have hdiff_rhs : DifferentiableAt ℝ (fun s => log (1 + s) - log (1 - s)) t :=
      ((differentiableAt_log h1p.ne').comp t hd1).sub ((differentiableAt_log h1m.ne').comp t hd2)
    exact hdiff_rhs.congr_of_eventuallyEq heq2
  -- Apply deriv_sub and the second derivative formulas
  have hderiv_sub : deriv (fun s => deriv sqrtTerm s - deriv phi s) t =
      deriv (deriv sqrtTerm) t - deriv (deriv phi) t :=
    deriv_sub hd_sqrtTerm' hd_phi'
  rw [hderiv_eq, hderiv_sub, deriv2_sqrtTerm ht, deriv2_phi ht]
  -- Goal: 0 ≤ 2/(1-t²) * (1/√(1-t²)) - 2/(1-t²)
  --     = 2/(1-t²) * (1/√(1-t²) - 1)
  have hfactor : 2 / (1 - t^2) * (1 / sqrt (1 - t^2)) - 2 / (1 - t^2) =
      2 / (1 - t^2) * (1 / sqrt (1 - t^2) - 1) := by
    field_simp [h1.ne', hsqrt_pos.ne']
  rw [hfactor]
  apply mul_nonneg
  · exact div_nonneg (by norm_num : (0 : ℝ) ≤ 2) h1.le
  · rw [sub_nonneg, one_le_div hsqrt_pos]
    exact hsqrt_le_one

/-- Differentiability of deriv rothausDefect on (-1, 1) -/
theorem differentiableAt_deriv_rothausDefect {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) :
    DifferentiableAt ℝ (deriv rothausDefect) t := by
  have h1 : 0 < 1 - t^2 := by nlinarith [ht.1, ht.2, sq_nonneg t]
  have hopen : Ioo (-1 : ℝ) 1 ∈ 𝓝 t := Ioo_mem_nhds ht.1 ht.2
  have heq : (fun s => deriv rothausDefect s) =ᶠ[𝓝 t]
      (fun s => 2 * s / sqrt (1 - s^2) - (log (1 + s) - log (1 - s))) := by
    filter_upwards [hopen] with s hs
    rw [deriv_rothausDefect hs]
  have h1p : 0 < 1 + t := by linarith [ht.1]
  have h1m : 0 < 1 - t := by linarith [ht.2]
  have hd_num : DifferentiableAt ℝ (fun s => (2 : ℝ) * s) t :=
    differentiableAt_const (2 : ℝ) |>.mul differentiableAt_id
  have hd_inner : DifferentiableAt ℝ (fun s => 1 - s^2) t :=
    differentiableAt_const 1 |>.sub (differentiableAt_pow 2)
  have hd1 : DifferentiableAt ℝ (fun s => 1 + s) t := differentiableAt_id.const_add 1
  have hd2 : DifferentiableAt ℝ (fun s => 1 - s) t := differentiableAt_id.const_sub 1
  have hdiff_rhs : DifferentiableAt ℝ (fun s => 2 * s / sqrt (1 - s^2) - (log (1 + s) - log (1 - s))) t :=
    (hd_num.div (hd_inner.sqrt h1.ne') (sqrt_ne_zero'.mpr h1)).sub
      (((differentiableAt_log h1p.ne').comp t hd1).sub ((differentiableAt_log h1m.ne').comp t hd2))
  exact hdiff_rhs.congr_of_eventuallyEq heq

/-- The Rothaus defect is nonnegative: 2 - 2√(1-t²) ≥ φ(t). -/
theorem rothausDefect_nonneg {t : ℝ} (ht : t ∈ Ioo (-1 : ℝ) 1) : 0 ≤ rothausDefect t := by
  by_cases ht0 : t = 0
  · simp [ht0]
  -- For t ≠ 0, use MVT twice
  rcases lt_trichotomy t 0 with ht_neg | ht_zero | ht_pos
  · -- Case t < 0: use MVT on [t, 0]
    have hcont : ContinuousOn rothausDefect (Icc t 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_rothausDefect hx_mem).continuousAt.continuousWithinAt
    have hdiff : DifferentiableOn ℝ rothausDefect (Ioo t 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_rothausDefect hx_mem).differentiableWithinAt
    obtain ⟨ξ₁, hξ₁_mem, hξ₁_eq⟩ := exists_deriv_eq_slope rothausDefect ht_neg hcont hdiff
    simp only [rothausDefect_zero] at hξ₁_eq
    -- rothausDefect(0) - rothausDefect(t) = deriv rothausDefect(ξ₁) * (0 - t)
    -- So rothausDefect(t) = -deriv rothausDefect(ξ₁) * (-t) = deriv rothausDefect(ξ₁) * t
    -- Now apply MVT again to deriv rothausDefect on [ξ₁, 0]
    have hξ₁_neg : ξ₁ < 0 := hξ₁_mem.2
    have hcont' : ContinuousOn (deriv rothausDefect) (Icc ξ₁ 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hξ₁_mem.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_deriv_rothausDefect hx_mem).continuousAt.continuousWithinAt
    have hdiff' : DifferentiableOn ℝ (deriv rothausDefect) (Ioo ξ₁ 0) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hξ₁_mem.1, hx.1], by linarith [hx.2]⟩
      exact (differentiableAt_deriv_rothausDefect hx_mem).differentiableWithinAt
    obtain ⟨ξ₂, hξ₂_mem, hξ₂_eq⟩ := exists_deriv_eq_slope (deriv rothausDefect) hξ₁_neg hcont' hdiff'
    simp only [deriv_rothausDefect_zero] at hξ₂_eq
    -- deriv rothausDefect(0) - deriv rothausDefect(ξ₁) = deriv² rothausDefect(ξ₂) * (0 - ξ₁)
    -- So deriv rothausDefect(ξ₁) = -deriv² rothausDefect(ξ₂) * (-ξ₁) = deriv² rothausDefect(ξ₂) * ξ₁
    have hξ₂_in : ξ₂ ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [ht.1, hξ₁_mem.1, hξ₂_mem.1], by linarith [hξ₂_mem.2]⟩
    have h_deriv_ξ₁ : deriv rothausDefect ξ₁ = deriv (deriv rothausDefect) ξ₂ * ξ₁ := by
      -- hξ₂_eq : deriv (deriv rothausDefect) ξ₂ = (0 - deriv rothausDefect ξ₁) / (0 - ξ₁)
      have hξ₁_ne : ξ₁ ≠ 0 := ne_of_lt hξ₁_neg
      have h1 : deriv (deriv rothausDefect) ξ₂ * (0 - ξ₁) = 0 - deriv rothausDefect ξ₁ := by
        rw [hξ₂_eq, div_mul_cancel₀]
        exact sub_ne_zero.mpr hξ₁_ne.symm
      simp only [zero_sub] at h1
      linarith
    -- Now combine: rothausDefect(t) = deriv rothausDefect(ξ₁) * t / t = -deriv rothausDefect(ξ₁) * (-t) / (-t)
    have h_rothausDefect_t : rothausDefect t = deriv (deriv rothausDefect) ξ₂ * ξ₁ * t := by
      -- hξ₁_eq : deriv rothausDefect ξ₁ = (0 - rothausDefect t) / (0 - t)
      have ht_ne : t ≠ 0 := ne_of_lt ht_neg
      have h1 : deriv rothausDefect ξ₁ * (0 - t) = 0 - rothausDefect t := by
        rw [hξ₁_eq, div_mul_cancel₀]
        exact sub_ne_zero.mpr ht_ne.symm
      simp only [zero_sub] at h1
      rw [h_deriv_ξ₁] at h1
      linarith
    rw [h_rothausDefect_t]
    -- deriv² rothausDefect(ξ₂) ≥ 0, ξ₁ < 0, t < 0
    -- So deriv² rothausDefect(ξ₂) * ξ₁ ≤ 0
    -- And deriv² rothausDefect(ξ₂) * ξ₁ * t ≥ 0
    have h_d2_nonneg : 0 ≤ deriv (deriv rothausDefect) ξ₂ := deriv2_rothausDefect_nonneg hξ₂_in
    have h_ξ₁_neg' : ξ₁ < 0 := hξ₁_mem.2
    have h_t_neg : t < 0 := ht_neg
    have h_mid : deriv (deriv rothausDefect) ξ₂ * ξ₁ ≤ 0 :=
      mul_nonpos_of_nonneg_of_nonpos h_d2_nonneg (le_of_lt h_ξ₁_neg')
    exact mul_nonneg_of_nonpos_of_nonpos h_mid (le_of_lt h_t_neg)
  · exact absurd ht_zero ht0
  · -- Case t > 0: use MVT on [0, t]
    have hcont : ContinuousOn rothausDefect (Icc 0 t) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hx.2]⟩
      exact (differentiableAt_rothausDefect hx_mem).continuousAt.continuousWithinAt
    have hdiff : DifferentiableOn ℝ rothausDefect (Ioo 0 t) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hx.2]⟩
      exact (differentiableAt_rothausDefect hx_mem).differentiableWithinAt
    obtain ⟨ξ₁, hξ₁_mem, hξ₁_eq⟩ := exists_deriv_eq_slope rothausDefect ht_pos hcont hdiff
    simp only [rothausDefect_zero] at hξ₁_eq
    -- Now apply MVT again to deriv rothausDefect on [0, ξ₁]
    have hξ₁_pos : 0 < ξ₁ := hξ₁_mem.1
    have hcont' : ContinuousOn (deriv rothausDefect) (Icc 0 ξ₁) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hξ₁_mem.2, hx.2]⟩
      exact (differentiableAt_deriv_rothausDefect hx_mem).continuousAt.continuousWithinAt
    have hdiff' : DifferentiableOn ℝ (deriv rothausDefect) (Ioo 0 ξ₁) := by
      intro x hx
      have hx_mem : x ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hx.1], by linarith [ht.2, hξ₁_mem.2, hx.2]⟩
      exact (differentiableAt_deriv_rothausDefect hx_mem).differentiableWithinAt
    obtain ⟨ξ₂, hξ₂_mem, hξ₂_eq⟩ := exists_deriv_eq_slope (deriv rothausDefect) hξ₁_pos hcont' hdiff'
    simp only [deriv_rothausDefect_zero] at hξ₂_eq
    have hξ₂_in : ξ₂ ∈ Ioo (-1 : ℝ) 1 := ⟨by linarith [hξ₂_mem.1], by linarith [ht.2, hξ₁_mem.2, hξ₂_mem.2]⟩
    have h_deriv_ξ₁ : deriv rothausDefect ξ₁ = deriv (deriv rothausDefect) ξ₂ * ξ₁ := by
      -- hξ₂_eq : deriv (deriv rothausDefect) ξ₂ = (deriv rothausDefect ξ₁ - 0) / (ξ₁ - 0)
      have hξ₁_ne : ξ₁ ≠ 0 := ne_of_gt hξ₁_pos
      have h1 : deriv (deriv rothausDefect) ξ₂ * (ξ₁ - 0) = deriv rothausDefect ξ₁ - 0 := by
        rw [hξ₂_eq, div_mul_cancel₀]
        exact sub_ne_zero.mpr hξ₁_ne
      simp only [sub_zero] at h1
      linarith
    have h_rothausDefect_t : rothausDefect t = deriv (deriv rothausDefect) ξ₂ * ξ₁ * t := by
      -- hξ₁_eq : deriv rothausDefect ξ₁ = (rothausDefect t - 0) / (t - 0)
      have ht_ne : t ≠ 0 := ne_of_gt ht_pos
      have h1 : deriv rothausDefect ξ₁ * (t - 0) = rothausDefect t - 0 := by
        rw [hξ₁_eq, div_mul_cancel₀]
        exact sub_ne_zero.mpr ht_ne
      simp only [sub_zero] at h1
      rw [h_deriv_ξ₁] at h1
      linarith
    rw [h_rothausDefect_t]
    have h_d2_nonneg : 0 ≤ deriv (deriv rothausDefect) ξ₂ := deriv2_rothausDefect_nonneg hξ₂_in
    have h_ξ₁_pos' : 0 < ξ₁ := hξ₁_mem.1
    have h_t_pos : 0 < t := ht_pos
    exact mul_nonneg (mul_nonneg h_d2_nonneg (le_of_lt h_ξ₁_pos')) (le_of_lt h_t_pos)

/-- The Rothaus lemma: entropy of the two-point distribution is bounded ABOVE.

    For a, b > 0:
    (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2) ≤ (√a - √b)² / 2 -/
theorem rothaus_lemma {a b : ℝ} (ha : 0 < a) (hb : 0 < b) :
    (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2) ≤
    (sqrt a - sqrt b)^2 / 2 := by
  -- Define key quantities
  set m := (a + b) / 2 with hm_def
  set t := (a - b) / (a + b) with ht_def
  -- Basic inequalities
  have hab_pos : 0 < a + b := by linarith
  have hm_pos : 0 < m := by rw [hm_def]; linarith
  have hab_ne : a + b ≠ 0 := hab_pos.ne'
  -- Bounds on t
  have ht_upper : t < 1 := by
    rw [ht_def, div_lt_one hab_pos]
    linarith
  have ht_lower : -1 < t := by
    rw [ht_def, lt_div_iff₀ hab_pos]
    linarith
  have ht_mem : t ∈ Ioo (-1 : ℝ) 1 := ⟨ht_lower, ht_upper⟩
  -- Express a, b in terms of m, t
  have ha_eq : a = m * (1 + t) := by
    rw [hm_def, ht_def]
    field_simp
    ring
  have hb_eq : b = m * (1 - t) := by
    rw [hm_def, ht_def]
    field_simp
    ring
  have h1pt_pos : 0 < 1 + t := by linarith [ht_lower]
  have h1mt_pos : 0 < 1 - t := by linarith [ht_upper]
  -- The LHS equals m * phi(t) / 2
  have hLHS : (a * log a + b * log b) / 2 - (a + b) / 2 * log ((a + b) / 2) =
      m * phi t / 2 := by
    rw [ha_eq, hb_eq]
    simp only [phi, gPlus, gMinus]
    have hlog_a : log (m * (1 + t)) = log m + log (1 + t) := by
      rw [log_mul hm_pos.ne' h1pt_pos.ne']
    have hlog_b : log (m * (1 - t)) = log m + log (1 - t) := by
      rw [log_mul hm_pos.ne' h1mt_pos.ne']
    rw [hlog_a, hlog_b]
    have hsum : m * (1 + t) + m * (1 - t) = 2 * m := by ring
    rw [hsum]
    have hmid : (2 * m) / 2 = m := by ring
    rw [hmid]
    ring
  -- The RHS equals m * sqrtTerm(t) / 2
  have hRHS : (sqrt a - sqrt b)^2 / 2 = m * sqrtTerm t / 2 := by
    rw [ha_eq, hb_eq]
    have hsqrt_a : sqrt (m * (1 + t)) = sqrt m * sqrt (1 + t) :=
      sqrt_mul hm_pos.le (1 + t)
    have hsqrt_b : sqrt (m * (1 - t)) = sqrt m * sqrt (1 - t) :=
      sqrt_mul hm_pos.le (1 - t)
    rw [hsqrt_a, hsqrt_b]
    have hsqrt_factor : (sqrt m * sqrt (1 + t) - sqrt m * sqrt (1 - t))^2 =
        m * (sqrt (1 + t) - sqrt (1 - t))^2 := by
      have hsq : sqrt m * sqrt m = m := Real.mul_self_sqrt hm_pos.le
      calc (sqrt m * sqrt (1 + t) - sqrt m * sqrt (1 - t))^2
          = (sqrt m * (sqrt (1 + t) - sqrt (1 - t)))^2 := by ring
        _ = sqrt m * sqrt m * (sqrt (1 + t) - sqrt (1 - t))^2 := by ring
        _ = m * (sqrt (1 + t) - sqrt (1 - t))^2 := by rw [hsq]
    rw [hsqrt_factor]
    -- Now show (sqrt (1 + t) - sqrt (1 - t))^2 = sqrtTerm t
    have hst : (sqrt (1 + t) - sqrt (1 - t))^2 = sqrtTerm t := by
      rw [sqrt_diff_sq_eq ht_mem, sqrtTerm]
    rw [hst]
  -- Now we need: m * phi(t) / 2 ≤ m * sqrtTerm(t) / 2
  rw [hLHS, hRHS]
  -- Since m > 0, this is equivalent to phi(t) ≤ sqrtTerm(t)
  have h := rothausDefect_nonneg ht_mem
  -- rothausDefect(t) = sqrtTerm(t) - phi(t) ≥ 0, so phi(t) ≤ sqrtTerm(t)
  unfold rothausDefect at h
  have h_ineq : phi t ≤ 2 - 2 * sqrt (1 - t^2) := by linarith
  -- 2 - 2 * sqrt (1 - t^2) = sqrtTerm t
  have h_eq : 2 - 2 * sqrt (1 - t^2) = sqrtTerm t := by simp [sqrtTerm]
  rw [h_eq] at h_ineq
  calc m * phi t / 2
      ≤ m * sqrtTerm t / 2 := by nlinarith [hm_pos, h_ineq]

end LogSobolev

end

