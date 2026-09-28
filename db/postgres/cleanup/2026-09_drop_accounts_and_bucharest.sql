-- One-off cleanup for databases created before accounts and Bucharest were removed
-- from 001_init.sql. Init scripts only run on an empty volume, so run this once by hand.
-- Irreversible: drops saved routes, favorites and users stored on the server.
--
-- Check first that Bucharest has no GTFS data you want to keep (gtfs_* rows are
-- deleted with it through ON DELETE CASCADE):
--   SELECT count(*) FROM gtfs_routes r JOIN cities c ON c.id = r.city_id
--    WHERE c.id = 'a1b2c3d4-e5f6-4789-a012-3456789abcde'
--       OR (c.name = 'Bucharest' AND c.country = 'Romania');
BEGIN;
DROP TABLE IF EXISTS favorite_stops, saved_routes, users;
DELETE FROM cities
 WHERE id = 'a1b2c3d4-e5f6-4789-a012-3456789abcde'
    OR (name = 'Bucharest' AND country = 'Romania');
COMMIT;
