CREATE TABLE IF NOT EXISTS management_companies (
    id    SERIAL PRIMARY KEY,
    name  TEXT UNIQUE NOT NULL,
    token TEXT UNIQUE NOT NULL
);

CREATE TABLE IF NOT EXISTS buildings (
    id      SERIAL PRIMARY KEY,
    address TEXT NOT NULL,
    mc_id   INT  NOT NULL REFERENCES management_companies(id)
);

CREATE TABLE IF NOT EXISTS owners (
    id          SERIAL PRIMARY KEY,
    building_id INT NOT NULL REFERENCES buildings(id),
    full_name   TEXT NOT NULL,
    phone       TEXT NOT NULL,
    email       TEXT NOT NULL
);

INSERT INTO management_companies (name, token) VALUES
    ('UK_A', 'token-uk-a-secret'),
    ('UK_B', 'token-uk-b-secret')
ON CONFLICT (name) DO NOTHING;

INSERT INTO buildings (address, mc_id) VALUES
    ('ЖК Северный',  (SELECT id FROM management_companies WHERE name='UK_A')),
    ('ЖК Восточный', (SELECT id FROM management_companies WHERE name='UK_A')),
    ('ЖК Южный',     (SELECT id FROM management_companies WHERE name='UK_B')),
    ('ЖК Западный',  (SELECT id FROM management_companies WHERE name='UK_B'))
ON CONFLICT DO NOTHING;

INSERT INTO owners (building_id, full_name, phone, email) VALUES
    (1, 'Алиса Иванова',   '+7-900-000-0001', 'alice@example.com'),
    (1, 'Боб Петров',      '+7-900-000-0002', 'bob@example.com'),
    (3, 'Виктор Сидоров',  '+7-900-000-0003', 'victor@example.com'),
    (4, 'Галина Тестова',  '+7-900-000-0004', 'galina@example.com')
ON CONFLICT DO NOTHING;
