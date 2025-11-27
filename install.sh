#!/usr/bin/env bash
# hipb
# 一键 MTR + 国家地区识别 + ipinfo 源/目标归属地 + 骨干识别 (T1/T2/T3) + 禁 ICMP / 不可达识别 + 评分

set -e

# ---------------- 基础函数 ----------------
command_exists() { command -v "$1" >/dev/null 2>&1; }

install_mtr() {
  echo "[*] 正在检查 mtr 是否已安装..."
  if command_exists mtr; then
    echo "[✓] 已检测到 mtr"
    return
  fi

  echo "[*] 未检测到 mtr，自动安装中..."

  if command_exists apt-get; then
    sudo apt-get update -y
    sudo apt-get install -y mtr-tiny || sudo apt-get install -y mtr
  elif command_exists yum; then
    sudo yum install -y mtr
  elif command_exists dnf; then
    sudo dnf install -y mtr
  elif command_exists pacman; then
    sudo pacman -Sy --noconfirm mtr
  else
    echo "[×] 未识别的包管理器，请手动安装 mtr"
    exit 1
  fi

  echo "[✓] mtr 安装完成"
}

install_mtr

echo
read -rp "请输入目标 IP 或域名: " TARGET
if [ -z "$TARGET" ]; then
  echo "[×] 不能为空"
  exit 1
fi

read -rp "探测次数（默认 100）: " COUNT
COUNT=${COUNT:-100}

read -rp "是否显示原始 MTR 报告？(y/N): " SHOW_RAW
SHOW_RAW=${SHOW_RAW,,}

# ---------------- ipinfo 查询 ----------------
echo "[*] 正在获取本机 IP 归属地..."
SRC_INFO=$(curl -s ipinfo.io || true)
SRC_COUNTRY=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"country":/ {print $4; exit}')
SRC_CITY=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"city":/ {print $4; exit}')
SRC_ORG=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"org":/ {print $4; exit}')

echo "[*] 正在获取目标 IP 归属地..."
DST_INFO=$(curl -s "ipinfo.io/$TARGET" || true)
DST_COUNTRY=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"country":/ {print $4; exit}')
DST_CITY=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"city":/ {print $4; exit}')
DST_ORG=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"org":/ {print $4; exit}')

REPORT="/tmp/mtr_report_${TARGET//[^a-zA-Z0-9_.-]/_}.txt"

echo "[*] 正在测试：$TARGET"
echo "[*] mtr -rwzbc $COUNT $TARGET"
echo "💫 开始检测（请耐心等待）"

spin='-\|/'
i=0
(
  while true; do
    i=$(( (i+1)%4 ))
    printf "\r⏳ 检测分析运行中... %s" "${spin:$i:1}"
    sleep 0.2
  done
) &
SPIN=$!

if [ "$EUID" -ne 0 ]; then
  sudo mtr -rwzbc "$COUNT" "$TARGET" > "$REPORT"
else
  mtr -rwzbc "$COUNT" "$TARGET" > "$REPORT"
fi

kill "$SPIN" >/dev/null 2>&1 || true
echo -e "\n✔ 检测完成\n"

if [ "$SHOW_RAW" = "y" ] || [ "$SHOW_RAW" = "yes" ]; then
  echo "================ 原始 MTR 报告 ================"
  cat "$REPORT"
  echo "================================================"
  echo
fi

echo "================ 自动分析报告 ================"

# ---------------- AWK 分析逻辑 ----------------
awk -v SRC_COUNTRY="$SRC_COUNTRY" \
    -v SRC_CITY="$SRC_CITY" \
    -v SRC_ORG="$SRC_ORG" \
    -v DST_COUNTRY="$DST_COUNTRY" \
    -v DST_CITY="$DST_CITY" \
    -v DST_ORG="$DST_ORG" '
