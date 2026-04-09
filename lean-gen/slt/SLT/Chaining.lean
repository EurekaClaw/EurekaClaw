/-
Copyright (c) 2026 Yuanhe Zhang. All rights reserved.
Released under Apache 2.0 license as described in the file LICENSE.
Authors: Yuanhe Zhang, Jason D. Lee, Fanghui Liu
-/
import SLT.CoveringNumber
import Mathlib.Analysis.SpecialFunctions.Pow.Real

/-!
# Chaining Infrastructure

This file provides the chaining infrastructure needed for Dudley's entropy integral bound.
The key idea is to approximate points using a hierarchy of epsilon-nets at dyadic scales.

-/

open Set Metric Real
open scoped BigOperators

noncomputable section

variable {A : Type*} [PseudoMetricSpace A]

/-- The dyadic scale at level k: D * 2^(-k) -/
def dyadicScale (D : ℝ) (k : ℕ) : ℝ := D * (2 : ℝ)^(-(k : ℤ))

lemma dyadicScale_pos {D : ℝ} (hD : 0 < D) (k : ℕ) : 0 < dyadicScale D k := by
  unfold dyadicScale
  apply mul_pos hD
  apply zpow_pos (by norm_num : (0 : ℝ) < 2)

lemma dyadicScale_mono {D : ℝ} (hD : 0 < D) {k₁ k₂ : ℕ} (h : k₁ ≤ k₂) :
    dyadicScale D k₂ ≤ dyadicScale D k₁ := by
  unfold dyadicScale
  apply mul_le_mul_of_nonneg_left _ (le_of_lt hD)
  apply zpow_le_zpow_right₀ (by norm_num : (1 : ℝ) ≤ 2)
  simp only [neg_le_neg_iff, Int.ofNat_le]
  exact h

lemma dyadicScale_zero (D : ℝ) : dyadicScale D 0 = D := by
  unfold dyadicScale
  simp

lemma dyadicScale_succ (D : ℝ) (k : ℕ) : dyadicScale D (k + 1) = dyadicScale D k / 2 := by
  unfold dyadicScale
  simp only [Nat.cast_add, Nat.cast_one, neg_add, zpow_add₀ (by norm_num : (2 : ℝ) ≠ 0)]
  ring

/-- A hierarchy of epsilon-nets at dyadic scales.
    At each level k, we have an eps_k-net where eps_k = D * 2^(-k). -/
structure DyadicNets (s : Set A) (D : ℝ) where
  /-- The epsilon-net at each level -/
  nets : ℕ → Finset A
  /-- Each net is indeed an epsilon-net at the appropriate scale -/
  isNet : ∀ k, IsENet (nets k) (dyadicScale D k) s
  /-- Each net consists of points in s -/
  nets_subset : ∀ k, (nets k : Set A) ⊆ s

/-- For a totally bounded set, we can construct dyadic nets at any scale. -/
theorem exists_dyadicNets {s : Set A} (hs : TotallyBounded s) {D : ℝ} (hD : 0 < D) :
    Nonempty (DyadicNets s D) := by
  -- For each k, use exists_finset_isENet_subset_of_totallyBounded
  have h : ∀ k, ∃ t : Finset A, IsENet t (dyadicScale D k) s ∧ (t : Set A) ⊆ s := by
    intro k
    exact exists_finset_isENet_subset_of_totallyBounded (dyadicScale_pos hD k) hs
  -- Use choice to get the nets
  choose nets hnets using h
  exact ⟨⟨nets, fun k => (hnets k).1, fun k => (hnets k).2⟩⟩

/-- DyadicNets with cardinality bounds: each net at scale k has cardinality bounded by
    the covering number at the next finer scale (k+1). This bound is crucial for relating
    chaining arguments to covering numbers in Dudley's theorem. -/
