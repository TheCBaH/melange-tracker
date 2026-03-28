(** CLI command implementations. *)

let with_db f =
  let db = Db.load () in
  f db

let with_db_save f =
  let db = Db.load () in
  let db = f db in
  Db.save db

(** scan — fetch upstream and add new commits as Queued *)
let scan _since =
  with_db_save (fun db ->
    let db, n = Scanner.scan ~db in
    Printf.printf "Added %d new commits to the queue.\n" n;
    if Option.is_some db.last_scan then
      Printf.printf "Last scan: %s\n" (Option.get db.last_scan);
    db)

(** status — summary stats *)
let status () =
  with_db (fun db ->
    let tbl = Db.count_by_status db in
    let total = List.length db.entries in
    Printf.printf "Total tracked: %d\n" total;
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
      | None -> db.entries
      | Some f ->
        List.filter
          (fun (e : Types.entry) -> Db.status_name e.status = f)
          db.entries
    in
    List.iter
      (fun (e : Types.entry) ->
        let info = Git.show_commit e.hash in
        let subject =
          match info with Some i -> i.subject | None -> "(unknown)"
        in
        Printf.printf "%-12s %-14s %s\n" (String.sub e.hash 0 (min 9 (String.length e.hash)))
          (Db.status_name e.status)
          subject)
      entries)

(** show — display full details for a commit *)
let show hash =
  with_db (fun db ->
    match Db.find_entry hash db with
    | None -> Printf.eprintf "No entry found for %s\n" hash
    | Some entry ->
      Printf.printf "Hash:   %s\n" entry.hash;
      Printf.printf "Status: %s\n" (Db.status_name entry.status);
      (match entry.status with
       | Deferred { reason } | Irrelevant { reason } | Wont_pick { reason } ->
         Printf.printf "Reason: %s\n" reason
       | Undecided { notes } ->
         Printf.printf "Notes:  %s\n" notes
       | Candidate { stage; depends_on; notes } ->
         (match stage with
          | Pull_request { pr_id } ->
            Printf.printf "PR:     #%d\n" pr_id
          | Merged { melange_hash } ->
            Printf.printf "Merged: %s\n" melange_hash
          | _ -> ());
         if depends_on <> [] then
           Printf.printf "Deps:   %s\n" (String.concat ", " depends_on);
         if notes <> "" then Printf.printf "Notes:  %s\n" notes
       | Queued -> ());
      (match Git.show_commit entry.hash with
       | None -> Printf.printf "\n(git info unavailable)\n"
       | Some info ->
         Printf.printf "\nSubject: %s\n" info.subject;
         Printf.printf "Author:  %s\n" info.author;
         Printf.printf "Date:    %s\n" info.date;
         Printf.printf "Files:\n";
         List.iter (fun f -> Printf.printf "  %s\n" f) info.files))

(** queue — shortcut for listing Queued entries *)
let queue () = list_entries (Some "queued")

(** triage — set the status of a commit *)
let triage hash status_str reason =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match status_str with
          | "irrelevant" ->
            let reason = Option.value ~default:"" reason in
            Types.Irrelevant { reason }
          | "wont_pick" ->
            let reason = Option.value ~default:"" reason in
            Types.Wont_pick { reason }
          | "deferred" ->
            let reason = Option.value ~default:"" reason in
            Types.Deferred { reason }
          | "undecided" ->
            let notes = Option.value ~default:"" reason in
            Types.Undecided { notes }
          | "candidate" ->
            let notes = Option.value ~default:"" reason in
            Types.Candidate { stage = Planned; depends_on = []; notes }
          | s -> failwith (Printf.sprintf "Unknown status: %s" s)
        in
        Printf.printf "%s -> %s\n" (String.sub e.hash 0 9) (Db.status_name status);
        { e with status })
      db)

