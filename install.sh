#!/usr/bin/env bash
#
# auto-mtr-pro-v2.sh
# 一键 mtr 测试 + 自动分析（国家 / 区域 / 骨干 / 评分）
# by ChatGPT & Mevu

set -e

# ---------- 工具函数 ----------

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_mtr() {
  echo "[*] 正在检查 mtr 是否已安装..."
  if command_exists mtr; then
    echo "[✓] 已检测到 mtr，跳过安装。"
    return 0
  fi

  echo "[*] 未检测到 mtr，尝试自动安装..."

  if command_exists apt-get; then
    echo "[*] 检测到 apt-get（Debian/Ubuntu 系）"
    sudo apt-get update -y && \
    (sudo apt-get install -y mtr-tiny || sudo apt-get install -y mtr)
  elif command_exists yum; then
    echo "[*] 检测到 yum（CentOS/RHEL 系）"
    sudo yum install -y mtr
  elif command_exists dnf; then
    echo "[*] 检测到 dnf（CentOS/RHEL/Fedora 系）"
    sudo dnf install -y mtr
  elif command_exists pacman; then
    echo "[*] 检测到 pacman（Arch 系）"
    sudo pacman -Sy --noconfirm mtr
  else
    echo "[×] 无法识别的包管理器，不能自动安装 mtr，请自己手动安装后再运行本脚本。"
    exit 1
  fi

  if command_exists mtr; then
    echo "[✓] mtr 安装成功。"
  else
    echo "[×] mtr 安装失败，请手动检查。"
    exit 1
  fi
}

# ---------- 主逻辑 ----------

install_mtr

echo
read -rp "请输入要测试的目标 IP 或域名: " TARGET

if [ -z "$TARGET" ]; then
  echo "[×] 目标不能为空。"
  exit 1
fi

read -rp "请输入探测次数（默认 100，回车使用默认）: " COUNT
if [ -z "$COUNT" ]; then
  COUNT=100
fi

REPORT_FILE="/tmp/mtr_report_${TARGET//[^a-zA-Z0-9_.-]/_}.txt"

echo
echo "[*] 开始使用 mtr 测试目标：$TARGET"
echo "[*] 命令：mtr -rwzbc $COUNT $TARGET"
echo
echo "⏳ 开始检测（预计 ${COUNT/10}～${COUNT/5} 秒）..."

# 小旋转动画
spin='-\|/'
i=0
(
  while true; do
    i=$(( (i+1) %4 ))
    printf "\r正在分析数据 %s" "${spin:$i:1}"
    sleep 0.2
  done
) &
SPIN_PID=$!

# 运行 mtr
if [ "$EUID" -ne 0 ]; then
  sudo mtr -rwzbc "$COUNT" "$TARGET" > "$REPORT_FILE"
else
  mtr -rwzbc "$COUNT" "$TARGET" > "$REPORT_FILE"
fi

# 停止动画
kill "$SPIN_PID" >/dev/null 2>&1 || true
printf "\r✔ 测试完成！                         \n\n"

echo "[✓] mtr 原始结果保存在：$REPORT_FILE"
echo

echo "================== 原始 MTR 报告 =================="
cat "$REPORT_FILE"
echo "==================================================="
echo

echo "================== 自动分析报告 ==================="

awk '
# ---------- 国家 & 区域识别 ----------

