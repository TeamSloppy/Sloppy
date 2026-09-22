enum RelayAdminPage {
    static let html = #"""
    <!doctype html>
    <html lang="en">
    <head>
      <meta charset="utf-8">
      <meta name="viewport" content="width=device-width, initial-scale=1">
      <title>Sloppy Relay Admin</title>
      <style>
        :root { color-scheme: dark; font-family: system-ui, -apple-system, sans-serif; }
        body { max-width: 920px; margin: 48px auto; padding: 0 20px; background: #101318; color: #e8ebf0; }
        h1 { font-size: 28px; margin-bottom: 4px; }
        p, small { color: #a8b0bc; }
        section { border: 1px solid #343b46; border-radius: 12px; padding: 20px; margin: 20px 0; }
        input { background: #171d25; border: 1px solid #475160; border-radius: 8px; color: inherit; padding: 10px; min-width: 280px; }
        button { background: #24c4e8; border: 0; border-radius: 8px; color: #07151b; padding: 10px 14px; font-weight: 650; cursor: pointer; }
        button.secondary { background: #353e4a; color: #e8ebf0; }
        button:disabled { opacity: .5; cursor: default; }
        .row { display: flex; gap: 12px; align-items: center; flex-wrap: wrap; margin-top: 12px; }
        .item { padding: 12px 0; border-top: 1px solid #343b46; }
        code { overflow-wrap: anywhere; }
        #status { min-height: 24px; }
      </style>
    </head>
    <body>
      <h1>Sloppy Relay Admin</h1>
      <p>Manage service invites and isolated personal spaces. Device keys stay in this browser.</p>
      <p id="status" role="status"></p>

      <section id="setup">
        <h2>Admin device</h2>
        <p>Register this browser once from the relay host using its public key. The private key is non-exportable and stored in this browser.</p>
        <div class="row"><button id="generate">Generate browser key</button></div>
        <p>Public key: <code id="public-key">Not generated</code></p>
        <div class="row">
          <label>Admin device ID <input id="admin-id" autocomplete="off" placeholder="UUID from bootstrap-admin"></label>
          <button id="login">Sign in</button>
        </div>
      </section>

      <section id="invites" hidden>
        <h2>Service invites</h2>
        <p>Each invite creates a new, isolated personal space.</p>
        <div class="row">
          <label>Lifetime (minutes) <input id="ttl" type="number" min="1" max="1440" value="60"></label>
          <button id="create-invite">Create invite</button>
        </div>
        <p id="new-invite" aria-live="polite"></p>
        <div id="invite-list"></div>
      </section>

      <section id="spaces" hidden>
        <h2>Personal spaces</h2>
        <div id="space-list"></div>
      </section>

      <section id="devices" hidden>
        <h2>Devices</h2>
        <div id="device-list"></div>
      </section>

      <section id="audit" hidden>
        <h2>Recent audit events</h2>
        <div id="audit-list"></div>
      </section>

      <section id="metrics" hidden>
        <h2>Relay health</h2>
        <div id="metrics-value"></div>
      </section>

      <script>
        const status = document.getElementById("status");
        const dbName = "sloppy-relay-admin";
        function setStatus(message) { status.textContent = message; }
        function base64(bytes) {
          let text = "";
          for (const byte of new Uint8Array(bytes)) text += String.fromCharCode(byte);
          return btoa(text);
        }
        async function database() {
          return await new Promise((resolve, reject) => {
            const request = indexedDB.open(dbName, 1);
            request.onupgradeneeded = () => request.result.createObjectStore("keys");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
          });
        }
        async function storedKey() {
          const db = await database();
          return await new Promise((resolve, reject) => {
            const tx = db.transaction("keys", "readonly");
            const request = tx.objectStore("keys").get("admin");
            request.onsuccess = () => resolve(request.result);
            request.onerror = () => reject(request.error);
          });
        }
        async function saveKey(key) {
          const db = await database();
          await new Promise((resolve, reject) => {
            const tx = db.transaction("keys", "readwrite");
            tx.objectStore("keys").put(key, "admin");
            tx.oncomplete = resolve;
            tx.onerror = () => reject(tx.error);
          });
        }
        async function api(path, options = {}) {
          const response = await fetch(path, {
            credentials: "same-origin",
            cache: "no-store",
            headers: {
              "Content-Type": "application/json",
              "X-Sloppy-Admin-Action": "1"
            },
            ...options
          });
          const body = await response.json();
          if (!response.ok) throw new Error(body.error || "Request failed");
          return body;
        }
        async function refresh() {
          const [spaces, invites, audit, metrics] = await Promise.all([
            api("/v1/admin/spaces"),
            api("/v1/admin/invites"),
            api("/v1/admin/audit"),
            api("/v1/admin/metrics")
          ]);
          document.getElementById("setup").hidden = true;
          document.getElementById("spaces").hidden = false;
          document.getElementById("invites").hidden = false;
          document.getElementById("audit").hidden = false;
          document.getElementById("metrics").hidden = false;
          document.getElementById("metrics-value").textContent =
            `${metrics.databaseHealthy ? "DB ready" : "DB unavailable"} · ` +
            `${metrics.relay.activeSessions} sessions · ${metrics.relay.hostsOnline} hosts online · ` +
            `${metrics.relay.pairingsApproved} approved pairings · ${metrics.relay.pairingsRejected} rejected · ` +
            `${metrics.relay.authFailures} auth failures · ${metrics.relay.crossTenantDenials} cross-space denials`;
          const spaceList = document.getElementById("space-list");
          spaceList.replaceChildren();
          for (const space of spaces) {
            const row = document.createElement("div");
            row.className = "item";
            const label = document.createElement("span");
            label.textContent = `${space.label} · ${space.status} · ${space.deviceCount} devices · ${space.id}`;
            const action = document.createElement("button");
            action.className = "secondary";
            action.textContent = space.status === "active" ? "Suspend" : "Resume";
            action.onclick = async () => {
              try {
                await api(`/v1/admin/spaces/${space.id}/${space.status === "active" ? "suspend" : "resume"}`, { method: "POST", body: "{}" });
                await refresh();
              } catch (error) { setStatus(error.message); }
            };
            const inspect = document.createElement("button");
            inspect.className = "secondary";
            inspect.textContent = "Devices";
            inspect.onclick = async () => {
              try {
                const devices = await api(`/v1/admin/spaces/${space.id}/devices`);
                const list = document.getElementById("device-list");
                list.replaceChildren();
                document.getElementById("devices").hidden = false;
                for (const device of devices) {
                  const item = document.createElement("div");
                  item.className = "item";
                  const details = document.createElement("span");
                  details.textContent = `${device.name} · ${device.kind} · ${device.status} · last seen ${device.lastSeenAt || "never"} · ${device.id}`;
                  item.append(details);
                  if (device.status === "active") {
                    const revoke = document.createElement("button");
                    revoke.className = "secondary";
                    revoke.textContent = "Revoke";
                    revoke.onclick = async () => {
                      if (!confirm(`Revoke ${device.name}?`)) return;
                      try {
                        await api(`/v1/admin/devices/${device.id}`, { method: "DELETE" });
                        await refresh();
                      } catch (error) { setStatus(error.message); }
                    };
                    item.append(" ", revoke);
                  }
                  list.append(item);
                }
              } catch (error) { setStatus(error.message); }
            };
            row.append(label, " ", inspect, " ", action);
            spaceList.append(row);
          }
          const inviteList = document.getElementById("invite-list");
          inviteList.replaceChildren();
          for (const invite of invites) {
            const row = document.createElement("div");
            row.className = "item";
            row.textContent = `${invite.id} · expires ${invite.expiresAt} · ${invite.consumedAt ? "used" : "unused"}`;
            if (!invite.consumedAt) {
              const action = document.createElement("button");
              action.className = "secondary";
              action.textContent = "Revoke";
              action.onclick = async () => {
                try {
                  await api(`/v1/admin/invites/${invite.id}`, { method: "DELETE" });
                  await refresh();
                } catch (error) { setStatus(error.message); }
              };
              row.append(" ", action);
            }
            inviteList.append(row);
          }
          const auditList = document.getElementById("audit-list");
          auditList.replaceChildren();
          for (const event of audit) {
            const row = document.createElement("div");
            row.className = "item";
            row.textContent = `${event.createdAt} · ${event.action} · ${event.spaceID || "service"} · ${event.targetID || ""}`;
            auditList.append(row);
          }
        }
        document.getElementById("generate").onclick = async () => {
          try {
            let key = await storedKey();
            if (!key) {
              key = await crypto.subtle.generateKey({ name: "Ed25519" }, false, ["sign", "verify"]);
              await saveKey(key);
            }
            document.getElementById("public-key").textContent =
              base64(await crypto.subtle.exportKey("raw", key.publicKey));
            setStatus("Public key ready. Run SloppyRelay bootstrap-admin on the relay host, then paste the device ID.");
          } catch (error) { setStatus(error.message); }
        };
        document.getElementById("login").onclick = async () => {
          try {
            const key = await storedKey();
            if (!key) throw new Error("Generate the browser key first.");
            const deviceID = document.getElementById("admin-id").value.trim();
            const challenge = await api("/v1/admin/auth/challenge", {
              method: "POST", body: JSON.stringify({ deviceID })
            });
            const nonce = Uint8Array.from(atob(challenge.nonce), c => c.charCodeAt(0));
            const signature = await crypto.subtle.sign("Ed25519", key.privateKey, nonce);
            await api("/v1/admin/auth/session", {
              method: "POST",
              body: JSON.stringify({ challengeID: challenge.id, signature: base64(signature) })
            });
            localStorage.setItem("sloppy-relay-admin-id", deviceID);
            await refresh();
            setStatus("Signed in.");
          } catch (error) { setStatus(error.message); }
        };
        document.getElementById("create-invite").onclick = async () => {
          try {
            const ttlMinutes = Number(document.getElementById("ttl").value);
            const result = await api("/v1/admin/invites", {
              method: "POST", body: JSON.stringify({ ttlMinutes })
            });
            document.getElementById("new-invite").textContent =
              "Copy this invite now; it will not be shown again: " + result.invite;
            await refresh();
          } catch (error) { setStatus(error.message); }
        };
        document.getElementById("admin-id").value =
          localStorage.getItem("sloppy-relay-admin-id") || "";
        refresh().catch(() => {});
      </script>
    </body>
    </html>
    """#
}
