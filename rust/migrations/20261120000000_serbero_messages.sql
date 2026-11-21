-- Serbero's reports (D13): the brief, the transcript (one row per part), the
-- updates after handoff and the final report that Serbero, the assistant Read
-- solver, sent to this solver key as send-dm messages. Its own table, so it
-- never mixes with the solver's chats (dispute_messages) or the observed chat.
-- One row per Nostr event, per node, dispute and solver key that read it (D6);
-- copies from other relays are one row. The text is stored as Serbero wrote
-- it and parsed when read (crate::serbero::parse).

CREATE TABLE serbero_messages (
    mostro_pubkey   TEXT NOT NULL,
    dispute_id      TEXT NOT NULL,
    -- The solver key (hex) it was sent to.
    solver_pubkey   TEXT NOT NULL,
    -- The outer kind 14 event id (hex).
    event_id        TEXT NOT NULL,
    -- The Serbero key (hex) that signed it, trusted on this node when read.
    serbero_pubkey  TEXT NOT NULL,
    content         TEXT NOT NULL,
    -- The event's created_at, as Serbero set it.
    created_at      INTEGER NOT NULL,
    -- This device's clock when it was read.
    received_at     INTEGER NOT NULL,

    PRIMARY KEY (mostro_pubkey, dispute_id, solver_pubkey, event_id)
);
