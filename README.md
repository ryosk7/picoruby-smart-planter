# picoruby-smart-planter

技術書典21で頒布する『PicoRubyでつくる スマートプランター』（内田涼介 / ryosk7）のサンプルコードです。

## ファイル

| ファイル | 内容 | 本書 |
|---|---|---|
| `soil_moisture.rb` | 土壌センサーの電圧をADCで読み取り、水分量（%）と植物の状態（dry / ok / wet）を表示する | 第2章 |
| `test/index.html` | PicoRuby.wasm で `soil_moisture.rb` を動かす確認ページ（ADCを決まった電圧を返す偽物に置き換える） | — |

## 使うもの

- Switch Science ISP1807 Dev Board（nRF52840）
- Lazentra 土壌湿度計 電容量式土壌水分センサー（ABM141）
- R2P2-nRF（nRF52840 で PicoRuby を動かすファームウェア。下の「ファームウェア」を参照）

## 配線

| センサー | ISP1807 Dev Board |
|---|---|
| VCC | 3V3 |
| GND | GND |
| AO | P0.02（AIN0） |

## ファームウェア（nRF52840）

`firmware/` に、本書で使ったファームウェアのリポジトリを、本書の時点のコミットでサブモジュールとして入れています。

| リポジトリ | 役割 | コミット |
|---|---|---|
| [R2P2-nRF](https://github.com/ryosk7/R2P2-nRF) | nRF52840 で R2P2（PicoRuby の shell と irb）を動かすファームウェア。USB 接続、ビルドと書き込みの手順 | `4ae66b6` |
| [picoruby-nRF](https://github.com/ryosk7/picoruby-nRF) | PicoRuby を nRF52 で動かす土台。起動処理、HAL、nRF5 SDK の設定 | `877f1bb` |

```console
git clone --recurse-submodules https://github.com/ryosk7/picoruby-smart-planter.git
```

ビルドと書き込みの手順は、[R2P2-nRF の README](https://github.com/ryosk7/R2P2-nRF) を見てください。
nRF52840 対応の進み具合は、PicoRuby の issue [#399 PicoRuby porting for nRF52840](https://github.com/picoruby/picoruby/issues/399) のロードマップにまとめています。

## 使い方

1. `soil_moisture.rb` をボードの PicoRuby に書き込んで実行します。
2. `DRY_V` と `WET_V` は例の値です。乾いた土と、水をたっぷり含ませた土にセンサーを挿して `read_voltage` の値を測り、その値に置き換えてください。

## ブラウザで動作を確かめる

ボードがなくても、PicoRuby.wasm で計算と判定の動きを確かめられます。
リポジトリのルートで HTTP サーバーを起動し、`test/index.html` を開くと、ブラウザの開発者ツールのコンソールに結果が出ます。

```console
ruby -run -e httpd . -p 8000
# http://localhost:8000/test/index.html を開く
```

ADC は、いくつかの電圧を順に返す偽物に置き換えています。
実機（nRF52840 上の PicoRuby）での読み取りは、ボードとセンサーをつないで確かめてください。

## ライセンス

MIT License
