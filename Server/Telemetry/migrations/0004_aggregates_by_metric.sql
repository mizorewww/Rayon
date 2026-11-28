-- The dashboard's daily and version queries and /v1/aggregates read one
-- metric (reports) over a range of days. The primary key leads with the day,
-- so without this each of them read every metric's rows in the range.
-- Without the count, an ingest that only adds to a cell leaves it unchanged.
CREATE INDEX IF NOT EXISTS aggregates_by_metric ON aggregates (metric, day);
