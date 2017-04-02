Require Import Coq.Numbers.Natural.Peano.NPeano.
Require Import mathcomp.ssreflect.ssreflect.
From mathcomp Require Import ssrbool ssrnat.
Require Import Sets GenLow.
Require Import Recdef.
Require Import List.

Require Import ZArith ZArith.Znat Arith.

Import GenLow.

Set Bullet Behavior "Strict Subproofs".

(** Instance Hierarchy  

   GenSized 
      |
      |
     Gen   Shrink
       \    /
        \  /
      Arbitrary
*)

(** * Generator-related classes *)

Class GenSized (A : Type) :=
  { arbitrarySized : nat -> G A }.

Class Gen (A : Type) := 
  { arbitrary : G A }.

(** Shrink class *)
Class Shrink (A : Type) :=
  { shrink : A -> list A }.

(** Arbitrary Class *)
Class Arbitrary (A : Type) `{Gen A} `{Shrink A}.

(** * Sizes of types *)
  
Class Sized (A : Type) :=
  {
    size : A -> nat
  }.

Class CanonicalSized (A : Type) `{Sized A} :=
  {
    zeroSized : set A;
    succSized : set A -> set A;

    zeroSized_spec : zeroSized <--> [ set x : A | size x = 0 ];
    succSized_spec :
      forall n, succSized [ set x : A | size x <= n ] <--> [ set x : A | size x <= S n ]
 
  }.

(** * Correctness classes *)

(** Correctness of sized generators *)
Class SizedCorrect {A : Type} `{Sized A} (g : nat -> G A) :=
  {
    genSizeCorrect : forall s, semGen (g s) <--> [set x : A | size x <= s ]
  }.

(** Correctness of generators *)
Class Correct (A : Type) (g : G A)  :=
  {
    arbitraryCorrect : semGen g <--> [set : A]
  }.

(** * Monotonic generators *)

(** Monotonicity of size parametric generators *)
Class GenSizedMonotonic (A : Type) `{GenSized A}
      `{forall s, SizeMonotonic (arbitrarySized s)}.

(** Monotonicity of size parametric generators v2 *)
(* TODO use SizedMonotonic instead *)
Class GenSizedSizeMonotonic (A : Type) `{GenSized A} :=
  {
    sizeMonotonic :
      forall s s1 s2,
        s1 <= s2 ->
        semGenSize (arbitrarySized s1) s 
        \subset semGenSize (arbitrarySized s2) s
  }.

Class GenMonotonic (A : Type) `{Gen A} `{SizeMonotonic A arbitrary}.

(** * Correct generators *)

Class GenSizedCorrect (A : Type) `{GenSized A} `{SizedCorrect A arbitrarySized}.

Class GenCorrect (A : Type) `{Gen A} `{Correct A arbitrary}.
 
(* Monotonic and Correct generators *)
Class GenMonotonicCorrect (A : Type)
      `{Gen A} `{SizeMonotonic A arbitrary} `{Correct A arbitrary}.

(** Coercions *)

Global Instance GenOfGenSized {A} `{GenSized A} : Gen A :=
  {| arbitrary := sized arbitrarySized |}.

Global Instance ArbitraryOfGenShrink {A} `{Gen A} `{Shrink A} : Arbitrary A.

Generalizable Variables PSized PMon PSMon PCorr.

Instance GenMonotonicOfSized (A : Type)
         {H : GenSized A}
         `{@GenSizedMonotonic A H PMon}
         `{@GenSizedSizeMonotonic A H}
: SizeMonotonic arbitrary.
Proof.
  constructor. eapply sizedSizeMonotonic.
  now intros n; eauto with typeclass_instances.
  edestruct H1. constructor. eauto.
Qed.

Instance GenCorrectOfSized (A : Type)
         {H : GenSized A}
         `{@GenSizedMonotonic A H PMon}
         `{@GenSizedSizeMonotonic A H}
         `{@GenSizedCorrect A H PSized PCorr} : Correct A arbitrary.
Proof.
  constructor. unfold arbitrary, GenOfGenSized. 
  eapply set_eq_trans.
  - eapply semSized_alt; eauto with typeclass_instances.
    destruct H1. eauto.
  - setoid_rewrite genSizeCorrect.
    split. intros [n H3]. constructor; eauto.
    intros H4. eexists; split; eauto.
Qed.
