/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.GaussianSobolevDense.Defs
import SLT.GaussianSobolevDense.Cutoff
import SLT.GaussianSobolevDense.Mollification

/-!
# Density of Smooth Compactly Supported Functions in W^{1,2}(γ)

This file proves the main theorem: C_c^∞(ℝⁿ) is dense in the Strong Gaussian Sobolev space W^{1,2}(γ).

## Main Results

* `exists_smooth_compactSupport_approx` - For any f ∈ W^{1,2}(γ) and δ > 0, exists smooth
  compactly supported g with ‖f - g‖_{W^{1,2}(γ)} < δ
* `dense_smooth_compactSupport_W12Gaussian` - C_c^∞ is dense in W^{1,2}(γ)
* `exists_smooth_compactSupport_seq_tendsto` - Constructs a sequence of smooth compactly
  supported functions converging to any regular f ∈ W^{1,2}(γ)

### One-Dimensional Specialization

* `exists_smooth_compactSupport_seq_tendsto_real` - 1D version: smooth compactly supported
  functions on ℝ converge to f in W^{1,2}(gaussianReal 0 1)
-/

open MeasureTheory ProbabilityTheory Filter Topology GaussianMeasure
open scoped ENNReal NNReal Topology

namespace GaussianSobolev

variable {n : ℕ}

/-! ### Auxiliary Lemmas for ENNReal Arithmetic -/

/-- GaussianSobolevNormSq is symmetric under negation: ||−f||² = ||f||² -/
lemma gaussianSobolevNormSq_neg (f : E n → ℝ) (γ : Measure (E n)) :
    GaussianSobolevNormSq n (-f) γ = GaussianSobolevNormSq n f γ := by
  simp only [GaussianSobolevNormSq]
  congr 1
  · -- eLpNorm of -f equals eLpNorm of f
    have h := eLpNorm_neg f 2 γ
    exact congrArg (· ^ 2) h
  · -- For the gradient term: fderiv of -f is -fderiv f
    have h_eq : (fun x => ‖fderiv ℝ (-f) x‖) = (fun x => ‖fderiv ℝ f x‖) := by
      ext x
      rw [fderiv_neg]
      simp only [norm_neg]
    rw [h_eq]

/-- GaussianSobolevNormSq is symmetric under swapping: ||a - b||² = ||b - a||² -/
lemma gaussianSobolevNormSq_sub_comm (f g : E n → ℝ) (γ : Measure (E n)) :
    GaussianSobolevNormSq n (f - g) γ = GaussianSobolevNormSq n (g - f) γ := by
  have h : f - g = -(g - f) := by
    ext x
    simp only [Pi.sub_apply, Pi.neg_apply]
    ring
  rw [h, gaussianSobolevNormSq_neg]

/-- The elementary inequality (a + b)² ≤ 2a² + 2b² for ENNReal -/
lemma ennreal_sq_add_le (a b : ℝ≥0∞) : (a + b)^2 ≤ 2 * a^2 + 2 * b^2 := by
  by_cases ha : a = ⊤
  · simp [ha]
  by_cases hb : b = ⊤
  · simp [hb]
  -- Both finite case: lift to NNReal
  lift a to ℝ≥0 using ha
  lift b to ℝ≥0 using hb
  simp only [← ENNReal.coe_add, ← ENNReal.coe_pow, ← ENNReal.coe_mul, ← ENNReal.coe_ofNat]
  rw [ENNReal.coe_le_coe]
  -- NNReal arithmetic: (a + b)² ≤ 2(a² + b²) = 2a² + 2b² by AM-GM
  calc (a + b)^2 ≤ 2 * (a^2 + b^2) := add_sq_le
    _ = 2 * a^2 + 2 * b^2 := by ring

/-- Triangle inequality for eLpNorm squared when p ≥ 1 -/
lemma eLpNorm_add_sq_le' (f g : E n → ℝ) (μ : Measure (E n))
    (hf : AEStronglyMeasurable f μ) (hg : AEStronglyMeasurable g μ) :
    eLpNorm (f + g) 2 μ ^ 2 ≤ 2 * eLpNorm f 2 μ ^ 2 + 2 * eLpNorm g 2 μ ^ 2 := by
  have h2 : (1 : ℝ≥0∞) ≤ 2 := by norm_num
  have htri := eLpNorm_add_le hf hg h2
  calc eLpNorm (f + g) 2 μ ^ 2
      ≤ (eLpNorm f 2 μ + eLpNorm g 2 μ)^2 := ENNReal.pow_le_pow_left htri
    _ ≤ 2 * eLpNorm f 2 μ ^ 2 + 2 * eLpNorm g 2 μ ^ 2 := ennreal_sq_add_le _ _

/-! ### Triangle Inequality for GaussianSobolevNormSq -/

/-- Triangle inequality for GaussianSobolevNormSq for differentiable functions -/
lemma gaussianSobolevNormSq_add_le_of_diff (f g : E n → ℝ) (γ : Measure (E n))
    (hf : AEStronglyMeasurable f γ) (hg : AEStronglyMeasurable g γ)
    (hf_diff : Differentiable ℝ f) (hg_diff : Differentiable ℝ g)
    (hf_cont : Continuous (fun x => fderiv ℝ f x))
    (hg_cont : Continuous (fun x => fderiv ℝ g x)) :
    GaussianSobolevNormSq n (f + g) γ ≤
      2 * GaussianSobolevNormSq n f γ + 2 * GaussianSobolevNormSq n g γ := by
  simp only [GaussianSobolevNormSq]
  -- L² term uses the triangle inequality
  have hL2 := eLpNorm_add_sq_le' f g γ hf hg
  -- Gradient term: use that fderiv (f + g) = fderiv f + fderiv g for differentiable functions
  have hgrad_eq : ∀ x, fderiv ℝ (f + g) x = fderiv ℝ f x + fderiv ℝ g x := by
    intro x
    exact fderiv_add (hf_diff x) (hg_diff x)
  -- Therefore ||fderiv (f+g) x|| ≤ ||fderiv f x|| + ||fderiv g x||
  have hgrad_bound : ∀ x, ‖fderiv ℝ (f + g) x‖ ≤ ‖fderiv ℝ f x‖ + ‖fderiv ℝ g x‖ := by
    intro x
    rw [hgrad_eq]
    exact norm_add_le _ _
  -- Measurability of gradient norms
  have hf_norm_aesm : AEStronglyMeasurable (fun x => ‖fderiv ℝ f x‖) γ :=
    hf_cont.aestronglyMeasurable.norm
  have hg_norm_aesm : AEStronglyMeasurable (fun x => ‖fderiv ℝ g x‖) γ :=
    hg_cont.aestronglyMeasurable.norm
  -- Use monotonicity: ||grad(f+g)||_Lp ≤ ||grad f + grad g||_Lp
  have hmono : eLpNorm (fun x => ‖fderiv ℝ (f + g) x‖) 2 γ ≤
      eLpNorm (fun x => ‖fderiv ℝ f x‖ + ‖fderiv ℝ g x‖) 2 γ := by
    apply eLpNorm_mono_real
    intro x
    simp only [Real.norm_eq_abs, abs_norm]
    exact hgrad_bound x
  -- Triangle inequality for gradient L² norms
  have h2 : (1 : ℝ≥0∞) ≤ 2 := by norm_num
  have hgrad_tri := eLpNorm_add_le hf_norm_aesm hg_norm_aesm h2
  -- Combine bounds for gradient term
  have hgrad : eLpNorm (fun x => ‖fderiv ℝ (f + g) x‖) 2 γ ^ 2 ≤
      2 * eLpNorm (fun x => ‖fderiv ℝ f x‖) 2 γ ^ 2 +
      2 * eLpNorm (fun x => ‖fderiv ℝ g x‖) 2 γ ^ 2 := by
    calc eLpNorm (fun x => ‖fderiv ℝ (f + g) x‖) 2 γ ^ 2
        ≤ eLpNorm (fun x => ‖fderiv ℝ f x‖ + ‖fderiv ℝ g x‖) 2 γ ^ 2 :=
          ENNReal.pow_le_pow_left hmono
      _ ≤ (eLpNorm (fun x => ‖fderiv ℝ f x‖) 2 γ + eLpNorm (fun x => ‖fderiv ℝ g x‖) 2 γ)^2 :=
          ENNReal.pow_le_pow_left hgrad_tri
      _ ≤ 2 * eLpNorm (fun x => ‖fderiv ℝ f x‖) 2 γ ^ 2 +
          2 * eLpNorm (fun x => ‖fderiv ℝ g x‖) 2 γ ^ 2 := ennreal_sq_add_le _ _
  -- Combine L² and gradient bounds
  calc eLpNorm (f + g) 2 γ ^ 2 + eLpNorm (fun x => ‖fderiv ℝ (f + g) x‖) 2 γ ^ 2
      ≤ (2 * eLpNorm f 2 γ ^ 2 + 2 * eLpNorm g 2 γ ^ 2) +
        (2 * eLpNorm (fun x => ‖fderiv ℝ f x‖) 2 γ ^ 2 +
         2 * eLpNorm (fun x => ‖fderiv ℝ g x‖) 2 γ ^ 2) := add_le_add hL2 hgrad
    _ = 2 * (eLpNorm f 2 γ ^ 2 + eLpNorm (fun x => ‖fderiv ℝ f x‖) 2 γ ^ 2) +
        2 * (eLpNorm g 2 γ ^ 2 + eLpNorm (fun x => ‖fderiv ℝ g x‖) 2 γ ^ 2) := by ring