function detect_country(host,    h) {
  h = tolower(host)

  # 常见城市 / 机场缩写 / 机房标记
  if (h ~ /hongkong|hong kong|hkg[0-9]*|hkix/) return "HK"
  if (h ~ /taipei|tpe|hsinchu|taichung/) return "TW"
  if (h ~ /singapore|sin[0-9]*|sgp/) return "SG"
  if (h ~ /tokyo|tyo|osaka|kix|nagoya/) return "JP"
  if (h ~ /seoul|icn|incheon|busan/) return "KR"
  if (h ~ /beijing|bj-|pek|shanghai|sh-|sha|guangzhou|gz-|shenzhen|sz-/) return "CN"
  if (h ~ /frankfurt|fra[0-9]*/) return "DE"
  if (h ~ /munich|muc/) return "DE"
  if (h ~ /london|lon[0-9]*|ldn/) return "GB"
  if (h ~ /paris|cdg/) return "FR"
  if (h ~ /amsterdam|ams[0-9]*/) return "NL"
  if (h ~ /madrid|mad/) return "ES"
  if (h ~ /rome|milano|mxp|fco/) return "IT"
  if (h ~ /stockholm|sto|arn/) return "SE"
  if (h ~ /oslo/) return "NO"
  if (h ~ /copenhagen|kastrup|cph/) return "DK"
  if (h ~ /zurich|zrh|geneva/) return "CH"
  if (h ~ /warsaw|waw/) return "PL"
  if (h ~ /prague|praha/) return "CZ"
  if (h ~ /vienna|vie/) return "AT"
  if (h ~ /moscow|msk/) return "RU"
  if (h ~ /sydney|syd|melbourne|mel|brisbane|bne/) return "AU"
  if (h ~ /auckland|akl|wellington/) return "NZ"

  if (h ~ /(newyork|nyc|nyc[0-9]*|ny[0-9]*\.|\.ny\.)/) return "US"
  if (h ~ /losangeles|lax/) return "US"
  if (h ~ /sanJose|sjc|sfo|sanfrancisco/) return "US"
  if (h ~ /seattle|sea/) return "US"
  if (h ~ /chicago|chi/) return "US"
  if (h ~ /dallas|dal|dfw/) return "US"
  if (h ~ /atlanta|atl/) return "US"
  if (h ~ /miami|mia/) return "US"
  if (h ~ /\.us/) return "US"

  if (h ~ /toronto|yyt|yyz|montreal|yul|vancouver|yvr/) return "CA"
  if (h ~ /\.ca/) return "CA"

  if (h ~ /dubai|dxb|abu-dhabi|auh/) return "AE"
  if (h ~ /riyadh|jedda/) return "SA"
  if (h ~ /doha|qatar/) return "QA"
  if (h ~ /telaviv|tel-aviv/) return "IL"
  if (h ~ /istanbul/) return "TR"

  if (h ~ /mumbai|bombay|delhi|bangalore|blr|chennai/) return "IN"
  if (h ~ /kualaLumpur|kualalumpur|kln|kul/) return "MY"
  if (h ~ /bangkok|bkk/) return "TH"
  if (h ~ /manila|mnl/) return "PH"
  if (h ~ /jakarta|jkt/) return "ID"
  if (h ~ /hanoi|saigon|hochiminh/) return "VN"

  if (h ~ /saoPaulo|saopaulo|gru|rio|rj-/) return "BR"
  if (h ~ /\.br/) return "BR"
  if (h ~ /mexico|mexicoCity|mexico-city/) return "MX"
  if (h ~ /\.ar/) return "AR"
  if (h ~ /\.cl/) return "CL"

  if (h ~ /johannesburg|jnb|capeTown|cpt/) return "ZA"
  if (h ~ /\.za/) return "ZA"
  if (h ~ /nairobi/) return "KE"
  if (h ~ /lagos/) return "NG"

  # 通过 TLD 粗略识别
  if (h ~ /\.hk/) return "HK"
  if (h ~ /\.tw/) return "TW"
  if (h ~ /\.jp/) return "JP"
  if (h ~ /\.kr/) return "KR"
  if (h ~ /\.cn/) return "CN"
  if (h ~ /\.sg/) return "SG"
  if (h ~ /\.de/) return "DE"
  if (h ~ /\.uk|\.co\.uk/) return "GB"
  if (h ~ /\.fr/) return "FR"
  if (h ~ /\.nl/) return "NL"
  if (h ~ /\.es/) return "ES"
  if (h ~ /\.it/) return "IT"
  if (h ~ /\.se/) return "SE"
  if (h ~ /\.no/) return "NO"
  if (h ~ /\.dk/) return "DK"
  if (h ~ /\.ch/) return "CH"
  if (h ~ /\.pl/) return "PL"
  if (h ~ /\.cz/) return "CZ"
  if (h ~ /\.at/) return "AT"
  if (h ~ /\.ru/) return "RU"
  if (h ~ /\.au/) return "AU"
  if (h ~ /\.nz/) return "NZ"
  if (h ~ /\.ae/) return "AE"
  if (h ~ /\.sa/) return "SA"
  if (h ~ /\.qa/) return "QA"
  if (h ~ /\.il/) return "IL"
  if (h ~ /\.tr/) return "TR"
  if (h ~ /\.in/) return "IN"
  if (h ~ /\.my/) return "MY"
  if (h ~ /\.th/) return "TH"
  if (h ~ /\.ph/) return "PH"
  if (h ~ /\.id/) return "ID"
  if (h ~ /\.vn/) return "VN"
  if (h ~ /\.br/) return "BR"
  if (h ~ /\.mx/) return "MX"
  if (h ~ /\.ar/) return "AR"
  if (h ~ /\.cl/) return "CL"
  if (h ~ /\.ke/) return "KE"
  if (h ~ /\.ng/) return "NG"

  return "UN"
}

