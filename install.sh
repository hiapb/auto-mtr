#!/usr/bin/env bash
# hipb
# 一键 mtr + 自动国家地区识别 + ipinfo 源/目标归属地 + 跨境判断 + 骨干识别 + 评分

set -e

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

install_mtr() {
  echo "[*] 正在检查 mtr 是否已安装..."
  if command_exists mtr; then
    echo "[✓] 已检测到 mtr"
    return 0
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
SHOW_RAW=${SHOW_RAW,,}   # 转小写

# ---------- 利用 ipinfo.io 获取本机 & 目标归属地 ----------
echo "[*] 正在获取本机 IP 归属地..."
SRC_INFO=$(curl -s ipinfo.io || true)

SRC_IP=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"ip":/ {print $4; exit}')
SRC_COUNTRY=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"country":/ {print $4; exit}')
SRC_CITY=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"city":/ {print $4; exit}')
SRC_ORG=$(printf '%s\n' "$SRC_INFO" | awk -F'"' '/"org":/ {print $4; exit}')

echo "[*] 正在获取目标 IP 归属地..."
DST_INFO=$(curl -s "ipinfo.io/$TARGET" || true)

DST_IP=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"ip":/ {print $4; exit}')
DST_COUNTRY=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"country":/ {print $4; exit}')
DST_CITY=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"city":/ {print $4; exit}')
DST_ORG=$(printf '%s\n' "$DST_INFO" | awk -F'"' '/"org":/ {print $4; exit}')

REPORT="/tmp/mtr_report_${TARGET//[^a-zA-Z0-9_.-]/_}.txt"

echo "[*] 正在测试：$TARGET"
echo "[*] mtr -rwzbc $COUNT $TARGET"
echo "💫 开始检测（预计 ${COUNT/10}~${COUNT/5} 秒）"

spin='-\|/'
i=0
(
  while true; do
    i=$(( (i+1)%4 ))
    printf "\r⏳ 检测分析运行中... %s" "${spin:$i:1}"
    sleep 0.2
  done
)&

SPIN=$!

if [ "$EUID" -ne 0 ]; then
  sudo mtr -rwzbc $COUNT "$TARGET" > "$REPORT"
else
  mtr -rwzbc $COUNT "$TARGET" > "$REPORT"
fi

kill $SPIN >/dev/null 2>&1
echo -e "\n✔ 检测完成\n"

if [ "$SHOW_RAW" = "y" ] || [ "$SHOW_RAW" = "yes" ]; then
  echo "================ 原始 MTR 报告 ================"
  cat "$REPORT"
  echo "================================================"
  echo
fi

echo "================ 自动分析报告 ================"

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

# -------- 区域 --------
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

# -------- 骨干识别（扩展版） --------
function detect_carrier(host,    h){
  h = tolower(host)

  # 日本相关
  if (h ~ /ntt\.net|\.ntt\.com/)          return "NTT"
  if (h ~ /kddi\.ne\.jp|kddi/)            return "KDDI"
  if (h ~ /softbank|bbtec\.net/)         return "SoftBank"
  if (h ~ /iij\.net/)                    return "IIJ"

  # 全球常见 Tier1 / 大骨干
  if (h ~ /telia|se.telia.net/)          return "Telia"
  if (h ~ /gtt\.net/)                    return "GTT"
  if (h ~ /cogentco\.com|cogent/)        return "Cogent"
  if (h ~ /he\.net|hurricane/)           return "Hurricane Electric"
  if (h ~ /level3|lumen/)                return "Lumen/Level3"
  if (h ~ /zayo/)                        return "Zayo"
  if (h ~ /tatacommunications|tata/)     return "Tata"
  if (h ~ /sparkle|seabone/)             return "Sparkle"
  if (h ~ /comcast/)                     return "Comcast"
  if (h ~ /verizon|alter\.net/)          return "Verizon"

  # 亚洲区域骨干 / 运营商
  if (h ~ /pccw|netvigator/)             return "PCCW"
  if (h ~ /hgc\.com\.hk|hgc/)            return "HGC"
  if (h ~ /cmi\.chinamobile\.com|cmi\.hk/)return "CMI"
  if (h ~ /kt\.co\.kr|kornet/)           return "KT"
  if (h ~ /skbroadband|sk broadband/)    return "SKB"

  # 你线路里经常出现的
  if (h ~ /gsl|globalsecurelayer/)       return "GSL"
  if (h ~ /nube\.sh/)                    return "Nube"
  if (h ~ /dmit\.com/)                   return "DMIT"

  return ""
}

BEGIN{
  hop=0
  prev=-1
  maxJump=0
}

# -------- 解析每跳 --------
/^[ ]*[0-9]+\./{
  hop++
  host=$3
  loss=$(NF-6); gsub(/%/,"",loss)
  last=$(NF-4)
  avg=$(NF-3)
  best=$(NF-2)
  wrst=$(NF-1)
  stdev=$NF

  h_country[hop]=detect_country(host)
  h_region[hop]=region(h_country[hop])
  h_host[hop]=host

  car=detect_carrier(host)
  if(car!="") carriers[car]=1

  if(prev>=0){
    diff=avg-prev
    if(diff>maxJump){
      maxJump=diff; maxHop=hop
    }
  }
  prev=avg

  dest_avg=avg+0
  dest_loss=loss+0
  dest_stdev=stdev+0
  dest_host=host
  dest_best=best+0
  dest_wrst=wrst+0
}

END{
  # --- 先用 hop 粗略推 src/dst（作为 ipinfo 失败时的 fallback） ---
  src_hop="UN"
  maxCnt=0
  for(i=1;i<=hop && i<=3;i++){
    c=h_country[i]
    if(c!="UN"){
      srcCount[c]++
      if(srcCount[c]>maxCnt){maxCnt=srcCount[c];src_hop=c}
    }
  }
  if(src_hop=="UN"){
    for(i=1;i<=hop;i++){
      if(h_country[i]!="UN"){src_hop=h_country[i];break}
    }
  }

  dst_hop="UN"
  maxCnt=0
  for(i=hop;i>=1 && i>=hop-2;i--){
    c=h_country[i]
    if(c!="UN"){
      dstCount[c]++
      if(dstCount[c]>maxCnt){maxCnt=dstCount[c];dst_hop=c}
    }
  }
  if(dst_hop=="UN"){
    for(i=hop;i>=1;i--){
      if(h_country[i]!="UN"){dst_hop=h_country[i];break}
    }
  }

  # --- 真正用于区域判断 / 评分的 src/dst：优先用 ipinfo ---
  src = (SRC_COUNTRY != "" ? SRC_COUNTRY : src_hop)
  dst = (DST_COUNTRY != "" ? DST_COUNTRY : dst_hop)

  sR = region(src)
  dR = region(dst)

  # --- ipinfo 归属地展示 ---
  print "🗺 IP 归属地 (来自 ipinfo.io，无 token 可能有少量误差)"
  if (SRC_COUNTRY != "")
    printf("- 本机: %s %s [%s]\n", SRC_COUNTRY, SRC_CITY, SRC_ORG)
  else
    print "- 本机: 未获取到 ipinfo 信息"
  if (DST_COUNTRY != "")
    printf("- 目标: %s %s [%s]\n\n", DST_COUNTRY, DST_CITY, DST_ORG)
  else
    print "- 目标: 未获取到 ipinfo 信息\n"

  # --- 总体延迟 / 丢包 ---
  printf("📍 目标节点: %s\n", dest_host)
  printf("📡 丢包率  : %.1f%%\n", dest_loss)
  printf("⏱ 延迟统计: Avg=%.1f ms, Best=%.1f ms, Worst=%.1f ms, 抖动=%.2f ms\n\n",
         dest_avg,dest_best,dest_wrst,dest_stdev)

  print "🌍 区域判断"
  print "- 源端国家: " src " (" sR ")"
  print "- 目标国家: " dst " (" dR ")"
  print ""

  # ------- 延迟评价（区域规则） -------
  print "⚙ 延迟评价"
  avg=dest_avg

  if(src==dst && src!="UN"){
    if(avg<=2){rate="极佳";comm="同机房 / 同城极限延迟。"}
    else if(avg<=5){rate="优秀";comm="本地骨干质量优秀，适合延迟敏感业务。"}
    else if(avg<=10){rate="良好";comm="本地延迟正常，多数业务可用。"}
    else{rate="一般";comm="同国延迟偏高，可能绕路。"}
  }
  else if( (src=="HK"&&dst=="SG") || (src=="SG"&&dst=="HK") ){
    if(avg<=35){rate="优秀";comm="港↔新 优质直连骨干水平。"}
    else if(avg<=50){rate="良好";comm="港↔新 正常水平。"}
    else{rate="偏高";comm="港↔新 延迟偏高，疑似绕路。"}
  }
  else if( (sR=="EAS"&&dst=="JP") || (dR=="EAS"&&src=="JP") ){
    if(avg<=25){rate="优秀";comm="东亚↔日本 顶级线路水准。"}
    else if(avg<=35){rate="良好";comm="东亚↔日本 正常水平。"}
    else{rate="偏高";comm="东亚↔日本 延迟偏高，可能绕路。"}
  }
  else if( sR=="EAS"&&dR=="NA" || sR=="SEAS"&&dR=="NA" ||
           dR=="EAS"&&sR=="NA" || dR=="SEAS"&&sR=="NA" ){
    if(avg<=160){rate="优秀";comm="亚↔美 跨太平洋优质线路。"}
    else if(avg<=220){rate="良好";comm="亚↔美 常规水平。"}
    else{rate="偏高";comm="亚↔美 延迟偏高，疑似绕路。"}
  }
  else{
    if(avg<=70){rate="大致良好";comm="整体 RTT 不高，多数业务可接受。"}
    else if(avg<=120){rate="一般";comm="延迟中等，适合非极端敏感业务。"}
    else{rate="较差";comm="延迟较高，建议仅作备线 / 非实时业务。"}
  }

  print "- 综合延迟评价: " rate
  print "- 说明: " comm
  print ""

  # ------- 稳定性 -------
  print "📈 稳定性评价"
  if(dest_stdev<=2) print "- 抖动很小，线路非常稳定。"
  else if(dest_stdev<=8) print "- 抖动中等，偶尔会有尖峰。"
  else print "- 抖动较大，网络波动明显。"
  print ""

  # ------- 丢包 -------
  print "📉 丢包评价"
  if(dest_loss <= 0.0001)       print "- 末跳无丢包，连通性良好。"
  else if(dest_loss < 3)        print "- 少量丢包（<3%），大部分业务可接受。"
  else                           print "- 丢包偏高，需谨慎用于关键业务。"
  print ""

  # ------- 瓶颈点 -------
  print "🧩 可能瓶颈点（跨境 / 出海处）"
  if(maxHop>1){
    print "- 跳数: 第 " maxHop " 跳"
    print "- 节点: " h_host[maxHop]
    printf("  ↑ 平均延迟在此处增加约 %.1f ms\n",maxJump)
  } else print "- 未发现明显延迟跳升点。"
  print ""

  # ------- 骨干运营商 -------
  print "🏢 骨干 / 运营商识别"
  found=0
  for(c in carriers){ print "- " c; found=1 }
  if(!found) print "- 未从主机名中识别出明显骨干（可能隐藏或自建网）。"
  print ""

  # ------- 评分 -------
  base=60
  if(rate=="极佳") base=95
  else if(rate=="优秀") base=90
  else if(rate=="良好") base=80
  else if(rate=="大致良好") base=70
  else if(rate=="一般") base=60
  else if(rate=="偏高") base=50
  else if(rate=="较差") base=30

  score=base
  score -= dest_stdev * 2
  score -= dest_loss * 3
  if(score<0) score=0
  if(score>100) score=100

  printf("⭐ 综合线路评分：%.0f / 100\n",score)
  print "（说明：评分基于区域评级 + 抖动 + 丢包的简单模型，仅供参考。）"
}
' "$REPORT"

echo "==================================================================="
echo "[✓] 分析结束"
