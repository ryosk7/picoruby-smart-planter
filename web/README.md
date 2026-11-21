# スマートプランター Web アプリ（PicoRuby on Cloudflare）

土壌水分センサーの測定値を受け取って保存し、ブラウザに表示する Web アプリです。
サーバーもブラウザも Ruby（PicoRuby）で書いていて、全体が Cloudflare の上で動きます。

```text
nRF52840（PicoRuby）──Thread──▶ Raspberry Pi 5 ──HTTPS POST──▶ Cloudflare Workers ──▶ D1
                                                                     │
                                         ブラウザ（Funicular）◀──────┘ GET /api/*
```

| 部分 | 技術 | ファイル |
|---|---|---|
| API | PicoRuby + Sinatra on Cloudflare Workers（[picoruby-cloudflare-worker-wasm](https://github.com/udzura/picoruby-cloudflare-worker-wasm)） | `app.rb` |
| データベース | Cloudflare D1（測定値 `readings` と植物のプロフィール `plants`） | `schema.sql`, `seed.sql` |
| 画面 | Funicular（PicoRuby.wasm の SPA フレームワーク）、Static Assets で配信 | `public/index.html` |
| 送信ツール | CRuby（標準ライブラリだけ） | `tools/post_reading.rb` |
| ビルド設定 | [picoruby-cloudflare-template](https://github.com/udzura/picoruby-cloudflare-template) | `build_config.rb`, `Rakefile`, `wrangler.jsonc`, `src/index.js` |

`/api/*` へのリクエストだけが Worker（PicoRuby の VM）を起動します。
それ以外の `/` などは Static Assets が `public/` をそのまま返すので、PicoRuby は起動しません。

## API

測定値は次の形の JSON です。

```json
{"device":"planter-1","moisture":46,"volt":1.9,"raw":2161,"status":"ok","measured_at":"2026-11-22T00:00:00Z"}
```

| 項目 | 型 | 内容 |
|---|---|---|
| `device` | 文字列 | 機器の ID（英数字と `_ . -`、64 文字まで） |
| `moisture` | 整数 | 水分量 0〜100（%） |
| `volt` | 数値 | センサーの電圧（V、0〜10） |
| `raw` | 整数 | ADC の値 0〜4095 |
| `status` | 文字列 | `dry` / `ok` / `wet`。**サーバーが植物ごとの最適な水分量で判定します**。送られた値は互換のため受け付けますが使いません（形の正しくない値は 400） |
| `measured_at` | 文字列 | 測定時刻（ISO8601、UTC、`Z` 付き）。省略するとサーバーの現在時刻 |

| メソッド | パス | 内容 |
|---|---|---|
| `POST` | `/api/readings` | 測定値を 1 件保存。`Authorization: Bearer <INGEST_TOKEN>` が必要。成功は 201、トークンなし・違いは 401、入力の誤りは 400 |
| `GET` | `/api/readings?device=...&limit=...` | 新しい順の測定値。`limit` の既定は 288（5 分ごとで 1 日分）、最大 2000 |
| `GET` | `/api/latest` | 機器ごとの最新の測定値。各行に植物のプロフィール `plant`（なければ `null`） |
| `GET` | `/api/plants` | 植物のプロフィールの一覧 |
| `PUT` | `/api/plants/:device` | プロフィールを作成・更新（`POST /api/readings` と同じトークンが必要） |

### 植物ごとの「ちょうどよい」

鉢（センサー）ごとに、植物のプロフィールを D1 の `plants` テーブルに持ちます。

| 項目 | 内容 |
|---|---|
| `device` | センサー／鉢の ID（例 `planter-1`） |
| `nickname` | ニックネーム（例 ぴょんきち）。40 文字まで |
| `species` | 植物の種類（例 ガジュマル）。40 文字まで |
| `scientific_name` | 学名（例 Ficus microcarpa）。省略可 |
| `photo_url` | 写真。`public/images/` のファイルなら `/images/...`、外部なら `https://...`。省略可 |
| `moisture_min`, `moisture_max` | 最適な水分量（%、両端を含む）。これより低いと `dry`、高いと `wet` |

プロフィールのない機器は、第 2 章と同じ 30〜59 % を「ちょうどよい」として判定します。

最初のプロフィールは `seed.sql` に入っています（ガジュマルの「ぴょんきち」、25〜54 %）。
ガジュマルは水やりの間に土が乾くのを好むので、低めの範囲から始めています。
25〜54 % は出発点です。実際の鉢と土で様子を見ながら調整してください。範囲は `PUT` で変えられます。

```sh
curl -X PUT http://127.0.0.1:8787/api/plants/planter-1 \
  -H "Authorization: Bearer $PLANTER_TOKEN" -H 'Content-Type: application/json' \
  -d '{"nickname":"ぴょんきち","species":"ガジュマル","scientific_name":"Ficus microcarpa","photo_url":"/images/gajumaru.jpg","moisture_min":25,"moisture_max":54}'
```

## 必要なもの

- Ruby 3.2 以上、Node.js（Wrangler が対応する版）
- Emscripten 5.0 以上（macOS は `brew install emscripten`）
- PicoRuby のソース（サブモジュール込み）。動作を確かめたのはタグ `4.0.5` です

```sh
git clone --recurse-submodules --branch 4.0.5 https://github.com/picoruby/picoruby.git ~/src/picoruby
export PICORUBY_ROOT=~/src/picoruby
export PATH="$(brew --prefix emscripten)/bin:$PATH"
```

## 手元で動かす

```sh
cd web
bundle install
npm install
bundle exec rake doctor      # PicoRuby・emcc・Node.js を確認
bundle exec rake             # Wasm と app.rb のバイトコードを generated/ に作る

cp .dev.vars.example .dev.vars   # INGEST_TOKEN を好きな値に書き換える
npm run db:local                 # ローカルの D1 に schema.sql と seed.sql を適用
npm run dev                      # http://localhost:8787/
```

`npm run dev`（`wrangler dev`）は起動時と `app.rb` の変更時に Rake を実行し直します。

別の端末から測定値を送ります。

```sh
export PLANTER_API_URL=http://127.0.0.1:8787
export PLANTER_TOKEN=<.dev.vars の INGEST_TOKEN>

ruby tools/post_reading.rb --device planter-1 --moisture 46 --volt 1.9 --raw 2161
echo '{"device":"planter-1","moisture":46,"volt":1.9,"raw":2161,"status":"ok"}' | ruby tools/post_reading.rb

curl http://127.0.0.1:8787/api/latest
curl 'http://127.0.0.1:8787/api/readings?device=planter-1&limit=10'
```

ブラウザ（スマートフォン向けの 1 列表示）で <http://localhost:8787/> を開くと、植物の写真・ニックネーム・種類、水分量・状態・ちょうどよい範囲・最終更新時刻と、
過去 24 時間のグラフが出ます。画面は 60 秒ごとに `/api/latest` と `/api/readings` を読み直します。

## Cloudflare に公開する

まだ実行していません。公開するときは次の順に進めます（Cloudflare へのログインが必要です）。

```sh
cd web
npx wrangler d1 create smart-planter
# 表示された database_id を wrangler.jsonc の d1_databases[0].database_id に書く

npx wrangler d1 execute smart-planter --remote --file schema.sql
npx wrangler d1 execute smart-planter --remote --file seed.sql
npx wrangler secret put INGEST_TOKEN    # 長いランダムな値を入力する
npm run check                           # wrangler deploy --dry-run
npm run deploy                          # wrangler deploy
```

公開後は、Raspberry Pi 5 の `PLANTER_API_URL` を `https://smart-planter.<アカウント>.workers.dev` にし、
`PLANTER_TOKEN` に `wrangler secret put` で入れた値を設定します。

## 固定している版

| もの | 版 |
|---|---|
| picoruby-cloudflare-template（gem） | 0.2.1 |
| picoruby-cloudflare-worker-wasm | 0.10.0（template 0.2.1 の既定） |
| mruby-rack | `afd805f1991b46639ce1fbb778820fe586155bc2`（template 0.2.1 の既定） |
| mruby-mustermann | `acc29b7a28721474ef07d40a6263a4806855fcd5` |
| picoruby-sinatra-covers（Sinatra 4.2.1 互換） | `70e96fc81153402b54c27bceb385bd9306717697` |
| PicoRuby（ビルド用） | 4.0.5 |
| @picoruby/wasm-wasi（ブラウザ、Funicular 0.5.2 入り） | 4.0.5 |
| Wrangler | 4.125.0（compatibility_date 2026-08-22） |

## メモ

- Funicular 0.5.2 の仮想 DOM は HTML 要素だけを作るので、グラフは Ruby で SVG の文字列を組み立て、
  `<img>` の data URI として表示しています。
- `.dev.vars` は Git に入れません（`.gitignore` 済み）。本番のトークンは `wrangler secret put` だけで設定します。
- picoruby-cloudflare-template 0.2.1 の README は PicoRuby `33540f66` を検証対象に挙げていますが、
  既定の worker-wasm 0.10.0 に含まれる mruby-time がそれより新しい mruby の API を使うため、
  その組み合わせではビルドできません。PicoRuby 4.0.5 ではビルドできます。
- 画面はスマートフォン向けです（幅 360〜430 px で 1 列、左右 16 px、ノッチなどの safe area を避ける）。PC では幅 560 px で中央に表示します。

## 写真のクレジット

`public/images/gajumaru.jpg` は、Wikimedia Commons の
[File:(MHNT) Ficus microcarpa 'Ginseng'.jpg](https://commons.wikimedia.org/wiki/File:(MHNT)_Ficus_microcarpa_%27Ginseng%27.jpg)
（撮影 Didier Descouens、[CC BY-SA 4.0](https://creativecommons.org/licenses/by-sa/4.0/)）を縮小したものです。
縮小した画像も CC BY-SA 4.0 で提供します。
