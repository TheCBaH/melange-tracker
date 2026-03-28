(** Load and save the tracker YAML database. *)

let default_path =
  let dir = Sys.getenv_opt "TRACKER_DIR" |> Option.value ~default:"." in
  Filename.concat dir "db.yaml"

let empty =
  Types.
    {
      upstream_remote = "upstream";
      upstream_branch = "master";
      last_scan_commit = None;
      queued = [];
      deferred = [];
      undecided = [];
      irrelevant = [];
      wont_pick = [];
      candidates = [];
    }

let load ?(path = default_path) () =
  if Sys.file_exists path then
    let contents = In_channel.with_open_text path In_channel.input_all in
    match Yamlt.decode_string Types.db_jsont contents with
    | Ok db -> db
    | Error msg -> failwith (Printf.sprintf "Failed to parse %s: %s" path msg)
  else empty

let save ?(path = default_path) db =
  let buf = Buffer.create 4096 in
  let w = Bytesrw.Bytes.Writer.of_buffer buf in
  match Yamlt.encode Types.db_jsont db ~eod:true w with
  | Ok () ->
    Out_channel.with_open_text path (fun oc ->
      output_string oc (Buffer.contents buf))
  | Error msg -> failwith (Printf.sprintf "Failed to encode database: %s" msg)

(** Unified view for display/search across all lists. *)
type status_view =
  | VQueued
  | VDeferred of string
  | VUndecided of string
  | VIrrelevant of string
  | VWont_pick of string
  | VCandidate of Types.candidate

let status_name = function
  | VQueued -> "queued"
  | VDeferred _ -> "deferred"
  | VUndecided _ -> "undecided"
  | VIrrelevant _ -> "irrelevant"
  | VWont_pick _ -> "wont_pick"
  | VCandidate { stage = Planned; _ } -> "planned"
  | VCandidate { stage = In_progress; _ } -> "in_progress"
  | VCandidate { stage = Pull_request _; _ } -> "pull_request"
  | VCandidate { stage = Merged _; _ } -> "merged"

let hash_matches prefix full =
  String.length prefix <= String.length full
  && String.sub full 0 (String.length prefix) = prefix

(** Find a commit across all lists by hash prefix. *)
let find hash (db : Types.db) : (string * status_view) option =
  let check_queued () =
    List.find_opt (hash_matches hash) db.queued
    |> Option.map (fun h -> (h, VQueued))
  in
  let check_reason lst make =
    List.find_opt (fun (r : Types.with_reason) -> hash_matches hash r.hash) lst
    |> Option.map (fun (r : Types.with_reason) -> (r.hash, make r.reason))
  in
  let check_candidates () =
    List.find_opt
      (fun (c : Types.candidate) -> hash_matches hash c.hash)
      db.candidates
    |> Option.map (fun (c : Types.candidate) -> (c.hash, VCandidate c))
  in
  match check_queued () with
  | Some _ as r -> r
  | None -> (
    match check_reason db.deferred (fun r -> VDeferred r) with
    | Some _ as r -> r
    | None -> (
      match check_reason db.undecided (fun r -> VUndecided r) with
      | Some _ as r -> r
      | None -> (
        match check_reason db.irrelevant (fun r -> VIrrelevant r) with
        | Some _ as r -> r
        | None -> (
          match check_reason db.wont_pick (fun r -> VWont_pick r) with
          | Some _ as r -> r
          | None -> check_candidates ()))))

(** Remove a commit from whichever list it's in. *)
let remove hash (db : Types.db) : Types.db =
  let not_match_hash h = not (hash_matches hash h) in
  let not_match_reason (r : Types.with_reason) = not (hash_matches hash r.hash) in
  let not_match_candidate (c : Types.candidate) = not (hash_matches hash c.hash) in
  {
    db with
    queued = List.filter not_match_hash db.queued;
    deferred = List.filter not_match_reason db.deferred;
    undecided = List.filter not_match_reason db.undecided;
    irrelevant = List.filter not_match_reason db.irrelevant;
    wont_pick = List.filter not_match_reason db.wont_pick;
    candidates = List.filter not_match_candidate db.candidates;
  }

(** Check if a hash exists in any list. *)
let mem hash (db : Types.db) = Option.is_some (find hash db)

(** Collect all entries as (hash, status_view) for iteration. *)
let all_entries (db : Types.db) : (string * status_view) list =
  let queued = List.map (fun h -> (h, VQueued)) db.queued in
  let deferred =
    List.map (fun (r : Types.with_reason) -> (r.hash, VDeferred r.reason)) db.deferred
  in
  let undecided =
    List.map (fun (r : Types.with_reason) -> (r.hash, VUndecided r.reason)) db.undecided
  in
  let irrelevant =
    List.map (fun (r : Types.with_reason) -> (r.hash, VIrrelevant r.reason)) db.irrelevant
  in
  let wont_pick =
    List.map (fun (r : Types.with_reason) -> (r.hash, VWont_pick r.reason)) db.wont_pick
  in
  let candidates =
    List.map (fun (c : Types.candidate) -> (c.hash, VCandidate c)) db.candidates
  in
  queued @ deferred @ undecided @ irrelevant @ wont_pick @ candidates

(** Count entries per status name. *)
let count_by_status (db : Types.db) =
  let tbl = Hashtbl.create 16 in
  let add name count =
    if count > 0 then Hashtbl.replace tbl name count
  in
  add "queued" (List.length db.queued);
  add "deferred" (List.length db.deferred);
  add "undecided" (List.length db.undecided);
  add "irrelevant" (List.length db.irrelevant);
  add "wont_pick" (List.length db.wont_pick);
  List.iter
    (fun (c : Types.candidate) ->
      let name =
        match c.stage with
        | Planned -> "planned"
        | In_progress -> "in_progress"
        | Pull_request _ -> "pull_request"
        | Merged _ -> "merged"
      in
      let n = try Hashtbl.find tbl name with Not_found -> 0 in
      Hashtbl.replace tbl name (n + 1))
    db.candidates;
  tbl

let total_count (db : Types.db) =
  List.length db.queued
  + List.length db.deferred
  + List.length db.undecided
  + List.length db.irrelevant
  + List.length db.wont_pick
  + List.length db.candidates
