---
name: ssh-machine-onboarding
description: Verify SSH access to an operator-authorized Windows, macOS, or Linux machine and prepare it to join Sloppy Mesh. Use for new machine enrollment or SSH and Mesh connectivity diagnostics, including requests like «подключи машину по SSH».
---

# SSH machine onboarding

Run onboarding in an operator session. Treat the SSH host alias, Sloppy machine alias such as `$home_machine`, and Mesh `nodeId` as separate identifiers. Task workers use Mesh. Keep SSH provisioning in the operator session.

## Verify SSH access

1. Resolve the requested machine from an existing SSH entry or the operator's host, port, user and key reference. Use the confirmed account, preferably a dedicated non-admin account. Check existing access before changing configuration. Obtain the expected SSH host key or fingerprint from the operator or a trusted console. Pin the verified host key in the operator's known-hosts file. For a new or changed host key, verify it before proceeding.
2. Use public-key authentication. Keep the private key on the SSH client and install only its public key for the named account. Use an already approved identity, or configure a dedicated identity with `IdentityFile` and `IdentitiesOnly yes`. Use the platform instructions below if the SSH server or the account's key file needs setup. Apply those changes only within the operator's requested scope.
3. Probe the confirmed SSH alias with fixed read-only commands. The probe below uses `sloppy-worker` as an example SSH config entry.

   ```sh
   ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o ForwardAgent=no -- sloppy-worker hostname
   ssh -o BatchMode=yes -o ConnectTimeout=10 -o StrictHostKeyChecking=yes -o ForwardAgent=no -- sloppy-worker whoami
   ```

4. Compare the reported host and account with the intended machine. Diagnose timeouts or refused connections as reachability or service issues. Diagnose `Permission denied (publickey)` using the selected identity, target account and server key-file permissions. A host-key mismatch requires independent verification of the new key. Prefer private LAN or the operator's approved VPN route. Keep private keys, passwords, invite tokens and provider credentials out of chat, command traces, and project files.

### Platform setup

- **Windows:** enable OpenSSH Server and check the `sshd` service and inbound rule from an authorized admin console. Limit access to the intended private network or operator host. For a standard user, OpenSSH reads `%USERPROFILE%\.ssh\authorized_keys`. For an administrator, follow the active `sshd_config` and the Windows ACL rules for the configured key file. Use PowerShell commands appropriate to the remote shell and the actual worker account. [Server setup](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_install_firstuse) · [Key-based authentication](https://learn.microsoft.com/en-us/windows-server/administration/openssh/openssh_keymanagement)
- **macOS:** open System Settings → General → Sharing → Remote Login, and allow the intended account. Grant only the access needed for the setup. [Apple Remote Login](https://support.apple.com/guide/mac-help/allow-a-remote-computer-to-access-your-mac-mchlp1066/mac)
- **Linux:** check the distribution's OpenSSH server service, private-network listener/firewall, and the target user's `authorized_keys` ownership and permissions.

## Enroll Sloppy

1. Check the installed Sloppy and SloppyNode versions and the actual build toolchain under the intended worker account. Use the repository's `docs/install.md` for the platform installation path when the request includes installation. Preserve existing services, checkout changes and node identity.
2. Follow `docs/guides/mesh.md` and `docs/guides/relay.md` for the installed version's pairing flow. Use a scoped invite on the worker through **Join Remote Mesh** or the documented CLI flow when supported by that version. Keep the invite private and enter it through the local operator interface when shell arguments or logs would expose it. A successful SSH probe establishes only reachability for provisioning.
3. On the coordinator, match the online Mesh identity and capabilities to the confirmed machine. Attach the allowed shared project to the worker's actual checkout and associate the requested Sloppy alias with the confirmed `nodeId` when configuring the target registry. Check the mapped repository and toolchain. Treat platform transport, enrollment and execution support as separately verifiable. Use `docs/specs/distributed-task-execution.md` for the proposed dispatch contract. Current chat delegation may report `remote_execution_unsupported`. Report that state and stop without dispatching over SSH.

Report per machine the verified SSH endpoint and account, Mesh `nodeId` and online state, project/checkout mapping, toolchain check, and executor readiness or blocker. Mark each stage based on direct evidence and leave credentials out of the report.
