require "adc"

# センサーの電圧の目安（例）。自分のセンサーで測った値に置き換える
DRY_V = 2.6   # 乾いた土のときの電圧
WET_V = 1.1   # 水を含んだ土のときの電圧

adc = ADC.new(2)          # P0.02（AIN0）
raw = adc.read_raw        # 0〜4095
volt = adc.read_voltage   # 0.0〜3.6 V

moisture_pct = (DRY_V - volt) * 100 / (DRY_V - WET_V)
moisture_pct = 0 if moisture_pct < 0
moisture_pct = 100 if moisture_pct > 100

puts "raw=#{raw} volt=#{volt} moisture=#{moisture_pct.to_i}%"
if moisture_pct < 30
  status = "dry"
elsif moisture_pct < 60
  status = "ok"
else
  status = "wet"
end

puts "status=#{status} moisture=#{moisture_pct.to_i}%"
