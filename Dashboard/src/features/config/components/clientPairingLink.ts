import type { DevicePairingRecord } from "../../../shared/api/coreApi";

const missingAddress = "Core did not provide an address for another device. Set Public Client URL to a LAN or HTTPS address and generate a new QR, or update Sloppy Core.";

export function clientPairingLink(pairing: DevicePairingRecord): { link: string; serverURL: string } {
  let url: URL;
  try {
    url = new URL(pairing.serverURL ?? "");
  } catch {
    throw new Error(missingAddress);
  }
  const host = url.hostname.toLowerCase().replace(/^\[|\]$/g, "").replace(/\.$/, "");
  if (!["http:", "https:"].includes(url.protocol) || url.username || url.password ||
      !host || host === "localhost" || host.endsWith(".localhost") || host.startsWith("127.") ||
      ["0.0.0.0", "::", "::1"].includes(host) || (url.pathname !== "/" && url.pathname !== "") || url.search || url.hash) {
    throw new Error("Core returned a local-only or invalid client address. Set Public Client URL to the host's LAN or HTTPS address and generate a new QR.");
  }
  if (pairing.setupCode) return { link: pairing.setupCode, serverURL: url.origin };
  const query = new URLSearchParams({
    host: url.hostname.replace(/^\[|\]$/g, ""),
    port: url.port || (url.protocol === "https:" ? "443" : "80"),
    scheme: url.protocol.slice(0, -1),
    label: `Sloppy @ ${url.hostname}`,
    pairingToken: pairing.token
  });
  return { link: `sloppy://connect?${query.toString()}`, serverURL: url.origin };
}
