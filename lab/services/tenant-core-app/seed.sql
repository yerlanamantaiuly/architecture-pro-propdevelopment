CREATE TABLE IF NOT EXISTS owners (
    id                  SERIAL PRIMARY KEY,
    full_name           TEXT NOT NULL,
    phone               TEXT NOT NULL,
    email               TEXT NOT NULL,
    passport_number     TEXT NOT NULL,
    passport_issued_by  TEXT NOT NULL,
    apartment_address   TEXT NOT NULL
);

INSERT INTO owners (full_name, phone, email, passport_number, passport_issued_by, apartment_address) VALUES
    ('Алиса Иванова',   '+7-900-000-0001', 'alice@example.com', '4510 123456', 'УВД района Тверское г.Москвы',  'ЖК Северный, кв.10'),
    ('Боб Петров',      '+7-900-000-0002', 'bob@example.com',   '4510 654321', 'УВД Юго-Запад г.Москвы',         'ЖК Южный, кв.42'),
    ('Виктор Сидоров',  '+7-900-000-0003', 'victor@example.com','4510 111222', 'УВД Восточное г.Москвы',         'ЖК Восточный, кв.7')
ON CONFLICT DO NOTHING;
