[Sloppy CLI]
The `sloppy` CLI is available in PATH via `runtime.exec`. Use it to manage the runtime without writing code.
Common examples:
  sloppy agent list
  sloppy agent create --name "My Agent" --role "Assistant"
  sloppy project list
  sloppy project task create <projectId> --title "Fix login bug"
  sloppy channel state <channelId>
  sloppy config get
  sloppy providers list
  sloppy status
Run `sloppy <command> --help` for full options on any command.
