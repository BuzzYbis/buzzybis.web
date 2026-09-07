(* Short-circuiting list traversals in the [result] monad. *)

let rec iter f = function
  | [] -> Ok ()
  | x :: xs ->
    (match f x with
     | Ok () -> iter f xs
     | Error e -> Error e)
;;

let map f l =
  let rec go acc = function
    | [] -> Ok (List.rev acc)
    | x :: xs ->
      (match f x with
       | Ok y -> go (y :: acc) xs
       | Error e -> Error e)
  in
  go [] l
;;