/-! ### Extracting ε from Tendsto -/

/-- Helper to extract a point achieving a bound from a Tendsto to nhds 0 in ENNReal. -/
lemma exists_lt_of_tendsto_nhdsWithin_right {f : ℝ → ℝ≥0∞} {b : ℝ≥0∞}
    (hf : Tendsto f (nhdsWithin 0 (Set.Ioi 0)) (nhds 0)) (hb : 0 < b) :
    ∃ ε : ℝ, 0 < ε ∧ f ε < b := by
  -- Use the Filter.Tendsto.eventually to get f x < b eventually
  have hev : ∀ᶠ x in nhdsWithin (0 : ℝ) (Set.Ioi 0), f x < b := by
    apply hf.eventually
    exact Iio_mem_nhds hb
  -- nhdsWithin 0 (Ioi 0) is the right filter
  rw [Filter.Eventually, mem_nhdsWithin] at hev
  obtain ⟨U, hU_open, h0U, hU_prop⟩ := hev
  -- U is open and contains 0, so contains some ball
  obtain ⟨δ, hδ_pos, hδ_ball⟩ := Metric.isOpen_iff.mp hU_open 0 h0U
  -- Take ε = δ/2
  use δ / 2, by linarith
  apply hU_prop
  constructor
  · apply hδ_ball
    rw [Metric.mem_ball, Real.dist_eq, sub_zero]
    rw [abs_of_pos (by linarith : δ / 2 > 0)]
    linarith
  · simp only [Set.mem_Ioi]; linarith

/-! ### Main Approximation Theorem -/

set_option maxHeartbeats 400000 in
/-- For any f ∈ W^{1,2}(γ) with sufficient regularity (differentiable with continuous gradient)
    and δ > 0, there exists a smooth compactly supported function g
    such that ‖f - g‖_{W^{1,2}(γ)} < δ. -/
