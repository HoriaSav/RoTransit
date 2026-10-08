-- Explicit ids so feed ids stay the same as before the redesign (/api/feeds/{id}/file URLs keep working).
INSERT INTO city (id, name)
VALUES
    (1,  'Brasov'),
    (2,  'Bucuresti'),
    (3,  'Buzau'),
    (4,  'Cluj-Napoca'),
    (5,  'Constanta'),
    (6,  'Craiova'),
    (7,  'Iasi'),
    (8,  'Oradea'),
    (9,  'Ploiesti'),
    (10, 'Sibiu'),
    (11, 'Sinaia'),
    (12, 'Targoviste'),
    (13, 'Timisoara');

INSERT INTO feed (id, city_id, name)
VALUES
    (1,  1,  'RATBV'),
    (2,  2,  'STB'),
    (3,  3,  'CJ-Buzau'),
    (4,  4,  'CTP-Cluj'),
    (5,  5,  'CT-Bus'),
    (6,  6,  'RAT-Craiova'),
    (7,  7,  'CTP-Iasi'),
    (8,  8,  'OTL'),
    (9,  9,  'TCE-Ploiesti'),
    (10, 10, 'Tursib'),
    (11, 11, 'TU-Sinaia'),
    (12, 12, 'SPM-Targoviste'),
    (13, 13, 'SMTT');

INSERT INTO feed_source (feed_id, kind, ref, priority)
VALUES
    (1,  'mobilitydb', 'mdb-2143', 1),
    (2,  'mobilitydb', 'mdb-2098', 1),
    (3,  'mobilitydb', 'mdb-3179', 1),
    (4,  'mobilitydb', 'mdb-2121', 1),
    (5,  'mobilitydb', 'mdb-2100', 1),
    (6,  'mobilitydb', 'mdb-2115', 1),
    (7,  'mobilitydb', 'mdb-2116', 1),
    (8,  'mobilitydb', 'mdb-2101', 1),
    (9,  'mobilitydb', 'mdb-2108', 1),
    (10, 'mobilitydb', 'mdb-2099', 1),
    (11, 'mobilitydb', 'mdb-2114', 1),
    (12, 'mobilitydb', 'mdb-2107', 1),
    (13, 'mobilitydb', 'mdb-2868', 1);

-- We inserted ids by hand, so move the id counters past them; otherwise the next insert would try id 1 again.
SELECT setval(pg_get_serial_sequence('city', 'id'), (SELECT max(id) FROM city));
SELECT setval(pg_get_serial_sequence('feed', 'id'), (SELECT max(id) FROM feed));
