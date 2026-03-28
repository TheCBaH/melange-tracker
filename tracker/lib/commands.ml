(** CLI command implementations. *)

let with_db f =
  let db = Db.load () in
  f db

let with_db_save f =
  let db = Db.load () in
  let db = f db in
  Db.save db

let short_hash h = String.sub h 0 (min 9 (String.length h))

(** scan — fetch upstream and add new commits as Queued *)
let scan _since =
  with_db_save (fun db ->
    let db, n = Scanner.scan ~db in
    Printf.printf "Added %d new commits to the queue.\n" n;
    (match db.last_scan_commit with
     | Some c ->
       Printf.printf "Scanned up to: %s\n"
         (String.sub c 0 (min 12 (String.length c)))
     | None -> ());
    db)

(** status — summary stats *)
let status () =
  with_db (fun db ->
    let tbl = Db.count_by_status db in
    Printf.printf "Total tracked: %d\n" (Db.total_count db);
    let order =
      [
        "queued";
        "deferred";
        "undecided";
        "irrelevant";
        "wont_pick";
        "planned";
        "in_progress";
        "pull_request";
        "merged";
      ]
    in
    List.iter
      (fun name ->
        let n = try Hashtbl.find tbl name with Not_found -> 0 in
        if n > 0 then Printf.printf "  %-14s %d\n" name n)
      order)

(** list — list entries with optional status filter *)
let list_entries filter =
  with_db (fun db ->
    let entries =
      match filter with
      | None -> Db.all_entries db
      | Some f ->
        List.filter (fun (_, sv) -> Db.status_name sv = f) (Db.all_entries db)
    in
    List.iter
      (fun (hash, sv) ->
        let info = Git.show_commit hash in
        let subject =
          match info with Some i -> i.subject | None -> "(unknown)"
        in
        Printf.printf "%-12s %-14s %s\n" (short_hash hash)
          (Db.status_name sv) subject)
      entries)

(** show — display full details for a commit *)
let show hash =
  with_db (fun db ->
    match Db.find hash db with
    | None -> Printf.eprintf "No entry found for %s\n" hash
    | Some (full_hash, sv) ->
      Printf.printf "Hash:   %s\n" full_hash;
      Printf.printf "Status: %s\n" (Db.status_name sv);
      (match sv with
       | VDeferred reason | VIrrelevant reason | VWont_pick reason ->
         Printf.printf "Reason: %s\n" reason
       | VUndecided notes -> Printf.printf "Notes:  %s\n" notes
       | VCandidate c ->
         (match c.stage with
          | Pull_request { pr_id } -> Printf.printf "PR:     #%d\n" pr_id
          | Merged { melange_hash } ->
            Printf.printf "Merged: %s\n" melange_hash
          | _ -> ());
         if c.depends_on <> [] then
           Printf.printf "Deps:   %s\n" (String.concat ", " c.depends_on);
         if c.notes <> "" then Printf.printf "Notes:  %s\n" c.notes
       | VQueued -> ());
      (match Git.show_commit full_hash with
       | None -> Printf.printf "\n(git info unavailable)\n"
       | Some info ->
         Printf.printf "\nSubject: %s\n" info.subject;
         Printf.printf "Author:  %s\n" info.author;
         Printf.printf "Date:    %s\n" info.date;
         Printf.printf "Files:\n";
         List.iter (fun f -> Printf.printf "  %s\n" f) info.files))

(** queue — shortcut for listing Queued entries *)
let queue () = list_entries (Some "queued")

(** triage — move a commit to a new status *)
let triage hash status_str reason =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (full_hash, _) ->
      let db = Db.remove full_hash db in
      let reason_str = Option.value ~default:"" reason in
      let db =
        match status_str with
        | "irrelevant" ->
          {
            db with
            irrelevant =
              db.irrelevant @ [ { hash = full_hash; reason = reason_str } ];
          }
        | "wont_pick" ->
          {
            db with
            wont_pick =
              db.wont_pick @ [ { hash = full_hash; reason = reason_str } ];
          }
        | "deferred" ->
          {
            db with
            deferred =
              db.deferred @ [ { hash = full_hash; reason = reason_str } ];
          }
        | "undecided" ->
          {
            db with
            undecided =
              db.undecided @ [ { hash = full_hash; reason = reason_str } ];
          }
        | "candidate" ->
          let subject = Git.subject full_hash in
          {
            db with
            candidates =
              db.candidates
              @ [
                  {
                    hash = full_hash;
                    subject;
                    stage = Planned;
                    depends_on = [];
                    notes = reason_str;
                  };
                ];
          }
        | s -> failwith (Printf.sprintf "Unknown status: %s" s)
      in
      Printf.printf "%s -> %s\n" (short_hash full_hash) status_str;
      db)