structure GoodDyadicNets (s : Set A) (D : ℝ) (hD : 0 < D) (hs : TotallyBounded s) extends DyadicNets s D where
  /-- Each net at scale k has cardinality ≤ coveringNumber at scale k+1 -/
  card_bound : ∀ k, (nets k).card ≤ (coveringNumber (dyadicScale D (k + 1)) s).untop
      (ne_top_of_lt (coveringNumber_lt_top_of_totallyBounded (dyadicScale_pos hD (k + 1)) hs))

/-- Good dyadic nets exist for nonempty totally bounded sets.
    The key insight: use exists_enet_subset_from_half at each scale, which gives an eps-net
    inside s with cardinality ≤ coveringNumber(eps/2). Since dyadicScale D k / 2 = dyadicScale D (k+1),
    this gives the desired cardinality bound. -/
theorem exists_goodDyadicNets {s : Set A} (hs : TotallyBounded s) (hsne : s.Nonempty)
    {D : ℝ} (hD : 0 < D) :
    Nonempty (GoodDyadicNets s D hD hs) := by
  -- For each k, use exists_enet_subset_from_half with eps = dyadicScale D k
  -- This gives an eps-net inside s with cardinality ≤ coveringNumber(eps/2)
  -- Since eps/2 = dyadicScale D k / 2 = dyadicScale D (k+1), we get the bound
  have h : ∀ k, ∃ t : Finset A, IsENet t (dyadicScale D k) s ∧ (t : Set A) ⊆ s ∧
      (t.card : WithTop ℕ) ≤ coveringNumber (dyadicScale D k / 2) s := by
    intro k
    exact exists_enet_subset_from_half (dyadicScale_pos hD k) hs hsne
  choose nets hnets using h
  -- Convert the cardinality bound from dyadicScale D k / 2 to dyadicScale D (k+1)
  have hcard_bound : ∀ k, (nets k).card ≤ (coveringNumber (dyadicScale D (k + 1)) s).untop
      (ne_top_of_lt (coveringNumber_lt_top_of_totallyBounded (dyadicScale_pos hD (k + 1)) hs)) := by
    intro k
    have hbound := (hnets k).2.2
    -- dyadicScale D (k+1) = dyadicScale D k / 2
    rw [← dyadicScale_succ] at hbound
    -- Now hbound : nets k .card ≤ coveringNumber (dyadicScale D (k+1)) s
    have hfin : coveringNumber (dyadicScale D (k + 1)) s < ⊤ :=
      coveringNumber_lt_top_of_totallyBounded (dyadicScale_pos hD (k + 1)) hs
    have hne : coveringNumber (dyadicScale D (k + 1)) s ≠ ⊤ := ne_top_of_lt hfin
    rw [← WithTop.coe_untop _ hne] at hbound
    exact WithTop.coe_le_coe.mp hbound
  exact ⟨⟨⟨nets, fun k => (hnets k).1, fun k => (hnets k).2.1⟩, hcard_bound⟩⟩

/-- Key lemma: Given an epsilon-net, any point in s has a nearby point in the net. -/
lemma exists_near_in_net {t : Finset A} {eps : ℝ} {s : Set A}
    (hnet : IsENet t eps s) {x : A} (hx : x ∈ s) :
    ∃ y ∈ t, dist x y ≤ eps := by
  have := hnet hx
  rw [mem_iUnion₂] at this
  obtain ⟨y, hy_mem, hy_ball⟩ := this
  exact ⟨y, hy_mem, mem_closedBall.mp hy_ball⟩

/-- The chaining approximation: for any point x and any level K,
    there exists a sequence of approximations through the nets. -/
theorem chaining_approximation {s : Set A} {D : ℝ} (dn : DyadicNets s D) {x : A} (hx : x ∈ s) (K : ℕ) :
    ∃ y ∈ dn.nets K, dist x y ≤ dyadicScale D K :=
  exists_near_in_net (dn.isNet K) hx

/-- The telescoping property: if we have approximations at levels k and k+1,
    the distance between them is bounded by 2 * eps_k. -/
