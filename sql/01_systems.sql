-- =====================================================================
-- 1-сұрақ. Процеске қатысатын жүйелер
-- ---------------------------------------------------------------------
-- Әр жүйе – жеке дерекқор (нақты өмірдегідей бөлек сервистер):
--   payments_db   – Төлемдер базасы (+ Saga оркестраторының журналы)
--   portal_db     – Студенттің жеке кабинеті
--   accounting_db – Бухгалтерия жүйесі
-- Координатор рөлін psql скрипті (2PC) / saga_log кестесі (Saga) атқарады.
-- Іске қосу: psql -U postgres -d postgres -f sql/01_systems.sql
-- =====================================================================

DROP DATABASE IF EXISTS payments_db;
DROP DATABASE IF EXISTS portal_db;
DROP DATABASE IF EXISTS accounting_db;

CREATE DATABASE payments_db;
CREATE DATABASE portal_db;
CREATE DATABASE accounting_db;

-- ---------------------------------------------------------------------
-- 1) Төлемдер базасы
-- ---------------------------------------------------------------------
\c payments_db

CREATE TABLE payments (
    id          SERIAL PRIMARY KEY,
    payment_ref TEXT          NOT NULL UNIQUE,              -- банктегі транзакция нөмірі
    student_id  INT           NOT NULL,
    amount      NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    status      TEXT          NOT NULL DEFAULT 'CREATED'
                CHECK (status IN ('CREATED', 'CANCELLED')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now()
);

-- Saga оркестраторының журналы: қай қадам орындалды / сәтсіз болды / компенсацияланды
CREATE TABLE saga_log (
    id         SERIAL PRIMARY KEY,
    saga_id    TEXT        NOT NULL,
    step       TEXT        NOT NULL,
    status     TEXT        NOT NULL
               CHECK (status IN ('DONE', 'FAILED', 'COMPENSATED')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- ---------------------------------------------------------------------
-- 2) Студенттің жеке кабинеті
-- ---------------------------------------------------------------------
\c portal_db

CREATE TABLE students (
    id             INT PRIMARY KEY,
    full_name      TEXT          NOT NULL,
    tuition_fee    NUMERIC(12,2) NOT NULL,
    payment_status TEXT          NOT NULL DEFAULT 'UNPAID'
                   CHECK (payment_status IN ('UNPAID', 'PAID')),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT now()
);

INSERT INTO students (id, full_name, tuition_fee) VALUES
    (1, 'Айгерім Серікова', 450000),
    (2, 'Нұрлан Ахметов',   450000),
    (3, 'Дана Жұмабаева',   450000);

-- ---------------------------------------------------------------------
-- 3) Бухгалтерия жүйесі
-- ---------------------------------------------------------------------
\c accounting_db

CREATE TABLE periods (
    period    TEXT PRIMARY KEY,          -- '2026-10'
    is_closed BOOLEAN NOT NULL DEFAULT false
);

CREATE TABLE ledger_entries (
    id          SERIAL PRIMARY KEY,
    payment_ref TEXT          NOT NULL,
    student_id  INT           NOT NULL,
    amount      NUMERIC(12,2) NOT NULL,   -- сторно кезінде теріс сан
    period      TEXT          NOT NULL REFERENCES periods(period),
    entry_type  TEXT          NOT NULL CHECK (entry_type IN ('INCOME', 'STORNO')),
    created_at  TIMESTAMPTZ   NOT NULL DEFAULT now(),
    UNIQUE (payment_ref, entry_type)
);

-- Жабық есепті кезеңге жазба енгізуге тыйым салатын ереже
CREATE FUNCTION reject_closed_period() RETURNS trigger AS $$
BEGIN
    IF (SELECT is_closed FROM periods WHERE period = NEW.period) THEN
        RAISE EXCEPTION 'Есепті кезең % жабық, төлемді тіркеу мүмкін емес', NEW.period;
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reject_closed_period
    BEFORE INSERT ON ledger_entries
    FOR EACH ROW EXECUTE FUNCTION reject_closed_period();

INSERT INTO periods VALUES ('2026-09', true), ('2026-10', false);

-- ---------------------------------------------------------------------
-- Нәтиже: қатысатын жүйелер және олардың кестелері
-- ---------------------------------------------------------------------
\c postgres
SELECT datname AS "Жүйе (дерекқор)"
FROM pg_database
WHERE datname IN ('payments_db', 'portal_db', 'accounting_db')
ORDER BY datname;
