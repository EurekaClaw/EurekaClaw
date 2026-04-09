/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import Mathlib.Topology.MetricSpace.Basic
import Mathlib.Topology.MetricSpace.Pseudo.Lemmas
import Mathlib.Topology.Instances.Real.Lemmas
import Mathlib.Data.Finset.Card
import Mathlib.Data.Finset.Pairwise
import Mathlib.Data.Nat.WithBot
import Mathlib.MeasureTheory.Measure.Lebesgue.VolumeOfBalls
import Mathlib.Analysis.InnerProductSpace.EuclideanDist
import Mathlib.Analysis.SpecialFunctions.Pow.Real
import Mathlib.Algebra.BigOperators.Option
import Mathlib.Data.Fintype.Option
import Mathlib.MeasureTheory.Integral.Pi
import Mathlib.Probability.ProbabilityMassFunction.Basic
import Mathlib.Probability.ProbabilityMassFunction.Integrals
import Mathlib.Probability.Independence.Basic
import Mathlib.Probability.Moments.Variance
import Mathlib.Analysis.Normed.Lp.PiLp

/-!
# Covering and packing numbers

Basic definitions of epsilon-nets, covering numbers, and packing numbers for pseudo-metric spaces.

-/

noncomputable section

open Set Metric
open scoped BigOperators
open Classical

/-- `t` is an `eps`-net for `s` if every point of `s` lies in a closed ball of radius `eps`
centered at some element of `t`. We use closed balls to avoid side conditions when `eps = 0`. -/
def IsENet {A : Type*} [PseudoMetricSpace A] (t : Finset A) (eps : ℝ) (s : Set A) : Prop :=
  s ⊆ ⋃ x ∈ t, closedBall x eps

/-- Covering number: the minimal cardinality of a finite `eps`-net, as `WithTop Nat` (`⊤` if no
finite net exists). -/
def coveringNumber {A : Type*} [PseudoMetricSpace A] (eps : ℝ) (s : Set A) : WithTop Nat :=
  sInf {n : WithTop Nat | ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop Nat) = n}

/-- `t` is an `eps`-packing for `s` if it is contained in `s` and any two distinct points are
`eps`-separated. -/
def IsPacking {A : Type*} [PseudoMetricSpace A] (t : Finset A) (eps : ℝ) (s : Set A) : Prop :=
  (↑t ⊆ s) ∧ (t : Set A).Pairwise (fun x y => eps < dist x y)

/-- Packing number: the maximal cardinality of a finite `eps`-packing, as `WithTop Nat` (`⊤` if
unbounded). -/
def packingNumber {A : Type*} [PseudoMetricSpace A] (eps : ℝ) (s : Set A) : WithTop Nat :=
  sSup {n : WithTop Nat | ∃ t : Finset A, IsPacking t eps s ∧ (t.card : WithTop Nat) = n}

lemma coveringNumber_le_card {A : Type*} [PseudoMetricSpace A] {t : Finset A} {eps : ℝ} {s : Set A}
    (h : IsENet t eps s) : coveringNumber eps s ≤ (t.card : WithTop Nat) := by
  unfold coveringNumber
  have : (t.card : WithTop Nat) ∈
      {n : WithTop Nat | ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop Nat) = n} :=
    ⟨t, h, rfl⟩
  simpa using (sInf_le this)

lemma coveringNumber_empty {A : Type*} [PseudoMetricSpace A] (eps : ℝ) :
    coveringNumber eps (∅ : Set A) = 0 := by
  refine le_antisymm ?upper ?lower
  · have hnet : IsENet (∅ : Finset A) eps (∅ : Set A) := by
      intro x hx
      cases hx
    simpa using (coveringNumber_le_card hnet)
  · exact bot_le

/-!
## Basic properties of epsilon-nets and covering numbers
-/

variable {A : Type*} [PseudoMetricSpace A]

/-- If `t` is an `eps1`-net and `eps1 ≤ eps2`, then `t` is also an `eps2`-net. -/
lemma IsENet.mono_eps {t : Finset A} {eps1 eps2 : ℝ} {s : Set A}
    (h : IsENet t eps1 s) (heps : eps1 ≤ eps2) : IsENet t eps2 s := by
  intro x hx
  obtain ⟨y, hy_mem, hy_dist⟩ := mem_iUnion₂.mp (h hx)
  exact mem_iUnion₂.mpr ⟨y, hy_mem, closedBall_subset_closedBall heps hy_dist⟩

/-- Covering number is anti-monotone in epsilon: larger epsilon means smaller covering number. -/
lemma coveringNumber_anti_eps {eps1 eps2 : ℝ} {s : Set A}
    (heps : eps1 ≤ eps2) : coveringNumber eps2 s ≤ coveringNumber eps1 s := by
  unfold coveringNumber
  apply sInf_le_sInf
  intro n hn
  obtain ⟨t, ht_net, ht_card⟩ := hn
  exact ⟨t, ht_net.mono_eps heps, ht_card⟩

/-- Covering number is monotone in the set: larger set means larger covering number. -/
lemma coveringNumber_mono_set {eps : ℝ} {s t : Set A}
    (h : s ⊆ t) : coveringNumber eps s ≤ coveringNumber eps t := by
  unfold coveringNumber
  apply sInf_le_sInf
  intro n hn
  obtain ⟨net, hnet, hcard⟩ := hn
  exact ⟨net, fun x hx => hnet (h hx), hcard⟩

/-- A singleton has covering number at most 1. -/
lemma coveringNumber_singleton {a : A} {eps : ℝ} (heps : 0 ≤ eps) :
    coveringNumber eps {a} ≤ 1 := by
  have hnet : IsENet {a} eps {a} := by
    intro x hx
    rw [mem_singleton_iff] at hx
    rw [hx]
    exact mem_iUnion₂.mpr ⟨a, Finset.mem_singleton_self a, mem_closedBall_self heps⟩
  simpa only [Finset.card_singleton] using coveringNumber_le_card hnet

/-!
## Properties relating covering and packing numbers
-/

/-- A maximal packing is a covering: if no point of `s` can be added to a packing `t`,
    then `t` is an `eps`-net for `s`. Requires `eps ≥ 0` for the closed ball condition. -/
lemma isENet_of_maximal {t : Finset A} {eps : ℝ} {s : Set A}
    (heps : 0 ≤ eps)
    (hmax : ∀ a ∈ s, a ∉ t → ∃ x ∈ t, dist a x ≤ eps) :
    IsENet t eps s := by
  intro a ha
  by_cases hat : a ∈ t
  · exact mem_iUnion₂.mpr ⟨a, hat, mem_closedBall_self heps⟩
  · obtain ⟨x, hx_mem, hx_dist⟩ := hmax a ha hat
    exact mem_iUnion₂.mpr ⟨x, hx_mem, mem_closedBall.mpr hx_dist⟩

/-!
## Covering numbers for totally bounded sets
-/

/-- For a totally bounded set, the covering number is finite for any positive epsilon. -/
lemma coveringNumber_lt_top_of_totallyBounded {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) :
    coveringNumber eps s < ⊤ := by
  -- TotallyBounded gives us a finite cover by open balls
  obtain ⟨t, ht_sub, ht_finite, ht_cover⟩ := finite_approx_of_totallyBounded hs eps heps
  -- Convert to a Finset
  let t' : Finset A := ht_finite.toFinset
  -- The open ball cover implies a closed ball cover (with same radius)
  have hnet : IsENet t' eps s := by
    intro x hx
    have hx_cover := ht_cover hx
    rw [mem_iUnion₂] at hx_cover
    obtain ⟨y, hy_mem, hy_ball⟩ := hx_cover
    refine mem_iUnion₂.mpr ⟨y, ?_, mem_closedBall.mpr (le_of_lt (mem_ball.mp hy_ball))⟩
    exact ht_finite.mem_toFinset.mpr hy_mem
  calc coveringNumber eps s ≤ (t'.card : WithTop ℕ) := coveringNumber_le_card hnet
    _ < ⊤ := WithTop.coe_lt_top t'.card

/-- Helper: extract a natural number from a finite WithTop ℕ -/
lemma WithTop.untop_of_lt_top {n : WithTop ℕ} (h : n < ⊤) : ∃ m : ℕ, n = m := by
  cases n with
  | top => simp at h
  | coe m => exact ⟨m, rfl⟩

/-- For a totally bounded set, there exists a finite epsilon-net with points in s. -/
lemma exists_finset_isENet_subset_of_totallyBounded {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) :
    ∃ t : Finset A, IsENet t eps s ∧ (t : Set A) ⊆ s := by
  obtain ⟨t, ht_sub, ht_finite, ht_cover⟩ := finite_approx_of_totallyBounded hs eps heps
  let t' : Finset A := ht_finite.toFinset
  refine ⟨t', ?_, ?_⟩
  · -- IsENet property
    intro x hx
    have hx_cover := ht_cover hx
    rw [mem_iUnion₂] at hx_cover
    obtain ⟨y, hy_mem, hy_ball⟩ := hx_cover
    refine mem_iUnion₂.mpr ⟨y, ?_, mem_closedBall.mpr (le_of_lt (mem_ball.mp hy_ball))⟩
    exact ht_finite.mem_toFinset.mpr hy_mem
  · -- Subset property
    intro x hx
    simp only [Finset.mem_coe] at hx
    exact ht_sub (ht_finite.mem_toFinset.mp hx)

/-- For a totally bounded set, there exists a finite epsilon-net. -/
lemma exists_finset_isENet_of_totallyBounded {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) :
    ∃ t : Finset A, IsENet t eps s :=
  (exists_finset_isENet_subset_of_totallyBounded heps hs).imp fun _ h => h.1

/-- For a totally bounded set, there exists an optimal epsilon-net whose cardinality
    equals the covering number. -/
lemma exists_optimal_enet {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) :
    ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop ℕ) = coveringNumber eps s := by
  -- The set of cardinalities of eps-nets is nonempty
  have hne_set : {n : WithTop ℕ | ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop ℕ) = n}.Nonempty := by
    obtain ⟨t, ht⟩ := exists_finset_isENet_of_totallyBounded heps hs
    exact ⟨t.card, t, ht, rfl⟩
  exact csInf_mem hne_set

/-- For an optimal epsilon-net, the cardinality equals the covering number as a natural number. -/
lemma exists_optimal_enet_nat {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) :
    ∃ t : Finset A, IsENet t eps s ∧ (t.card : ℕ) = (coveringNumber eps s).untop
        (ne_top_of_lt (coveringNumber_lt_top_of_totallyBounded heps hs)) := by
  obtain ⟨t, ht_net, ht_card⟩ := exists_optimal_enet heps hs
  exact ⟨t, ht_net, WithTop.coe_injective (ht_card.trans (WithTop.coe_untop _ _).symm)⟩

/-- An eps-net inside s can be constructed from an (eps/2)-net by projecting points to s.
    For any (eps/2)-net t (possibly outside s), we project each point x ∈ t to some
    representative f(x) ∈ s ∩ closedBall(x, eps/2). The image f(t) is an eps-net for s
    contained in s (by triangle inequality: eps/2 + eps/2 = eps), with |f(t)| ≤ |t|. -/