(** plan — set a commit as a planned candidate with notes *)
let plan hash notes =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (full_hash, sv) ->
      let db = Db.remove full_hash db in
      let candidate =
        match sv with
        | VCandidate c -> { c with stage = Planned; notes }
        | VQueued | VUndecided _ | VDeferred _ ->
          let subject = Git.subject full_hash in
          Types.
            { hash = full_hash; subject; stage = Planned; depends_on = []; notes }
        | _ ->
          failwith
            (Printf.sprintf "Cannot plan from status %s" (Db.status_name sv))
      in
      { db with candidates = db.candidates @ [ candidate ] })

(** advance — move candidate to next stage *)
let advance hash =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (_, VCandidate ({ stage = Planned; _ } as c)) ->
      let db = Db.remove c.hash db in
      let c = { c with stage = In_progress } in
      Printf.printf "%s -> in_progress\n" (short_hash c.hash);
      { db with candidates = db.candidates @ [ c ] }
    | Some (_, VCandidate { stage = In_progress; _ }) ->
      failwith "Use 'pr' or 'merge' to advance from in_progress"
    | Some (_, sv) ->
      failwith
        (Printf.sprintf "Cannot advance from status %s" (Db.status_name sv)))

(** depend — add dependency links *)
let depend hash dep_hashes =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (_, VCandidate c) ->
      let db = Db.remove c.hash db in
      let depends_on =
        List.fold_left
          (fun acc d -> if List.mem d acc then acc else acc @ [ d ])
          c.depends_on dep_hashes
      in
      let c = { c with depends_on } in
      { db with candidates = db.candidates @ [ c ] }
    | Some (_, sv) ->
      failwith
        (Printf.sprintf "Cannot add deps to status %s" (Db.status_name sv)))

(** pr — record a PR for a candidate *)
let pr hash pr_id =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (_, VCandidate c) ->
      let db = Db.remove c.hash db in
      let c = { c with stage = Pull_request { pr_id } } in
      Printf.printf "%s -> pull_request #%d\n" (short_hash c.hash) pr_id;
      { db with candidates = db.candidates @ [ c ] }
    | Some (_, sv) ->
      failwith
        (Printf.sprintf "Cannot set PR from status %s" (Db.status_name sv)))

(** merge — record merge with melange commit hash *)
let merge hash melange_hash =
  with_db_save (fun db ->
    match Db.find hash db with
    | None -> failwith (Printf.sprintf "No entry found for %s" hash)
    | Some (_, VCandidate c) ->
      let db = Db.remove c.hash db in
      let c = { c with stage = Merged { melange_hash } } in
      Printf.printf "%s -> merged (%s)\n" (short_hash c.hash) melange_hash;
      { db with candidates = db.candidates @ [ c ] }
    | Some (_, sv) ->
      failwith
        (Printf.sprintf "Cannot merge from status %s" (Db.status_name sv)))

(** check — verify merge-ready candidates can be cherry-picked and built *)
let check () =
  with_db (fun db ->
    (* Collect candidates that are in_progress or pull_request *)
    let merge_ready =
      List.filter
        (fun (c : Types.candidate) ->
          match c.stage with
          | Pull_request _ | In_progress -> true
          | _ -> false)
        db.candidates
    in
    if merge_ready = [] then (
      Printf.printf "No candidates ready to check.\n";
      exit 0);
    (* Build a map from hash to candidate for dependency resolution *)
    let all_candidates = db.candidates in
    (* Topological sort: apply dependencies before dependents *)
    let rec resolve_order ~visited ~ordered (c : Types.candidate) =
      if List.mem c.hash visited then (visited, ordered)
      else
        let visited = c.hash :: visited in
        let visited, ordered =
          List.fold_left
            (fun (visited, ordered) dep_hash ->
              match
                List.find_opt
                  (fun (cand : Types.candidate) ->
                    Db.hash_matches dep_hash cand.hash)
                  all_candidates
              with
              | Some dep -> resolve_order ~visited ~ordered dep
              | None -> (visited, ordered))
            (visited, ordered) c.depends_on
        in
        (visited, ordered @ [ c ])
    in
    let _, ordered =
      List.fold_left
        (fun (visited, ordered) c -> resolve_order ~visited ~ordered c)
        ([], []) merge_ready
    in
    Printf.printf "Checking %d candidates (with dependencies)...\n\n"
      (List.length ordered);
    let saved_head = Git.head () in
    let passed = ref 0 in
    let failed = ref 0 in
    let check_one (c : Types.candidate) =
      Printf.printf "  %s  %s\n" (short_hash c.hash) c.subject;
      match Git.try_cherry_pick c.hash with
      | Error msg ->
        Printf.printf "    FAIL: %s\n" msg;
        incr failed
      | Ok () ->
        incr passed;
        Printf.printf "    cherry-pick: OK\n"
    in
    List.iter check_one ordered;
    (* Try building after all cherry-picks applied *)
    if !failed = 0 then (
      Printf.printf "\nRunning dune build...\n";
      match Git.try_build () with
      | Ok () -> Printf.printf "Build: OK\n"
      | Error msg ->
        Printf.printf "Build: FAIL — %s\n" msg;
        incr failed);
    (* Reset to original HEAD *)
    Git.reset_hard saved_head;
    Printf.printf "\n---\n";
    Printf.printf "Checked: %d candidates, %d passed, %d failed\n"
      (List.length ordered) !passed !failed;
    if !failed > 0 then (
      Printf.eprintf "\nCheck FAILED.\n";
      exit 1)
    else Printf.printf "\nCheck passed.\n")