theorem exists_smooth_compactSupport_approx (f : E n → ℝ) (hf : MemW12Gaussian n f (stdGaussianE n))
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x))
    {δ : ℝ} (hδ : 0 < δ) :
    ∃ g : E n → ℝ, ContDiff ℝ (⊤ : ℕ∞) g ∧ HasCompactSupport g ∧
      GaussianSobolevNormSq n (f - g) (stdGaussianE n) < ENNReal.ofReal (δ^2) := by
  -- Step 1: Choose R large enough that ‖f*χ_R - f‖_{W^{1,2}}² < δ²/4
  have hcutoff := tendsto_cutoff_W12 f hf
  have htarget : (0 : ℝ≥0∞) < ENNReal.ofReal (δ^2 / 4) := by
    rw [ENNReal.ofReal_pos]; positivity
  have heventually := (ENNReal.nhds_zero_basis.tendsto_right_iff.mp hcutoff) _ htarget
  obtain ⟨N, hN⟩ := heventually.exists_forall_of_atTop
  set R := max N 1
  have hR : 0 < R := lt_max_of_lt_right one_pos
  have hR_bound : GaussianSobolevNormSq n (f - f * smoothCutoffR R) (stdGaussianE n) <
      ENNReal.ofReal (δ^2 / 4) := by
    have hsym := gaussianSobolevNormSq_sub_comm (f * smoothCutoffR R) f (stdGaussianE n)
    rw [← hsym]
    exact hN R (le_max_left N 1)

  -- Step 2: Choose ε small enough that ‖mollify ε (f*χ_R) - f*χ_R‖² < δ²/4
  have hmollify := tendsto_mollify_W12 f hR hf_diff hf_grad_cont
  obtain ⟨ε, hε, hε_bound⟩ := exists_lt_of_tendsto_nhdsWithin_right hmollify htarget

  -- Step 3: Define g = mollify ε (f * smoothCutoffR R)
  set g := mollify ε (f * smoothCutoffR R)

  -- Step 4: g is smooth and has compact support
  have hf_int : LocallyIntegrable f volume := hf_diff.continuous.locallyIntegrable
  obtain ⟨hg_smooth, hg_supp⟩ := mollify_cutoff_smooth_compactSupport f hR hε hf_int

  -- Step 5: Bound the approximation error
  use g
  refine ⟨hg_smooth, hg_supp, ?_⟩

  -- Note: g - (f*χ_R) has reversed sign from hε_bound
  have hε_bound' : GaussianSobolevNormSq n (f * smoothCutoffR R - g) (stdGaussianE n) <
      ENNReal.ofReal (δ^2 / 4) := by
    rw [gaussianSobolevNormSq_sub_comm]
    convert hε_bound using 2

  have hne : (↑(⊤ : ℕ∞) : WithTop ℕ∞) ≠ 0 := WithTop.coe_ne_zero.mpr ENat.top_ne_zero
  have hχ_diff : Differentiable ℝ (smoothCutoffR R : E n → ℝ) :=
    (smoothCutoffR_contDiff hR).differentiable hne
  have hχ_cont : Continuous (fun x => fderiv ℝ (smoothCutoffR R : E n → ℝ) x) :=
    (smoothCutoffR_contDiff hR).continuous_fderiv hne
  have hfχ_diff : Differentiable ℝ (f * smoothCutoffR R) :=
    hf_diff.mul hχ_diff
  have hg_diff : Differentiable ℝ g :=
    hg_smooth.differentiable hne
  have hg_grad_cont : Continuous (fun x => fderiv ℝ g x) :=
    hg_smooth.continuous_fderiv hne

  -- f - f*χ_R = f * (1 - χ_R) is differentiable
  have h1_diff : Differentiable ℝ (f - f * smoothCutoffR R) := hf_diff.sub hfχ_diff
  have h2_diff : Differentiable ℝ (f * smoothCutoffR R - g) := hfχ_diff.sub hg_diff

  -- Continuity of gradients
  -- For product: fderiv (f * g) x = f x • fderiv g x + g x • fderiv f x
  have hfχ_cont : Continuous (fun x => fderiv ℝ (f * smoothCutoffR R) x) := by
    have heq : ∀ x, fderiv ℝ (f * smoothCutoffR R) x =
        f x • fderiv ℝ (smoothCutoffR R) x + smoothCutoffR R x • fderiv ℝ f x := by
      intro x
      exact fderiv_mul (hf_diff x) (hχ_diff x)
    have hcont : Continuous (fun x =>
        f x • fderiv ℝ (smoothCutoffR R) x + smoothCutoffR R x • fderiv ℝ f x) := by
      apply Continuous.add
      · exact hf_diff.continuous.smul hχ_cont
      · exact hχ_diff.continuous.smul hf_grad_cont
    exact hcont.congr (fun x => (heq x).symm)
  -- For difference: fderiv (f - g) x = fderiv f x - fderiv g x
  have h1_cont : Continuous (fun x => fderiv ℝ (f - f * smoothCutoffR R) x) := by
    have heq : ∀ x, fderiv ℝ (f - f * smoothCutoffR R) x =
        fderiv ℝ f x - fderiv ℝ (f * smoothCutoffR R) x := by
      intro x
      exact fderiv_sub (hf_diff x) (hfχ_diff x)
    have hcont : Continuous (fun x => fderiv ℝ f x - fderiv ℝ (f * smoothCutoffR R) x) :=
      hf_grad_cont.sub hfχ_cont
    exact hcont.congr (fun x => (heq x).symm)
  have h2_cont : Continuous (fun x => fderiv ℝ (f * smoothCutoffR R - g) x) := by
    have heq : ∀ x, fderiv ℝ (f * smoothCutoffR R - g) x =
        fderiv ℝ (f * smoothCutoffR R) x - fderiv ℝ g x := by
      intro x
      exact fderiv_sub (hfχ_diff x) (hg_diff x)
    have hcont : Continuous (fun x => fderiv ℝ (f * smoothCutoffR R) x - fderiv ℝ g x) :=
      hfχ_cont.sub hg_grad_cont
    exact hcont.congr (fun x => (heq x).symm)

  -- AE measurability
  have hf_aesm : AEStronglyMeasurable f (stdGaussianE n) := hf.1.1
  have hfχ_aesm : AEStronglyMeasurable (f * smoothCutoffR R) (stdGaussianE n) := by
    apply AEStronglyMeasurable.mul hf_aesm
    exact (smoothCutoffR_contDiff hR).continuous.aestronglyMeasurable
  have hg_aesm : AEStronglyMeasurable g (stdGaussianE n) :=
    hg_smooth.continuous.aestronglyMeasurable
  have h1_aesm : AEStronglyMeasurable (f - f * smoothCutoffR R) (stdGaussianE n) :=
    hf_aesm.sub hfχ_aesm
  have h2_aesm : AEStronglyMeasurable (f * smoothCutoffR R - g) (stdGaussianE n) :=
    hfχ_aesm.sub hg_aesm

  -- f - g = h1 + h2 where h1 = f - f*χ_R, h2 = f*χ_R - g
  have hdecomp : f - g = (f - f * smoothCutoffR R) + (f * smoothCutoffR R - g) := by
    ext x; simp only [Pi.sub_apply, Pi.add_apply, Pi.mul_apply]; ring

  -- Apply triangle inequality
  have htriangle := gaussianSobolevNormSq_add_le_of_diff
    (f - f * smoothCutoffR R) (f * smoothCutoffR R - g) (stdGaussianE n)
    h1_aesm h2_aesm h1_diff h2_diff h1_cont h2_cont

  calc GaussianSobolevNormSq n (f - g) (stdGaussianE n)
      = GaussianSobolevNormSq n ((f - f * smoothCutoffR R) + (f * smoothCutoffR R - g))
          (stdGaussianE n) := by rw [hdecomp]
    _ ≤ 2 * GaussianSobolevNormSq n (f - f * smoothCutoffR R) (stdGaussianE n) +
        2 * GaussianSobolevNormSq n (f * smoothCutoffR R - g) (stdGaussianE n) := htriangle
    _ < 2 * ENNReal.ofReal (δ^2 / 4) + 2 * ENNReal.ofReal (δ^2 / 4) := by
        apply ENNReal.add_lt_add
        · exact ENNReal.mul_lt_mul_right (by norm_num) (by norm_num) hR_bound
        · exact ENNReal.mul_lt_mul_right (by norm_num) (by norm_num) hε_bound'
    _ = ENNReal.ofReal (δ^2) := by
        -- Convert 2 * ofReal (δ²/4) to ofReal (2 * δ²/4) = ofReal (δ²/2)
        have h1 : (2 : ℝ≥0∞) * ENNReal.ofReal (δ^2 / 4) = ENNReal.ofReal (2 * (δ^2 / 4)) := by
          rw [← ENNReal.ofReal_ofNat 2, ENNReal.ofReal_mul (by norm_num : (0 : ℝ) ≤ 2)]
        rw [h1, ← ENNReal.ofReal_add (by positivity) (by positivity)]
        congr 1
        ring

/-! ### Main Density Theorem -/

/-- The space of smooth compactly supported functions C_c^∞(ℝⁿ) is dense in W^{1,2}(γ). -/
theorem dense_smooth_compactSupport_W12Gaussian :
    ∀ f : E n → ℝ, MemW12Gaussian n f (stdGaussianE n) →
    Differentiable ℝ f →
    Continuous (fun x => fderiv ℝ f x) →
    ∀ ε > 0, ∃ g : E n → ℝ, ContDiff ℝ (⊤ : ℕ∞) g ∧ HasCompactSupport g ∧
      GaussianSobolevNormSq n (f - g) (stdGaussianE n) < ENNReal.ofReal ε := by
  intro f hf hf_diff hf_grad_cont ε hε
  have hε' : 0 < Real.sqrt ε := Real.sqrt_pos.mpr hε
  obtain ⟨g, hg_smooth, hg_supp, hg_close⟩ :=
    exists_smooth_compactSupport_approx f hf hf_diff hf_grad_cont hε'
  use g
  refine ⟨hg_smooth, hg_supp, ?_⟩
  calc GaussianSobolevNormSq n (f - g) (stdGaussianE n)
      < ENNReal.ofReal ((Real.sqrt ε)^2) := hg_close
    _ = ENNReal.ofReal ε := by rw [Real.sq_sqrt (le_of_lt hε)]

/-- Alternative formulation: for any regular f ∈ W^{1,2}(γ), f is in the closure of C_c^∞
    in the Gaussian Sobolev topology. -/