# -------- 国家识别（用于每跳，大致判断区域用） --------
function detect_country(host,    h) {
  h=tolower(host)

  # 香港 HK
  if (h~/hongkong|hong-kong|hkg[0-9]*|\.hkix\.net|\.hkix\./) return "HK"
  if (h~/pccw|netvigator|hgc\.com\.hk|i-cable|icable|hkt\.com|hkbnes/) return "HK"
  if (h~/\.hk$/ || h~/\.hk\./) return "HK"

  # 台湾 TW
  if (h~/hinet\.net|seed\.net\.tw|cht\.com\.tw|emome\.net|tfbnw\.net|tfn\.net\.tw/) return "TW"
  if (h~/dynamic-ip\.pni\.tw|\.pni\.tw/) return "TW"
  if (h~/\.tw$/ || h~/\.tw\./) return "TW"

  # 中国大陆 CN
  if (h~/beijing|bj-|pek/) return "CN"
  if (h~/shanghai|sh-|sha/) return "CN"
  if (h~/guangzhou|gz-/) return "CN"
  if (h~/shenzhen|sz-/) return "CN"
  if (h~/\.cn$/ || h~/\.cn\./) return "CN"

  # 日本 JP
  if (h~/tokyo|tyo|osaka|kix|nagoya/) return "JP"
  if (h~/\.jp$/ || h~/\.jp\./) return "JP"

  # 韩国 KR
  if (h~/seoul|icn|busan/) return "KR"
  if (h~/\.kr$/ || h~/\.kr\./) return "KR"

  # 新加坡 SG
  if (h~/singapore|sin[0-9]*|sgp/) return "SG"
  if (h~/\.sg$/ || h~/\.sg\./) return "SG"

  # 美国 US / 加拿大 CA / 欧洲若干
  if (h~/newyork|nyc|ny-*/) return "US"
  if (h~/losangeles|lax|sanjose|sjc|seattle|sea|chicago|chi|dallas|dfw|atlanta|atl|miami|mia/) return "US"
  if (h~/\.us$/ || h~/\.us\./) return "US"

  if (h~/toronto|yyz|montreal|yul|vancouver|yvr/) return "CA"
  if (h~/\.ca$/ || h~/\.ca\./) return "CA"

  if (h~/frankfurt|fra[0-9]*/) return "DE"
  if (h~/\.de$/ || h~/\.de\./) return "DE"
  if (h~/london|lon[0-9]*/) return "GB"
  if (h~/\.uk$/ || h~/\.co\.uk/) return "GB"
  if (h~/amsterdam|ams[0-9]*/) return "NL"
  if (h~/\.nl$/ || h~/\.nl\./) return "NL"
  if (h~/paris|cdg/) return "FR"
  if (h~/\.fr$/ || h~/\.fr\./) return "FR"

  # 其他一些
  if (h~/sydney|melbourne|brisbane|\.au/) return "AU"
  if (h~/johannesburg|cpt|\.za/) return "ZA"

  return "UN"
}

# -------- 区域大类 --------
function region(c){
  if (c ~ /HK|TW|CN|JP|KR/) return "EAS"
  if (c ~ /SG|MY|TH|PH|ID|VN|LA|KH|MM|BN|TL/) return "SEAS"
  if (c ~ /IN|PK|BD|LK|NP|BT|MV/) return "SAS"
  if (c ~ /DE|GB|FR|NL|ES|IT|SE|NO|AT|CZ|CH|PL|BE|LU|IE|FI|DK|PT|GR|RO|HU|BG|HR|SK|SI|EE|LV|LT|IS|MT|CY|UA|BY|RU/) return "EU"
  if (c ~ /US|CA|MX/) return "NA"
  if (c ~ /BR|AR|CL|PE|CO|VE|UY|PY|BO|EC|GY|SR|GF|FK/) return "SA"
  if (c ~ /AE|SA|QA|TR|IL|KW|BH|OM|JO|LB|IR|IQ|SY|YE/) return "ME"
  if (c ~ /ZA|EG|NG|KE|TZ|GH|MA|DZ|TN|ET|UG|CM|CI|SN|SD|LY|ZW|ZM|NA|BW|MW|MZ|AO|CD|GA/) return "AF"
  if (c ~ /AU|NZ|FJ|PG|SB|VU|NC|PF|WS|TO|KI|TV|NR/) return "OC"
  return "OT"
}

