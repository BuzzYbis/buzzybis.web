(** Short-circuiting list traversals in the [result] monad. *)

(** [iter f l] applies [f] to each element in order, stopping at the first error. *)
val iter : ('a -> (unit, 'e) result) -> 'a list -> (unit, 'e) result

(** [map f l] maps [f] over [l] in order, stopping at the first error. *)
val map : ('a -> ('b, 'e) result) -> 'a list -> ('b list, 'e) result