function country_name(c) {
  if (c=="HK") return "中国香港"
  if (c=="TW") return "中国台湾"
  if (c=="CN") return "中国大陆"
  if (c=="JP") return "日本"
  if (c=="KR") return "韩国"
  if (c=="SG") return "新加坡"
  if (c=="DE") return "德国"
  if (c=="GB") return "英国"
  if (c=="FR") return "法国"
  if (c=="NL") return "荷兰"
  if (c=="ES") return "西班牙"
  if (c=="IT") return "意大利"
  if (c=="SE") return "瑞典"
  if (c=="NO") return "挪威"
  if (c=="DK") return "丹麦"
  if (c=="CH") return "瑞士"
  if (c=="PL") return "波兰"
  if (c=="CZ") return "捷克"
  if (c=="AT") return "奥地利"
  if (c=="RU") return "俄罗斯"
  if (c=="US") return "美国"
  if (c=="CA") return "加拿大"
  if (c=="AE") return "阿联酋"
  if (c=="SA") return "沙特阿拉伯"
  if (c=="QA") return "卡塔尔"
  if (c=="IL") return "以色列"
  if (c=="TR") return "土耳其"
  if (c=="IN") return "印度"
  if (c=="MY") return "马来西亚"
  if (c=="TH") return "泰国"
  if (c=="PH") return "菲律宾"
  if (c=="ID") return "印尼"
  if (c=="VN") return "越南"
  if (c=="BR") return "巴西"
  if (c=="MX") return "墨西哥"
  if (c=="AR") return "阿根廷"
  if (c=="CL") return "智利"
  if (c=="AU") return "澳大利亚"
  if (c=="NZ") return "新西兰"
  if (c=="ZA") return "南非"
  if (c=="KE") return "肯尼亚"
  if (c=="NG") return "尼日利亚"
  if (c=="UN") return "未知国家"
  return c
}

# 大区：东亚、东南亚、南亚、欧洲、北美、南美、中东、非洲、澳洲 等
function country_region(c) {
  if (c=="CN"||c=="HK"||c=="TW"||c=="JP"||c=="KR") return "EAS"   # East Asia
  if (c=="SG"||c=="MY"||c=="TH"||c=="PH"||c=="ID"||c=="VN") return "SEAS"  # Southeast Asia
  if (c=="IN") return "SAS"  # South Asia
  if (c=="DE"||c=="GB"||c=="FR"||c=="NL"||c=="ES"||c=="IT"||c=="SE"||c=="NO"||c=="DK"||c=="CH"||c=="PL"||c=="CZ"||c=="AT"||c=="RU") return "EU"
  if (c=="US"||c=="CA") return "NA"
  if (c=="BR"||c=="MX"||c=="AR"||c=="CL") return "SA"
  if (c=="AE"||c=="SA"||c=="QA"||c=="IL"||c=="TR") return "ME"
  if (c=="ZA"||c=="KE"||c=="NG") return "AF"
  if (c=="AU"||c=="NZ") return "OC"
  return "OT"
}

# ---------- 骨干识别 ----------

