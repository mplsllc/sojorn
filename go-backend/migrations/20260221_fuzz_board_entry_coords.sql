-- Fuzz existing board_entries coordinates to ~1.1km precision (2 decimal places).
-- The trigger trg_board_entry_location will auto-update the location geometry column.
UPDATE board_entries
SET lat  = ROUND(lat::numeric, 2)::double precision,
    long = ROUND(long::numeric, 2)::double precision,
    updated_at = NOW()
WHERE lat != ROUND(lat::numeric, 2)::double precision
   OR long != ROUND(long::numeric, 2)::double precision;