theorem telescoping_bound {D : ℝ} (k : ℕ)
    {x y_k : A} (hy_k_near : dist x y_k ≤ dyadicScale D k)
    {y_k1 : A} (hy_k1_near : dist x y_k1 ≤ dyadicScale D (k + 1)) :
    dist y_k y_k1 ≤ dyadicScale D k + dyadicScale D (k + 1) := by
  calc dist y_k y_k1 ≤ dist y_k x + dist x y_k1 := dist_triangle _ _ _
    _ ≤ dyadicScale D k + dyadicScale D (k + 1) := by
        apply add_le_add
        · rw [dist_comm]; exact hy_k_near
        · exact hy_k1_near

/-- Simplified telescoping bound using the dyadic relationship. -/
theorem telescoping_bound' {D : ℝ} (k : ℕ)
    {x y_k : A} (hy_k_near : dist x y_k ≤ dyadicScale D k)
    {y_k1 : A} (hy_k1_near : dist x y_k1 ≤ dyadicScale D (k + 1)) :
    dist y_k y_k1 ≤ 3 / 2 * dyadicScale D k :=
  calc dist y_k y_k1
    _ ≤ dyadicScale D k + dyadicScale D (k + 1) :=
        telescoping_bound k hy_k_near hy_k1_near
    _ = dyadicScale D k + dyadicScale D k / 2 := by rw [dyadicScale_succ]
    _ = 3 / 2 * dyadicScale D k := by ring

/-!
## Projection Maps for Chaining

For the Dudley chaining argument, we need projection maps that assign each point
to its nearest neighbor in a given net.
-/

/-- Choose a nearest point in a nonempty finset to a given point x.
    We use a simple choice-based definition: pick any element that minimizes distance. -/
