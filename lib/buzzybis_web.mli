(** buzzybis.web entry points for executable binaries.

    This library exposes exclusively the top-level execution entry points for the
    fetch/sync engine and the static HTTP server. Internal modules ([Util], [Config],
    [Page_gen], [Error], and [Logger]) are encapsulated and hidden from external
    consumers. *)

(** Synchronization and repository fetch engine *)
module Sync : sig
  (** [main ()] starts the GitHub synchronization loop and Typst blog compiler. *)
  val main : unit -> unit
end

(** Static asset and cached PDF HTTP web server *)
module Serve : sig
  (** [main ()] starts the HTTP server on the configured port. *)
  val main : unit -> unit
end