function detect_carrier(host,    h) {
  h = tolower(host)
  if (h ~ /ntt/) return "NTT"
  if (h ~ /kddi/) return "KDDI"
  if (h ~ /softbank/) return "SoftBank"
  if (h ~ /iij/) return "IIJ"
  if (h ~ /telia/) return "Telia"
  if (h ~ /gtt/) return "GTT"
  if (h ~ /cogentco|cogent/) return "Cogent"
  if (h ~ /he\.net|hopone/) return "HE"
  if (h ~ /zayo/) return "Zayo"
  if (h ~ /level3|centurylink|lumen/) return "Lumen"
  if (h ~ /pccw|netvigator/) return "PCCW"
  if (h ~ /hgc/) return "HGC"
  if (h ~ /singtel/) return "Singtel"
  if (h ~ /tata/) return "Tata"
  if (h ~ /cn2/ || host ~ /^59\.43\./) return "China Telecom CN2"
  if (h ~ /chinatelecom|ctc/) return "China Telecom"
  if (h ~ /chinaunicom|cuc|cun/) return "China Unicom"
  if (h ~ /cmcc|china ?mobile/) return "China Mobile"
  if (h ~ /globalsecurelayer|gsl/) return "GSL"
  if (h ~ /nube\.sh|nube/) return "Nube"
  if (h ~ /dmit/) return "DMIT"
  if (h ~ /aliyun|alibaba/) return "Alibaba Cloud"
  if (h ~ /tencent|qcloud|cloud\.tencent/) return "Tencent Cloud"
  if (h ~ /google|googlenet/) return "Google"
  if (h ~ /amazon|aws/) return "AWS"
  if (h ~ /azure|microsoft/) return "Azure"
  return ""
}

# ---------- 其他小工具 ----------

function max(a,b){ return (a>b)?a:b }
function min(a,b){ return (a<b)?a:b }

# ---------- 解析 mtr 主逻辑 ----------

BEGIN {
  hopCount = 0
  maxJump = 0
  prevAvg = -1
}

# 匹配每一跳
/^[ ]*[0-9]+\./ {
  hopCount++
  asn  = $2
  host = $3

  loss  = $(NF-6); gsub(/%/, "", loss)
  snt   = $(NF-5)
  last  = $(NF-4)
  avg   = $(NF-3)
  best  = $(NF-2)
  wrst  = $(NF-1)
  stdev = $NF

  hops[hopCount]      = host
  hop_avg[hopCount]   = avg + 0
  hop_loss[hopCount]  = loss + 0
  hop_country[hopCount] = detect_country(host)
  hop_region[hopCount]  = country_region(hop_country[hopCount])

  carrier = detect_carrier(host)
  if (carrier != "") carriers[carrier] = 1

  if (prevAvg >= 0) {
    diff = (avg + 0) - prevAvg
    if (diff > maxJump) {
      maxJump = diff
      maxHop  = hopCount
    }
  }
  prevAvg = avg + 0

  # 末跳记录
  dest_loss  = loss + 0
  dest_snt   = snt + 0
  dest_last  = last + 0
  dest_avg   = avg + 0
  dest_best  = best + 0
  dest_wrst  = wrst + 0
  dest_stdev = stdev + 0
  dest_host  = host
}

