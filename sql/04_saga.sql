-- =====================================================================
-- 4-сұрақ. Saga үлгісі (оркестрация)
-- ---------------------------------------------------------------------
-- Әр қадам – жергілікті транзакция, БІРДЕН commit жасалады.
-- Қате болса, орындалған қадамдар кері ретпен компенсацияланады:
--   T1 төлем жазбасы        <-> C1 жазбаны CANCELLED деп белгілеу
--   T2 кабинеттегі мәртебе  <-> C2 мәртебені UNPAID-ке қайтару
--   T3 бухгалтерияға тіркеу <-> C3 сторно (кері проводка)
-- Оркестратор әр қадамды payments_db.saga_log кестесіне жазады.
-- =====================================================================

-- #####################################################################
-- А) СӘТТІ SAGA: студент 2, төлем TX-2001
-- #####################################################################

-- T1: Төлемдер базасы
\c payments_db
BEGIN;
INSERT INTO payments (payment_ref, student_id, amount) VALUES ('TX-2001', 2, 450000);
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2001', 'T1_payment', 'DONE');
COMMIT;

-- T2: Жеке кабинет
\c portal_db
BEGIN;
UPDATE students SET payment_status = 'PAID', updated_at = now() WHERE id = 2;
COMMIT;
\c payments_db
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2001', 'T2_portal', 'DONE');

-- T3: Бухгалтерия
\c accounting_db
BEGIN;
INSERT INTO ledger_entries (payment_ref, student_id, amount, period, entry_type)
VALUES ('TX-2001', 2, 450000, '2026-10', 'INCOME');
COMMIT;
\c payments_db
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2001', 'T3_accounting', 'DONE');

SELECT saga_id, step, status FROM saga_log WHERE saga_id = 'TX-2001' ORDER BY id;


-- #####################################################################
-- Ә) СӘТСІЗ SAGA + КОМПЕНСАЦИЯ: студент 3, төлем TX-2002
--    T3 сәтсіз (кезең 2026-09 жабық) -> C2, C1 кері ретпен
-- #####################################################################

-- T1
\c payments_db
BEGIN;
INSERT INTO payments (payment_ref, student_id, amount) VALUES ('TX-2002', 3, 450000);
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2002', 'T1_payment', 'DONE');
COMMIT;

-- T2
\c portal_db
BEGIN;
UPDATE students SET payment_status = 'PAID', updated_at = now() WHERE id = 3;
COMMIT;
\c payments_db
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2002', 'T2_portal', 'DONE');

-- T3 – ҚАТЕ
\c accounting_db
BEGIN;
INSERT INTO ledger_entries (payment_ref, student_id, amount, period, entry_type)
VALUES ('TX-2002', 3, 450000, '2026-09', 'INCOME');   -- ҚАТЕ: кезең жабық
ROLLBACK;
\c payments_db
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2002', 'T3_accounting', 'FAILED');

-- Аралық күй (Saga-ның ерекшелігі – eventual consistency):
-- T1, T2 commit болған, яғни басқалар оларды КӨРЕ АЛАДЫ
SELECT payment_ref, status FROM payments WHERE payment_ref = 'TX-2002';   -- CREATED

-- C2: кабинеттегі мәртебені қайтару (идемпотентті: қайта орындалса да зиянсыз)
\c portal_db
BEGIN;
UPDATE students SET payment_status = 'UNPAID', updated_at = now()
WHERE id = 3 AND payment_status = 'PAID';
COMMIT;
\c payments_db
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2002', 'T2_portal', 'COMPENSATED');

-- C1: төлем жазбасын болдырмау (жоймаймыз – аудит үшін CANCELLED деп белгілейміз)
BEGIN;
UPDATE payments SET status = 'CANCELLED'
WHERE payment_ref = 'TX-2002' AND status = 'CREATED';
INSERT INTO saga_log (saga_id, step, status) VALUES ('TX-2002', 'T1_payment', 'COMPENSATED');
COMMIT;

-- Saga журналы: T1 DONE, T2 DONE, T3 FAILED, C2, C1
SELECT saga_id, step, status FROM saga_log WHERE saga_id = 'TX-2002' ORDER BY id;

-- Қорытынды күй: жүйелер қайтадан келісілген
SELECT payment_ref, status FROM payments WHERE payment_ref = 'TX-2002';   -- CANCELLED
\c portal_db
SELECT id, payment_status FROM students WHERE id = 3;                     -- UNPAID


-- #####################################################################
-- Б) C3 мысалы: бухгалтериядағы жазбаны компенсациялау – СТОРНО
--    (мысалы, TX-2001 кейін банк тарапынан қайтарылды)
--    Бухгалтерияда жазба жойылмайды, кері проводка жасалады.
-- #####################################################################
\c accounting_db
INSERT INTO ledger_entries (payment_ref, student_id, amount, period, entry_type)
VALUES ('TX-2001', 2, -450000, '2026-10', 'STORNO');

SELECT payment_ref, entry_type, amount FROM ledger_entries WHERE payment_ref = 'TX-2001' ORDER BY id;
SELECT payment_ref, sum(amount) AS balance FROM ledger_entries
WHERE payment_ref = 'TX-2001' GROUP BY payment_ref;                       -- 0
