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

-- One plant profile per sensor/pot. The optimal moisture range decides
-- dry (below moisture_min) / ok / wet (above moisture_max).
CREATE TABLE IF NOT EXISTS plants (
  device TEXT PRIMARY KEY,            -- which sensor/pot, e.g. planter-1
  nickname TEXT NOT NULL,             -- e.g. ぴょんきち
  species TEXT NOT NULL,              -- plant type shown to people, e.g. ガジュマル
  scientific_name TEXT,               -- e.g. Ficus microcarpa
  photo_url TEXT,                     -- e.g. /images/pyonkichi.jpg (file in public/images)
  moisture_min INTEGER NOT NULL CHECK (moisture_min BETWEEN 0 AND 100),  -- optimal range start (inclusive)
  moisture_max INTEGER NOT NULL CHECK (moisture_max BETWEEN 0 AND 100),  -- optimal range end (inclusive)
  CHECK (moisture_min <= moisture_max)
);
