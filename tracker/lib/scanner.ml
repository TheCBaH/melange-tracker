(** Scan upstream commits and auto-classify them. *)

let bug_keywords =
  [ "fix"; "crash"; "bug"; "regression"; "incorrect"; "wrong"; "broken" ]

let irrelevant_patterns =
  [
    "bump";
    "version";
    "changelog";
    "ci:";
    "ci(";
    "chore:";
    "chore(";
    "release";
  ]

let shared_paths =
  [
    "jscomp/core/";
    "compiler/core/";
    "jscomp/syntax/";
    "compiler/syntax/";
    "jscomp/ext/";
    "compiler/ext/";
    "jscomp/ml/";
    "compiler/ml/";
  ]

let rescript_only_paths =
  [
    "rescript-vscode/";
    "rewatch/";
    "tools/";
    "runtime/";
    "cli/";
    "npm/";
    "scripts/";
  ]

let string_contains_ci haystack needle =
  let h = String.lowercase_ascii haystack in
  let n = String.lowercase_ascii needle in
  let nlen = String.length n in
  let hlen = String.length h in
  if nlen > hlen then false
  else
    let found = ref false in
    for i = 0 to hlen - nlen do
      if String.sub h i nlen = n then found := true
    done;
    !found

let has_shared_files files =
  List.exists
    (fun f -> List.exists (fun p -> string_contains_ci f p) shared_paths)
    files

let has_only_rescript_files files =
  files <> []
  && List.for_all
       (fun f ->
         List.exists (fun p -> string_contains_ci f p) rescript_only_paths
         || String.ends_with ~suffix:".res" f
         || String.ends_with ~suffix:".resi" f)
       files

let has_bug_keyword subject =
  List.exists (fun kw -> string_contains_ci subject kw) bug_keywords

let has_irrelevant_pattern subject =
  List.exists (fun p -> string_contains_ci subject p) irrelevant_patterns

type classification =
  | Auto_irrelevant
  | High_priority
  | Normal_candidate
  | Needs_review

let classify subject files =
  if has_irrelevant_pattern subject then Auto_irrelevant
  else if has_only_rescript_files files then Auto_irrelevant
  else if has_shared_files files && has_bug_keyword subject then High_priority
  else if has_shared_files files then Normal_candidate
  else Needs_review

let scan ~(db : Types.db) =
  let remote = db.upstream_remote in
  let branch = db.upstream_branch in
  let since =
    match db.last_scan with Some d -> d | None -> "2024-01-01"
  in
  let lines = Git.log_oneline ~since ~remote ~branch () in
  let new_entries = ref 0 in
  let db = ref db in
  List.iter
    (fun line ->
      match Git.parse_log_line line with
      | None -> ()
      | Some (hash, _subject) ->
        if Db.find_entry hash !db |> Option.is_none then (
          let entry = Types.{ hash; status = Queued } in
          db := Db.add_entry entry !db;
          incr new_entries))
    lines;
  let today =
    let t = Unix.gmtime (Unix.gettimeofday ()) in
    Printf.sprintf "%04d-%02d-%02d" (1900 + t.tm_year) (1 + t.tm_mon) t.tm_mday
  in
  let db = { !db with last_scan = Some today } in
  (db, !new_entries)
