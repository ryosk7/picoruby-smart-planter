# Raspberry Pi 5 の設定（OpenThread Border Router）

Raspberry Pi 5 を Thread ネットワーク「SoilNet」の親（Border Router）にして、植物の側のボードから届く値を受け取るまでの手順です。
本書（4 章）では流れを説明し、細かい設定とスクリプトはこのディレクトリに置いています。

| ファイル | 内容 |
|---|---|
| `setup-otbr.sh` | ot-br-posix（OpenThread Border Router）のインストール |
| `otbr-agent.default` | `/etc/default/otbr-agent` の例（RCP の USB シリアルを指定） |
| `form-network.sh` | SoilNet をつくり、植物の側に渡す値（データセットと宛先アドレス）を表示する |
| `soil_receiver.py` | UDP 50000 番で値を受け取り、`~/soil.log` に書き、アプリ（`web/`）に転送する |
| `soil-receiver.env.example` | 転送先のアプリの URL とトークン（`/etc/default/soil-receiver`） |
| `soil-receiver.service` | 上のプログラムを常に動かす systemd のサービス |
| `rcp/README.md` | 2 台目の ISP1807 に書き込む RCP ファームウェアのビルドと書き込み |

## 0. 用意するもの

- Raspberry Pi 5（8GB）、microSD カード（本書では 60GB）
- Raspberry Pi OS Lite（64-bit、Debian 13 trixie）
- RCP にする 2 台目の ISP1807 Dev Board と USB ケーブル

## 1. OS を書き込む

Raspberry Pi Imager で Raspberry Pi OS Lite（64-bit）を書き込みます。
カスタマイズ設定で、ホスト名とユーザー名（本書では `otbr`）、Wi-Fi、SSH（公開鍵）を設定しておくと、モニターをつながずに作業できます。
起動したら `ssh otbr@otbr.local` で入ります。

## 2. OTBR をインストールする

```console
curl -O https://raw.githubusercontent.com/ryosk7/picoruby-smart-planter/main/raspberrypi/setup-otbr.sh
bash setup-otbr.sh 2>&1 | tee install-otbr.log
```

数十分かかります。最後に `OTBR_INSTALL_DONE` と出れば完了です。

## 3. RCP を書き込んでつなぐ

`rcp/README.md` の手順で 2 台目の ISP1807 に `ot-rcp` を書き込み、Raspberry Pi 5 に USB でつなぎます。

## 4. otbr-agent に RCP を設定する

```console
ls /dev/serial/by-id/
sudo cp otbr-agent.default /etc/default/otbr-agent   # <SERIAL> を自分のボードのシリアルに書き換える
sudo systemctl restart otbr-agent
sudo ot-ctl rcp version
sudo ot-ctl state
```

`rcp version` に OpenThread のバージョンが表示されれば、RCP とつながっています。

## 5. SoilNet をつくる

```console
bash form-network.sh
```

`state: leader` と表示され、続いて DATASET（16 進数の長い文字列）と DEST（`fd` で始まる IPv6 アドレス）が表示されます。
この 2 つを、植物の側の `app.rb` の `DATASET` と `DEST` に貼ります。
データセットにはネットワークの鍵が含まれるので、人に見せたり公開したりしないでください。

## 6. 受信サービスを動かす

```console
cp soil_receiver.py ~/
sudo cp soil-receiver.service /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now soil-receiver
```

アプリ（5 章）を公開したら、`soil-receiver.env.example` を `/etc/default/soil-receiver` にコピーして URL とトークンを書き、`sudo chmod 600 /etc/default/soil-receiver` と `sudo systemctl restart soil-receiver` を実行します。
これで、届いた値がアプリにも送られます。

## 7. 植物の側のボードを起動する

植物の側の ISP1807（R2P2-nRF の Thread 版）に、リポジトリの `app.rb` を `/home/app.rb` として書き込み、再起動します。
`DATASET` と `DEST` は、手順 5 で表示された値に書き換えてから書き込みます。

R2P2-nRF の USB ドライブ（`R2P2 NRF52`）は `/home` とは別の領域なので、そこにコピーしても `/home/app.rb` にはなりません。
起動時に `/home/app.rb` が動いているときは、リセット直後の「Press 's' to skip」で `s` を押すと shell に入れます。
本書の執筆時は、shell の `irb` から `File.open("/home/app.rb", "w")` で、短く区切った ASCII の文字列を書き込みました。

> **注意（2026-11-22）**：irb から長いファイル（日本語のコメントを含む `app.rb` など）を続けて書き込むと、途中でボードが再起動することを確認しています。
> 書き込むときは、日本語のコメントを消した短いファイルにするか、何回かに分けてください。
> R2P2-nRF で `/home` に確実にファイルを置ける方法は、いま用意しているところです。

## 8. 届いたか確かめる

```console
sudo ot-ctl child table     # 植物の側のボードが子としてつながっている
tail -f ~/soil.log          # 60 秒ごとに 1 行ずつ増える
```

`2026-11-20T11:29:03 fdf9:... moisture=46 volt=1.9 raw=2161 status=ok` のような行が増えていけば完成です。