# -------- 骨干识别（T1/T2/T3） --------
# 返回: "T1|NTT" / "T2|China Telecom" / "T3|GSL"
function detect_backbone(host,    h){
  h = tolower(host)

  # Tier1
  if (h ~ /ntt\.net|\.ntt\.com/)               return "T1|NTT"
  if (h ~ /telia|se\.telia\.net|arelion/)      return "T1|Telia/Arelion"
  if (h ~ /gtt\.net/)                          return "T1|GTT"
  if (h ~ /cogentco\.com|\.cogent\./)          return "T1|Cogent"
  if (h ~ /he\.net|hurricane/)                 return "T1|Hurricane Electric"
  if (h ~ /level3|l3net|centurylink|lumen/)    return "T1|Lumen/Level3"
  if (h ~ /zayo/)                              return "T1|Zayo"
  if (h ~ /tatacommunications|tata\.|seabone/) return "T1|Tata/Sparkle"
  if (h ~ /orange|opentransit|oti/)            return "T1|Orange"
  if (h ~ /verizon|alter\.net/)                return "T1|Verizon"
  if (h ~ /comcast/)                           return "T1|Comcast"

  # Tier2：区域骨干 + 三大 + 大云/CDN
  if (h ~ /chinatelecom|chinanet|ctc|cn2|\.ctc\./)                 return "T2|China Telecom"
  if (h ~ /chinaunicom|cucc|cuc\.cn|unicom/)                       return "T2|China Unicom"
  if (h ~ /chinamobile|cmcc|cmi\.chinamobile\.com|cmi\.hk|cmi\./)  return "T2|China Mobile/CMI"
  if (h ~ /pccw|netvigator/)                  return "T2|PCCW"
  if (h ~ /hgc\.com\.hk|hgc/)                 return "T2|HGC"
  if (h ~ /hkbn|bwbn|wizcloud/)              return "T2|HKBN"
  if (h ~ /singtel|asean\.ix|starhub/)       return "T2|Singtel/SG Carrier"
  if (h ~ /kt\.co\.kr|kornet/)               return "T2|KT"
  if (h ~ /skbroadband|sk broadband/)        return "T2|SK Broadband"
  if (h ~ /telstra|pacificnet/)              return "T2|Telstra"
  if (h ~ /retn\.net/)                       return "T2|RETN"
  if (h ~ /vodafone|cable-wireless|cw\.net/) return "T2|Vodafone/C&W"
  if (h ~ /iij\.net/)                        return "T2|IIJ"
  if (h ~ /softbank|bbtec\.net/)             return "T2|SoftBank"
  if (h ~ /kddi\.ne\.jp|\.kddi\.com|kddi/)   return "T2|KDDI"

  if (h ~ /google|1e100\.net|googlenet/)     return "T2|Google"
  if (h ~ /amazonaws|aws/)                   return "T2|AWS"
  if (h ~ /cloudflare|warp|cf-ns/)           return "T2|Cloudflare"
  if (h ~ /facebook|fbcdn|tfbnw/)            return "T2|Meta/Facebook"
  if (h ~ /akamai|akam\.net/)                return "T2|Akamai"
  if (h ~ /edgecast|fastly/)                 return "T2|EdgeCast/Fastly"

  # Tier3
  if (h ~ /gsl|globalsecurelayer/)           return "T3|GSL"

  return ""
}

BEGIN{
  hop=0
  prev_avg=0
  maxJump=0
  maxHop=0
  alive_hops=0
}

