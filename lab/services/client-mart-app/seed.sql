CREATE TABLE IF NOT EXISTS users (
    id              SERIAL PRIMARY KEY,
    full_name       TEXT NOT NULL,
    phone           TEXT NOT NULL,
    email           TEXT UNIQUE NOT NULL,
    passport_number TEXT,
    password_hash   TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS properties (
    id      SERIAL PRIMARY KEY,
    address TEXT NOT NULL,
    price   NUMERIC NOT NULL
);

CREATE TABLE IF NOT EXISTS bookings (
    id            SERIAL PRIMARY KEY,
    user_id       INT REFERENCES users(id),
    property_id   INT REFERENCES properties(id),
    status        TEXT NOT NULL DEFAULT 'new',
    viewing_type  TEXT NOT NULL DEFAULT 'offline',
    created_at    TIMESTAMP DEFAULT now()
);

INSERT INTO users (full_name, phone, email, passport_number, password_hash) VALUES
    ('Алиса Иванова', '+7-900-000-0001', 'alice@example.com', '4510 123456', 'pwd-alice'),
    ('Боб Петров',    '+7-900-000-0002', 'bob@example.com',   '4510 654321', 'pwd-bob'),
    ('Виктор Сидоров','+7-900-000-0003', 'victor@example.com','4510 111222', 'pwd-victor')
ON CONFLICT (email) DO NOTHING;

INSERT INTO properties (address, price) VALUES
    ('ЖК Северный, кв.10',  12000000),
    ('ЖК Южный, кв.42',     18500000),
    ('ЖК Восточный, кв.7',   9800000)
ON CONFLICT DO NOTHING;

INSERT INTO bookings (user_id, property_id, status, viewing_type) VALUES
    (1, 1, 'confirmed', 'online'),
    (2, 2, 'new',       'offline'),
    (3, 3, 'cancelled', 'offline')
ON CONFLICT DO NOTHING;
