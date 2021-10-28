From Coq Require Import ZArith NArith Int63 List Lia.

Require Import mathcomp.ssreflect.ssreflect.
From mathcomp Require Import ssrfun ssrbool ssrnat eqtype.

Set Primitive Projections.

Import ListNotations.

(** A splittable source of randomness *)
(** Implementation notes

    Represented as an infinite tree of [int], to be generated from some
    PRNG algorithm and a seed.

    One should only call at most one of [split] or [bits] on a given [random],
    because they are correlated in practice. Enforcing that requirement seems
    challenging. We could change the implementation to avoid the correlation (TODO).

    The fields take a [unit] argument to delay the evaluation of both fields,
    since only at most one is necessary. *)
CoInductive random :=
  { split : unit -> random * random
  ; bits : unit -> int
  }.

(**)

Definition dummy_random : random.
Proof.
  exact (cofix dummy := {| split := fun _ => (dummy, dummy) ; bits := fun _ => 0%int63 |}).
Qed.

Lemma inhabited_random : inhabited random.
Proof. constructor; apply dummy_random. Qed.

Definition unsplit s1 s2 : random :=
  {| split := fun _ => (s1, s2)
  ;  bits := fun _ => 0%int63
  |}.

Definition unbits x : random :=
  {| split := fun _ => (dummy_random, dummy_random)
  ;  bits := fun _ => x
  |}.

(** [random_int s bound] chooses a random [int] (63-bit) in [[0 .. bound-1]],
    i.e., [bound] is the number of possible values.

    This is not a uniform distribution in general, but should be close enough
    for practical purposes.

    Assumes [0 < bound].
*)
(** Implementation notes

    We simply take the remainder of a big random number uniformly in [[0 .. max_int]]
    modulo [bound], which does not yield a uniform distribution unless [bound]
    divides [max_int+1], but it is arguably "close enough".

    The least probable elements have probabilty [(max_int `div` bound) / max_int] where
    [div] is integer division. Note that when [bound] is much smaller than [max_int],
    this is close to the ideal [1/bound].

    There are [max_int `mod` bound] elements whose probability is
    [((max_int `div` bound) + 1) / max_int] instead. When [bound > max_int/2]
    those elements are twice as likely as others, but they have a very
    small probability [2 / max_int].
  *)
Definition random_int (s : random) (bound : int) : int :=
  let b := bits s tt in
  Int63.mod b bound.

(* [0 < bound < 2^63] *)
Definition random_Z_small (s : random) (bound : Z) : Z :=
  Int63.to_Z (random_int s (Int63.of_Z bound)).

Definition random_N_small (s : random) (bound : N) : N :=
  Z.to_N (random_Z_small s (Z.of_N bound)).

Definition random_bool (s : random) : bool :=
  Int63.is_zero (bits s tt).

Lemma random_bool_complete : forall b, exists s, random_bool s = b.
Proof.
  intros []; [ exists (unbits 0%int63) | exists (unbits 1%int63)]; reflexivity.
Qed.

(**)

(* Type class machinery for generating things in intervals *)

Class OrdType (A: Type) :=
  {
    leq     : A -> A -> bool;
    refl    : reflexive leq;
    trans   : transitive leq;
    antisym : antisymmetric leq
  }.

Program Instance OrdBool : OrdType bool :=
  {
    leq b1 b2 := implb b1 b2
  }.
Next Obligation.
  by case.
Qed.
Next Obligation.
  by do 3! case.
Qed.
Next Obligation.
  by do 2! case.
Qed.

Program Instance OrdNat : OrdType nat :=
  {
    leq := ssrnat.leq;
    refl := leqnn;
    trans := leq_trans;
    antisym := anti_leq
  }.

Program Instance OrdZ : OrdType Z :=
  {
    leq := Z.leb;
    refl := Z.leb_refl
  }.
Next Obligation.
move=> x y z le_yx le_xz.
exact: (Zle_bool_trans y x z).
Qed.
Next Obligation.
move=> x y /andP[].
exact: Zle_bool_antisym.
Qed.

Program Instance OrdN : OrdType N :=
  {
    leq := N.leb;
    refl := N.leb_refl
  }.
Next Obligation.
  move=> x y z le_yx le_xz.
  unfold is_true in *.
  apply N.leb_le in le_yx.
  apply N.leb_le in le_xz.
  apply N.leb_le.
  eapply N.le_trans; eauto.
