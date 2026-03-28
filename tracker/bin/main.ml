open Cmdliner

(* Common arguments *)
let hash_arg =
  Arg.(required & pos 0 (some string) None & info [] ~docv:"HASH" ~doc:"Commit hash or prefix.")

let reason_arg =
  Arg.(value & pos 2 (some string) None & info [] ~docv:"REASON" ~doc:"Reason or notes.")

(* scan *)
let scan_cmd =
  let since =
    Arg.(value & opt (some string) None & info [ "since" ] ~docv:"DATE"
           ~doc:"Scan commits since this date (YYYY-MM-DD).")
  in
  let doc = "Scan upstream for new commits and add them to the queue." in
  Cmd.v (Cmd.info "scan" ~doc) Term.(const Tracker_lib.Commands.scan $ since)

(* status *)
let status_cmd =
  let doc = "Show summary statistics by status." in
  Cmd.v (Cmd.info "status" ~doc) Term.(const Tracker_lib.Commands.status $ const ())

(* list *)
let list_cmd =
  let filter =
    Arg.(value & opt (some string) None & info [ "status"; "s" ] ~docv:"STATUS"
           ~doc:"Filter by status name.")
  in
  let doc = "List tracked entries." in
  Cmd.v (Cmd.info "list" ~doc) Term.(const Tracker_lib.Commands.list_entries $ filter)

(* show *)
let show_cmd =
  let doc = "Show full details for a commit." in
  Cmd.v (Cmd.info "show" ~doc) Term.(const Tracker_lib.Commands.show $ hash_arg)

(* queue *)
let queue_cmd =
  let doc = "List all commits in the triage queue." in
  Cmd.v (Cmd.info "queue" ~doc) Term.(const Tracker_lib.Commands.queue $ const ())

(* triage *)
let triage_cmd =
  let status_arg =
    Arg.(required & pos 1 (some string) None & info [] ~docv:"STATUS"
           ~doc:"New status: irrelevant, wont_pick, deferred, undecided, candidate.")
  in
  let doc = "Set the triage status of a commit." in
  Cmd.v (Cmd.info "triage" ~doc)
    Term.(const Tracker_lib.Commands.triage $ hash_arg $ status_arg $ reason_arg)

(* plan *)
let plan_cmd =
  let notes =
    Arg.(required & pos 1 (some string) None & info [] ~docv:"NOTES"
           ~doc:"Adaptation plan notes.")
  in
  let doc = "Set a commit as a planned candidate with notes." in
  Cmd.v (Cmd.info "plan" ~doc) Term.(const Tracker_lib.Commands.plan $ hash_arg $ notes)

(* advance *)
let advance_cmd =
  let doc = "Advance a candidate to the next stage." in
  Cmd.v (Cmd.info "advance" ~doc) Term.(const Tracker_lib.Commands.advance $ hash_arg)

(* depend *)
let depend_cmd =
  let deps =
    Arg.(non_empty & pos_right 0 string [] & info [] ~docv:"DEP_HASH"
           ~doc:"Dependency commit hashes.")
  in
  let doc = "Add dependency links to a candidate." in
  Cmd.v (Cmd.info "depend" ~doc)
    Term.(const Tracker_lib.Commands.depend $ hash_arg $ deps)

(* pr *)
let pr_cmd =
  let pr_id =
    Arg.(required & pos 1 (some int) None & info [] ~docv:"PR_ID"
           ~doc:"Pull request number.")
  in
  let doc = "Record a pull request for a candidate." in
  Cmd.v (Cmd.info "pr" ~doc) Term.(const Tracker_lib.Commands.pr $ hash_arg $ pr_id)

(* merge *)
let merge_cmd =
  let melange_hash =
    Arg.(required & pos 1 (some string) None & info [] ~docv:"MELANGE_HASH"
           ~doc:"Commit hash in the melange repo.")
  in
  let doc = "Record that a candidate has been merged into melange." in
  Cmd.v (Cmd.info "merge" ~doc)
    Term.(const Tracker_lib.Commands.merge $ hash_arg $ melange_hash)

(* report *)
let report_cmd =
  let doc = "Show actionable candidates grouped by stage." in
  Cmd.v (Cmd.info "report" ~doc) Term.(const Tracker_lib.Commands.report $ const ())

(* main *)
let () =
  let doc = "Track upstream rescript commits as cherry-pick candidates for melange." in
  let info = Cmd.info "tracker" ~version:"0.1.0" ~doc in
  let cmd =
    Cmd.group info
      [
        scan_cmd;
        status_cmd;
        list_cmd;
        show_cmd;
        queue_cmd;
        triage_cmd;
        plan_cmd;
        advance_cmd;
        depend_cmd;
        pr_cmd;
        merge_cmd;
        report_cmd;
      ]
  in
  exit (Cmd.eval cmd)