lemma exists_enet_subset_from_half {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) (hsne : s.Nonempty) :
    ∃ t : Finset A, IsENet t eps s ∧ (t : Set A) ⊆ s ∧
      (t.card : WithTop ℕ) ≤ coveringNumber (eps / 2) s := by
  have heps2 : 0 < eps / 2 := by linarith
  -- Get an optimal (eps/2)-net (which may have points outside s)
  obtain ⟨net, hnet_isNet, hnet_card⟩ := exists_optimal_enet heps2 hs
  -- hnet_card : net.card = coveringNumber(eps/2, s)
  obtain ⟨s₀, hs₀⟩ := hsne
  -- Define the projection: for x, if closedBall(x, eps/2) ∩ s is nonempty, pick an element
  -- Otherwise use s₀ (this case won't affect the covering property)
  let proj : A → A := fun x =>
    if h : (s ∩ closedBall x (eps / 2)).Nonempty then h.some else s₀
  -- Project the net to s
  let t' := net.image proj
  refine ⟨t', ?_, ?_, ?_⟩
  -- 1. t' is an eps-net for s
  · intro y hy
    -- y ∈ s, so by hnet_isNet, ∃ x ∈ net with y ∈ closedBall(x, eps/2)
    have hy_covered := hnet_isNet hy
    rw [mem_iUnion₂] at hy_covered
    obtain ⟨x, hx_mem, hy_ball⟩ := hy_covered
    have hdist_yx : dist y x ≤ eps / 2 := mem_closedBall.mp hy_ball
    -- proj x is in s ∩ closedBall(x, eps/2)
    have hproj_spec : (s ∩ closedBall x (eps / 2)).Nonempty := ⟨y, hy, hy_ball⟩
    have hproj_in : proj x ∈ s ∩ closedBall x (eps / 2) := by
      simp only [proj, dif_pos hproj_spec]
      exact hproj_spec.some_mem
    have hdist_proj_x : dist (proj x) x ≤ eps / 2 := mem_closedBall.mp hproj_in.2
    -- By triangle inequality: dist(y, proj x) ≤ dist(y, x) + dist(x, proj x) ≤ eps
    have hdist_y_proj : dist y (proj x) ≤ eps := by
      calc dist y (proj x) ≤ dist y x + dist x (proj x) := dist_triangle y x (proj x)
        _ ≤ eps / 2 + eps / 2 := add_le_add hdist_yx (by rw [dist_comm]; exact hdist_proj_x)
        _ = eps := by ring
    have hproj_in_t' : proj x ∈ t' := Finset.mem_image.mpr ⟨x, hx_mem, rfl⟩
    exact mem_iUnion₂.mpr ⟨proj x, hproj_in_t', mem_closedBall.mpr hdist_y_proj⟩
  -- 2. t' ⊆ s
  · intro z hz
    rw [Finset.mem_coe, Finset.mem_image] at hz
    obtain ⟨x, _, rfl⟩ := hz
    by_cases h : (s ∩ closedBall x (eps / 2)).Nonempty
    · simp only [proj, dif_pos h]; exact h.some_mem.1
    · simp only [proj, dif_neg h]; exact hs₀
  -- 3. |t'| ≤ coveringNumber(eps/2, s)
  · have h_card_le : t'.card ≤ net.card := Finset.card_image_le
    calc (t'.card : WithTop ℕ) ≤ net.card := by exact_mod_cast h_card_le
      _ = coveringNumber (eps / 2) s := hnet_card

/-- Covering number is positive for nonempty totally bounded sets. -/
lemma coveringNumber_pos_of_nonempty_totallyBounded {eps : ℝ} {s : Set A}
    (heps : 0 < eps) (hs : TotallyBounded s) (hne : s.Nonempty) :
    0 < coveringNumber eps s := by
  have hfin : coveringNumber eps s < ⊤ := coveringNumber_lt_top_of_totallyBounded heps hs
  obtain ⟨n, hn⟩ := WithTop.untop_of_lt_top hfin
  rw [hn]
  by_contra h
  simp only [not_lt, nonpos_iff_eq_zero] at h
  rw [h] at hn
  have hzero : coveringNumber eps s = 0 := hn
  unfold coveringNumber at hzero
  have hmem : (0 : WithTop ℕ) ∈ {n : WithTop ℕ | ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop ℕ) = n} := by
    have hne_set : {n : WithTop ℕ | ∃ t : Finset A, IsENet t eps s ∧ (t.card : WithTop ℕ) = n}.Nonempty := by
      obtain ⟨t, ht⟩ := exists_finset_isENet_of_totallyBounded heps hs
      exact ⟨t.card, t, ht, rfl⟩
    have hsInf := csInf_mem hne_set
    rwa [← hzero]
  obtain ⟨t, ht_net, ht_card⟩ := hmem
  have ht_card' : t.card = 0 := by simpa using ht_card
  rw [Finset.card_eq_zero] at ht_card'
  obtain ⟨x, hx⟩ := hne
  have := ht_net hx
  rw [ht_card'] at this
  simp at this

end

/-!
## Covering Number Bound for Euclidean Balls

We prove the standard covering number bound: for the Euclidean ball B_2^d(R) of radius R
in d dimensions, the covering number satisfies:

  N(ε, B_2^d(R)) ≤ (1 + 2R/ε)^d

-/

section EuclideanBall

open MeasureTheory Finset

variable {ι : Type*} [Fintype ι] [Nonempty ι]

/-- The closed Euclidean ball of radius R centered at 0 in EuclideanSpace ℝ ι. -/
abbrev euclideanBall (R : ℝ) : Set (EuclideanSpace ℝ ι) := Metric.closedBall 0 R

omit [Nonempty ι] in
/-- The Euclidean ball is totally bounded (since it's compact in finite dimensions). -/
lemma euclideanBall_totallyBounded (R : ℝ) : TotallyBounded (euclideanBall R : Set (EuclideanSpace ℝ ι)) :=
  (ProperSpace.isCompact_closedBall 0 R).totallyBounded

omit [Nonempty ι] in
/-- The Euclidean ball is nonempty for non-negative radius. -/
lemma euclideanBall_nonempty {R : ℝ} (hR : 0 ≤ R) : (euclideanBall R : Set (EuclideanSpace ℝ ι)).Nonempty :=
  ⟨0, Metric.mem_closedBall_self hR⟩

/-- If points x and y are ε-separated (dist x y > ε), then the closed balls of radius ε/2
    around them are disjoint. -/
lemma closedBall_half_disjoint {E : Type*} [PseudoMetricSpace E] {x y : E} {eps : ℝ}
    (_heps : 0 ≤ eps) (hsep : eps < dist x y) :
    Disjoint (Metric.closedBall x (eps / 2)) (Metric.closedBall y (eps / 2)) := by
  apply Metric.closedBall_disjoint_closedBall
  calc eps / 2 + eps / 2 = eps := by ring
    _ < dist x y := hsep

/-- For a packing, the half-radius balls around distinct points are pairwise disjoint. -/
lemma packing_halfBalls_pairwiseDisjoint {E : Type*} [PseudoMetricSpace E]
    {t : Finset E} {eps : ℝ} {s : Set E}
    (heps : 0 ≤ eps) (hpacking : IsPacking t eps s) :
    (t : Set E).PairwiseDisjoint (fun x => Metric.closedBall x (eps / 2)) := by
  intro x hx y hy hxy
  have hsep := hpacking.2 hx hy hxy
  exact closedBall_half_disjoint heps hsep

/-- A half-radius ball around a point in closedBall(0, R) is contained in closedBall(0, R + eps/2). -/
lemma halfBall_subset_enlargedBall {E : Type*} [SeminormedAddCommGroup E]
    {x : E} {R eps : ℝ} (hx : x ∈ Metric.closedBall (0 : E) R) :
    Metric.closedBall x (eps / 2) ⊆ Metric.closedBall (0 : E) (R + eps / 2) := by
  intro z hz
  rw [Metric.mem_closedBall] at hx hz ⊢
  simp only [dist_zero_right] at hx ⊢
  have h1 : ‖z‖ = ‖z - x + x‖ := by simp
  calc ‖z‖ = ‖z - x + x‖ := h1
    _ ≤ ‖z - x‖ + ‖x‖ := norm_add_le _ _
    _ = dist z x + ‖x‖ := by rw [dist_eq_norm]
    _ ≤ eps / 2 + R := by linarith [hz, hx]
    _ = R + eps / 2 := by ring

/-- Union of half-balls around a packing in B(0, R) is contained in B(0, R + eps/2). -/
lemma packing_halfBalls_subset {E : Type*} [SeminormedAddCommGroup E]
    {t : Finset E} {R eps : ℝ} {s : Set E}
    (hpacking : IsPacking t eps s) (hs : s ⊆ Metric.closedBall (0 : E) R) :
    (⋃ x ∈ t, Metric.closedBall x (eps / 2)) ⊆ Metric.closedBall (0 : E) (R + eps / 2) := by
  intro z hz
  rw [Set.mem_iUnion₂] at hz
  obtain ⟨x, hxt, hzx⟩ := hz
  have hxs : x ∈ s := hpacking.1 hxt
  have hxR : x ∈ Metric.closedBall (0 : E) R := hs hxs
  exact halfBall_subset_enlargedBall hxR hzx

omit [Nonempty ι] in
/-- Key volume lemma: The volume of disjoint half-balls equals the sum of individual volumes. -/
lemma volume_disjoint_union_closedBalls
    {t : Finset (EuclideanSpace ℝ ι)} {eps : ℝ} (_heps : 0 ≤ eps)
    (hpwd : (t : Set (EuclideanSpace ℝ ι)).PairwiseDisjoint
        (fun x => Metric.closedBall x (eps / 2))) :
    MeasureTheory.volume (⋃ x ∈ t, Metric.closedBall x (eps / 2)) =
    ∑ x ∈ t, MeasureTheory.volume (Metric.closedBall x (eps / 2)) := by
  have hmeas : ∀ b ∈ t, MeasurableSet (Metric.closedBall b (eps / 2)) :=
    fun _ _ => measurableSet_closedBall
  exact measure_biUnion_finset hpwd hmeas

/-- The volume of a closed ball in EuclideanSpace is proportional to r^d. -/
lemma volume_closedBall_euclidean (x : EuclideanSpace ℝ ι) (r : ℝ) :
    MeasureTheory.volume (Metric.closedBall x r) =
    ENNReal.ofReal r ^ (Fintype.card ι) *
      ENNReal.ofReal (Real.pi.sqrt ^ Fintype.card ι /
        Real.Gamma (Fintype.card ι / 2 + 1)) :=
  EuclideanSpace.volume_closedBall ι x r

/-- The constant factor in the volume of a unit ball. -/
noncomputable def euclideanBallVolumeConst (d : ℕ) : ℝ :=
  Real.pi.sqrt ^ d / Real.Gamma (d / 2 + 1)

lemma euclideanBallVolumeConst_pos (d : ℕ) : 0 < euclideanBallVolumeConst d := by
  unfold euclideanBallVolumeConst
  apply div_pos
  · exact pow_pos (Real.sqrt_pos.mpr Real.pi_pos) d
  · have h : (0 : ℝ) < (d : ℝ) / 2 + 1 := by positivity
    exact Real.Gamma_pos_of_pos h

/-- The volume of a closed ball with radius r equals r^d times the unit ball volume. -/
lemma volume_closedBall_eq_rpow (x : EuclideanSpace ℝ ι) (r : ℝ) (hr : 0 ≤ r) :
    MeasureTheory.volume (Metric.closedBall x r) =
    ENNReal.ofReal (r ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) := by
  rw [volume_closedBall_euclidean]
  have hr_pow : ENNReal.ofReal r ^ Fintype.card ι = ENNReal.ofReal (r ^ Fintype.card ι) := by
    induction Fintype.card ι with
    | zero => simp
    | succ n ih =>
      rw [pow_succ, pow_succ, ih]
      rw [mul_comm (ENNReal.ofReal _) (ENNReal.ofReal r)]
      rw [← ENNReal.ofReal_mul hr]
      rw [mul_comm r (r ^ n)]
  rw [hr_pow]
  unfold euclideanBallVolumeConst
  rw [← ENNReal.ofReal_mul (pow_nonneg hr _)]

/-- Key cardinality bound: For a packing in B(0, R), we have
    |t| ≤ ((R + ε/2) / (ε/2))^d = (1 + 2R/ε)^d -/
lemma packing_card_bound_aux
    {t : Finset (EuclideanSpace ℝ ι)} {R eps : ℝ}
    (hR : 0 ≤ R) (heps : 0 < eps)
    (hpacking : IsPacking t eps (euclideanBall R)) :
    (t.card : ℝ) ≤ ((R + eps / 2) / (eps / 2)) ^ Fintype.card ι := by
  -- The half-balls are pairwise disjoint
  have hpwd := packing_halfBalls_pairwiseDisjoint (le_of_lt heps) hpacking
  -- They are contained in the larger ball
  have hsub := packing_halfBalls_subset hpacking (le_refl _)
  -- Volume of union = sum of volumes
  have hvol_eq := volume_disjoint_union_closedBalls (le_of_lt heps) hpwd
  -- Volume of union ≤ volume of containing ball
  have hvol_le : MeasureTheory.volume (⋃ x ∈ t, Metric.closedBall x (eps / 2)) ≤
      MeasureTheory.volume (Metric.closedBall (0 : EuclideanSpace ℝ ι) (R + eps / 2)) :=
    MeasureTheory.measure_mono hsub
  -- Each ball has the same volume
  have heps_half_pos : 0 < eps / 2 := by linarith
  have heps_half_nonneg : 0 ≤ eps / 2 := le_of_lt heps_half_pos
  have hR_plus_pos : 0 ≤ R + eps / 2 := by linarith
  -- Volume of each small ball
  have hvol_small : ∀ x : EuclideanSpace ℝ ι, MeasureTheory.volume (Metric.closedBall x (eps / 2)) =
      ENNReal.ofReal ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) :=
    fun x => volume_closedBall_eq_rpow x (eps / 2) heps_half_nonneg
  -- Volume of large ball
  have hvol_large : MeasureTheory.volume (Metric.closedBall (0 : EuclideanSpace ℝ ι) (R + eps / 2)) =
      ENNReal.ofReal ((R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) :=
    volume_closedBall_eq_rpow 0 (R + eps / 2) hR_plus_pos
  -- Sum of small ball volumes
  have hvol_sum : ∑ x ∈ t, MeasureTheory.volume (Metric.closedBall x (eps / 2)) =
      t.card * ENNReal.ofReal ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) := by
    simp only [hvol_small]
    rw [sum_const]
    simp only [nsmul_eq_mul]
  -- Combine: t.card * vol_small ≤ vol_large
  rw [hvol_eq, hvol_sum] at hvol_le
  rw [hvol_large] at hvol_le
  -- Convert to real inequality
  have hconst_pos := euclideanBallVolumeConst_pos (Fintype.card ι)
  have hsmall_pos : 0 < (eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) :=
    mul_pos (pow_pos heps_half_pos _) hconst_pos
  have hlarge_pos : 0 < (R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) :=
    mul_pos (pow_pos (by linarith : 0 < R + eps / 2) _) hconst_pos
  have hlarge_nonneg : 0 ≤ (R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) :=
    le_of_lt hlarge_pos
  -- Use ENNReal.ofReal for the bound
  have h : t.card * ENNReal.ofReal ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) ≤
      ENNReal.ofReal ((R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) := hvol_le
  rw [← ENNReal.ofReal_natCast] at h
  rw [← ENNReal.ofReal_mul (Nat.cast_nonneg _)] at h
  have h' := ENNReal.ofReal_le_ofReal_iff hlarge_nonneg |>.mp h
  -- Simplify: t.card * vol_small ≤ vol_large gives t.card ≤ vol_large / vol_small
  have hdiv : t.card * ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) ≤
      (R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) := h'
  have hcancel : (t.card : ℝ) ≤ (R + eps / 2) ^ Fintype.card ι / (eps / 2) ^ Fintype.card ι := by
    have hne : (eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) ≠ 0 :=
      ne_of_gt hsmall_pos
    have hsmall_nonneg : 0 ≤ (eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) :=
      le_of_lt hsmall_pos
    calc (t.card : ℝ)
      _ = t.card * ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) /
          ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) := by
        rw [mul_div_cancel_right₀ _ hne]
      _ ≤ (R + eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι) /
          ((eps / 2) ^ Fintype.card ι * euclideanBallVolumeConst (Fintype.card ι)) := by
        apply div_le_div_of_nonneg_right hdiv hsmall_nonneg
      _ = (R + eps / 2) ^ Fintype.card ι / (eps / 2) ^ Fintype.card ι := by
        rw [mul_div_mul_right _ _ (ne_of_gt hconst_pos)]
  have hdiv_eq : (R + eps / 2) ^ Fintype.card ι / (eps / 2) ^ Fintype.card ι =
      ((R + eps / 2) / (eps / 2)) ^ Fintype.card ι := by
    rw [← div_pow]
  rw [hdiv_eq] at hcancel
  exact hcancel

