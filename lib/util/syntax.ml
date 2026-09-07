(* Monadic binding syntax operators for result *)

let ( let* ) = Result.bind
let ( let+ ) x f = Result.map f x