theorem mem_closure_smooth_compactSupport (f : E n → ℝ) (hf : MemW12Gaussian n f (stdGaussianE n))
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x)) :
    ∀ ε > 0, ∃ g : E n → ℝ, ContDiff ℝ (⊤ : ℕ∞) g ∧ HasCompactSupport g ∧
      GaussianSobolevNormSq n (f - g) (stdGaussianE n) < ENNReal.ofReal ε := by
  intro ε hε
  exact dense_smooth_compactSupport_W12Gaussian f hf hf_diff hf_grad_cont ε hε

/-! ### Convergent Sequence from Density -/

/-- From the density theorem, we can construct a sequence of smooth compactly supported
    functions converging to any regular f ∈ W^{1,2}(γ) in the Gaussian Sobolev norm. -/
theorem exists_smooth_compactSupport_seq_tendsto (f : E n → ℝ)
    (hf : MemW12Gaussian n f (stdGaussianE n))
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x)) :
    ∃ g : ℕ → (E n → ℝ),
      (∀ k, ContDiff ℝ (⊤ : ℕ∞) (g k)) ∧
      (∀ k, HasCompactSupport (g k)) ∧
      Tendsto (fun k => GaussianSobolevNormSq n (f - g k) (stdGaussianE n)) atTop (nhds 0) := by
  -- For each k, apply the density theorem with ε = 1/(k+1) > 0
  have heps : ∀ k : ℕ, (0 : ℝ) < 1 / (k + 1) := fun k => by positivity
  -- Use the density theorem to get existence for each k
  have hexists : ∀ k : ℕ, ∃ g : E n → ℝ, ContDiff ℝ (⊤ : ℕ∞) g ∧ HasCompactSupport g ∧
      GaussianSobolevNormSq n (f - g) (stdGaussianE n) < ENNReal.ofReal (1 / (k + 1)) :=
    fun k => dense_smooth_compactSupport_W12Gaussian f hf hf_diff hf_grad_cont _ (heps k)
  -- Extract the sequence using choice
  choose g hg_smooth hg_supp hg_bound using hexists
  use g
  refine ⟨hg_smooth, hg_supp, ?_⟩
  -- Show convergence to 0
  rw [ENNReal.tendsto_nhds_zero]
  intro ε hε
  -- The sequence ENNReal.ofReal (1/(k+1)) → 0
  have htend : Tendsto (fun k : ℕ => ENNReal.ofReal (1 / ((k : ℝ) + 1))) atTop (nhds 0) := by
    have h1 : ENNReal.ofReal 0 = 0 := ENNReal.ofReal_zero
    rw [← h1]
    exact ENNReal.tendsto_ofReal tendsto_one_div_add_atTop_nhds_zero_nat
  -- Get N such that for k ≥ N, ENNReal.ofReal (1/(k+1)) ≤ ε
  rw [ENNReal.tendsto_nhds_zero] at htend
  obtain ⟨N, hN⟩ := (htend ε hε).exists_forall_of_atTop
  filter_upwards [Filter.Ici_mem_atTop (α := ℕ) N] with k hk
  exact le_of_lt (lt_of_lt_of_le (hg_bound k) (hN k hk))

end GaussianSobolev

/-! ## One-Dimensional Gaussian Sobolev Space (Specialized)-/

namespace GaussianSobolevReal

open MeasureTheory ProbabilityTheory Filter Topology GaussianMeasure

/-! ### 1D Gaussian Sobolev Space Definitions -/

/-- The 1D Gaussian Sobolev norm squared: ‖f‖_{L²(γ)}² + ‖f'‖_{L²(γ)}²
    where f' is the derivative (via fderiv). -/
noncomputable def GaussianSobolevNormSqReal (f : ℝ → ℝ) (γ : Measure ℝ) : ℝ≥0∞ :=
  eLpNorm f 2 γ ^ 2 + eLpNorm (fun x ↦ ‖fderiv ℝ f x‖) 2 γ ^ 2

/-- Membership in W^{1,2}(γ) for 1D: f ∈ L²(γ) and f' ∈ L²(γ) -/
def MemW12GaussianReal (f : ℝ → ℝ) (γ : Measure ℝ) : Prop :=
  MemLp f 2 γ ∧ MemLp (fun x ↦ fderiv ℝ f x) 2 γ

/-! ### 1D Smooth Cutoff Functions -/

/-- Rescaled smooth cutoff for ℝ: χ_R(x) = χ(|x|/R) where χ is the standard cutoff -/
noncomputable def smoothCutoffRReal (R : ℝ) (x : ℝ) : ℝ :=
  GaussianSobolev.smoothCutoff (|x| / R)

lemma smoothCutoffRReal_eq_one_of_abs_le {R : ℝ} (hR : 0 < R) {x : ℝ}
    (hx : |x| ≤ R) : smoothCutoffRReal R x = 1 := by
  unfold smoothCutoffRReal
  apply GaussianSobolev.smoothCutoff_eq_one_of_le
  rw [abs_of_nonneg (div_nonneg (abs_nonneg _) hR.le)]
  exact div_le_one_of_le₀ hx hR.le

lemma smoothCutoffRReal_eq_zero_of_abs_ge {R : ℝ} (hR : 0 < R) {x : ℝ}
    (hx : 2 * R ≤ |x|) : smoothCutoffRReal R x = 0 := by
  unfold smoothCutoffRReal
  apply GaussianSobolev.smoothCutoff_eq_zero_of_ge
  rw [abs_of_nonneg (div_nonneg (abs_nonneg _) hR.le)]
  calc 2 = 2 * R / R := by field_simp
    _ ≤ |x| / R := div_le_div_of_nonneg_right hx hR.le

lemma smoothCutoffRReal_nonneg (R : ℝ) (x : ℝ) : 0 ≤ smoothCutoffRReal R x :=
  GaussianSobolev.smoothCutoff_nonneg _

lemma smoothCutoffRReal_le_one (R : ℝ) (x : ℝ) : smoothCutoffRReal R x ≤ 1 :=
  GaussianSobolev.smoothCutoff_le_one _