(** plan — set a candidate to Planned with notes *)
let plan hash notes =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match e.status with
          | Candidate c -> Types.Candidate { c with stage = Planned; notes }
          | Queued | Undecided _ | Deferred _ ->
            Types.Candidate { stage = Planned; depends_on = []; notes }
          | s ->
            failwith
              (Printf.sprintf "Cannot plan from status %s" (Db.status_name s))
        in
        { e with status })
      db)

(** advance — move candidate to next stage *)
let advance hash =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match e.status with
          | Candidate ({ stage = Planned; _ } as c) ->
            Types.Candidate { c with stage = In_progress }
          | Candidate ({ stage = In_progress; _ } as _c) ->
            failwith "Use 'pr' or 'merge' to advance from in_progress"
          | s ->
            failwith
              (Printf.sprintf "Cannot advance from status %s"
                 (Db.status_name s))
        in
        Printf.printf "%s -> %s\n"
          (String.sub e.hash 0 9)
          (Db.status_name status);
        { e with status })
      db)

(** depend — add dependency links *)
let depend hash dep_hashes =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match e.status with
          | Candidate c ->
            let depends_on =
              List.fold_left
                (fun acc d -> if List.mem d acc then acc else acc @ [ d ])
                c.depends_on dep_hashes
            in
            Types.Candidate { c with depends_on }
          | s ->
            failwith
              (Printf.sprintf "Cannot add deps to status %s"
                 (Db.status_name s))
        in
        { e with status })
      db)

(** pr — record a PR for a candidate *)
let pr hash pr_id =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match e.status with
          | Candidate c ->
            Types.Candidate { c with stage = Pull_request { pr_id } }
          | s ->
            failwith
              (Printf.sprintf "Cannot set PR from status %s"
                 (Db.status_name s))
        in
        Printf.printf "%s -> pull_request #%d\n" (String.sub e.hash 0 9) pr_id;
        { e with status })
      db)

(** merge — record merge with melange commit hash *)
let merge hash melange_hash =
  with_db_save (fun db ->
    Db.update_entry hash
      (fun (e : Types.entry) ->
        let status =
          match e.status with
          | Candidate c ->
            Types.Candidate { c with stage = Merged { melange_hash } }
          | s ->
            failwith
              (Printf.sprintf "Cannot merge from status %s"
                 (Db.status_name s))
        in
        Printf.printf "%s -> merged (%s)\n" (String.sub e.hash 0 9) melange_hash;
        { e with status })
      db)

(** report — show actionable candidates grouped by stage *)
let report () =
  with_db (fun db ->
    let candidates =
      List.filter
        (fun (e : Types.entry) ->
          match e.status with Types.Candidate _ -> true | _ -> false)
        db.entries
    in
    let groups =
      [ "planned"; "in_progress"; "pull_request"; "merged" ]
    in
    List.iter
      (fun group ->
        let entries =
          List.filter
            (fun (e : Types.entry) -> Db.status_name e.status = group)
            candidates
        in
        if entries <> [] then (
          Printf.printf "\n=== %s ===\n" (String.uppercase_ascii group);
          List.iter
            (fun (e : Types.entry) ->
              let info = Git.show_commit e.hash in
              let subject =
                match info with Some i -> i.subject | None -> "(unknown)"
              in
              Printf.printf "  %s  %s\n"
                (String.sub e.hash 0 (min 9 (String.length e.hash)))
                subject;
              (match e.status with
               | Candidate { depends_on; notes; stage } ->
                 (match stage with
                  | Pull_request { pr_id } ->
                    Printf.printf "           PR #%d\n" pr_id
                  | Merged { melange_hash } ->
                    Printf.printf "           merged as %s\n" melange_hash
                  | _ -> ());
                 if depends_on <> [] then
                   Printf.printf "           depends on: %s\n"
                     (String.concat ", " depends_on);
                 if notes <> "" then
                   Printf.printf "           %s\n" notes
               | _ -> ()))
            entries))
      groups;
    let queued =
      List.length
        (List.filter
           (fun (e : Types.entry) -> e.status = Queued)
           db.entries)
    in
    if queued > 0 then
      Printf.printf "\n(%d commits in triage queue)\n" queued)

