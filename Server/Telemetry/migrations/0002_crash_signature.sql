-- A crash or hang item's signature: its kind, its exception and the first app
-- frame of the attributed thread, so the dashboard can count items alike
-- without reading them. Items stored before this had no frame part; they
-- expire within 90 days.
ALTER TABLE crashes ADD COLUMN signature TEXT NOT NULL DEFAULT '';
UPDATE crashes SET signature = kind
    || COALESCE(' ' || json_extract(item, '$.objcExceptionName'), '')
    || COALESCE(' EXC ' || json_extract(item, '$.exceptionType'), '')
    || COALESCE(' SIG ' || json_extract(item, '$.signal'), '')
    || CASE WHEN json_extract(item, '$.terminationReason') IN (NULL, 'signal') THEN '' ELSE COALESCE(' ' || json_extract(item, '$.terminationReason'), '') END;
CREATE INDEX crashes_by_signature ON crashes (day, signature);