Qed.
Next Obligation.
  move=> x y /andP[].
  unfold is_true.
  repeat rewrite N.leb_le.
  intros.
  apply N.le_antisymm; auto.
Qed.

Class ChoosableFromInterval (A : Type)  :=
  {
    super :> OrdType A;
    randomR : A * A -> random -> A;
    randomRCorrect :
      forall (a1 a2 : A), leq a1 a2 -> forall a,
       (leq a1 a && leq a a2 <->
       exists seed, randomR (a1, a2) seed = a)
  }.

Definition int_of_nat (n : nat) : int := Int63.of_Z (Z.of_nat n).
Definition nat_of_int (n : int) : nat := Z.to_nat (Int63.to_Z n).

Section RandomR.

Context {A : Type} `{OrdType A}
    {add : A -> A -> A}
    {sub : A -> A -> A}
    {mul : A -> A -> A}
    {div : A -> A -> A}
    {modulo : A -> A -> A}
    {shiftl : A -> A -> A}
    {shiftr : A -> A -> A}
    {log2 : A -> A}
    {of_int : int -> A}
    {to_int : A -> int}
    {iter : A -> forall (X : Type), (X -> X) -> X -> X}.

#[local] Declare Scope a_scope.
#[local] Delimit Scope a_scope with a.
#[local] Open Scope a_scope.

#[local] Infix "+" := add : a_scope.
#[local] Infix "-" := sub : a_scope.
#[local] Infix "*" := mul : a_scope.
#[local] Infix "/" := div : a_scope.
#[local] Infix "<=" := leq : a_scope.

Let seq {X} (_ : X) (x : Prop) := x.

Class RandomRAssum : Prop :=
  { ssss : seq H (seq sub (seq add (seq mul (seq modulo (seq shiftr (seq log2 (seq div (seq of_int (seq to_int (seq iter (seq shiftl False)))))))))))
  ; leq_sub : forall x y z, x <= y -> y <= z -> y - x <= z - x
  ; sub_diag : forall x, x - x = of_int 0
  ; add_sub : forall x y, x <= y -> x + (y - x) = y
  ; sub_add : forall x y, (x + y) - x = y
  ; add_mon : forall x y z, y <= z -> x + y <= x + z
  ; add_0_r : forall x, x + of_int 0 = x
  ; iter_ind : forall {T} (P : A -> T -> Prop) (f : T -> T) (t0 : T),
      (forall y t, P y t -> P (add (of_int 1) y) (f t)) ->
      P (of_int 0) t0 ->
      forall x, P x (iter x T f t0)
  }.

Context {RRA : RandomRAssum}.

Definition leq_sub_0 : forall x y, leq x y -> leq (of_int 0) (sub y x).
Proof.
  intros x y; rewrite <- (sub_diag x).
  apply leq_sub. apply refl.
Qed.

Definition manybits (l63 : A) : random -> A :=
  iter l63 _
    (fun prefix s =>
      let '(sp, s) := split s tt in
      shiftl (prefix sp) (of_int 63) + of_int (bits s tt))
    (fun s => of_int (bits s tt)).

Definition randomR0 (bound : A) (s : random) : A :=
  let l2 := log2 bound in
  let l63 := l2 / of_int 63 in
  let bs := manybits l63 s in
  modulo bs bound.

Definition randomR_ (bounds : A * A) (s : random) : A :=
  let '(minb, maxb) := bounds in
  let b := maxb - minb in
  minb + randomR0 (of_int 1 + (maxb - minb)) s.

Lemma manybitsCorrect (l63 : A)
  : (of_int 0 <= l63) ->
    forall r : A,
      (of_int 0 <= r /\ log2 r <= of_int 62 + of_int 63 * l63) <-> exists s, manybits l63 s = r.
Proof.
  intros Hl63. unfold manybits. eapply iter_ind; intros *.
  - intros IH r; specialize (IH (shiftr r (of_int 63))). destruct IH as [IH1 IH2].
    split.
    + intros [Hr0 Hr1].
      eassert (HH : _); [ | specialize (IH1 HH) ].
      { admit. }
      destruct IH1 as [s Hs].

Abort.

Lemma randomR0Correct (bound : A)
  : of_int 0 <= bound - of_int 1 ->
    forall r,
      ((of_int 0 <= r) && (r <= bound - of_int 1)) <-> exists s, randomR0 bound s = r.
Proof.
  intros Hbound; split.
  { move => /andP [Hmin Hmax].
Admitted.

Lemma randomRCorrect_ (minb maxb : A)
  : leq minb maxb ->
    forall r,
      ((minb <= r) && (r <= maxb)) <->
      exists seed, randomR_ (minb, maxb) seed = r.
Proof.
  intros Hb r.
  assert (HR0 := randomR0Correct (of_int 1 + (maxb - minb))).
  rewrite sub_add in HR0. specialize (HR0 (leq_sub_0 _ _ Hb)).
  split.
  { destruct (HR0 (r - minb)) as [HR1 _].
    move => /andP [Hmin Hmax].
    destruct HR1 as [s Hs].
    { apply (introT andP); split.
      { apply leq_sub_0, Hmin. }
      { apply leq_sub; assumption. } }
    exists s; cbn; rewrite Hs add_sub; auto. }
  { move => [s Hs]. cbn in Hs.
    destruct (HR0 (randomR0 (of_int 1 + (maxb - minb)) s)) as [_ HR2].
    specialize (HR2 (ex_intro _ s Logic.eq_refl)).
    apply (elimT andP) in HR2. destruct HR2 as [H1 H2].
    apply (introT andP); split.
    { apply (add_mon minb) in H1. rewrite add_0_r Hs in H1. exact H1. }
    { apply (add_mon minb) in H2. rewrite Hs add_sub in H2; [ exact H2 | exact Hb ]. } }
Qed.

End RandomR.

(** [randomR_nat (minb, maxb)] generates a rendom [nat] in the closed
    interval [[minb, maxb]].

    Assumes the bounds fit in an [int]. Otherwise, you're gonna
    have a bad time anyway.

    Assumes [0 <= minb < maxb <= max_int] and [maxb - minb < max_int]. *)
#[local] Instance RandomRAssum_nat : RandomRAssum (A := nat)
  (add := Nat.add) (sub := Nat.sub) (mul := Nat.mul) (div := Nat.div) (modulo := Nat.modulo)
  (log2 := Nat.log2) (shiftl := Nat.shiftl) (shiftr := Nat.shiftr)
  (of_int := nat_of_int) (to_int := int_of_nat)
  (iter := Nat.iter).
Proof.
  constructor; cbn [leq OrdNat]; intros.
  - admit.
  - apply (introT leP). apply (elimT leP) in H. apply (elimT leP) in H0. lia.
  - rewrite Nat.sub_diag. reflexivity.
  - apply (elimT leP) in H. apply le_plus_minus_r, H.
  - lia.
  - apply (introT leP); apply (elimT leP) in H; lia.
  - cbn. lia.
Admitted.

#[local] Instance RandomRAssum_Z : RandomRAssum (A := Z)
  (add := Z.add) (sub := Z.sub) (mul := Z.mul) (div := Z.div) (modulo := Z.modulo)
  (log2 := Z.log2) (shiftl := Z.shiftl) (shiftr := Z.shiftr)
  (of_int := Int63.to_Z) (to_int := Int63.of_Z)
  (iter := Z.iter).
Proof.
Admitted.

#[local] Instance RandomRAssum_N : RandomRAssum (A := N)
  (add := N.add) (sub := N.sub) (mul := N.mul) (div := N.div) (modulo := N.modulo)
  (log2 := N.log2) (shiftl := N.shiftl) (shiftr := N.shiftr)
  (of_int := fun i => Z.to_N (Int63.to_Z i)) (to_int := fun n => Int63.of_Z (Z.of_N n))
  (iter := N.iter).
Proof.
Admitted.

Instance ChooseNat : ChoosableFromInterval nat :=
  { randomR := _;
    randomRCorrect := randomRCorrect_ (A := nat)
  }.

Instance ChooseZ : ChoosableFromInterval Z :=
  { randomR := _;
    randomRCorrect := randomRCorrect_ (A := Z)
  }.

Instance ChooseN : ChoosableFromInterval N :=
  { randomR := _;
    randomRCorrect := randomRCorrect_ (A := N)
  }.

Inductive SplitDirection := Left | Right.

Definition SplitPath := list SplitDirection.

Fixpoint varySeed (p : SplitPath) (s : random) : random :=
  match p with
  | [] => s
  | Left  :: p' => varySeed p' (fst (split s tt))
  | Right :: p' => varySeed p' (snd (split s tt))
  end.
