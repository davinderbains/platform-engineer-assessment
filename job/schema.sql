CREATE TABLE IF NOT EXISTS image_results (
    image_key   text PRIMARY KEY,
    etag        text NOT NULL,
    status      text NOT NULL CHECK (status IN ('done', 'failed')),
    width       integer,
    height      integer,
    brightness  real,
    error       text,
    attempts    integer NOT NULL DEFAULT 1,
    updated_at  timestamptz NOT NULL DEFAULT now(),
    retryable   boolean NOT NULL DEFAULT false
);