lemma smoothCutoffRReal_contDiff {R : ℝ} (hR : 0 < R) :
    ContDiff ℝ (⊤ : ℕ∞) (smoothCutoffRReal R) := by
  rw [contDiff_iff_contDiffAt]
  intro x
  by_cases hx : |x| < R
  · -- Case: |x| < R, so smoothCutoffRReal R is locally constant = 1
    have h_eq : ∀ᶠ y in nhds x, smoothCutoffRReal R y = 1 := by
      have hmem : Metric.ball x (R - |x|) ∈ nhds x := Metric.ball_mem_nhds x (by linarith)
      filter_upwards [hmem] with y hy
      apply smoothCutoffRReal_eq_one_of_abs_le hR
      rw [Metric.mem_ball, Real.dist_eq] at hy
      -- |y| ≤ |x| + |y - x| < |x| + (R - |x|) = R
      have h1 : |y| ≤ |x| + |y - x| := by
        calc |y| = |y - x + x| := by ring_nf
          _ ≤ |y - x| + |x| := abs_add_le _ _
          _ = |x| + |y - x| := add_comm _ _
      linarith
    have h_const : ContDiffAt ℝ (⊤ : ℕ∞) (fun _ : ℝ => (1 : ℝ)) x := contDiffAt_const
    apply h_const.congr_of_eventuallyEq
    filter_upwards [h_eq] with y hy
    simp [hy]
  · -- Case: |x| ≥ R, so x ≠ 0 and |·| is smooth at x
    push_neg at hx
    have hx_ne : x ≠ 0 := by
      intro h
      rw [h, abs_zero] at hx
      linarith
    unfold smoothCutoffRReal
    -- Compose: smoothCutoff ∘ (· / R) ∘ |·|
    -- |·| is smooth at x ≠ 0
    have h_abs : ContDiffAt ℝ (⊤ : ℕ∞) (fun y : ℝ => |y|) x := by
      rcases abs_cases x with ⟨habs, hpos⟩ | ⟨habs, hneg⟩
      · -- x ≥ 0, so x > 0 (since x ≠ 0), and |·| = id locally
        have hpos' : 0 < x := lt_of_le_of_ne hpos (Ne.symm hx_ne)
        have h_eq : ∀ᶠ y in nhds x, |y| = y := by
          filter_upwards [Ioi_mem_nhds hpos'] with y hy
          exact abs_of_pos hy
        exact contDiffAt_id.congr_of_eventuallyEq h_eq
      · -- x < 0, so |·| = -id locally
        have hneg' : x < 0 := hneg
        have h_eq : ∀ᶠ y in nhds x, |y| = -y := by
          filter_upwards [Iio_mem_nhds hneg'] with y hy
          exact abs_of_neg hy
        exact contDiff_neg.contDiffAt.congr_of_eventuallyEq h_eq
    have h_div : ContDiff ℝ (⊤ : ℕ∞) (fun t : ℝ => t / R) := contDiff_id.div_const R
    have h_comp1 : ContDiffAt ℝ (⊤ : ℕ∞) (fun y : ℝ => |y| / R) x :=
      h_div.contDiffAt.comp x h_abs
    exact GaussianSobolev.smoothCutoff_contDiff.contDiffAt.comp x h_comp1

lemma smoothCutoffRReal_hasCompactSupport {R : ℝ} (hR : 0 < R) :
    HasCompactSupport (smoothCutoffRReal R) := by
  rw [hasCompactSupport_def]
  apply IsCompact.of_isClosed_subset (isCompact_Icc (a := -2*R) (b := 2*R)) isClosed_closure
  calc closure (Function.support (smoothCutoffRReal R))
      ⊆ closure (Set.Icc (-2*R) (2*R)) := by
        apply closure_mono
        intro x hx
        simp only [Function.mem_support, ne_eq] at hx
        simp only [Set.mem_Icc]
        constructor
        · by_contra hlt
          push_neg at hlt
          have habs : 2 * R ≤ |x| := by rw [abs_of_neg (by linarith : x < 0)]; linarith
          exact hx (smoothCutoffRReal_eq_zero_of_abs_ge hR habs)
        · by_contra hgt
          push_neg at hgt
          have habs : 2 * R ≤ |x| := by rw [abs_of_nonneg (by linarith : 0 ≤ x)]; linarith
          exact hx (smoothCutoffRReal_eq_zero_of_abs_ge hR habs)
    _ = Set.Icc (-2*R) (2*R) := IsClosed.closure_eq isClosed_Icc

/-! ### Equivalence Between E 1 and ℝ -/

/-- The equivalence between E 1 = EuclideanSpace ℝ (Fin 1) and ℝ.
    This composes `EuclideanSpace.equiv` with `Equiv.funUnique`. -/
noncomputable def equivE1Real : GaussianSobolev.E 1 ≃ ℝ :=
  (EuclideanSpace.equiv (Fin 1) ℝ).toEquiv.trans (Equiv.funUnique (Fin 1) ℝ)

/-- Lemma: equivE1Real x = x 0 for x : E 1 -/
lemma equivE1Real_apply (x : GaussianSobolev.E 1) : equivE1Real x = x 0 := by
  simp only [equivE1Real, Equiv.trans_apply, Equiv.funUnique_apply]
  rfl

/-- The equivalence is a linear isometry equivalence. -/
noncomputable def linearIsometryEquivE1Real : GaussianSobolev.E 1 ≃ₗᵢ[ℝ] ℝ := by
  refine LinearIsometryEquiv.mk ?_ ?_
  · -- The linear equivalence
    exact {
      toFun := equivE1Real
      map_add' := fun x y => by simp only [equivE1Real, Equiv.trans_apply]; rfl
      map_smul' := fun r x => by simp only [equivE1Real, Equiv.trans_apply, RingHom.id_apply]; rfl
      invFun := equivE1Real.symm
      left_inv := equivE1Real.left_inv
      right_inv := equivE1Real.right_inv
    }
  · -- Isometry: ‖e(x)‖ = ‖x‖
    intro x
    show ‖equivE1Real x‖ = ‖x‖
    rw [equivE1Real_apply, Real.norm_eq_abs]
    -- ‖x‖ = |x 0| for x : E 1
    rw [EuclideanSpace.norm_eq]
    simp only [Finset.univ_unique, Fin.default_eq_zero, Finset.sum_singleton, Real.sqrt_sq_eq_abs]
    rw [abs_norm, Real.norm_eq_abs]

/-- Transform a function f : ℝ → ℝ to a function on E 1 -/
noncomputable def toE1Fun (f : ℝ → ℝ) : GaussianSobolev.E 1 → ℝ :=
  f ∘ equivE1Real

/-- Transform a function g : E 1 → ℝ to a function on ℝ -/
noncomputable def fromE1Fun (g : GaussianSobolev.E 1 → ℝ) : ℝ → ℝ :=
  g ∘ equivE1Real.symm

/-- The funUnique equivalence for Fin 1 is continuous. -/
lemma continuous_funUnique_symm : Continuous (Equiv.funUnique (Fin 1) ℝ).symm := by
  simp only [Equiv.funUnique_symm_apply]
  exact continuous_pi (fun _ => continuous_id)

/-- The funUnique equivalence for Fin 1 is measurable. -/
lemma measurable_funUnique_symm : Measurable (Equiv.funUnique (Fin 1) ℝ).symm :=
  continuous_funUnique_symm.measurable

/-- The product measure Measure.pi on Fin 1 → ℝ with each coordinate being gaussianReal 0 1
    equals gaussianReal 0 1 transported via funUnique. -/
lemma measurePi_fin1_eq_gaussianReal :
    Measure.pi (fun _ : Fin 1 ↦ gaussianReal 0 1) =
      Measure.map (Equiv.funUnique (Fin 1) ℝ).symm (gaussianReal 0 1) := by
  -- Use Measure.pi_eq to characterize the product measure
  apply Measure.pi_eq
  intro s hs
  rw [Measure.map_apply measurable_funUnique_symm (MeasurableSet.univ_pi hs)]
  -- The preimage of Set.univ.pi s under funUnique.symm
  have h_preimage : (Equiv.funUnique (Fin 1) ℝ).symm ⁻¹' Set.univ.pi s = s 0 := by
    ext x
    simp only [Set.mem_preimage, Set.mem_pi, Equiv.funUnique_symm_apply]
    constructor
    · intro hx
      convert hx 0 (Set.mem_univ 0) using 1
    · intro hx i _
      have hi : i = 0 := Subsingleton.elim i 0
      subst hi
      convert hx using 1
  rw [h_preimage]
  simp only [Finset.univ_unique, Fin.default_eq_zero, Finset.prod_singleton]

/-- The equivE1Real.symm is continuous. -/
lemma continuous_equivE1Real_symm : Continuous equivE1Real.symm :=
  linearIsometryEquivE1Real.symm.continuous

/-- The equivE1Real is continuous. -/
lemma continuous_equivE1Real : Continuous equivE1Real :=
  linearIsometryEquivE1Real.continuous

/-- The equivE1Real.symm is measurable. -/
lemma measurable_equivE1Real_symm : Measurable equivE1Real.symm :=
  continuous_equivE1Real_symm.measurable

/-- The equivE1Real is measurable. -/
lemma measurable_equivE1Real : Measurable equivE1Real :=
  continuous_equivE1Real.measurable

/-- The MeasurableEquiv corresponding to equivE1Real. -/
noncomputable def measurableEquivE1Real : GaussianSobolev.E 1 ≃ᵐ ℝ :=
  linearIsometryEquivE1Real.toHomeomorph.toMeasurableEquiv

/-- The MeasurableEquiv agrees with equivE1Real. -/
lemma measurableEquivE1Real_eq : ⇑measurableEquivE1Real = equivE1Real := rfl

/-- The symm of MeasurableEquiv agrees with equivE1Real.symm. -/
lemma measurableEquivE1Real_symm_eq : ⇑measurableEquivE1Real.symm = equivE1Real.symm := rfl

/-- The standard Gaussian on E 1 equals the 1D Gaussian transported via the equivalence. -/
lemma stdGaussianE_1_eq_map_gaussianReal :
    stdGaussianE 1 =
      Measure.map equivE1Real.symm (gaussianReal 0 1) := by
  show stdGaussianE 1 = Measure.map equivE1Real.symm (gaussianReal 0 1)
  unfold stdGaussianE stdGaussianPi
  rw [measurePi_fin1_eq_gaussianReal]
  rw [Measure.map_map (EuclideanSpace.equiv (Fin 1) ℝ).symm.continuous.measurable
      measurable_funUnique_symm]
  congr 1

/-! ### Transfer of Norms -/

/-- The eLpNorm of f on ℝ with gaussianReal 0 1 equals the eLpNorm of toE1Fun f
    on E 1 with stdGaussianE 1. -/
lemma eLpNorm_toE1Fun_eq (f : ℝ → ℝ) (p : ℝ≥0∞)
    (hf : AEStronglyMeasurable f (gaussianReal 0 1)) :
    eLpNorm (toE1Fun f) p (stdGaussianE 1) = eLpNorm f p (gaussianReal 0 1) := by
  unfold toE1Fun
  rw [stdGaussianE_1_eq_map_gaussianReal]
  -- The key: f ∘ equivE1Real is AEStronglyMeasurable on map measure
  have hg : AEStronglyMeasurable (f ∘ equivE1Real) (Measure.map equivE1Real.symm (gaussianReal 0 1)) := by
    -- Use comp_measurable: AEStronglyMeasurable g (map f μ) → Measurable f → AEStronglyMeasurable (g ∘ f) μ
    -- Here μ = map e.symm (gaussianReal 0 1), f = e, g = f (the original function)
    -- So map e μ = map e (map e.symm (gaussianReal 0 1)) = gaussianReal 0 1
    have h_map_map : Measure.map equivE1Real (Measure.map equivE1Real.symm (gaussianReal 0 1)) = gaussianReal 0 1 := by
      rw [Measure.map_map measurable_equivE1Real measurable_equivE1Real_symm]
      simp only [Equiv.self_comp_symm]
      exact Measure.map_id
    rw [← h_map_map] at hf
    exact hf.comp_measurable measurable_equivE1Real
  -- Use eLpNorm_map_measure: eLpNorm g (map f μ) = eLpNorm (g ∘ f) μ
  rw [eLpNorm_map_measure hg measurable_equivE1Real_symm.aemeasurable]
  -- (f ∘ e) ∘ e.symm = f by congruence
  congr 1

/-- The fderiv of toE1Fun f at a point relates to the fderiv of f. -/
lemma fderiv_toE1Fun (f : ℝ → ℝ) (hf_diff : Differentiable ℝ f) (x : GaussianSobolev.E 1) :
    fderiv ℝ (toE1Fun f) x = (fderiv ℝ f (equivE1Real x)).comp (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ) := by
  unfold toE1Fun
  have hdiff_eq : DifferentiableAt ℝ equivE1Real x := linearIsometryEquivE1Real.differentiable.differentiableAt
  rw [fderiv_comp x (hf_diff (equivE1Real x)) hdiff_eq]
  congr 1
  -- fderiv of a linear isometry equiv is itself
  exact linearIsometryEquivE1Real.toContinuousLinearEquiv.fderiv

/-- The norm of fderiv of toE1Fun equals the norm of fderiv of f (both are 1D). -/
lemma norm_fderiv_toE1Fun_eq (f : ℝ → ℝ) (hf_diff : Differentiable ℝ f) (x : GaussianSobolev.E 1) :
    ‖fderiv ℝ (toE1Fun f) x‖ = ‖fderiv ℝ f (equivE1Real x)‖ := by
  rw [fderiv_toE1Fun f hf_diff x]
  -- The coercion of linearIsometryEquivE1Real to ContinuousLinearMap goes through toLinearIsometry
  have h : (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ) =
      linearIsometryEquivE1Real.toLinearIsometry.toContinuousLinearMap := rfl
  rw [h]
  exact ContinuousLinearMap.opNorm_comp_linearIsometryEquiv _ _

/-! ### Transfer of W^{1,2} Membership -/

/-- If f ∈ W^{1,2}(gaussianReal 0 1) on ℝ, then toE1Fun f ∈ W^{1,2}(stdGaussianE 1) on E 1. -/
lemma memW12Gaussian_toE1Fun (f : ℝ → ℝ) (hf : MemW12GaussianReal f (gaussianReal 0 1))
    (hf_diff : Differentiable ℝ f) :
    GaussianSobolev.MemW12Gaussian 1 (toE1Fun f) (stdGaussianE 1) := by
  -- MemW12Gaussian means: MemLp f 2 γ ∧ MemLp (fun x ↦ fderiv ℝ f x) 2 γ
  constructor
  · rw [stdGaussianE_1_eq_map_gaussianReal]
    rw [← measurableEquivE1Real_symm_eq]
    rw [MeasurableEquiv.memLp_map_measure_iff measurableEquivE1Real.symm]
    have heq : toE1Fun f ∘ measurableEquivE1Real.symm = f := by
      ext x
      simp only [toE1Fun, Function.comp_apply, measurableEquivE1Real_symm_eq, Equiv.apply_symm_apply]
    rw [heq]
    exact hf.1
  · -- fderiv of toE1Fun f ∈ Lp²(stdGaussianE 1)
    rw [stdGaussianE_1_eq_map_gaussianReal]
    rw [← measurableEquivE1Real_symm_eq]
    rw [MeasurableEquiv.memLp_map_measure_iff measurableEquivE1Real.symm]
    -- Show the fderiv on E 1 composed with equiv.symm relates to fderiv on ℝ
    have heq : (fun x => fderiv ℝ (toE1Fun f) x) ∘ measurableEquivE1Real.symm =
        fun y => (fderiv ℝ f y).comp (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ) := by
      ext y
      simp only [Function.comp_apply, measurableEquivE1Real_symm_eq]
      rw [fderiv_toE1Fun f hf_diff]
      simp only [Equiv.apply_symm_apply]
    rw [heq]
    -- Now show that x ↦ (fderiv ℝ f x).comp iso has the same Lp norm as fderiv ℝ f
    -- Use: ‖L.comp iso‖ = ‖L‖ for isometries
    have hiso_eq : (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ) =
        linearIsometryEquivE1Real.toLinearIsometry.toContinuousLinearMap := rfl
    have hnorm_eq : ∀ y, ‖(fderiv ℝ f y).comp (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ)‖ =
        ‖fderiv ℝ f y‖ := by
      intro y
      rw [hiso_eq]
      exact ContinuousLinearMap.opNorm_comp_linearIsometryEquiv _ _
    -- Use MemLp.of_le: MemLp g p μ → AEStronglyMeasurable f μ → (∀ᵐ x ∂μ, ‖f x‖ ≤ ‖g x‖) → MemLp f p μ
    apply MemLp.of_le hf.2
    · -- AEStronglyMeasurable: (fderiv ℝ f ·).comp iso is measurable
      -- The map L ↦ L.comp iso is a continuous linear map (apply compSL.flip to iso)
      let iso := (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ)
      -- compSL.flip iso : (ℝ →L[ℝ] ℝ) →L[ℝ] (E 1 →L[ℝ] ℝ) maps L to L.comp iso
      let compWithIso : (ℝ →L[ℝ] ℝ) →L[ℝ] (GaussianSobolev.E 1 →L[ℝ] ℝ) :=
        (ContinuousLinearMap.compSL (GaussianSobolev.E 1) ℝ ℝ (RingHom.id ℝ) (RingHom.id ℝ)).flip iso
      exact compWithIso.continuous.comp_aestronglyMeasurable hf.2.aestronglyMeasurable
    · filter_upwards with x
      rw [hnorm_eq]

/-! ### Transfer of Differentiability -/

/-- If f is differentiable on ℝ, then toE1Fun f is differentiable on E 1. -/
lemma differentiable_toE1Fun (f : ℝ → ℝ) (hf : Differentiable ℝ f) :
    Differentiable ℝ (toE1Fun f) :=
  hf.comp linearIsometryEquivE1Real.differentiable

/-- If f has continuous fderiv on ℝ, then toE1Fun f has continuous fderiv on E 1. -/
lemma continuous_fderiv_toE1Fun (f : ℝ → ℝ) (hf_diff : Differentiable ℝ f)
    (hf_cont : Continuous (fun x => fderiv ℝ f x)) :
    Continuous (fun x => fderiv ℝ (toE1Fun f) x) := by
  have heq : (fun x => fderiv ℝ (toE1Fun f) x) =
      fun x => (fderiv ℝ f (equivE1Real x)).comp (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ) := by
    funext x
    exact fderiv_toE1Fun f hf_diff x
  rw [heq]
  -- Show that composition with a fixed CLM on the right is continuous
  -- Use compSL.flip iso which is a continuous linear map
  let iso := (linearIsometryEquivE1Real : GaussianSobolev.E 1 →L[ℝ] ℝ)
  let compWithIso : (ℝ →L[ℝ] ℝ) →L[ℝ] (GaussianSobolev.E 1 →L[ℝ] ℝ) :=
    (ContinuousLinearMap.compSL (GaussianSobolev.E 1) ℝ ℝ (RingHom.id ℝ) (RingHom.id ℝ)).flip iso
  have h1 : (fun x => (fderiv ℝ f (equivE1Real x)).comp iso) =
      compWithIso ∘ (fun x => fderiv ℝ f (equivE1Real x)) := rfl
  rw [h1]
  exact compWithIso.continuous.comp (hf_cont.comp linearIsometryEquivE1Real.continuous)

/-! ### Transfer of Smooth Functions with Compact Support -/

/-- If g : E 1 → ℝ is smooth, then fromE1Fun g is smooth on ℝ. -/
lemma contDiff_fromE1Fun (g : GaussianSobolev.E 1 → ℝ) (hg : ContDiff ℝ (⊤ : ℕ∞) g) :
    ContDiff ℝ (⊤ : ℕ∞) (fromE1Fun g) := by
  unfold fromE1Fun
  exact hg.comp linearIsometryEquivE1Real.symm.contDiff

/-- If g : E 1 → ℝ has compact support, then fromE1Fun g has compact support on ℝ. -/
lemma hasCompactSupport_fromE1Fun (g : GaussianSobolev.E 1 → ℝ) (hg : HasCompactSupport g) :
    HasCompactSupport (fromE1Fun g) := by
  unfold fromE1Fun
  -- HasCompactSupport is about tsupport, so use the equiv to transfer it
  have hcont : Continuous equivE1Real := linearIsometryEquivE1Real.continuous
  -- The coercions agree
  have heq_coe : ⇑equivE1Real = ⇑linearIsometryEquivE1Real.toHomeomorph := rfl
  -- Function.support (g ∘ e.symm) = e '' Function.support g
  have hsupp_eq : Function.support (g ∘ equivE1Real.symm) = equivE1Real '' Function.support g := by
    ext x
    simp only [Function.mem_support, ne_eq, Function.comp_apply, Set.mem_image]
    constructor
    · intro hx
      use equivE1Real.symm x
      exact ⟨hx, Equiv.apply_symm_apply _ _⟩
    · intro ⟨y, hy, hyx⟩
      rw [← hyx, Equiv.symm_apply_apply]
      exact hy
  -- closure (support (g ∘ e.symm)) = closure (e '' support g) = e '' closure (support g)
  -- since e is a homeomorphism
  rw [hasCompactSupport_def, hsupp_eq, heq_coe]
  rw [← linearIsometryEquivE1Real.toHomeomorph.image_closure (Function.support g)]
  exact hg.image hcont

/-! ### Transfer of Sobolev Norm -/

/-- The Gaussian Sobolev norm squared of fromE1Fun g on ℝ equals that of g on E 1. -/
lemma gaussianSobolevNormSq_fromE1Fun (g : GaussianSobolev.E 1 → ℝ) (hg_smooth : ContDiff ℝ 1 g) :
    GaussianSobolevNormSqReal (fromE1Fun g) (gaussianReal 0 1) =
      GaussianSobolev.GaussianSobolevNormSq 1 g (stdGaussianE 1) := by
  have hg_diff := hg_smooth.differentiable one_ne_zero
  unfold GaussianSobolevNormSqReal GaussianSobolev.GaussianSobolevNormSq fromE1Fun
  -- AEMeasurable with the right measure
  have haem : AEMeasurable equivE1Real.symm (gaussianReal 0 1) :=
    measurableEquivE1Real.symm.measurable.aemeasurable
  congr 1
  · -- eLpNorm terms: eLpNorm g (map e.symm γ) = eLpNorm (g ∘ e.symm) γ
    rw [stdGaussianE_1_eq_map_gaussianReal]
    -- Need: AEStronglyMeasurable g (map equivE1Real.symm (gaussianReal 0 1))
    have hg_aesm : AEStronglyMeasurable g (Measure.map equivE1Real.symm (gaussianReal 0 1)) :=
      hg_diff.continuous.aestronglyMeasurable
    rw [eLpNorm_map_measure hg_aesm haem]
  · -- Gradient terms
    rw [stdGaussianE_1_eq_map_gaussianReal]
    -- Need: AEStronglyMeasurable (‖fderiv ℝ g ·‖) (map equivE1Real.symm (gaussianReal 0 1))
    have hfderiv_cont : Continuous (fderiv ℝ g) := hg_smooth.continuous_fderiv one_ne_zero
    have hgrad_aesm : AEStronglyMeasurable (fun x => ‖fderiv ℝ g x‖) (Measure.map equivE1Real.symm (gaussianReal 0 1)) :=
      (continuous_norm.comp hfderiv_cont).aestronglyMeasurable
    rw [eLpNorm_map_measure hgrad_aesm haem]
    -- Need to prove the functions are equal, which makes the eLpNorms equal
    have hfun_eq : (fun x => ‖fderiv ℝ (g ∘ equivE1Real.symm) x‖) =
        (fun x => ‖fderiv ℝ g x‖) ∘ equivE1Real.symm := by
      funext x
      simp only [Function.comp_apply]
      -- Need: ‖fderiv ℝ (g ∘ e.symm) x‖ = ‖fderiv ℝ g (e.symm x)‖
      -- equivE1Real.symm = linearIsometryEquivE1Real.symm as functions
      have heq_symm : ⇑equivE1Real.symm = ⇑linearIsometryEquivE1Real.symm := rfl
      have h : fderiv ℝ (g ∘ equivE1Real.symm) x =
          (fderiv ℝ g (equivE1Real.symm x)).comp (linearIsometryEquivE1Real.symm : ℝ →L[ℝ] GaussianSobolev.E 1) := by
        conv_lhs => rw [heq_symm]
        rw [fderiv_comp x (hg_diff _) linearIsometryEquivE1Real.symm.differentiable.differentiableAt]
        congr 1
        exact linearIsometryEquivE1Real.symm.toContinuousLinearEquiv.fderiv
      rw [h]
      have hiso_eq : (linearIsometryEquivE1Real.symm : ℝ →L[ℝ] GaussianSobolev.E 1) =
          linearIsometryEquivE1Real.symm.toLinearIsometry.toContinuousLinearMap := rfl
      rw [hiso_eq, ContinuousLinearMap.opNorm_comp_linearIsometryEquiv]
    rw [hfun_eq]

/-- toE1Fun and fromE1Fun are inverses on functions. -/
lemma fromE1Fun_toE1Fun (f : ℝ → ℝ) : fromE1Fun (toE1Fun f) = f := by
  ext x
  simp only [fromE1Fun, toE1Fun, Function.comp_apply, Equiv.apply_symm_apply]

/-- fromE1Fun (g - h) = fromE1Fun g - fromE1Fun h -/
lemma fromE1Fun_sub (g h : GaussianSobolev.E 1 → ℝ) :
    fromE1Fun (g - h) = fromE1Fun g - fromE1Fun h := by
  ext x
  simp only [fromE1Fun, Pi.sub_apply, Function.comp_apply]

/-- Gaussian Sobolev norm of (f - fromE1Fun g) relates to norm of (toE1Fun f - g). -/
lemma gaussianSobolevNormSq_sub_eq (f : ℝ → ℝ) (g : GaussianSobolev.E 1 → ℝ)
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fderiv ℝ f))
    (hg_smooth : ContDiff ℝ 1 g) :
    GaussianSobolevNormSqReal (f - fromE1Fun g) (gaussianReal 0 1) =
      GaussianSobolev.GaussianSobolevNormSq 1 (toE1Fun f - g) (stdGaussianE 1) := by
  have h1 : f - fromE1Fun g = fromE1Fun (toE1Fun f - g) := by
    rw [fromE1Fun_sub, fromE1Fun_toE1Fun]
  rw [h1]
  apply gaussianSobolevNormSq_fromE1Fun
  -- toE1Fun f - g is ContDiff 1 since toE1Fun f is smooth (f is ContDiff 1) and g is
  have hf_contdiff : ContDiff ℝ 1 f := contDiff_one_iff_fderiv.mpr ⟨hf_diff, hf_grad_cont⟩
  have hf'_smooth : ContDiff ℝ 1 (toE1Fun f) := by
    unfold toE1Fun
    exact hf_contdiff.comp linearIsometryEquivE1Real.contDiff
  exact hf'_smooth.sub hg_smooth

