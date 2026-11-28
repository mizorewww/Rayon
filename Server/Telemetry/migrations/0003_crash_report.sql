-- Which report a crash or hang item came in, as a random id drawn at ingest
-- (not the client's nonce), so the dashboard counts reports per signature
-- rather than items: one crash-looping device cannot fill a cell by itself.
-- Items stored before this count as one report each; they expire within 90 days.
ALTER TABLE crashes ADD COLUMN report TEXT NOT NULL DEFAULT '';
UPDATE crashes SET report = 'row ' || id;
