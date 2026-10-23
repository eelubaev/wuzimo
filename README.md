# wuzimo

Университеттің ақпараттық жүйесіндегі оқу ақысын төлеу процесі:
таратылған транзакциялар, 2PC және Saga үлгісі (PostgreSQL).

| Файл | Сұрақ |
|------|-------|
| `sql/01_systems.sql`  | 1. Қатысатын жүйелер: `payments_db`, `portal_db`, `accounting_db` |
| `sql/02_failures.sql` | 2. Транзакцияның сәтсіз аяқталуының үш жағдайы |
| `sql/03_2pc.sql`      | 3. 2PC: `PREPARE TRANSACTION` / `COMMIT PREPARED` / `ROLLBACK PREPARED` |
| `sql/04_saga.sql`     | 4. Saga: жергілікті транзакциялар + компенсациялар |

## Іске қосу

2PC үшін `postgresql.conf` ішінде `max_prepared_transactions = 10` болуы керек (серверді қайта қосу қажет).

```sh
for f in sql/0*.sql; do psql -U postgres -d postgres -f "$f"; done
```

Шығыстағы `ERROR` жолдары әдейі модельденген сәтсіздіктер.
