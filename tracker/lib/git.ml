(** Git operations using shexp for safe command execution. *)

module P = Shexp_process

let melange_dir () =
  Sys.getenv_opt "MELANGE_DIR"
  |> Option.value ~default:(Filename.concat (Sys.getcwd ()) "../melange")

let run_git args =
  let dir = melange_dir () in
  P.eval
    (P.chdir dir
       (P.capture_unit [ Stdout ] (P.run "git" args)))

let run_git_lines args =
  let output = run_git args in
  String.split_on_char '\n' output
  |> List.filter (fun s -> String.trim s <> "")

type commit_info = {
  hash : string;
  subject : string;
  author : string;
  date : string;
  files : string list;
}

let show_commit hash =
  let output =
    run_git [ "show"; "--no-patch"; "--format=%H%n%s%n%an%n%ai"; hash ]
  in
  match String.split_on_char '\n' output with
  | full_hash :: subject :: author :: date :: _ ->
    let files =
      run_git_lines [ "diff-tree"; "--no-commit-id"; "--name-only"; "-r"; hash ]
    in
    Some { hash = full_hash; subject; author; date; files }
  | _ -> None

let log_since_commit ~since_commit ~remote ~branch () =
  let _ = run_git [ "fetch"; remote ] in
  let ref_spec = Printf.sprintf "%s/%s" remote branch in
  let range =
    match since_commit with
    | Some commit -> Printf.sprintf "%s..%s" commit ref_spec
    | None -> ref_spec
  in
  run_git_lines [ "log"; "--format=%H %s"; "--reverse"; range ]

let tip_commit ~remote ~branch () =
  let ref_spec = Printf.sprintf "%s/%s" remote branch in
  String.trim (run_git [ "rev-parse"; ref_spec ])

let parse_log_line line =
  match String.index_opt line ' ' with
  | Some i ->
    let hash = String.sub line 0 i in
    let subject = String.sub line (i + 1) (String.length line - i - 1) in
    Some (hash, subject)
  | None -> None
