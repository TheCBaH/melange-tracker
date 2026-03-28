(** Core types for the melange cherry-pick tracker.

    Only stores metadata not derivable from the git commit itself.
    Each status category has its own type and top-level DB field. *)

(** Integration stage for commits being ported to melange. *)
type candidate_stage =
  | Planned
  | In_progress
  | Pull_request of { pr_id : int } [@nowrap]
  | Merged of { melange_hash : string } [@nowrap]
[@@deriving jsont] [@@type_key "stage"]

(** A candidate for integration — rich per-commit data. *)
type candidate = {
  hash : string;
  stage : candidate_stage;
  depends_on : string list;
  notes : string;
}
[@@deriving jsont]

(** A commit with an associated reason or notes string. *)
type with_reason = {
  hash : string;
  reason : string;
}
[@@deriving jsont]

(** Top-level database — each status category is a separate field. *)
type db = {
  upstream_remote : string; [@absent "upstream"]
  upstream_branch : string; [@absent "master"]
  last_scan_commit : string option; [@option]
  queued : string list;
  deferred : with_reason list;
  undecided : with_reason list;
  irrelevant : with_reason list;
  wont_pick : with_reason list;
  candidates : candidate list;
}
[@@deriving jsont]
