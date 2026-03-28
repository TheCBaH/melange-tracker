(** Core types for the melange cherry-pick tracker.

    Only stores metadata not derivable from the git commit itself. *)

(** Integration stage for commits being ported to melange. *)
type candidate_stage =
  | Planned
  | In_progress
  | Pull_request of { pr_id : int } [@nowrap]
  | Merged of { melange_hash : string } [@nowrap]
[@@deriving jsont] [@@type_key "stage"]

(** Commit status — each variant carries only the data specific to that state. *)
type status =
  | Queued
  | Deferred of { reason : string } [@nowrap]
  | Undecided of { notes : string } [@nowrap]
  | Irrelevant of { reason : string } [@nowrap]
  | Wont_pick of { reason : string } [@nowrap]
  | Candidate of {
      stage : candidate_stage;
      depends_on : string list;
      notes : string;
    }
      [@nowrap]
[@@deriving jsont] [@@type_key "kind"]

(** A tracked commit — only stores data NOT in the git commit itself. *)
type entry = {
  hash : string;
  status : status;
}
[@@deriving jsont]

(** Top-level database. *)
type db = {
  upstream_remote : string; [@absent "upstream"]
  upstream_branch : string; [@absent "master"]
  last_scan : string option; [@option]
  entries : entry list;
}
[@@deriving jsont]