(** report — show actionable candidates grouped by stage *)
let report () =
  with_db (fun db ->
    let groups =
      [ ("PLANNED", fun (c : Types.candidate) -> c.stage = Planned);
        ("IN_PROGRESS", fun c -> c.stage = In_progress);
        ("PULL_REQUEST", fun c ->
           match c.stage with Pull_request _ -> true | _ -> false);
        ("MERGED", fun c ->
           match c.stage with Merged _ -> true | _ -> false);
      ]
    in
    List.iter
      (fun (label, pred) ->
        let entries = List.filter pred db.candidates in
        if entries <> [] then (
          Printf.printf "\n=== %s ===\n" label;
          List.iter
            (fun (c : Types.candidate) ->
              let info = Git.show_commit c.hash in
              let subject =
                match info with Some i -> i.subject | None -> "(unknown)"
              in
              Printf.printf "  %s  %s\n" (short_hash c.hash) subject;
              (match c.stage with
               | Pull_request { pr_id } ->
                 Printf.printf "           PR #%d\n" pr_id
               | Merged { melange_hash } ->
                 Printf.printf "           merged as %s\n" melange_hash
               | _ -> ());
              if c.depends_on <> [] then
                Printf.printf "           depends on: %s\n"
                  (String.concat ", " c.depends_on);
              if c.notes <> "" then
                Printf.printf "           %s\n" c.notes)
            entries))
      groups;
    if db.queued <> [] then
      Printf.printf "\n(%d commits in triage queue)\n" (List.length db.queued))

(** verify — check all merge-ready candidates, resolving dependencies *)
let verify () =
  with_db (fun db ->
    let merge_ready =
      List.filter
        (fun (c : Types.candidate) ->
          match c.stage with
          | Pull_request _ | In_progress -> true
          | _ -> false)
        db.candidates
    in
    if merge_ready = [] then (
      Printf.printf "No candidates ready to merge.\n";
      exit 0);
    let errors = ref 0 in
    let warnings = ref 0 in
    let rec check_deps ~visited hash =
      if List.mem hash visited then (
        Printf.eprintf "  ERROR: circular dependency detected at %s\n" hash;
        incr errors;
        false)
      else
        match Db.find hash db with
        | None ->
          Printf.eprintf "  ERROR: dependency %s not found in database\n" hash;
          incr errors;
          false
        | Some (_, VCandidate dep) -> (
          match dep.stage with
          | Merged _ ->
            List.for_all
              (fun d -> check_deps ~visited:(hash :: visited) d)
              dep.depends_on
          | Pull_request _ ->
            Printf.eprintf
              "  WARNING: dependency %s is still a PR (not yet merged)\n"
              (short_hash dep.hash);
            incr warnings;
            List.for_all
              (fun d -> check_deps ~visited:(hash :: visited) d)
              dep.depends_on
          | In_progress | Planned ->
            Printf.eprintf
              "  ERROR: dependency %s is not ready (status: %s)\n"
              (short_hash dep.hash)
              (Db.status_name (VCandidate dep));
            incr errors;
            false)
        | Some (_, sv) ->
          Printf.eprintf
            "  ERROR: dependency %s has non-candidate status: %s\n"
            (short_hash hash) (Db.status_name sv);
          incr errors;
          false
    in
    Printf.printf "Verifying %d merge-ready candidates...\n\n"
      (List.length merge_ready);
    List.iter
      (fun (c : Types.candidate) ->
        let info = Git.show_commit c.hash in
        let subject =
          match info with Some i -> i.subject | None -> "(unknown)"
        in
        Printf.printf "  %s  %s\n" (short_hash c.hash) subject;
        (match c.stage with
         | Pull_request { pr_id } ->
           Printf.printf "    stage: pull_request #%d\n" pr_id
         | In_progress -> Printf.printf "    stage: in_progress\n"
         | _ -> ());
        if c.depends_on = [] then Printf.printf "    deps: none\n"
        else (
          Printf.printf "    deps: %s\n" (String.concat ", " c.depends_on);
          let _ =
            List.for_all
              (fun d -> check_deps ~visited:[ c.hash ] d)
              c.depends_on
          in
          ());
        Printf.printf "\n")
      merge_ready;
    Printf.printf "---\n";
    Printf.printf "Checked: %d candidates, %d errors, %d warnings\n"
      (List.length merge_ready) !errors !warnings;
    if !errors > 0 then (
      Printf.eprintf "\nVerification FAILED.\n";
      exit 1)
    else Printf.printf "\nVerification passed.\n")