/-- Main bound: For a packing, |t| ≤ (1 + 2R/ε)^d. -/
lemma packing_card_bound
    {t : Finset (EuclideanSpace ℝ ι)} {R eps : ℝ}
    (hR : 0 ≤ R) (heps : 0 < eps)
    (hpacking : IsPacking t eps (euclideanBall R)) :
    (t.card : ℝ) ≤ (1 + 2 * R / eps) ^ Fintype.card ι := by
  have h := packing_card_bound_aux hR heps hpacking
  have heq : (R + eps / 2) / (eps / 2) = 1 + 2 * R / eps := by
    field_simp
    ring
  rw [heq] at h
  exact h

/-- A maximal packing is an ε-net: if no point of s can be added while maintaining
    ε-separation, then the packing is an ε-net. -/
lemma maximal_packing_isENet {E : Type*} [PseudoMetricSpace E]
    {t : Finset E} {eps : ℝ} {s : Set E}
    (heps : 0 ≤ eps)
    (_hpacking : IsPacking t eps s)
    (hmaximal : ∀ x ∈ s, x ∉ t → ∃ y ∈ t, dist x y ≤ eps) :
    IsENet t eps s :=
  isENet_of_maximal heps hmaximal

/-- Any ε-separated subset of a totally bounded set is finite. -/
lemma separated_finite_of_totallyBounded {E : Type*} [PseudoMetricSpace E]
    {s : Set E} {eps : ℝ} (heps : 0 < eps) (hs : TotallyBounded s)
    {t : Set E} (ht_sub : t ⊆ s) (ht_sep : t.Pairwise (fun x y => eps < dist x y)) :
    t.Finite := by
  -- If s is covered by finitely many ε/2-balls, any ε-separated set has bounded cardinality
  have heps2 : 0 < eps / 2 := by linarith
  obtain ⟨cover, _, hcover_finite, hcover⟩ := Metric.finite_approx_of_totallyBounded hs (eps / 2) heps2
  -- Each ε/2-ball can contain at most one point from t
  -- Define a function from t to cover: for each x ∈ t, pick a c ∈ cover with x ∈ ball(c, eps/2)
  classical
  have hmaps : ∀ x ∈ t, ∃ c ∈ cover, x ∈ Metric.ball c (eps / 2) := fun x hx => by
    have hxs := ht_sub hx
    have := hcover hxs
    simp only [Set.mem_iUnion] at this
    obtain ⟨c, hc, hxball⟩ := this
    exact ⟨c, hc, hxball⟩
  -- This function is injective
  let f : t → cover := fun ⟨x, hx⟩ => ⟨(hmaps x hx).choose, (hmaps x hx).choose_spec.1⟩
  have hf_inj : Function.Injective f := by
    intro ⟨x, hx⟩ ⟨y, hy⟩ heq
    simp only [f, Subtype.mk.injEq] at heq
    -- If f x = f y = c, then x, y ∈ ball(c, eps/2), so dist x y < eps
    have hxc := (hmaps x hx).choose_spec.2
    have hyc : y ∈ Metric.ball (hmaps y hy).choose (eps / 2) := (hmaps y hy).choose_spec.2
    by_cases hxy : x = y
    · exact Subtype.ext hxy
    · exfalso
      have hsep_xy := ht_sep hx hy hxy
      have hdist : dist x y < eps := by
        have heq' : (hmaps x hx).choose = (hmaps y hy).choose := heq
        calc dist x y ≤ dist x (hmaps x hx).choose + dist (hmaps x hx).choose y := dist_triangle _ _ _
          _ < eps / 2 + eps / 2 := by
            apply add_lt_add
            · exact Metric.mem_ball.mp hxc
            · rw [heq', dist_comm]; exact Metric.mem_ball.mp hyc
          _ = eps := by ring
      linarith
  -- cover is finite, so t is finite via the injection
  have hfin_cover : Finite cover := hcover_finite
  have hfin_t : Finite t := Finite.of_injective f hf_inj
  exact Set.finite_coe_iff.mp hfin_t

/-- The existence of a maximal packing in a totally bounded set. -/
lemma exists_maximal_packing {E : Type*} [PseudoMetricSpace E]
    {s : Set E} (eps : ℝ) (heps : 0 < eps) (hs : TotallyBounded s) :
    ∃ t : Finset E, IsPacking t eps s ∧
      (∀ x ∈ s, x ∉ t → ∃ y ∈ t, dist x y ≤ eps) := by
  classical
  -- Get the cover that bounds packing sizes
  have heps2 : 0 < eps / 2 := by linarith
  obtain ⟨cover, _, hcover_finite, hcover⟩ := Metric.finite_approx_of_totallyBounded hs (eps / 2) heps2
  -- Any packing has size at most |cover|
  have hbound : ∀ t : Finset E, IsPacking t eps s → t.card ≤ cover.ncard := by
    intro t ht
    have ht_sep : (t : Set E).Pairwise (fun x y => eps < dist x y) := ht.2
    have hmaps : ∀ x ∈ t, ∃ c ∈ cover, x ∈ Metric.ball c (eps / 2) := fun x hx => by
      have hxs := ht.1 hx
      have := hcover hxs
      simp only [Set.mem_iUnion] at this
      obtain ⟨c, hc, hxball⟩ := this
      exact ⟨c, hc, hxball⟩
    let f : t → cover := fun ⟨x, hx⟩ => ⟨(hmaps x hx).choose, (hmaps x hx).choose_spec.1⟩
    have hf_inj : Function.Injective f := by
      intro ⟨x, hx⟩ ⟨y, hy⟩ heq
      simp only [f, Subtype.mk.injEq] at heq
      have hxc := (hmaps x hx).choose_spec.2
      have hyc : y ∈ Metric.ball (hmaps y hy).choose (eps / 2) := (hmaps y hy).choose_spec.2
      by_cases hxy : x = y
      · exact Subtype.ext hxy
      · exfalso
        have hsep_xy := ht_sep hx hy hxy
        have heq' : (hmaps x hx).choose = (hmaps y hy).choose := heq
        have hdist : dist x y < eps := by
          calc dist x y ≤ dist x (hmaps x hx).choose + dist (hmaps x hx).choose y := dist_triangle _ _ _
            _ < eps / 2 + eps / 2 := by
              apply add_lt_add
              · exact Metric.mem_ball.mp hxc
              · rw [heq', dist_comm]; exact Metric.mem_ball.mp hyc
            _ = eps := by ring
        linarith
    haveI : Finite cover := hcover_finite
    haveI : Fintype cover := Fintype.ofFinite cover
    calc t.card = Fintype.card t := by rw [Fintype.card_coe]
      _ ≤ Fintype.card cover := Fintype.card_le_of_injective f hf_inj
      _ = cover.ncard := by
          rw [Set.ncard_eq_toFinset_card cover]
          simp [Set.toFinset_card]
  -- Construct maximal packing by induction on (bound - current_size)
  let bound := cover.ncard
  -- Iterate: if current packing is not maximal, extend it
  have iterate : ∀ n : ℕ, ∀ t : Finset E, IsPacking t eps s → bound - t.card = n →
      ∃ t' : Finset E, t ⊆ t' ∧ IsPacking t' eps s ∧
        (∀ x ∈ s, x ∉ t' → ∃ y ∈ t', dist x y ≤ eps) := by
    intro n
    induction n with
    | zero =>
      intro t ht_pack heq
      -- bound - t.card = 0, so t.card ≥ bound, hence t must be maximal
      use t, Finset.Subset.refl t, ht_pack
      intro x hxs hxt
      by_contra h
      push_neg at h
      -- x is ε-separated from t, so we could add x
      have hx_sep : ∀ y ∈ t, eps < dist x y := fun y hy => h y hy
      have ht'_pack : IsPacking (insert x t) eps s := by
        constructor
        · intro y hy
          rw [Finset.mem_coe, Finset.mem_insert] at hy
          rcases hy with rfl | hy
          · exact hxs
          · exact ht_pack.1 hy
        · intro y hy z hz hyz
          rw [Finset.mem_coe, Finset.mem_insert] at hy hz
          rcases hy with rfl | hy <;> rcases hz with rfl | hz
          · exact absurd rfl hyz
          · exact hx_sep z hz
          · rw [dist_comm]; exact hx_sep y hy
          · exact ht_pack.2 hy hz hyz
      have h_bound := hbound (insert x t) ht'_pack
      have h_card : (insert x t).card = t.card + 1 := Finset.card_insert_of_notMem hxt
      omega
    | succ n ih =>
      intro t ht_pack heq
      by_cases hmaximal : ∀ x ∈ s, x ∉ t → ∃ y ∈ t, dist x y ≤ eps
      · use t, Finset.Subset.refl t, ht_pack, hmaximal
      · push_neg at hmaximal
        obtain ⟨x, hxs, hxt, hx_sep⟩ := hmaximal
        -- Add x to get a larger packing
        have ht'_pack : IsPacking (insert x t) eps s := by
          constructor
          · intro y hy
            rw [Finset.mem_coe, Finset.mem_insert] at hy
            rcases hy with rfl | hy
            · exact hxs
            · exact ht_pack.1 hy
          · intro y hy z hz hyz
            rw [Finset.mem_coe, Finset.mem_insert] at hy hz
            rcases hy with rfl | hy <;> rcases hz with rfl | hz
            · exact absurd rfl hyz
            · have := hx_sep z hz; linarith
            · have := hx_sep y hy; rw [dist_comm]; linarith
            · exact ht_pack.2 hy hz hyz
        have h_card : (insert x t).card = t.card + 1 := Finset.card_insert_of_notMem hxt
        have h_gap : bound - (insert x t).card = n := by omega
        obtain ⟨t'', ht''_sub, ht''_pack, ht''_max⟩ := ih (insert x t) ht'_pack h_gap
        exact ⟨t'', Finset.Subset.trans (Finset.subset_insert x t) ht''_sub, ht''_pack, ht''_max⟩
  -- Apply with empty packing
  have hempty_pack : IsPacking (∅ : Finset E) eps s := by
    constructor
    · simp
    · simp
  have hgap : bound - (∅ : Finset E).card = bound := by simp
  obtain ⟨t, _, ht_pack, ht_max⟩ := iterate bound ∅ hempty_pack hgap
  exact ⟨t, ht_pack, ht_max⟩

/-- The covering number of the Euclidean ball B(0, R) satisfies N(ε, B(0,R)) ≤ (1 + 2R/ε)^d.
    The metric (2-norm) is implicitly determined by the type EuclideanSpace ℝ ι.
    This version casts the covering number to ℝ for a clean bound without ceilings. -/
theorem coveringNumber_euclideanBall_le {R eps : ℝ} (hR : 0 ≤ R) (heps : 0 < eps) :
    ((coveringNumber eps (euclideanBall R : Set (EuclideanSpace ℝ ι))).untop
        (ne_top_of_lt (coveringNumber_lt_top_of_totallyBounded heps
          (euclideanBall_totallyBounded R))) : ℝ) ≤
    (1 + 2 * R / eps) ^ Fintype.card ι := by
  have htb := euclideanBall_totallyBounded (ι := ι) R
  -- Get a maximal packing, which is also an ε-net
  obtain ⟨t, ht_pack, ht_max⟩ := exists_maximal_packing eps heps htb
  -- The maximal packing is an ε-net
  have ht_net : IsENet t eps (euclideanBall R) := isENet_of_maximal (le_of_lt heps) ht_max
  -- The covering number is at most t.card
  have hcov_le : coveringNumber eps (euclideanBall R : Set (EuclideanSpace ℝ ι)) ≤ t.card :=
    coveringNumber_le_card ht_net
  -- By the packing bound, t.card ≤ (1 + 2R/ε)^d
  have hpack_bound : (t.card : ℝ) ≤ (1 + 2 * R / eps) ^ Fintype.card ι :=
    packing_card_bound hR heps ht_pack
  -- Extract the natural number from the covering number
  have htop : coveringNumber eps (euclideanBall R : Set (EuclideanSpace ℝ ι)) < ⊤ :=
    coveringNumber_lt_top_of_totallyBounded heps htb
  obtain ⟨n, hn⟩ := WithTop.untop_of_lt_top htop
  simp only [hn]
  -- n ≤ t.card from hcov_le, and t.card ≤ bound from hpack_bound
  have hn_le_card : n ≤ t.card := by
    rw [hn] at hcov_le
    exact WithTop.coe_le_coe.mp hcov_le
  calc (n : ℝ) ≤ t.card := by exact_mod_cast hn_le_card
    _ ≤ (1 + 2 * R / eps) ^ Fintype.card ι := hpack_bound

end EuclideanBall

/-!
## Covering Number Bound for the L1 Ball in Euclidean Space

We show the standard bound

  N(ε, B₁^d(R), ‖·‖₂) ≤ (2d+1)^{⌈R^2/ε^2⌉₊}.
-/

section L1Ball

open Finset BigOperators Real MeasureTheory ProbabilityTheory

variable {d : ℕ}

-- MeasurableSpace for Option (Fin d) using discrete sigma-algebra
instance instMeasurableSpaceOptionFin (d : ℕ) : MeasurableSpace (Option (Fin d)) := ⊤
instance instMeasurableSingletonClassOptionFin (d : ℕ) : MeasurableSingletonClass (Option (Fin d)) :=
  ⟨fun _ => trivial⟩

-- L1 norm on EuclideanSpace ℝ (Fin d)
def l1norm (x : EuclideanSpace ℝ (Fin d)) : ℝ := ∑ i, ‖x i‖

def l1Ball (R : ℝ) : Set (EuclideanSpace ℝ (Fin d)) := {x | l1norm x ≤ R}

-- deterministic sign (+1 for nonnegative, -1 for negative)
noncomputable def sgn (x : ℝ) : ℝ := if 0 ≤ x then 1 else -1

lemma abs_mul_sgn (x : ℝ) : |x| * sgn x = x := by
  by_cases hx : 0 ≤ x
  · simp [sgn, hx, abs_of_nonneg hx]
  · have hx' : x < 0 := lt_of_not_ge hx
    simp [sgn, hx, abs_of_neg hx']

lemma sgn_sq (x : ℝ) : sgn x ^ 2 = 1 := by
  by_cases hx : 0 ≤ x <;> simp [sgn, hx]

-- vector-valued random variable depending on θ
noncomputable def vecθ (θ : EuclideanSpace ℝ (Fin d)) (R : ℝ) : Option (Fin d) → EuclideanSpace ℝ (Fin d)
  | none => 0
  | some j => EuclideanSpace.single j (R * sgn (θ j))

-- base sign for the net
def sgnBool (b : Bool) : ℝ := if b then 1 else -1

noncomputable def vec (R : ℝ) : Option (Fin d × Bool) → EuclideanSpace ℝ (Fin d)
  | none => 0
  | some (j, b) => EuclideanSpace.single j (R * sgnBool b)

noncomputable def embed (θ : EuclideanSpace ℝ (Fin d)) : Option (Fin d) → Option (Fin d × Bool)
  | none => none
  | some j => some (j, decide (0 ≤ θ j))

lemma sgnBool_decide (x : ℝ) : sgnBool (decide (0 ≤ x)) = sgn x := by
  by_cases hx : 0 ≤ x <;> simp [sgnBool, sgn, hx]

lemma vec_embed (θ : EuclideanSpace ℝ (Fin d)) (R : ℝ) (o : Option (Fin d)) :
    vec R (embed θ o) = vecθ θ R o := by
  cases o <;> simp [embed, vec, vecθ, sgnBool_decide]

noncomputable def avg (R : ℝ) (k : ℕ) (f : Fin k → Option (Fin d × Bool)) :
    EuclideanSpace ℝ (Fin d) :=
  (1 / (k : ℝ)) • ∑ i, vec R (f i)

noncomputable def avgθ (θ : EuclideanSpace ℝ (Fin d)) (R : ℝ) (k : ℕ) (f : Fin k → Option (Fin d)) :
    EuclideanSpace ℝ (Fin d) :=
  (1 / (k : ℝ)) • ∑ i, vecθ θ R (f i)

lemma avg_embed (θ : EuclideanSpace ℝ (Fin d)) (R : ℝ) (k : ℕ) (f : Fin k → Option (Fin d)) :
    avg R k (fun i => embed θ (f i)) = avgθ θ R k f := by
  simp [avg, avgθ, vec_embed]

-- Finite net built from all averages of k points in {0, ±R e_j}
noncomputable def l1Net (R : ℝ) (k : ℕ) : Finset (EuclideanSpace ℝ (Fin d)) := by
  classical
  exact (Finset.univ.image (avg R k))

lemma l1Net_card_le (R : ℝ) (k : ℕ) :
    (l1Net (d := d) R k).card ≤ (2 * d + 1) ^ k := by
  classical
  have hle : (l1Net (d := d) R k).card ≤
      (Finset.univ : Finset (Fin k → Option (Fin d × Bool))).card := by
    simpa [l1Net] using (Finset.card_image_le : (Finset.univ.image (avg R k)).card ≤ _)
  have hcardS : Fintype.card (Option (Fin d × Bool)) = 2 * d + 1 := by
    simp [Fintype.card_option, Fintype.card_prod, Fintype.card_bool,
      Nat.mul_comm, Nat.add_comm]
  -- card univ for function space
  have hcard_univ :
      (Finset.univ : Finset (Fin k → Option (Fin d × Bool))).card = (2 * d + 1) ^ k := by
    -- card_univ = card_fun
    simp [hcardS]
  simpa [hcard_univ] using hle

-- Probability distribution on Option (Fin d) based on θ
noncomputable def l1pmf (θ : EuclideanSpace ℝ (Fin d)) (R : ℝ) (hθ : l1norm θ ≤ R) :
    PMF (Option (Fin d)) := by
  classical
  refine PMF.ofFintype (fun o : Option (Fin d) => ?_) ?_
  · cases o with
    | none => exact ENNReal.ofReal (1 - l1norm θ / R)
    | some j => exact ENNReal.ofReal (‖θ j‖ / R)
  · -- sum to 1
    -- split option sum
    have hl1nonneg : 0 ≤ l1norm θ := Finset.sum_nonneg (fun i _ => norm_nonneg (θ i))
    have hR : 0 ≤ R := le_trans hl1nonneg hθ
    have hpos : 0 ≤ l1norm θ / R := by
      by_cases hR0 : R = 0
      · simp [hR0]
      · have hRpos : 0 < R := lt_of_le_of_ne hR (fun h => hR0 h.symm)
        exact div_nonneg hl1nonneg (le_of_lt hRpos)
    have hle : l1norm θ / R ≤ 1 := by
      by_cases hR0 : R = 0
      · simp [hR0]
      · have hRpos : 0 < R := lt_of_le_of_ne hR (fun h => hR0 h.symm)
        exact (div_le_one hRpos).2 hθ
    have hnonneg : 0 ≤ 1 - l1norm θ / R := by linarith
    -- evaluate sum over Option using Fintype.sum_option
    rw [Fintype.sum_option]
    by_cases hR0 : R = 0
    · -- R = 0 case: l1norm θ = 0 so θ = 0
      have hl1zero : l1norm θ = 0 := by
        have : l1norm θ ≤ 0 := by simp only [hR0] at hθ; exact hθ
        linarith
      have hcoord_zero : ∀ j : Fin d, ‖θ j‖ = 0 := by
        intro j
        have hsum : ∑ i, ‖θ i‖ = 0 := hl1zero
        exact Finset.sum_eq_zero_iff_of_nonneg (fun i _ => norm_nonneg _) |>.1 hsum j (by simp)
      simp only [hR0, div_zero, ENNReal.ofReal_zero, Finset.sum_const_zero, add_zero,
        sub_zero, ENNReal.ofReal_one]
    · -- R > 0 case
      have hRpos : 0 < R := lt_of_le_of_ne hR (fun h => hR0 h.symm)
      -- Convert to real calculation
      have hsum_real : (1 - l1norm θ / R) + ∑ j, ‖θ j‖ / R = 1 := by
        have : ∑ j : Fin d, ‖θ j‖ / R = l1norm θ / R := by
          simp only [l1norm, Finset.sum_div]
        rw [this]
        ring
      -- Use ENNReal.ofReal properties
      have hcoord_le : ∀ j : Fin d, ‖θ j‖ / R ≤ 1 := fun j => by
        have hjle : ‖θ j‖ ≤ l1norm θ := by
          simp only [l1norm]
          exact Finset.single_le_sum (fun i _ => norm_nonneg _) (Finset.mem_univ j)
        exact (div_le_one hRpos).2 (le_trans hjle hθ)
      rw [← ENNReal.ofReal_sum_of_nonneg (fun j _ => div_nonneg (norm_nonneg _) (le_of_lt hRpos))]
      rw [← ENNReal.ofReal_add hnonneg (Finset.sum_nonneg (fun j _ =>
        div_nonneg (norm_nonneg _) (le_of_lt hRpos)))]
      rw [hsum_real, ENNReal.ofReal_one] 

-- expectation of coordinate for base pmf
lemma l1pmf_mean_coord (θ : EuclideanSpace ℝ (Fin d)) {R : ℝ} (hR : 0 < R)
    (hθ : l1norm θ ≤ R) (j : Fin d) :
    ∫ o, (vecθ θ R o) j ∂(l1pmf θ R hθ).toMeasure = θ j := by
  classical
  -- integral as finite sum using PMF.integral_eq_sum
  rw [PMF.integral_eq_sum]
  -- Split sum over Option using Fintype.sum_option
  rw [Fintype.sum_option]
  -- The none term contributes 0
  simp only [vecθ, WithLp.ofLp_zero, Pi.zero_apply, smul_zero, zero_add]
  -- For EuclideanSpace, use single_apply and collapse the sum
  simp only [EuclideanSpace.single_apply, smul_ite, smul_zero]
  rw [Finset.sum_ite_eq Finset.univ j (fun x => _ • (R * sgn (θ x)))]
  simp only [Finset.mem_univ, ite_true]
  -- Now simplify the PMF value and sign
  simp only [l1pmf, PMF.ofFintype_apply]
  have hnorm_nonneg : 0 ≤ ‖θ j‖ := norm_nonneg _
  have hpos : 0 ≤ ‖θ j‖ / R := div_nonneg hnorm_nonneg (le_of_lt hR)
  rw [ENNReal.toReal_ofReal hpos]
  -- Use sgn and norm relationship: |θ j| / R * (R * sgn(θ j)) = |θ j| * sgn(θ j) = θ j
  rw [Real.norm_eq_abs, smul_eq_mul]
  have hRne : R ≠ 0 := ne_of_gt hR
  field_simp
  rw [abs_mul_sgn] 

lemma l1pmf_second_moment_coord (θ : EuclideanSpace ℝ (Fin d)) {R : ℝ} (hR : 0 < R)
    (hθ : l1norm θ ≤ R) (j : Fin d) :
    ∫ o, ((vecθ θ R o) j) ^ 2 ∂(l1pmf θ R hθ).toMeasure = R * ‖θ j‖ := by
  classical
  -- compute by finite sum, only the j term contributes
  rw [PMF.integral_eq_sum]
  rw [Fintype.sum_option]
  -- The none term contributes 0^2 = 0
  simp only [vecθ, WithLp.ofLp_zero, Pi.zero_apply, sq]
  -- Handle EuclideanSpace.single_apply
  simp only [EuclideanSpace.single_apply, ite_mul, mul_ite, mul_zero, zero_mul, smul_ite, smul_zero]
  -- Simplify nested if with same condition
  have hsum_simp : ∀ x, (if j = x then (if j = x then ((l1pmf θ R hθ) (some x)).toReal •
      (R * sgn (θ x) * (R * sgn (θ x))) else 0) else 0) =
      (if j = x then ((l1pmf θ R hθ) (some x)).toReal • (R * sgn (θ x) * (R * sgn (θ x))) else 0) := by
    intro x; split_ifs <;> rfl
  simp only [hsum_simp]
  rw [Finset.sum_ite_eq Finset.univ j (fun x => _ • ((R * sgn (θ x)) * (R * sgn (θ x))))]
  simp only [Finset.mem_univ, ite_true]
  -- Simplify (R * sgn(θ j))^2 = R^2
  have hsgn_sq : (R * sgn (θ j)) * (R * sgn (θ j)) = R ^ 2 := by
    rw [← sq, mul_pow, sgn_sq, mul_one]
  rw [hsgn_sq]
  -- Simplify PMF value
  simp only [l1pmf, PMF.ofFintype_apply]
  have hnorm_nonneg : 0 ≤ ‖θ j‖ := norm_nonneg _
  have hpos : 0 ≤ ‖θ j‖ / R := div_nonneg hnorm_nonneg (le_of_lt hR)
  rw [ENNReal.toReal_ofReal hpos]
  rw [Real.norm_eq_abs, smul_eq_mul]
  field_simp
  ring

-- Main bound: existence of close average
lemma exists_avgθ_close (θ : EuclideanSpace ℝ (Fin d)) {R eps : ℝ} (hR : 0 < R)
    (hε : 0 < eps) (hθ : l1norm θ ≤ R) (k : ℕ) (hk : R ^ 2 ≤ (k : ℝ) * eps ^ 2) :
    ∃ f : Fin k → Option (Fin d), dist (avgθ θ R k f) θ ≤ eps := by
  classical
  -- build product measure of k independent samples
  let p := l1pmf θ R hθ
  let μ : Measure (Option (Fin d)) := p.toMeasure
  let ν : Measure (Fin k → Option (Fin d)) := Measure.pi (fun _ : Fin k => μ)
  have hprob : IsProbabilityMeasure ν := by
    infer_instance

  -- expected squared distance bound
  have hbound :
      ∫ ω, dist (avgθ θ R k ω) θ ^ 2 ∂ν ≤ R ^ 2 / (k : ℝ) := by
    -- Express dist² as sum of coordinate squared differences
    have hdist_eq : ∀ ω, dist (avgθ θ R k ω) θ ^ 2 =
        ∑ j, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 := by
      intro ω
      rw [PiLp.dist_sq_eq_of_L2]
      congr 1
      ext j
      rw [Real.dist_eq, sq_abs]
    simp_rw [hdist_eq]
    -- Push integral inside sum (finite sum)
    rw [MeasureTheory.integral_finset_sum Finset.univ]
    swap
    · intro j _
      exact Integrable.of_finite
    -- Now bound each coordinate's contribution
    -- The goal is: ∑ j, ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν ≤ R² / k
    have hcoord_bound : ∀ j : Fin d,
        ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν ≤ R * ‖θ j‖ / k := by
      intro j
      -- The average at coordinate j: (avgθ θ R k ω).ofLp j = (1/k) * ∑ᵢ (vecθ θ R (ω i)).ofLp j
      have havg_coord : ∀ ω, (avgθ θ R k ω).ofLp j = (k : ℝ)⁻¹ * ∑ i, (vecθ θ R (ω i)).ofLp j := by
        intro ω
        simp only [avgθ, one_div, PiLp.smul_apply, smul_eq_mul]
        congr 1
        simp only [WithLp.ofLp_sum, Finset.sum_apply]
      calc ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν
          ≤ ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν := le_refl _
        _ ≤ R * ‖θ j‖ / k := by
            -- Use that for product measure, the variance of sum equals sum of variances
            -- and bound each variance by R * |θ_j| / k
            by_cases hk0 : k = 0
            · -- k = 0 is impossible since R² ≤ k * ε² and R > 0
              exfalso
              simp only [hk0, Nat.cast_zero, zero_mul] at hk
              have : 0 < R ^ 2 := sq_pos_of_pos hR
              linarith
            · have hkpos : (0 : ℝ) < k := Nat.cast_pos.mpr (Nat.pos_of_ne_zero hk0)
              have h2mom := l1pmf_second_moment_coord θ hR hθ j
              have hmean := l1pmf_mean_coord θ hR hθ j
              have hsingle_var : ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ ≤ R * ‖θ j‖ := by
                -- E[(X - θ_j)²] = E[X²] - 2θ_j·E[X] + θ_j² = E[X²] - θ_j²
                -- = R*|θ_j| - θ_j² ≤ R*|θ_j| (since θ_j² ≥ 0)
                have hexp_sq : ∫ o, ((vecθ θ R o).ofLp j)^2 ∂μ = R * ‖θ j‖ := h2mom
                have hexp : ∫ o, (vecθ θ R o).ofLp j ∂μ = θ.ofLp j := hmean
                -- Use E[(X-μ)²] = E[X²] - μ²
                have hvariance : ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ =
                    ∫ o, ((vecθ θ R o).ofLp j)^2 ∂μ - (θ.ofLp j)^2 := by
                  calc ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ
                      = ∫ o, ((vecθ θ R o).ofLp j)^2 - 2 * θ.ofLp j * (vecθ θ R o).ofLp j +
                          (θ.ofLp j)^2 ∂μ := by
                        congr 1; ext o; ring
                    _ = ∫ o, ((vecθ θ R o).ofLp j)^2 ∂μ -
                        2 * θ.ofLp j * ∫ o, (vecθ θ R o).ofLp j ∂μ +
                        ∫ o, (θ.ofLp j)^2 ∂μ := by
                        rw [MeasureTheory.integral_add]
                        rw [MeasureTheory.integral_sub]
                        rw [MeasureTheory.integral_const_mul]
                        all_goals exact Integrable.of_finite
                    _ = ∫ o, ((vecθ θ R o).ofLp j)^2 ∂μ -
                        2 * θ.ofLp j * θ.ofLp j + (θ.ofLp j)^2 := by
                        rw [hexp]
                        rw [MeasureTheory.integral_const]
                        -- μ = PMF.toMeasure, which is a probability measure
                        have hμprob : MeasureTheory.IsProbabilityMeasure μ := by
                          simp only [μ]
                          infer_instance
                        simp only [smul_eq_mul]
                        -- μ.real Set.univ = (μ Set.univ).toReal = 1.toReal = 1
                        have huniv : μ.real Set.univ = 1 := by
                          unfold Measure.real
                          rw [hμprob.measure_univ]
                          rfl
                        rw [huniv, one_mul]
                    _ = ∫ o, ((vecθ θ R o).ofLp j)^2 ∂μ - (θ.ofLp j)^2 := by ring
                rw [hvariance, hexp_sq]
                have hsq_nonneg : 0 ≤ (θ.ofLp j)^2 := sq_nonneg _
                linarith
              calc ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν
                  ≤ (k : ℝ)⁻¹ * (∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ) := by
                    -- Define centered random variable
                    let Y := fun i (ω : Fin k → Option (Fin d)) => (vecθ θ R (ω i)).ofLp j - θ.ofLp j
                    have havg_Y : ∀ ω, (avgθ θ R k ω).ofLp j - θ.ofLp j = (↑k)⁻¹ * ∑ i, Y i ω := by
                      intro ω
                      rw [havg_coord]
                      simp only [Y]
                      have hsum_eq : ∑ x : Fin k, ((vecθ θ R (ω x)).ofLp j - θ.ofLp j) =
                          ∑ x : Fin k, (vecθ θ R (ω x)).ofLp j - ∑ _x : Fin k, θ.ofLp j := by
                        rw [Finset.sum_sub_distrib]
                      rw [hsum_eq]
                      have hconst : ∑ _x : Fin k, θ.ofLp j = k * θ.ofLp j := by
                        simp only [Finset.sum_const, Finset.card_fin]
                        rw [nsmul_eq_mul]
                      rw [hconst]
                      have hkne : (k : ℝ) ≠ 0 := ne_of_gt hkpos
                      field_simp
                    simp_rw [havg_Y]
                    have hsq_factor : ∀ ω, ((↑k)⁻¹ * ∑ i, Y i ω) ^ 2 = (↑k)⁻¹ ^ 2 * (∑ i, Y i ω) ^ 2 := by intro ω; ring
                    simp_rw [hsq_factor]
                    rw [integral_const_mul]
                    have hexpand_sq : ∀ ω, (∑ i, Y i ω) ^ 2 = ∑ i, ∑ l, Y i ω * Y l ω := by intro ω; rw [sq, Finset.sum_mul_sum]
                    simp_rw [hexpand_sq]
                    rw [integral_finset_sum]; swap; · intro i _; exact Integrable.of_finite
                    simp_rw [integral_finset_sum _ (fun _ _ => Integrable.of_finite)]
                    -- Establish independence of Y_i under ν using iIndepFun_pi
                    have hindep : ProbabilityTheory.iIndepFun (fun i (ω : Fin k → Option (Fin d)) => Y i ω) ν := by
                      simp only [Y]
                      have hμprob : ∀ _ : Fin k, IsProbabilityMeasure μ := fun _ => by simp only [μ]; infer_instance
                      -- First establish that coordinate projections are iIndepFun
                      let f : (i : Fin k) → Option (Fin d) → Option (Fin d) := fun _ => id
                      have hf_meas : ∀ i, AEMeasurable (f i) μ := fun _ => measurable_id.aemeasurable
                      have hid := @ProbabilityTheory.iIndepFun_pi (Fin k) _ (fun _ => Option (Fin d)) _
                        (fun _ => μ) hμprob (fun _ => Option (Fin d)) _ f hf_meas
                      simp only [f, id_eq] at hid
                      -- Now compose with the centering function
                      let g : (i : Fin k) → Option (Fin d) → ℝ := fun _ o => (vecθ θ R o).ofLp j - θ.ofLp j
                      have hg_meas : ∀ i, Measurable (g i) := fun _ => measurable_of_countable _
                      have hcomp := hid.comp g hg_meas
                      simp only [g] at hcomp
                      exact hcomp
                    -- Show each Y_i has mean 0
                    have hY_mean_zero : ∀ i, ∫ ω, Y i ω ∂ν = 0 := by
                      intro i; simp only [Y]
                      have hmeas : AEStronglyMeasurable (fun o : Option (Fin d) => (vecθ θ R o).ofLp j - θ.ofLp j) μ := by
                        exact Measurable.aestronglyMeasurable (measurable_of_countable _)
                      have heq := MeasureTheory.integral_comp_eval (μ := fun _ : Fin k => μ) (i := i) hmeas
                      simp only [μ, ν] at heq ⊢; rw [heq, integral_sub (Integrable.of_finite) (Integrable.of_finite), hmean, integral_const]
                      have hμprob : IsProbabilityMeasure ((l1pmf θ R hθ).toMeasure) := by infer_instance
                      unfold Measure.real
                      rw [hμprob.measure_univ, ENNReal.toReal_one, smul_eq_mul, one_mul, sub_self]
                    -- Cross terms (i ≠ l) vanish due to independence and zero mean
                    have hcross : ∀ i l, i ≠ l → ∫ ω, Y i ω * Y l ω ∂ν = 0 := by
                      intro i l hil; have hpair := hindep.indepFun hil
                      have hmeas_i : AEStronglyMeasurable (Y i) ν := Measurable.aestronglyMeasurable (measurable_of_countable _)
                      have hmeas_l : AEStronglyMeasurable (Y l) ν := Measurable.aestronglyMeasurable (measurable_of_countable _)
                      rw [ProbabilityTheory.IndepFun.integral_fun_mul_eq_mul_integral hpair hmeas_i hmeas_l, hY_mean_zero i, hY_mean_zero l, mul_zero]
                    -- Diagonal terms equal single-sample variance
                    have hdiag : ∀ i, ∫ ω, Y i ω * Y i ω ∂ν = ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ := by
                      intro i; simp only [Y]
                      have hmeas : AEStronglyMeasurable (fun o : Option (Fin d) => ((vecθ θ R o).ofLp j - θ.ofLp j)^2) μ := by
                        exact Measurable.aestronglyMeasurable (measurable_of_countable _)
                      have heq := MeasureTheory.integral_comp_eval (μ := fun _ : Fin k => μ) (i := i) hmeas
                      simp only [μ, ν] at heq ⊢; convert heq using 2; ext ω; ring
                    -- Simplify sum: only diagonal terms survive
                    have hsum_eq : ∑ i : Fin k, ∑ l : Fin k, ∫ ω, Y i ω * Y l ω ∂ν = ∑ i : Fin k, ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ := by
                      congr 1; ext i
                      rw [Finset.sum_eq_single (a := i)]
                      · exact hdiag i
                      · intro l _ hli; exact hcross i l (Ne.symm hli)
                      · intro hi; exact (hi (Finset.mem_univ i)).elim
                    rw [hsum_eq, Finset.sum_const, Finset.card_fin]
                    -- Now k⁻² * (k * ∫ ...) = k⁻¹ * ∫ ...
                    have halg : ((↑k)⁻¹ : ℝ) ^ 2 * (↑k * ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ) =
                                (↑k)⁻¹ * ∫ o, ((vecθ θ R o).ofLp j - θ.ofLp j)^2 ∂μ := by
                      have hkne : (k : ℝ) ≠ 0 := ne_of_gt hkpos
                      field_simp
                    rw [nsmul_eq_mul, halg]
                _ ≤ (k : ℝ)⁻¹ * (R * ‖θ j‖) := by
                    apply mul_le_mul_of_nonneg_left hsingle_var (inv_nonneg.mpr (le_of_lt hkpos))
                _ = R * ‖θ j‖ / k := by rw [mul_comm, div_eq_mul_inv]
    -- Sum the coordinate bounds
    calc ∑ j, ∫ ω, ((avgθ θ R k ω).ofLp j - θ.ofLp j) ^ 2 ∂ν
        ≤ ∑ j, R * ‖θ j‖ / k := Finset.sum_le_sum (fun j _ => hcoord_bound j)
      _ = R / k * ∑ j, ‖θ j‖ := by rw [← Finset.sum_div, ← Finset.mul_sum]; ring
      _ = R / k * l1norm θ := by rfl
      _ ≤ R / k * R := by
          apply mul_le_mul_of_nonneg_left hθ
          by_cases hk0 : k = 0
          · simp [hk0]
          · exact div_nonneg (le_of_lt hR) (Nat.cast_nonneg k)
      _ = R ^ 2 / k := by ring
  -- apply first moment method
  have hint : Integrable (fun ω => dist (avgθ θ R k ω) θ ^ 2) ν := by
    -- finite space integrability
    have : Finite (Fin k → Option (Fin d)) := by
      infer_instance
    exact (Integrable.of_finite (μ := ν))
  obtain ⟨f, hf⟩ :=
    (MeasureTheory.exists_le_integral (μ := ν)
      (f := fun ω => dist (avgθ θ R k ω) θ ^ 2) hint)
  -- compare to eps^2
  have hk' : R ^ 2 / (k : ℝ) ≤ eps ^ 2 := by
    -- from hk
    have hk_rearranged : R ^ 2 ≤ eps ^ 2 * (k : ℝ) := by
      rw [mul_comm]; exact hk
    have hkpos : 0 < (k : ℝ) := by
      by_cases hk0 : k = 0
      · -- if k=0, then hk implies R=0, contradiction with hR
        exfalso
        have hR2 : R ^ 2 ≤ 0 := by
          have : R ^ 2 ≤ (k : ℝ) * eps ^ 2 := hk
          simp only [hk0, Nat.cast_zero, zero_mul] at this
          exact this
        have hRpos2 : 0 < R ^ 2 := sq_pos_of_pos hR
        linarith
      · exact Nat.cast_pos.mpr (Nat.pos_of_ne_zero hk0)
    exact (div_le_iff₀ hkpos).2 hk_rearranged
  have hdist : dist (avgθ θ R k f) θ ^ 2 ≤ eps ^ 2 := by
    exact le_trans hf (le_trans hbound hk')
  have hdist' : dist (avgθ θ R k f) θ ≤ eps := by
    -- take square root
    have hnonneg : 0 ≤ dist (avgθ θ R k f) θ := dist_nonneg
    have hnonneg' : 0 ≤ eps := le_of_lt hε
    exact (sq_le_sq₀ hnonneg hnonneg').1 hdist
  exact ⟨f, hdist'⟩

-- Final covering number bound
theorem coveringNumber_l1Ball_le {R eps : ℝ} (hR : 0 ≤ R) (hε : 0 < eps) :
    coveringNumber eps (l1Ball (d := d) R) ≤ (2 * d + 1) ^ (⌈R ^ 2 / eps ^ 2⌉₊) := by
  classical
  -- handle R = 0 separately
  by_cases hR0 : R = 0
  · subst hR0
    -- l1Ball 0 = {0}
    have hnet : IsENet ({0} : Finset (EuclideanSpace ℝ (Fin d))) eps (l1Ball (d := d) 0) := by
      intro x hx
      have hxeq0 : x = 0 := by
        have hle : l1norm x ≤ 0 := hx
        have hnonneg : 0 ≤ l1norm x := Finset.sum_nonneg (fun i _ => norm_nonneg _)
        have hl1zero : l1norm x = 0 := le_antisymm hle hnonneg
        -- if l1norm x = 0, then x=0
        ext i
        have hcoord : ‖x i‖ = 0 := by
          have hsum : ∑ j, ‖x j‖ = 0 := hl1zero
          exact Finset.sum_eq_zero_iff_of_nonneg (fun j _ => norm_nonneg _) |>.1 hsum i (by simp)
        exact norm_eq_zero.1 hcoord
      subst hxeq0
      exact Set.mem_iUnion₂.mpr ⟨0, by simp, Metric.mem_closedBall_self (by linarith)⟩
    simpa using (coveringNumber_le_card hnet)
  · have hRpos : 0 < R := lt_of_le_of_ne hR (fun h => hR0 h.symm)
    set k : ℕ := ⌈R ^ 2 / eps ^ 2⌉₊ with hk
    -- build the net
    let N : Finset (EuclideanSpace ℝ (Fin d)) := l1Net (d := d) R k
    have hcard : (N.card : WithTop ℕ) ≤ (2 * d + 1) ^ k := by
      exact_mod_cast (l1Net_card_le (d := d) R k)
    -- show N is an eps-net
    have hnet : IsENet N eps (l1Ball (d := d) R) := by
      intro θ hθ
      -- choose f with avg close
      have hk' : R ^ 2 ≤ (k : ℝ) * eps ^ 2 := by
        -- from k = ceil
        have := Nat.le_ceil (R ^ 2 / eps ^ 2)
        -- rearrange
        have hk' : (R ^ 2 / eps ^ 2) ≤ k := by
          simpa [hk] using this
        have hk'' : R ^ 2 ≤ (k : ℝ) * eps ^ 2 := by
          have hε2 : 0 < eps ^ 2 := by nlinarith
          have := (div_le_iff₀ hε2).1 hk'
          simpa [mul_comm, mul_left_comm, mul_assoc] using this
        exact hk''
      obtain ⟨f, hf⟩ := exists_avgθ_close (θ := θ) (R := R) (eps := eps) hRpos hε hθ k hk'
      -- map to N using embed
      let g : Fin k → Option (Fin d × Bool) := fun i => embed θ (f i)
      have hmem : avg R k g ∈ N := by
        -- by definition of N
        have : avg R k g ∈ Finset.univ.image (avg R k) := by
          exact Finset.mem_image.mpr ⟨g, Finset.mem_univ g, rfl⟩
        simp only [N, l1Net, this]
      -- conclude
      have hdist : dist θ (avg R k g) ≤ eps := by
        -- use avg_embed and dist_comm
        have heq : avg R k g = avgθ θ R k f := avg_embed θ R k f
        rw [heq, dist_comm]
        exact hf
      exact Set.mem_iUnion₂.mpr ⟨_, hmem, Metric.mem_closedBall.mpr hdist⟩
    -- finish with coveringNumber_le_card
    exact (coveringNumber_le_card hnet).trans hcard

/-!
## Peeling Inequality for ℓ₁-Balls

For θ in the ℓ₁-ball of radius 2R and τ > 0, we have:
  ‖θ‖₁ ≤ √(2R/τ + 1) · ‖θ‖₂ + 2R

This bounds the ℓ₁ norm in terms of the ℓ₂ norm via a "peeling" argument that
separates coordinates into those with large magnitude (> τ) and small magnitude (≤ τ).
-/

/-- The set of coordinates j where |θ j| > τ -/
noncomputable def largeCoords (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) : Finset (Fin d) :=
  Finset.filter (fun j => τ < ‖θ j‖) Finset.univ

/-- The ℓ₁ norm decomposes as sum over large coordinates plus sum over small coordinates -/
lemma l1norm_eq_sum_large_add_small (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) :
    l1norm θ = ∑ j ∈ largeCoords θ τ, ‖θ j‖ + ∑ j ∈ (largeCoords θ τ)ᶜ, ‖θ j‖ := by
  unfold l1norm largeCoords
  rw [← Finset.sum_filter_add_sum_filter_not Finset.univ (fun j => τ < ‖θ j‖) (fun j => ‖θ j‖)]
  simp only [Finset.compl_filter]

/-- Sum over small coordinates is at most the full ℓ₁ norm -/
lemma sum_small_coords_le_l1norm (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) :
    ∑ j ∈ (largeCoords θ τ)ᶜ, ‖θ j‖ ≤ l1norm θ := by
  unfold l1norm
  apply Finset.sum_le_univ_sum_of_nonneg
  intro x
  exact norm_nonneg _

/-- Sum over small coordinates is bounded by 2R when θ is in the ℓ₁-ball of radius 2R -/
lemma sum_small_coords_le (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) (R : ℝ)
    (hθ : l1norm θ ≤ 2 * R) :
    ∑ j ∈ (largeCoords θ τ)ᶜ, ‖θ j‖ ≤ 2 * R :=
  le_trans (sum_small_coords_le_l1norm θ τ) hθ

/-- Cauchy-Schwarz: sum of |θ j| over large coordinates is at most √|S| · ‖θ‖₂ -/
lemma sum_large_coords_le_sqrt_card_mul_norm (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) :
    ∑ j ∈ largeCoords θ τ, ‖θ j‖ ≤ Real.sqrt (largeCoords θ τ).card * ‖θ‖ := by
  -- Apply Cauchy-Schwarz: ∑ 1·|θⱼ| ≤ √(∑ 1²) · √(∑ |θⱼ|²)
  have hCS := Real.sum_mul_le_sqrt_mul_sqrt (largeCoords θ τ) (fun _ => (1 : ℝ)) (fun j => ‖θ j‖)
  simp only [one_mul, one_pow, Finset.sum_const, nsmul_eq_mul, mul_one] at hCS
  -- Now we need √(∑_{j∈S} ‖θ j‖²) ≤ ‖θ‖
  have hsub : ∑ j ∈ largeCoords θ τ, ‖θ j‖ ^ 2 ≤ ∑ j : Fin d, ‖θ j‖ ^ 2 := by
    apply Finset.sum_le_univ_sum_of_nonneg
    intro x
    exact sq_nonneg _
  have hnorm_sq : ‖θ‖ ^ 2 = ∑ j : Fin d, ‖θ j‖ ^ 2 := by
    rw [EuclideanSpace.norm_eq θ]
    rw [Real.sq_sqrt (Finset.sum_nonneg (fun i _ => sq_nonneg _))]
  have hpart_le_whole : Real.sqrt (∑ j ∈ largeCoords θ τ, ‖θ j‖ ^ 2) ≤ ‖θ‖ := by
    rw [← Real.sqrt_sq (norm_nonneg θ), hnorm_sq]
    apply Real.sqrt_le_sqrt
    exact hsub
  calc ∑ j ∈ largeCoords θ τ, ‖θ j‖
      ≤ Real.sqrt ↑(largeCoords θ τ).card * Real.sqrt (∑ j ∈ largeCoords θ τ, ‖θ j‖ ^ 2) := hCS
    _ ≤ Real.sqrt ↑(largeCoords θ τ).card * ‖θ‖ := by
        apply mul_le_mul_of_nonneg_left hpart_le_whole
        exact Real.sqrt_nonneg _

/-- Cardinality of large coordinates satisfies |S| · τ < 2R + τ -/
lemma largeCoords_card_mul_lt (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) (R : ℝ)
    (hτ : 0 < τ) (hθ : l1norm θ ≤ 2 * R) :
    (largeCoords θ τ).card * τ < 2 * R + τ := by
  have hsum_large : ∑ j ∈ largeCoords θ τ, τ ≤ ∑ j ∈ largeCoords θ τ, ‖θ j‖ := by
    apply Finset.sum_le_sum
    intro j hj
    simp only [largeCoords, Finset.mem_filter, Finset.mem_univ, true_and] at hj
    exact le_of_lt hj
  have hsum_large' : ∑ j ∈ largeCoords θ τ, ‖θ j‖ ≤ l1norm θ := by
    unfold l1norm
    apply Finset.sum_le_univ_sum_of_nonneg
    intro x
    exact norm_nonneg _
  have hcard_τ : (largeCoords θ τ).card * τ = ∑ j ∈ largeCoords θ τ, τ := by
    simp [Finset.sum_const, nsmul_eq_mul]
  rw [hcard_τ]
  calc ∑ j ∈ largeCoords θ τ, τ
      ≤ ∑ j ∈ largeCoords θ τ, ‖θ j‖ := hsum_large
    _ ≤ l1norm θ := hsum_large'
    _ ≤ 2 * R := hθ
    _ < 2 * R + τ := by linarith

/-- If |S| · τ < 2R + τ and τ > 0, then |S| < 2R/τ + 1 -/
lemma largeCoords_card_lt_div_add_one (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) (R : ℝ)
    (hτ : 0 < τ) (hθ : l1norm θ ≤ 2 * R) :
    ((largeCoords θ τ).card : ℝ) < 2 * R / τ + 1 := by
  have h := largeCoords_card_mul_lt θ τ R hτ hθ
  have hτpos : (0 : ℝ) < τ := hτ
  have h2 : (largeCoords θ τ).card * τ / τ < (2 * R + τ) / τ := by
    exact div_lt_div_of_pos_right h hτpos
  simp only [mul_div_assoc, div_self (ne_of_gt hτpos), mul_one] at h2
  have heq : (2 * R + τ) / τ = 2 * R / τ + 1 := by field_simp
  linarith

/-- Square root of cardinality bound: √|S| ≤ √(2R/τ + 1) -/
lemma sqrt_largeCoords_card_le (θ : EuclideanSpace ℝ (Fin d)) (τ : ℝ) (R : ℝ)
    (hτ : 0 < τ) (hθ : l1norm θ ≤ 2 * R) :
    Real.sqrt (largeCoords θ τ).card ≤ Real.sqrt (2 * R / τ + 1) := by
  apply Real.sqrt_le_sqrt
  have h := largeCoords_card_lt_div_add_one θ τ R hτ hθ
  linarith

/-- Peeling inequality: for θ in B₁(2R) and τ > 0,
    ‖θ‖₁ ≤ √(2R/τ + 1) · ‖θ‖₂ + 2R -/
theorem l1_peeling_inequality (θ : EuclideanSpace ℝ (Fin d)) (τ R : ℝ)
    (hτ : 0 < τ) (hθ : l1norm θ ≤ 2 * R) :
    l1norm θ ≤ Real.sqrt (2 * R / τ + 1) * ‖θ‖ + 2 * R := by
  rw [l1norm_eq_sum_large_add_small θ τ]
  have h1 : ∑ j ∈ largeCoords θ τ, ‖θ j‖ ≤ Real.sqrt (2 * R / τ + 1) * ‖θ‖ := by
    calc ∑ j ∈ largeCoords θ τ, ‖θ j‖
        ≤ Real.sqrt (largeCoords θ τ).card * ‖θ‖ := sum_large_coords_le_sqrt_card_mul_norm θ τ
      _ ≤ Real.sqrt (2 * R / τ + 1) * ‖θ‖ := by
          apply mul_le_mul_of_nonneg_right
          · exact sqrt_largeCoords_card_le θ τ R hτ hθ
          · exact norm_nonneg θ
  have h2 : ∑ j ∈ (largeCoords θ τ)ᶜ, ‖θ j‖ ≤ 2 * R := sum_small_coords_le θ τ R hθ
  linarith

/-- √(a + b) ≤ √a + √b for non-negative a, b -/
lemma sqrt_add_le_peeling {a b : ℝ} (ha : 0 ≤ a) (hb : 0 ≤ b) :
    Real.sqrt (a + b) ≤ Real.sqrt a + Real.sqrt b := by
  have hsum_nonneg : 0 ≤ Real.sqrt a + Real.sqrt b := by
    apply add_nonneg (Real.sqrt_nonneg a) (Real.sqrt_nonneg b)
  rw [← Real.sqrt_sq hsum_nonneg]
  apply Real.sqrt_le_sqrt
  ring_nf
  have h1 : (Real.sqrt a) ^ 2 = a := Real.sq_sqrt ha
  have h2 : (Real.sqrt b) ^ 2 = b := Real.sq_sqrt hb
  have h3 : 0 ≤ 2 * Real.sqrt a * Real.sqrt b := by
    apply mul_nonneg
    apply mul_nonneg (by norm_num : (0 : ℝ) ≤ 2) (Real.sqrt_nonneg a)
    exact Real.sqrt_nonneg b
  linarith

/-- Alternative form of peeling inequality using τ^(-1/2) notation -/
theorem l1_peeling_inequality' (θ : EuclideanSpace ℝ (Fin d)) (τ R : ℝ)
    (hτ : 0 < τ) (hR : 0 ≤ R) (hθ : l1norm θ ≤ 2 * R) :
    l1norm θ ≤ Real.sqrt (2 * R) * τ ^ (-(1:ℝ)/2) * ‖θ‖ + ‖θ‖ + 2 * R := by
  have h := l1_peeling_inequality θ τ R hτ hθ
  -- We have √(2R/τ + 1) ≤ √(2R/τ) + 1 = √(2R) · τ^(-1/2) + 1
  have hsplit : Real.sqrt (2 * R / τ + 1) ≤ Real.sqrt (2 * R / τ) + 1 := by
    have h1 : 0 ≤ 2 * R / τ := by positivity
    have h2 : Real.sqrt (2 * R / τ + 1) ≤ Real.sqrt (2 * R / τ) + Real.sqrt 1 := by
      exact sqrt_add_le_peeling h1 (by norm_num : (0:ℝ) ≤ 1)
    simp at h2
    exact h2
  have hrewrite : Real.sqrt (2 * R / τ) = Real.sqrt (2 * R) * τ ^ (-(1:ℝ)/2) := by
    rw [Real.sqrt_div' (2 * R) (le_of_lt hτ)]
    rw [div_eq_mul_inv]
    congr 1
    rw [Real.sqrt_eq_rpow]
    rw [← Real.rpow_neg (le_of_lt hτ)]
    norm_num
  calc l1norm θ
      ≤ Real.sqrt (2 * R / τ + 1) * ‖θ‖ + 2 * R := h
    _ ≤ (Real.sqrt (2 * R / τ) + 1) * ‖θ‖ + 2 * R := by gcongr
    _ = Real.sqrt (2 * R / τ) * ‖θ‖ + ‖θ‖ + 2 * R := by ring
    _ = Real.sqrt (2 * R) * τ ^ (-(1:ℝ)/2) * ‖θ‖ + ‖θ‖ + 2 * R := by rw [hrewrite]

end L1Ball

/-!
## Covering Numbers Under Lipschitz Maps

If f : A → B is an L-Lipschitz surjection onto f(S), then any ε-net for S
induces an ε·L-net for f(S). This gives: N(ε·L, f(S)) ≤ N(ε, S).
-/

section LipschitzImage

variable {A B : Type*} [PseudoMetricSpace A] [PseudoMetricSpace B]

/-- An ε-net for a set S induces an ε·L-net for the image f(S) under an L-Lipschitz map. -/
lemma IsENet.image_of_lipschitz [DecidableEq B] {L : ℝ} (hL : 0 ≤ L) {f : A → B}
    (hf : ∀ x y : A, dist (f x) (f y) ≤ L * dist x y)
    {t : Finset A} {eps : ℝ} {s : Set A}
    (hnet : IsENet t eps s) :
    IsENet (t.image f) (L * eps) (f '' s) := by
  intro y hy
  rw [Set.mem_image] at hy
  obtain ⟨x, hx, rfl⟩ := hy
  have hx_cover := hnet hx
  rw [Set.mem_iUnion₂] at hx_cover
  obtain ⟨z, hz_mem, hx_ball⟩ := hx_cover
  rw [Set.mem_iUnion₂]
  refine ⟨f z, Finset.mem_image.mpr ⟨z, hz_mem, rfl⟩, ?_⟩
  rw [Metric.mem_closedBall] at hx_ball ⊢
  calc dist (f x) (f z) ≤ L * dist x z := hf x z
    _ ≤ L * eps := mul_le_mul_of_nonneg_left hx_ball hL

/-- Covering number of a Lipschitz image: N(L·ε, f(S)) ≤ N(ε, S). -/
lemma coveringNumber_image_le_of_lipschitz [DecidableEq B] {L : ℝ} (hL : 0 < L) {f : A → B}
    (hf : ∀ x y : A, dist (f x) (f y) ≤ L * dist x y)
    {eps : ℝ} {s : Set A} :
    coveringNumber (L * eps) (f '' s) ≤ coveringNumber eps s := by
  -- If coveringNumber eps s = ⊤, the inequality is trivial
  by_cases h : coveringNumber eps s = ⊤
  · simp [h]
  -- Otherwise, there exists a finite ε-net for s
  · push_neg at h
    -- Extract the covering number as a natural number
    obtain ⟨n, hn⟩ := WithTop.ne_top_iff_exists.mp h
    -- The set of ε-net sizes is nonempty (since coveringNumber < ⊤)
    have hne : {m : WithTop ℕ | ∃ t : Finset A, IsENet t eps s ∧ ↑t.card = m}.Nonempty := by
      by_contra hemp
      have hemp' : {m : WithTop ℕ | ∃ t : Finset A, IsENet t eps s ∧ ↑t.card = m} = ∅ :=
        Set.not_nonempty_iff_eq_empty.mp hemp
      have : coveringNumber eps s = ⊤ := by
        unfold coveringNumber
        simp only [hemp', WithTop.sInf_empty]
      exact h this
    -- Get a finite ε-net achieving the infimum
    have hmem := csInf_mem hne
    unfold coveringNumber at hmem
    obtain ⟨t, ht_net, ht_card⟩ := hmem
    have hnet_image := IsENet.image_of_lipschitz (le_of_lt hL) hf ht_net
    have hcard_le : (t.image f).card ≤ t.card := Finset.card_image_le
    calc coveringNumber (L * eps) (f '' s)
      _ ≤ (t.image f).card := coveringNumber_le_card hnet_image
      _ ≤ t.card := by exact_mod_cast hcard_le
      _ = coveringNumber eps s := ht_card

/-- For a 1-Lipschitz map, covering number of image ≤ covering number of preimage. -/
lemma coveringNumber_image_le_of_nonexpansive [DecidableEq B] {f : A → B}
    (hf : ∀ x y : A, dist (f x) (f y) ≤ dist x y)
    {eps : ℝ} {s : Set A} :
    coveringNumber eps (f '' s) ≤ coveringNumber eps s := by
  have h1 : ∀ x y : A, dist (f x) (f y) ≤ 1 * dist x y := fun x y => by simpa using hf x y
  have h := coveringNumber_image_le_of_lipschitz one_pos h1 (eps := eps) (s := s)
  simp only [one_mul] at h
  exact h

/-- Covering number is preserved under isometric bijections -/
theorem coveringNumber_image_of_isometry {f : A → B} (hf : Isometry f) (hbij : Function.Bijective f)
    {eps : ℝ} (s : Set A) :
    coveringNumber eps (f '' s) = coveringNumber eps s := by
  apply le_antisymm
  · -- Forward: coveringNumber (f '' s) ≤ coveringNumber s
    haveI : DecidableEq B := Classical.decEq B
    have h1Lip : ∀ x y : A, dist (f x) (f y) ≤ dist x y := fun x y => by
      rw [hf.dist_eq]
    exact coveringNumber_image_le_of_nonexpansive h1Lip
  · -- Backward: coveringNumber s ≤ coveringNumber (f '' s)
    by_cases hcover : coveringNumber eps (f '' s) = ⊤
    · simp [hcover]
    push_neg at hcover
    have hne : {m : WithTop ℕ | ∃ t : Finset B, IsENet t eps (f '' s) ∧ (t.card : WithTop ℕ) = m}.Nonempty := by
      by_contra hemp
      have : coveringNumber eps (f '' s) = ⊤ := by
        unfold coveringNumber
        simp only [Set.not_nonempty_iff_eq_empty.mp hemp, WithTop.sInf_empty]
      exact hcover this
    have hmem := csInf_mem hne
    obtain ⟨t, ht_net, ht_card⟩ := hmem
    haveI : DecidableEq A := Classical.decEq A
    obtain ⟨g, hfg⟩ := hbij.2.hasRightInverse
    let t' : Finset A := t.image g
    have ht'_net : IsENet t' eps s := by
      intro x hx
      have hfx : f x ∈ f '' s := Set.mem_image_of_mem f hx
      have hcover_fx := ht_net hfx
      rw [Set.mem_iUnion₂] at hcover_fx ⊢
      obtain ⟨y, hy_mem, hfx_ball⟩ := hcover_fx
      refine ⟨g y, Finset.mem_image.mpr ⟨y, hy_mem, rfl⟩, ?_⟩
      rw [Metric.mem_closedBall] at hfx_ball ⊢
      calc dist x (g y) = dist (f x) (f (g y)) := (hf.dist_eq x (g y)).symm
        _ = dist (f x) y := by rw [hfg y]
        _ ≤ eps := hfx_ball
    calc coveringNumber eps s ≤ t'.card := coveringNumber_le_card ht'_net
      _ ≤ t.card := by exact_mod_cast Finset.card_image_le
      _ = coveringNumber eps (f '' s) := ht_card

end LipschitzImage
