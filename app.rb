# 植物の側の ISP1807 Dev Board（R2P2-nRF の Thread 版）で動かす。
# /home/app.rb に置くと、起動したときに自動で実行される。
# 土壌湿度計の値を読み、60 秒ごとに Thread（UDP）で Raspberry Pi 5 に送る。
require "adc"

# Raspberry Pi 5 で raspberrypi/form-network.sh を実行して表示された値に置き換える
DATASET = "ここに dataset active -x の値を貼る"
DEST = "ここに Raspberry Pi 5 の ML-EID を貼る"
PORT = 50000
INTERVAL = 60

# センサーの電圧の目安（例）。自分のセンサーで測った値に置き換える
DRY_V = 2.6
WET_V = 1.1

# 16 進数の文字列を、バイト列に直す
tlvs = ""
i = 0
while i < DATASET.size
  tlvs << DATASET[i, 2].to_i(16).chr
  i += 2
end

OpenThread.init
OpenThread.configure(tlvs: tlvs)
OpenThread.start
attached = false
while !attached
  begin
    attached = OpenThread.wait_attached(timeout_ms: 30000)
  rescue OpenThread::ConnectTimeout
    puts "waiting for Thread..."
  end
end
puts "attached as #{OpenThread.role}"

adc = ADC.new(2)            # P0.02（AIN0）
udp = OpenThread::UDP.new
udp.bind(50001)

while true
  raw = adc.read_raw
  volt = adc.read_voltage
  moisture_pct = (DRY_V - volt) * 100 / (DRY_V - WET_V)
  moisture_pct = 0 if moisture_pct < 0
  moisture_pct = 100 if moisture_pct > 100

  if moisture_pct < 30
    status = "dry"
  elsif moisture_pct < 60
    status = "ok"
  else
    status = "wet"
  end

  msg = "moisture=#{moisture_pct.to_i} volt=#{volt} raw=#{raw} status=#{status}"
  puts msg
  begin
    udp.send(msg, 0, DEST, PORT)
  rescue => e
    puts "send failed: #{e.message}"
  end
  sleep INTERVAL
end
