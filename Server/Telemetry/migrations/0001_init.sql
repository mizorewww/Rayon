-- Daily counts: how many reports fell into each bucket of each metric.
-- No row holds an identifier, an IP address or a time finer than the day.
CREATE TABLE aggregates (
    day TEXT NOT NULL,
    app_version TEXT NOT NULL,
    os_version TEXT NOT NULL,
    metric TEXT NOT NULL,
    bucket TEXT NOT NULL,
    count INTEGER NOT NULL,
    PRIMARY KEY (day, app_version, os_version, metric, bucket)
) WITHOUT ROWID;

-- Scrubbed crash and hang items, kept 90 days for symbolication.
CREATE TABLE crashes (
    id INTEGER PRIMARY KEY,
    day TEXT NOT NULL,
    app_version TEXT NOT NULL,
    os_version TEXT NOT NULL,
    kind TEXT NOT NULL,
    item TEXT NOT NULL
);
CREATE INDEX crashes_by_day ON crashes (day);

-- Report nonces seen in the last days, so a retried report counts once.
CREATE TABLE nonces (
    nonce TEXT PRIMARY KEY,
    day TEXT NOT NULL
) WITHOUT ROWID;
CREATE INDEX nonces_by_day ON nonces (day);