# -------- 解析每跳 --------
/^[ ]*[0-9]+\./{
  hop++
  host=$3
  loss=$(NF-6); gsub(/%/,"",loss)
  avg=$(NF-3)
  stdev=$NF

  h_host[hop]=host
  h_loss[hop]=loss+0
  h_avg[hop]=avg+0
  h_stdev[hop]=stdev+0

  if (loss+0 < 100) alive_hops++

  # 骨干识别
  bb = detect_backbone(host)
  if(bb!=""){
    split(bb, tmp, "|")
    tier = tmp[1]
    name = tmp[2]
    if(tier=="T1") bb_t1[name]=1
    else if(tier=="T2") bb_t2[name]=1
    else if(tier=="T3") bb_t3[name]=1
  }

  # 延迟跳变
  if(hop>1){
    diff = (avg+0) - prev_avg
    if(diff > maxJump){
      maxJump = diff
      maxHop  = hop
    }
  }
  prev_avg = avg+0

  # 记录末跳
  dest_host  = host
  dest_loss  = loss+0
  dest_avg   = avg+0
  dest_stdev = stdev+0
}

END{
  # ---------------- 完全不可达：所有跳都是 100% 丢包 ----------------
  if (alive_hops == 0 || hop == 0){
    print "🗺 IP 归属地"
    if (SRC_COUNTRY != "")
      printf("- 本机: %s %s [%s]\n", SRC_COUNTRY,SRC_CITY,SRC_ORG)
    else
      print "- 本机: 未获取到 IP 归属地"

    print "- 目标: 未获取（全链路无任何 ICMP 返回）\n"

    print "📍 目标节点: 无法获取（全链路 100% 丢包）"
    print "📡 丢包率  : 100%"
    print "⏱ 延迟统计: 无法获取\n"

    print "⚙ 延迟评价"
    print "- 综合延迟评价: 不可用"
    print "- 说明: 自首跳起即无任何 ICMP 响应，线路中断或被防火墙完全屏蔽。\n"

    print "📉 丢包评价"
    print "- 全链路 100% 丢包，可能："
    print "  · 目标完全宕机或未上线"
    print "  · 黑洞路由（RTBH）或上游丢弃"
    print "  · 区域性防火墙策略丢弃 ICMP\n"

    print "🧩 可能瓶颈点"
    print "- 无法分析（没有任何可用跳）\n"

    print "🏢 骨干 / 运营商识别"
    print "- 无可识别骨干（无路由信息）\n"

    print "⭐ 综合线路评分：0 / 100"
    print "（说明：全链路不可达。）"
    exit
  }

  # ---------------- 归属地展示 ----------------
  print "🗺 IP 归属地"
  if (SRC_COUNTRY != "")
    printf("- 本机: %s %s [%s]\n", SRC_COUNTRY,SRC_CITY,SRC_ORG)
  else
    print "- 本机: 未获取到 IP 归属地"

  if (DST_COUNTRY != "")
    printf("- 目标: %s %s [%s]\n\n", DST_COUNTRY,DST_CITY,DST_ORG)
  else
    print "- 目标: 未获取到 IP 归属地\n"

  # ---------------- 修正目标节点名称：避免 ??? ----------------
  real_dest = dest_host
  if (real_dest == "???"){
    for(i=hop;i>=1;i--){
      if(h_host[i] != "???"){
        real_dest = h_host[i] " (最终节点不回应 ICMP)"
        break
      }
    }
    if(real_dest == "???") real_dest = "未知节点 (无有效主机名)"
  }

  printf("📍 目标节点: %s\n", real_dest)
  printf("📡 丢包率  : %.1f%%\n", dest_loss)
  printf("⏱ 延迟统计: Avg=%.1f ms, 抖动=%.2f ms\n\n", dest_avg, dest_stdev)

  # ---------------- 延迟 & 稳定性 & 丢包 评价 ----------------
  print "⚙ 延迟评价"
  rating = ""
  explain = ""

  if (dest_loss >= 80){
    rating  = "不可用"
    explain = "末跳几乎不响应 ICMP，目标可能禁 ping 或丢弃 ICMP，只能参考前几跳质量。"
  } else {
    if (dest_avg <= 10)      { rating="极佳"; explain="延迟极低，适合延迟敏感业务。"}
    else if (dest_avg <=30 ) { rating="优秀"; explain="延迟较低，体验良好。"}
    else if (dest_avg <=80 ) { rating="一般"; explain="延迟中等，多数业务可接受。"}
    else                     { rating="较差"; explain="延迟较高，实时性业务体验会较差。"}
  }

  print "- 综合延迟评价: " rating
  print "- 说明: " explain
  print ""

  print "📈 稳定性评价"
  if (dest_loss >= 80){
    print "- 由于末跳不响应 ICMP，无法准确评估抖动，仅可参考前几跳。"
  } else if (dest_stdev <= 2){
    print "- 抖动很小，线路非常稳定。"
  } else if (dest_stdev <= 8){
    print "- 抖动中等，偶尔有波动。"
  } else {
    print "- 抖动较大，网络存在明显波动。"
  }
  print ""

  print "📉 丢包评价"
  if (dest_loss >= 80){
    print "- 末跳 ICMP 丢包率接近 100%，更像是禁 ping / 防火墙策略，而非纯粹链路质量问题。"
  } else if (dest_loss <= 0.1){
    print "- 基本无丢包，连通性良好。"
  } else if (dest_loss < 3){
    print "- 少量丢包（<3%），大部分业务可接受。"
  } else {
    print "- 丢包偏高，关键业务需谨慎使用。"
  }
  print ""

  # ---------------- 瓶颈点 ----------------
  print "🧩 可能瓶颈点（跨境 / 出海处附近）"
  if (maxHop > 1 && maxJump > 3){
    printf("- 跳数: 第 %d 跳\n", maxHop)
    printf("- 节点: %s\n", h_host[maxHop])
    printf("  ↑ 平均延迟在此处增加约 %.1f ms\n\n", maxJump)
  } else {
    print "- 未发现明显的单点延迟跃升。"
    print ""
  }

  # ---------------- 骨干展示 ----------------
  print "🏢 骨干 / 运营商识别 "

  has_t1=0; has_t2=0; has_t3=0
  for(c in bb_t1){ has_t1=1; break }
  for(c in bb_t2){ has_t2=1; break }
  for(c in bb_t3){ has_t3=1; break }

  if(!has_t1 && !has_t2 && !has_t3){
    print "- 未从主机名中识别出明显骨干网/运营商（可能隐藏 / 内网 / 自建网）。"
  } else {
    if(has_t1){
      print "- Tier1 Backbone："
      for(c in bb_t1) printf("  · %s\n", c)
    }
    if(has_t2){
      print "- Tier2 / 区域骨干 / 云网："
      for(c in bb_t2) printf("  · %s\n", c)
    }
    if(has_t3){
      print "- Tier3 / 小骨干："
      for(c in bb_t3) printf("  · %s\n", c)
    }
  }
  print ""

  # ---------------- 评分 ----------------
  base=60
  if (rating=="极佳") base=95
  else if (rating=="优秀") base=85
  else if (rating=="一般") base=65
  else if (rating=="较差") base=45
  else if (rating=="不可用") base=15

  score = base
  score -= dest_stdev * 2
  score -= dest_loss * 1.5
  if (score < 0) score=0
  if (score > 100) score=100

  printf("⭐ 综合线路评分：%.0f / 100\n", score)
  print "（说明：评分基于末跳延迟/抖动/丢包的简单模型，仅供参考，真实体验请结合业务实际情况。）"
}
' "$REPORT"

echo "==================================================================="
echo "[✓] 分析结束"