(** verify — check all merge-ready candidates, resolving dependencies *)
let verify () =
  with_db (fun db ->
    let entry_by_hash h =
      List.find_opt
        (fun (e : Types.entry) ->
          String.length h <= String.length e.hash
          && String.sub e.hash 0 (String.length h) = h)
        db.entries
    in
    (* Collect all candidates that are in PR or in_progress stage *)
    let merge_ready =
      List.filter
        (fun (e : Types.entry) ->
          match e.status with
          | Candidate { stage = Pull_request _ | In_progress; _ } -> true
          | _ -> false)
        db.entries
    in
    if merge_ready = [] then (
      Printf.printf "No candidates ready to merge.\n";
      exit 0);
    let errors = ref 0 in
    let warnings = ref 0 in
    (* Topological check: verify dependency ordering *)
    let rec check_deps ~visited hash =
      if List.mem hash visited then (
        Printf.eprintf "  ERROR: circular dependency detected at %s\n" hash;
        incr errors;
        false)
      else
        match entry_by_hash hash with
        | None ->
          Printf.eprintf "  ERROR: dependency %s not found in database\n" hash;
          incr errors;
          false
        | Some dep -> (
          match dep.status with
          | Candidate { stage = Merged _; depends_on; _ } ->
            (* Merged dep is OK, but check its own deps recursively *)
            List.for_all
              (fun d -> check_deps ~visited:(hash :: visited) d)
              depends_on
          | Candidate { stage = Pull_request _; depends_on; _ } ->
            Printf.eprintf "  WARNING: dependency %s is still a PR (not yet merged)\n"
              (String.sub dep.hash 0 (min 9 (String.length dep.hash)));
            incr warnings;
            List.for_all
              (fun d -> check_deps ~visited:(hash :: visited) d)
              depends_on
          | Candidate { stage = In_progress | Planned; _ } ->
            Printf.eprintf "  ERROR: dependency %s is not ready (status: %s)\n"
              (String.sub dep.hash 0 (min 9 (String.length dep.hash)))
              (Db.status_name dep.status);
            incr errors;
            false
          | status ->
            Printf.eprintf "  ERROR: dependency %s has non-candidate status: %s\n"
              (String.sub dep.hash 0 (min 9 (String.length dep.hash)))
              (Db.status_name status);
            incr errors;
            false)
    in
    Printf.printf "Verifying %d merge-ready candidates...\n\n"
      (List.length merge_ready);
    List.iter
      (fun (e : Types.entry) ->
        let short = String.sub e.hash 0 (min 9 (String.length e.hash)) in
        let info = Git.show_commit e.hash in
        let subject =
          match info with Some i -> i.subject | None -> "(unknown)"
        in
        Printf.printf "  %s  %s\n" short subject;
        (match e.status with
         | Candidate { depends_on; stage; _ } ->
           (match stage with
            | Pull_request { pr_id } ->
              Printf.printf "    stage: pull_request #%d\n" pr_id
            | In_progress -> Printf.printf "    stage: in_progress\n"
            | _ -> ());
           if depends_on = [] then
             Printf.printf "    deps: none\n"
           else (
             Printf.printf "    deps: %s\n" (String.concat ", " depends_on);
             let _ =
               List.for_all
                 (fun d -> check_deps ~visited:[ e.hash ] d)
                 depends_on
             in
             ())
         | _ -> ());
        Printf.printf "\n")
      merge_ready;
    Printf.printf "---\n";
    Printf.printf "Checked: %d candidates, %d errors, %d warnings\n"
      (List.length merge_ready) !errors !warnings;
    if !errors > 0 then (
      Printf.eprintf "\nVerification FAILED.\n";
      exit 1)
    else Printf.printf "\nVerification passed.\n")
