CREATE TABLE IF NOT EXISTS personal_spaces (
    id UUID PRIMARY KEY,
    label TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'suspended')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS principals (
    id UUID PRIMARY KEY,
    space_id UUID NOT NULL REFERENCES personal_spaces(id),
    role TEXT NOT NULL CHECK (role IN ('owner', 'member')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    UNIQUE (space_id, id)
);

CREATE TABLE IF NOT EXISTS auth_identities (
    provider TEXT NOT NULL,
    subject TEXT NOT NULL,
    principal_id UUID NOT NULL REFERENCES principals(id),
    PRIMARY KEY (provider, subject),
    UNIQUE (principal_id, provider)
);

CREATE TABLE IF NOT EXISTS devices (
    id UUID PRIMARY KEY,
    space_id UUID NOT NULL,
    principal_id UUID NOT NULL,
    kind TEXT NOT NULL CHECK (kind IN ('host', 'mobile', 'admin')),
    name TEXT NOT NULL,
    signing_public_key BYTEA NOT NULL,
    encryption_public_key BYTEA NOT NULL,
    encryption_key_signature BYTEA NOT NULL,
    capabilities TEXT[] NOT NULL DEFAULT '{}',
    status TEXT NOT NULL CHECK (status IN ('active', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    last_seen_at TIMESTAMPTZ,
    FOREIGN KEY (space_id, principal_id) REFERENCES principals(space_id, id),
    UNIQUE (space_id, id)
);
CREATE INDEX IF NOT EXISTS devices_space_status ON devices(space_id, status);

CREATE TABLE IF NOT EXISTS admin_devices (
    id UUID PRIMARY KEY,
    signing_public_key BYTEA NOT NULL,
    name TEXT NOT NULL,
    status TEXT NOT NULL CHECK (status IN ('active', 'revoked')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS admin_sessions (
    token_hash BYTEA PRIMARY KEY,
    admin_device_id UUID NOT NULL REFERENCES admin_devices(id),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS service_invites (
    id UUID PRIMARY KEY,
    token_hash BYTEA NOT NULL UNIQUE,
    created_by_admin_device_id UUID NOT NULL REFERENCES admin_devices(id),
    expires_at TIMESTAMPTZ NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS device_pairings (
    id UUID PRIMARY KEY,
    space_id UUID NOT NULL REFERENCES personal_spaces(id),
    created_by_device_id UUID NOT NULL,
    claim_nonce_hash BYTEA NOT NULL,
    requested_kind TEXT NOT NULL CHECK (requested_kind IN ('host', 'mobile')),
    claimed_device_id UUID,
    claimed_name TEXT,
    claimed_signing_public_key BYTEA,
    claimed_encryption_public_key BYTEA,
    claimed_encryption_key_signature BYTEA,
    status TEXT NOT NULL CHECK (status IN ('open', 'pending', 'approved', 'rejected')),
    expires_at TIMESTAMPTZ NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    FOREIGN KEY (space_id, created_by_device_id) REFERENCES devices(space_id, id),
    UNIQUE (space_id, id)
);
CREATE INDEX IF NOT EXISTS pairings_space_status ON device_pairings(space_id, status);

CREATE TABLE IF NOT EXISTS device_sessions (
    token_hash BYTEA PRIMARY KEY,
    device_id UUID NOT NULL REFERENCES devices(id),
    expires_at TIMESTAMPTZ NOT NULL,
    revoked_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE TABLE IF NOT EXISTS recovery_codes (
    space_id UUID NOT NULL REFERENCES personal_spaces(id),
    code_hash BYTEA NOT NULL,
    pepper_version INTEGER NOT NULL,
    consumed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    PRIMARY KEY (space_id, code_hash)
);

CREATE TABLE IF NOT EXISTS audit_events (
    id UUID PRIMARY KEY,
    space_id UUID,
    actor_device_id UUID,
    action TEXT NOT NULL,
    target_id UUID,
    allowed BOOLEAN NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX IF NOT EXISTS audit_events_space_time ON audit_events(space_id, created_at DESC);