/-! ### Main Density Theorem for 1D -/

/-- From the density theorem, we can construct a sequence of smooth compactly supported
    functions converging to any regular f ∈ W^{1,2}(γ) in the 1D Gaussian Sobolev norm.

    This is the 1D specialization of `exists_smooth_compactSupport_seq_tendsto` for
    functions f : ℝ → ℝ with the standard 1D Gaussian measure. -/
theorem exists_smooth_compactSupport_seq_tendsto_real (f : ℝ → ℝ)
    (hf : MemW12GaussianReal f (gaussianReal 0 1))
    (hf_diff : Differentiable ℝ f) (hf_grad_cont : Continuous (fun x => fderiv ℝ f x)) :
    ∃ g : ℕ → (ℝ → ℝ),
      (∀ k, ContDiff ℝ (⊤ : ℕ∞) (g k)) ∧
      (∀ k, HasCompactSupport (g k)) ∧
      Tendsto (fun k => GaussianSobolevNormSqReal (f - g k) (gaussianReal 0 1)) atTop (nhds 0) := by
  -- Transform f to E 1
  let f' := toE1Fun f
  -- Verify hypotheses for the general theorem
  have hf' : GaussianSobolev.MemW12Gaussian 1 f' (stdGaussianE 1) :=
    memW12Gaussian_toE1Fun f hf hf_diff
  have hf'_diff : Differentiable ℝ f' := differentiable_toE1Fun f hf_diff
  have hf'_grad_cont : Continuous (fun x => fderiv ℝ f' x) :=
    continuous_fderiv_toE1Fun f hf_diff hf_grad_cont
  -- Apply the general density theorem
  obtain ⟨g', hg'_smooth, hg'_supp, hg'_conv⟩ :=
    GaussianSobolev.exists_smooth_compactSupport_seq_tendsto f' hf' hf'_diff hf'_grad_cont
  -- Transform the sequence back to ℝ
  use fun k => fromE1Fun (g' k)
  refine ⟨?_, ?_, ?_⟩
  · -- Smoothness
    intro k
    exact contDiff_fromE1Fun (g' k) (hg'_smooth k)
  · -- Compact support
    intro k
    exact hasCompactSupport_fromE1Fun (g' k) (hg'_supp k)
  · -- Convergence
    -- The key is: ‖f - fromE1Fun (g' k)‖ = ‖toE1Fun f - g' k‖
    have heq : (fun k => GaussianSobolevNormSqReal (f - fromE1Fun (g' k)) (gaussianReal 0 1)) =
        fun k => GaussianSobolev.GaussianSobolevNormSq 1 (f' - g' k) (stdGaussianE 1) := by
      ext k
      rw [gaussianSobolevNormSq_sub_eq f (g' k) hf_diff hf_grad_cont]
      -- g' k is ContDiff ⊤, hence ContDiff 1
      exact (hg'_smooth k).of_le (WithTop.coe_le_coe.mpr le_top)
    rw [heq]
    exact hg'_conv

end GaussianSobolevReal
