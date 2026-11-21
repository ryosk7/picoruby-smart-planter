CREATE TABLE IF NOT EXISTS readings (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device TEXT NOT NULL,
  moisture INTEGER NOT NULL CHECK (moisture BETWEEN 0 AND 100),
  volt REAL NOT NULL,
  raw INTEGER NOT NULL CHECK (raw BETWEEN 0 AND 4095),
  status TEXT NOT NULL CHECK (status IN ('dry', 'ok', 'wet')),
  measured_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS readings_device_measured_at
  ON readings (device, measured_at);
