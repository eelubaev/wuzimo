-- =====================================================================
-- 3-сұрақ. 2PC (Two-Phase Commit) протоколы
-- ---------------------------------------------------------------------
-- PostgreSQL-да 2PC командалары:
--   PREPARE TRANSACTION 'id'  – 1-фаза: қатысушы «YES, дайынмын» дейді
--   COMMIT PREPARED 'id'      – 2-фаза: бекіту
--   ROLLBACK PREPARED 'id'    – 2-фаза: болдырмау
-- Талап: postgresql.conf ішінде max_prepared_transactions > 0.
-- Координатор рөлін осы скрипт атқарады.
-- =====================================================================

-- #####################################################################
-- А) СӘТТІ СЦЕНАРИЙ: студент 1, төлем TX-1001
-- #####################################################################

-- ---------- 1-ФАЗА: PREPARE (дауыс беру) ----------
\c payments_db
BEGIN;
INSERT INTO payments (payment_ref, student_id, amount) VALUES ('TX-1001', 1, 450000);
PREPARE TRANSACTION 'pay_TX-1001';        -- Төлемдер базасы: YES

\c portal_db
BEGIN;
UPDATE students SET payment_status = 'PAID', updated_at = now() WHERE id = 1;
PREPARE TRANSACTION 'portal_TX-1001';     -- Жеке кабинет: YES

\c accounting_db
BEGIN;
INSERT INTO ledger_entries (payment_ref, student_id, amount, period, entry_type)
VALUES ('TX-1001', 1, 450000, '2026-10', 'INCOME');
PREPARE TRANSACTION 'acc_TX-1001';        -- Бухгалтерия: YES

-- Үш қатысушы да дайын. Дайындалған транзакциялар:
SELECT gid, database, prepared FROM pg_prepared_xacts ORDER BY gid;

-- 2PC кемшілігі: дайындалған транзакция жолды ҚҰЛЫПТАП тұр.
-- Басқа сессия студент 1-ді өзгерте алмайды (блокталады):
\c portal_db
SET lock_timeout = '1s';
UPDATE students SET full_name = full_name WHERE id = 1;   -- ҚАТЕ: lock timeout
RESET lock_timeout;

-- Ал commit болмағандықтан, өзгеріс әлі көрінбейді:
SELECT id, payment_status FROM students WHERE id = 1;     -- әлі UNPAID

-- ---------- 2-ФАЗА: COMMIT (барлығы YES) ----------
\c payments_db
COMMIT PREPARED 'pay_TX-1001';
\c portal_db
COMMIT PREPARED 'portal_TX-1001';
\c accounting_db
COMMIT PREPARED 'acc_TX-1001';

-- Тексеру: үш жүйеде де жазба бар
SELECT 'accounting_db' AS system, payment_ref, amount FROM ledger_entries WHERE payment_ref = 'TX-1001';
\c portal_db
SELECT 'portal_db' AS system, id, payment_status FROM students WHERE id = 1;
\c payments_db
SELECT 'payments_db' AS system, payment_ref, status FROM payments WHERE payment_ref = 'TX-1001';


-- #####################################################################
-- Ә) СӘТСІЗ СЦЕНАРИЙ: студент 2, төлем TX-1002 (кезең 2026-09 жабық)
-- #####################################################################

-- ---------- 1-ФАЗА: PREPARE ----------
\c payments_db
BEGIN;
INSERT INTO payments (payment_ref, student_id, amount) VALUES ('TX-1002', 2, 450000);
PREPARE TRANSACTION 'pay_TX-1002';        -- YES

\c portal_db
BEGIN;
UPDATE students SET payment_status = 'PAID', updated_at = now() WHERE id = 2;
PREPARE TRANSACTION 'portal_TX-1002';     -- YES

\c accounting_db
BEGIN;
INSERT INTO ledger_entries (payment_ref, student_id, amount, period, entry_type)
VALUES ('TX-1002', 2, 450000, '2026-09', 'INCOME');   -- ҚАТЕ: кезең жабық
PREPARE TRANSACTION 'acc_TX-1002';        -- транзакция қатемен үзілген -> ROLLBACK = NO

SELECT gid, database FROM pg_prepared_xacts ORDER BY gid;   -- acc_TX-1002 жоқ

-- ---------- 2-ФАЗА: ROLLBACK (біреуі NO деді) ----------
\c payments_db
ROLLBACK PREPARED 'pay_TX-1002';
\c portal_db
ROLLBACK PREPARED 'portal_TX-1002';

-- Тексеру: ешбір жүйеде із қалмады (атомарлық сақталды)
SELECT 'portal_db' AS system, id, payment_status FROM students WHERE id = 2;   -- UNPAID
\c payments_db
SELECT 'payments_db' AS system, count(*) AS tx_1002 FROM payments WHERE payment_ref = 'TX-1002';  -- 0
\c accounting_db
SELECT 'accounting_db' AS system, count(*) AS tx_1002 FROM ledger_entries WHERE payment_ref = 'TX-1002'; -- 0
