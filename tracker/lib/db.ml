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
      entries = [];
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
  | Ok () -> Out_channel.with_open_text path (fun oc ->
      output_string oc (Buffer.contents buf))
  | Error msg -> failwith (Printf.sprintf "Failed to encode database: %s" msg)

let find_entry hash (db : Types.db) =
  List.find_opt (fun (e : Types.entry) ->
    String.length hash <= String.length e.hash
    && String.sub e.hash 0 (String.length hash) = hash) db.entries

let update_entry hash f (db : Types.db) =
  let found = ref false in
  let entries =
    List.map
      (fun (e : Types.entry) ->
        if
          String.length hash <= String.length e.hash
          && String.sub e.hash 0 (String.length hash) = hash
        then (
          found := true;
          f e)
        else e)
      db.entries
  in
  if not !found then
    failwith (Printf.sprintf "No entry found for hash prefix %s" hash);
  { db with entries }

let add_entry entry (db : Types.db) =
  if
    List.exists
      (fun (e : Types.entry) -> e.hash = entry.Types.hash)
      db.entries
  then db
  else { db with entries = db.entries @ [ entry ] }

let status_name = function
  | Types.Queued -> "queued"
  | Deferred _ -> "deferred"
  | Undecided _ -> "undecided"
  | Irrelevant _ -> "irrelevant"
  | Wont_pick _ -> "wont_pick"
  | Candidate { stage = Planned; _ } -> "planned"
  | Candidate { stage = In_progress; _ } -> "in_progress"
  | Candidate { stage = Pull_request _; _ } -> "pull_request"
  | Candidate { stage = Merged _; _ } -> "merged"

let count_by_status (db : Types.db) =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (e : Types.entry) ->
      let name = status_name e.status in
      let n = try Hashtbl.find tbl name with Not_found -> 0 in
      Hashtbl.replace tbl name (n + 1))
    db.entries;
  tbl