END {
  if (hopCount == 0) {
    print "[×] 没解析到任何跳数，可能 mtr 运行失败。"
    exit
  }

  # 寻找首尾有效国家
  srcC="UN"
  for (i=1;i<=hopCount;i++){
    if (hop_country[i]!="UN"){ srcC=hop_country[i]; break }
  }
  dstC="UN"
  for (i=hopCount;i>=1;i--){
    if (hop_country[i]!="UN"){ dstC=hop_country[i]; break }
  }
  srcR = country_region(srcC)
  dstR = country_region(dstC)

  print "目标节点: " dest_host
  print "发送次数: " dest_snt
  print "丢包率  : " dest_loss "%";
  printf "延迟统计: Avg=%.1f ms, Best=%.1f ms, Worst=%.1f ms, 抖动(StDev)=%.1f ms\n", dest_avg, dest_best, dest_wrst, dest_stdev
  print ""

  print "【区域判断】"
  print "- 源端国家: " country_name(srcC) "（" srcC "，大区 " srcR "）"
  print "- 目标国家: " country_name(dstC) "（" dstC "，大区 " dstR "）"
  print ""

  # ---------- 延迟评价（国家+区域组合） ----------

  print "【延迟评价】"
  avg = dest_avg + 0
  rating  = ""
  comment = ""

  # 同一国家
  if (srcC!=\"UN\" && srcC==dstC) {
    if (avg <= 2)      { rating=\"极佳\"; comment=\"同机房 / 同城级，延迟几乎极限，非常适合一切延迟敏感业务。\" }
    else if (avg <= 5) { rating=\"优秀\"; comment=\"同城 / 同国骨干质量很好，适合绝大部分场景。\" }
    else if (avg <=10) { rating=\"良好\"; comment=\"本地网络基本正常，如为同城可怀疑轻微绕路。\" }
    else               { rating=\"一般\"; comment=\"同国 RTT 偏高，可能绕路或结构复杂，建议排查。\" }
  }

  # 港 ↔ 新
  else if ((srcC==\"HK\" && dstC==\"SG\") || (srcC==\"SG\" && dstC==\"HK\")) {
    if (avg <= 35)      { rating=\"优秀\"; comment=\"港-新 30~35ms 属于高质量骨干表现。\" }
    else if (avg <= 50) { rating=\"良好\"; comment=\"港-新 延迟尚可，可能设备多一点或轻微绕路。\" }
    else                { rating=\"偏高\"; comment=\"港-新 RTT 偏高，多半是绕路或走廉价线路。\" }
  }

  # 华东/港 ↔ 日本（大部分你关心的沪日）
  else if ((srcR==\"EAS\" && dstC==\"JP\") || (dstR==\"EAS\" && srcC==\"JP\")) {
    if (avg <= 25)      { rating=\"优秀\"; comment=\"东亚 ↔ 日本 20~25ms 为高质量专线 / 优质骨干水准。\" }
    else if (avg <= 35) { rating=\"良好\"; comment=\"东亚 ↔ 日本 延迟正常。\" }
    else                { rating=\"偏高\"; comment=\"东亚 ↔ 日本 RTT 偏高，疑似绕路或走低质骨干。\" }
  }

  # 东亚 / 东南亚 内部
  else if ((srcR==\"EAS\" && dstR==\"EAS\") || (srcR==\"SEAS\" && dstR==\"SEAS\") || (srcR==\"EAS\" && dstR==\"SEAS\") || (srcR==\"SEAS\" && dstR==\"EAS\")) {
    if (avg <= 30)      { rating=\"优秀\"; comment=\"东亚 / 东南亚 区域内 RTT ≤30ms，非常优秀。\" }
    else if (avg <= 60) { rating=\"良好\"; comment=\"区域内 RTT 正常，大多数业务可接受。\" }
    else                { rating=\"偏高\"; comment=\"区域内 RTT 偏高，可能多次绕路或走差线路。\" }
  }

  # 亚洲 ↔ 欧洲
  else if (((srcR==\"EAS\"||srcR==\"SEAS\"||srcR==\"SAS\") && dstR==\"EU\") || ((dstR==\"EAS\"||dstR==\"SEAS\"||dstR==\"SAS\") && srcR==\"EU\")) {
    if (avg <= 190)      { rating=\"优秀\"; comment=\"亚-欧 RTT 较低，说明走了比较直的跨亚欧骨干。\" }
    else if (avg <= 230) { rating=\"良好\"; comment=\"亚-欧 RTT 正常，多数业务可接受。\" }
    else                 { rating=\"偏高\"; comment=\"亚-欧 RTT 偏高，可能走奇怪路径或拥塞严重。\" }
  }

  # 亚洲 ↔ 北美
  else if (((srcR==\"EAS\"||srcR==\"SEAS\"||srcR==\"SAS\") && dstR==\"NA\") || ((dstR==\"EAS\"||dstR==\"SEAS\"||dstR==\"SAS\") && srcR==\"NA\")) {
    if (avg <= 160)      { rating=\"优秀\"; comment=\"亚-美 RTT 较好，多半走优质跨太平洋骨干。\" }
    else if (avg <= 220) { rating=\"良好\"; comment=\"亚-美 RTT 常见水平，适合大多非实时业务。\" }
    else                 { rating=\"偏高\"; comment=\"亚-美 RTT 偏高，可能绕路多次或骨干质量差。\" }
  }

  # 欧洲 ↔ 北美
  else if ((srcR==\"EU\" && dstR==\"NA\") || (srcR==\"NA\" && dstR==\"EU\")) {
    if (avg <= 90)       { rating=\"优秀\"; comment=\"欧-美 RTT 很好，跨大西洋骨干质量高。\" }
    else if (avg <= 130) { rating=\"良好\"; comment=\"欧-美 RTT 正常。\" }
    else                 { rating=\"偏高\"; comment=\"欧-美 RTT 偏高，可能绕路或拥塞。\" }
  }

  # 欧洲内部
  else if (srcR==\"EU\" && dstR==\"EU\") {
    if (avg <= 30)      { rating=\"优秀\"; comment=\"欧洲区域 30ms 内，表现不错。\" }
    else if (avg <= 60) { rating=\"良好\"; comment=\"欧洲内部 RTT 正常。\" }
    else                { rating=\"偏高\"; comment=\"欧洲内部 RTT 偏高，可能绕路。\" }
  }

  # 北美内部
  else if (srcR==\"NA\" && dstR==\"NA\") {
    if (avg <= 40)      { rating=\"优秀\"; comment=\"北美区域 40ms 内，表现很好。\" }
    else if (avg <= 80) { rating=\"良好\"; comment=\"北美内部 RTT 正常。\" }
    else                { rating=\"偏高\"; comment=\"北美内部 RTT 偏高，可能跨东西海岸绕行。\" }
  }

  # 其它跨洲（南美 / 非洲 / 中东 / 澳洲等）
  else if (srcR!=dstR) {
    if (avg <= 180)      { rating=\"大致良好\"; comment=\"跨大洲 RTT 不算高，多数用途可接受。\" }
    else if (avg <= 260) { rating=\"一般\"; comment=\"跨洲 RTT 偏大但尚可，适合非实时业务。\" }
    else                 { rating=\"较差\"; comment=\"跨洲 RTT 很高，建议仅用作备线或容灾。\" }
  }

  # fallback
  else {
    if (avg <= 50)       { rating=\"大致良好\"; comment=\"整体 RTT 不算高，多数业务可用。\" }
    else if (avg <= 120) { rating=\"一般\"; comment=\"中等偏上的网络质量。\" }
    else                 { rating=\"较差\"; comment=\"延迟较高，可能跨洲严重或绕路明显。\" }
  }

  print "- 综合延迟评价: " rating
  print "- 说明: " comment
  print ""

  # ---------- 稳定性 / 丢包 ----------

  print "【稳定性评价】"
  if (dest_stdev <= 3)      print "- 抖动很小，线路非常稳定，适合延迟敏感业务。"
  else if (dest_stdev <=10) print "- 抖动中等，偶尔有尖峰，一般业务可接受。"
  else                      print "- 抖动较大，网络波动明显，可能有拥塞或路由不稳。"
  print ""

  print "【丢包评价】"
  if (dest_loss == 0)        print "- 末跳无丢包，整体连通性良好。"
  else if (dest_loss < 3)    print "- 少量丢包（<3%），大部分场景仍可接受。"
  else if (dest_loss < 10)   print "- 丢包偏高（3%~10%），慎重用于重要业务。"
  else                        print "- 丢包严重（>=10%），不适合承载关键或实时业务。"
  print ""

  # ---------- 最大延迟跳升点 ----------

  print "【可能的跨境 / 出海 / 瓶颈节点】"
  if (maxHop > 1) {
    printf "- 第 %d 跳：%s\n", maxHop, hops[maxHop]
    printf "  与上一跳平均延迟相差约 %.1f ms。\n", maxJump
  } else {
    print "- 未发现明显的延迟跳升点。"
  }
  print ""

  # ---------- 骨干 / 运营商 ----------

  print "【疑似涉及的骨干 / 运营商】"
  hasCarrier = 0
  for (c in carriers) {
    print "- " c
    hasCarrier = 1
  }
  if (!hasCarrier) {
    print "- 未能从主机名中识别出明显的骨干（很多运营商会隐藏信息）。"
  }
  print ""

  # ---------- 综合评分 ----------

  score = 100
  score -= dest_avg / 5
  score -= dest_stdev * 2
  score -= dest_loss * 2
  score -= maxJump / 5

  if (score < 0) score = 0
  if (score > 100) score = 100

  printf "【综合线路评分】\n- 评分: %.0f / 100（基于延迟 / 抖动 / 丢包 / 大跳变的启发式模型，仅供参考）\n", score
  print ""
  print "（提示：中间某跳显示 100% loss 但最后一跳无丢包，多半是该路由器屏蔽 ICMP，不代表真实丢包。）"
}
' "$REPORT_FILE"

echo "==================================================="
echo
echo "[✓] 分析结束。你可以根据上面的自动报告快速判断这条线路质量。"
