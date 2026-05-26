CREATE TABLE IF NOT EXISTS clients (
    id         SERIAL PRIMARY KEY,
    full_name  TEXT NOT NULL,
    phone      TEXT NOT NULL,
    email      TEXT NOT NULL,
    source     TEXT NOT NULL DEFAULT 'manual',
    created_at TIMESTAMP DEFAULT now()
);

-- Те же люди, что и в client-mart-app, но с «расхождениями» — типичный итог отсутствия
-- единой точки регистрации. Алиса с другой почтой, Боб с другим телефоном, плюс
-- дополнительная «manual»-запись Алисы — менеджер заносит вручную, не зная, что
-- клиент уже регистрировался на витрине.
INSERT INTO clients (full_name, phone, email, source) VALUES
    ('Алиса Иванова', '+7-900-000-0001', 'alice.ivanova@example.com', 'mart-import'),
    ('Боб Петров',    '+7-900-000-9999', 'bob@example.com',           'mart-import'),
    ('Алиса Иванова', '+7-900-000-0001', 'alice@example.com',         'manual')
ON CONFLICT DO NOTHING;