def nearestInFinset (t : Finset A) (ht : t.Nonempty) (x : A) : A :=
  -- Just use the witness from the nonempty condition if we can't find argmin
  -- This is a simple definition that doesn't require complicated API
  Classical.choose (Finset.exists_mem_eq_inf' ht (fun y => dist x y))

/-- The nearest point in t is actually in t. -/
lemma nearestInFinset_mem (t : Finset A) (ht : t.Nonempty) (x : A) :
    nearestInFinset t ht x ∈ t := by
  unfold nearestInFinset
  exact (Classical.choose_spec (Finset.exists_mem_eq_inf' ht (fun y => dist x y))).1

/-- The distance to the nearest point is at most the distance to any point in t. -/
lemma dist_nearestInFinset_le (t : Finset A) (ht : t.Nonempty) (x : A) (y : A) (hy : y ∈ t) :
    dist x (nearestInFinset t ht x) ≤ dist x y := by
  unfold nearestInFinset
  have hspec := Classical.choose_spec (Finset.exists_mem_eq_inf' ht (fun y => dist x y))
  rw [← hspec.2]
  exact Finset.inf'_le _ hy

/-- If t is an ε-net for s, the nearest point in t to any x ∈ s is within distance ε. -/
lemma dist_nearestInFinset_of_isENet {t : Finset A} {eps : ℝ} {s : Set A}
    (hnet : IsENet t eps s) (ht : t.Nonempty)
    {x : A} (hx : x ∈ s) :
    dist x (nearestInFinset t ht x) ≤ eps := by
  obtain ⟨y, hy_mem, hy_dist⟩ := exists_near_in_net hnet hx
  calc dist x (nearestInFinset t ht x)
    _ ≤ dist x y := dist_nearestInFinset_le t ht x y hy_mem
    _ ≤ eps := hy_dist

/-- Projection to the k-th level net of a dyadic net hierarchy. -/
def projectToNet {s : Set A} {D : ℝ} (dn : DyadicNets s D) (k : ℕ)
    (ht : (dn.nets k).Nonempty) (x : A) : A :=
  nearestInFinset (dn.nets k) ht x

/-- The projection is in the net. -/
lemma projectToNet_mem {s : Set A} {D : ℝ} (dn : DyadicNets s D) (k : ℕ)
    (ht : (dn.nets k).Nonempty) (x : A) :
    projectToNet dn k ht x ∈ dn.nets k :=
  nearestInFinset_mem _ ht x

/-- If x is in the finset, the distance to the nearest point is 0. -/
lemma dist_nearestInFinset_eq_zero_of_mem (t : Finset A) (ht : t.Nonempty) (x : A) (hx : x ∈ t) :
    dist x (nearestInFinset t ht x) = 0 :=
  le_antisymm (by simpa only [dist_self] using dist_nearestInFinset_le t ht x x hx) dist_nonneg

/-- If x is in the k-th net, distance to projection is 0. -/
lemma dist_projectToNet_eq_zero_of_mem {s : Set A} {D : ℝ} (dn : DyadicNets s D) (k : ℕ)
    (ht : (dn.nets k).Nonempty) (x : A) (hx : x ∈ dn.nets k) :
    dist x (projectToNet dn k ht x) = 0 :=
  dist_nearestInFinset_eq_zero_of_mem _ ht x hx

/-- Distance to projection is bounded by the scale. -/
lemma dist_projectToNet_le {s : Set A} {D : ℝ} (dn : DyadicNets s D) (k : ℕ)
    (ht : (dn.nets k).Nonempty) {x : A} (hx : x ∈ s) :
    dist x (projectToNet dn k ht x) ≤ dyadicScale D k :=
  dist_nearestInFinset_of_isENet (dn.isNet k) ht hx

/-- Distance between successive projections is bounded by 3/2 times the coarser scale.
    This follows from triangle inequality + scale relationship. -/
lemma dist_successive_projections {s : Set A} {D : ℝ} (dn : DyadicNets s D) (k : ℕ)
    (htk : (dn.nets k).Nonempty) (htk1 : (dn.nets (k + 1)).Nonempty)
    {x : A} (hx : x ∈ s) :
    dist (projectToNet dn k htk x) (projectToNet dn (k + 1) htk1 x) ≤ 3 / 2 * dyadicScale D k :=
  calc dist (projectToNet dn k htk x) (projectToNet dn (k + 1) htk1 x)
    _ ≤ dist (projectToNet dn k htk x) x + dist x (projectToNet dn (k + 1) htk1 x) :=
        dist_triangle _ _ _
    _ = dist x (projectToNet dn k htk x) + dist x (projectToNet dn (k + 1) htk1 x) := by
        rw [dist_comm (projectToNet dn k htk x) x]
    _ ≤ dyadicScale D k + dyadicScale D (k + 1) :=
        add_le_add (dist_projectToNet_le dn k htk hx) (dist_projectToNet_le dn (k + 1) htk1 hx)
    _ = dyadicScale D k + dyadicScale D k / 2 := by rw [dyadicScale_succ]
    _ = 3 / 2 * dyadicScale D k := by ring

/-- For nonempty totally bounded sets, the nets at each level are nonempty. -/
lemma dyadicNets_nonempty {s : Set A} (hsne : s.Nonempty) {D : ℝ}
    (dn : DyadicNets s D) (k : ℕ) :
    (dn.nets k).Nonempty := by
  -- Since s is nonempty, any point x ∈ s must be covered by some point in the net
  obtain ⟨x, hx⟩ := hsne
  obtain ⟨y, hy, _⟩ := exists_near_in_net (dn.isNet k) hx
  exact ⟨y, hy⟩

/-!
## Transitive Projection for Improved Chaining (To improve Dudley's constant)

The standard chaining approach projects each point u directly to each net level k,
giving distance bounds via triangle inequality: dist(proj_k u, proj_{k+1} u) ≤ (3/2)ε_k.

Transitive projection improves this by projecting recursively from finer to coarser nets:
- transitiveProj K K u = u  (finest level)
- transitiveProj K k u = projectToNet_k(transitiveProj K (k+1) u)  for k < K

This gives a tighter distance bound: dist(transitiveProj K k u, transitiveProj K (k+1) u) ≤ ε_k
because we project directly from a point in s (the finer projection) to the coarser net.
-/

/-- Transitive projection: project recursively from finer to coarser nets.
    - transitiveProj K K u = u
    - transitiveProj K k u = projectToNet k (transitiveProj K (k+1) u) for k < K -/
def transitiveProj {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (u : A) : A :=
  if h : K ≤ k then u
  else projectToNet dn k (hnet_nonempty k) (transitiveProj dn hnet_nonempty K (k + 1) u)
termination_by K - k

/-- Transitive projection unfolds correctly when k ≥ K. -/
lemma transitiveProj_of_le {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (hk : K ≤ k) (u : A) :
    transitiveProj dn hnet_nonempty K k u = u := by
  unfold transitiveProj
  simp [hk]

/-- Transitive projection unfolds correctly when k < K. -/
lemma transitiveProj_of_lt {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (hk : k < K) (u : A) :
    transitiveProj dn hnet_nonempty K k u =
      projectToNet dn k (hnet_nonempty k) (transitiveProj dn hnet_nonempty K (k + 1) u) := by
  conv_lhs => unfold transitiveProj
  simp [not_le.mpr hk]

/-- Transitive projection at level K is the identity. -/
lemma transitiveProj_self {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K : ℕ) (u : A) :
    transitiveProj dn hnet_nonempty K K u = u :=
  transitiveProj_of_le dn hnet_nonempty K K (le_refl K) u

/-- Transitive projection lands in the appropriate net when k < K. -/
lemma transitiveProj_mem_nets {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (hk : k < K) (u : A) :
    transitiveProj dn hnet_nonempty K k u ∈ dn.nets k := by
  rw [transitiveProj_of_lt dn hnet_nonempty K k hk]
  exact projectToNet_mem dn k (hnet_nonempty k) _

/-- Transitive projection lands in s when u ∈ nets K. -/
lemma transitiveProj_mem_s {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (u : A) (hu : u ∈ dn.nets K) :
    transitiveProj dn hnet_nonempty K k u ∈ s := by
  by_cases hk : K ≤ k
  · rw [transitiveProj_of_le dn hnet_nonempty K k hk]
    exact dn.nets_subset K hu
  · push_neg at hk
    exact dn.nets_subset k (transitiveProj_mem_nets dn hnet_nonempty K k hk u)

/-- KEY LEMMA: Distance between consecutive transitive projections is ≤ ε_k (instead of (3/2)ε_k).

This is the crucial improvement over standard chaining. Because transitiveProj K (k+1) u ∈ s,
and nets_k is an ε_k-net of s, the distance from the projection point to its image in nets_k
is directly bounded by ε_k, without the triangle inequality factor. -/
lemma dist_transitiveProj_consecutive {s : Set A} {D : ℝ} (dn : DyadicNets s D)
    (hnet_nonempty : ∀ k, (dn.nets k).Nonempty)
    (K k : ℕ) (hk : k < K) (u : A) (hu : u ∈ dn.nets K) :
    dist (transitiveProj dn hnet_nonempty K k u)
         (transitiveProj dn hnet_nonempty K (k + 1) u) ≤ dyadicScale D k := by
  -- Let v = transitiveProj K (k+1) u. We have v ∈ s.
  set v := transitiveProj dn hnet_nonempty K (k + 1) u
  have hv_mem_s : v ∈ s := transitiveProj_mem_s dn hnet_nonempty K (k + 1) u hu
  -- transitiveProj K k u = projectToNet k v
  have heq : transitiveProj dn hnet_nonempty K k u =
      projectToNet dn k (hnet_nonempty k) v := by
    rw [transitiveProj_of_lt dn hnet_nonempty K k hk]
  rw [heq]
  -- Since nets_k is an ε_k-net of s and v ∈ s, we have dist(projectToNet k v, v) ≤ ε_k
  rw [dist_comm]
  exact dist_projectToNet_le dn k (hnet_nonempty k) hv_mem_s


end
