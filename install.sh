#!/usr/bin/env bash
#
# auto-mtr-pro.sh
# 一键 mtr 测试 + 自动分析（地区 / 骨干 / 评分）
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
echo "⏳ 正在检测中（预计 ${COUNT/10}～${COUNT/5} 秒）..."

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
# ---------- 辅助函数 ----------

function detect_region(host,    h) {
  h = tolower(host)
  if (h ~ /hongkong|\.hk|hkg[0-9]*|hkix/) return "HK"
  if (h ~ /singapore|\.sg|sin[0-9]*|sgp/) return "SG"
  if (h ~ /tokyo|osaka|\.jp|jpn|tyo|kix/) return "JP"
  if (h ~ /taiwan|\.tw|chunghwa|hinet|tpe/) return "TW"
  if (h ~ /china|\.cn|ctc|chinatelecom|cmcc|cuc|cnc|bj-|sh-|gz-/) return "CN"
  if (h ~ /seoul|\.kr|korea/) return "KR"
  if (h ~ /frankfurt|fra[0-9]*|\.de/) return "DE"
  if (h ~ /london|lon[0-9]*|\.uk|\.co\.uk/) return "UK"
  if (h ~ /amsterdam|ams[0-9]*|\.nl/) return "NL"
  if (h ~ /paris|\.fr/) return "FR"
  if (h ~ /sydney|melbourne|\.au/) return "AU"
  if (h ~ /newyork|nyc|\.us/ || h ~ /losangeles|lax/ || h ~ /sanJose|sjc/ || h ~ /seattle|sea/ || h ~ /chicago|chi/) return "US"
  if (h ~ /\.ca/) return "CA"
  return "UN"  # unknown
}

function region_name(r) {
  if (r == "HK") return "香港"
  if (r == "SG") return "新加坡"
  if (r == "JP") return "日本"
  if (r == "TW") return "台湾"
  if (r == "CN") return "中国大陆"
  if (r == "KR") return "韩国"
  if (r == "DE") return "德国"
  if (r == "UK") return "英国"
  if (r == "NL") return "荷兰"
  if (r == "FR") return "法国"
  if (r == "AU") return "澳大利亚"
  if (r == "US") return "美国"
  if (r == "CA") return "加拿大"
  if (r == "UN") return "未知地区"
  return r
}

function region_group(r) {
  if (r == "HK" || r == "SG" || r == "JP" || r == "TW" || r == "CN" || r == "KR" || r == "IN" || r == "MY" || r == "TH" || r == "PH" || r == "ID" || r == "VN") return "AS"
  if (r == "DE" || r == "UK" || r == "NL" || r == "FR" || r == "SE" || r == "NO" || r == "FI" || r == "IT" || r == "ES") return "EU"
  if (r == "US" || r == "CA") return "NA"
  if (r == "AU" || r == "NZ") return "OC"
  return "OT"
}

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

function max(a,b){ return (a>b)?a:b }
function min(a,b){ return (a<b)?a:b }

# ---------- 解析主逻辑 ----------

BEGIN {
  hopCount = 0
  maxJump = 0
  prevAvg = -1
}

# 匹配 mtr 的每一跳行：开头是序号+点
/^[ ]*[0-9]+\./ {
  hopCount++
  # 结构：序号.  ASN  HOST  Loss% Snt Last Avg Best Wrst StDev
  idx = $1
  gsub(/\./, "", idx)
  asn = $2
  host = $3

  loss  = $(NF-6); gsub(/%/, "", loss)
  snt   = $(NF-5)
  last  = $(NF-4)
  avg   = $(NF-3)
  best  = $(NF-2)
  wrst  = $(NF-1)
  stdev = $NF

  hops[hopCount] = host
  hop_avg[hopCount] = avg + 0
  hop_loss[hopCount] = loss + 0
  hop_region[hopCount] = detect_region(host)

  carrier = detect_carrier(host)
  if (carrier != "") carriers[carrier] = 1

  if (prevAvg >= 0) {
    diff = (avg + 0) - prevAvg
    if (diff > maxJump) {
      maxJump = diff
      maxHop = hopCount
    }
  }
  prevAvg = avg + 0

  # 记录末跳（目标）
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

  # 尝试确定源/目标地区
  srcR = "UN"
  for (i=1; i<=hopCount; i++) {
    if (hop_region[i] != "UN") { srcR = hop_region[i]; break }
  }
  dstR = "UN"
  for (i=hopCount; i>=1; i--) {
    if (hop_region[i] != "UN") { dstR = hop_region[i]; break }
  }

  print "目标节点: " dest_host
  print "发送次数: " dest_snt
  print "丢包率  : " dest_loss "%";
  printf "延迟统计: Avg=%.1f ms, Best=%.1f ms, Worst=%.1f ms, 抖动(StDev)=%.1f ms\n", dest_avg, dest_best, dest_wrst, dest_stdev
  print ""

  print "【区域判断】"
  print "- 源端大致地区: " region_name(srcR)
  print "- 目标大致地区: " region_name(dstR)
  print ""

  # 延迟评价（根据区域组合做不同标准）
  print "【延迟评价】"
  avg = dest_avg + 0
  gSrc = region_group(srcR)
  gDst = region_group(dstR)
  rating = ""
  comment = ""

  if (srcR != "UN" && srcR == dstR) {
    # 同地区
    if (avg <= 2)      { rating="极佳"; comment="同机房/同城级别，延迟非常低，非常适合实时业务与中转。"}
    else if (avg <= 5) { rating="优秀"; comment="本地网络质量很好，适合大部分延迟敏感业务。"}
    else if (avg <=10) { rating="良好"; comment="本地网络基本可用，如为同城可考虑排查轻微绕路。"}
    else               { rating="一般"; comment="本地 RTT 偏高，可能绕路或网络结构复杂，建议进一步排查。"}
  }
  else if ((srcR=="HK" && dstR=="SG") || (srcR=="SG" && dstR=="HK")) {
    if (avg <= 35)      { rating="优秀"; comment="港-新 30~35ms 属于骨干级表现，非常不错。"}
    else if (avg <= 50) { rating="良好"; comment="港-新 延迟尚可，偶尔绕路或设备较多。"}
    else                { rating="偏高"; comment="港-新 RTT 偏高，疑似绕路或拥塞。"}
  }
  else if ((srcR=="HK" && dstR=="JP") || (srcR=="JP" && dstR=="HK") || (srcR=="CN" && dstR=="JP") || (srcR=="JP" && dstR=="CN")) {
    if (avg <= 25)      { rating="优秀"; comment="沪/港/华东 ↔ 日本 20~25ms 为高质量专线水准。"}
    else if (avg <= 35) { rating="良好"; comment="东亚互联延迟正常，适合绝大多数业务。"}
    else                { rating="偏高"; comment="东亚互联 RTT 偏高，疑似绕路或走廉价骨干。"}
  }
  else if (gSrc=="AS" && gDst=="AS") {
    if (avg <= 30)      { rating="优秀"; comment="亚洲区域内 30ms 以内，非常优秀。"}
    else if (avg <= 60) { rating="良好"; comment="亚洲区域内 60ms 以内，为正常可接受水平。"}
    else                { rating="偏高"; comment="亚洲区域内 RTT 偏高，可能绕路或走低质线路。"}
  }
  else if ((gSrc=="AS" && gDst=="NA") || (gSrc=="NA" && gDst=="AS")) {
    if (avg <= 160)      { rating="优秀"; comment="亚美跨境 RTT 较低，多半走优质跨太平洋骨干。"}
    else if (avg <= 220) { rating="良好"; comment="亚美跨境常见水平，适合大部分非实时业务。"}
    else                 { rating="偏高"; comment="亚美跨境 RTT 偏高，疑似多次绕路或拥塞。"}
  }
  else if (gSrc=="EU" && gDst=="NA" || gSrc=="NA" && gDst=="EU") {
    if (avg <= 90)       { rating="优秀"; comment="欧美互联表现很好，走优质跨大西洋骨干。"}
    else if (avg <= 130) { rating="良好"; comment="欧美互联常见水平。"}
    else                 { rating="偏高"; comment="欧美 RTT 偏高，可能绕路或拥塞。"}
  }
  else if (gSrc==gDst && gSrc=="EU") {
    if (avg <= 30)      { rating="优秀"; comment="欧洲区域 30ms 内，很好。"}
    else if (avg <= 60) { rating="良好"; comment="欧洲区域延迟正常。"}
    else                { rating="偏高"; comment="欧洲内部 RTT 偏高，可能绕路。"}
  }
  else {
    # 无法准确判断地区时的通用标准
    if (avg <= 50)       { rating="大致良好"; comment="整体 RTT 不算高，多数业务可接受。"}
    else if (avg <=120 ) { rating="一般"; comment="属于中等偏上的网络质量。"}
    else                 { rating="较差"; comment="延迟较高，可能跨洲严重或路径绕行。"}
  }

  print "- 综合延迟评价: " rating
  print "- 说明: " comment
  print ""

  # 稳定性评价
  print "【稳定性评价】"
  if (dest_stdev <= 3)      print "- 抖动很小，线路非常稳定，适合延迟敏感业务。"
  else if (dest_stdev <=10) print "- 抖动中等，偶尔有尖峰，一般业务可接受。"
  else                      print "- 抖动较大，网络不太稳定，可能存在拥塞或质量问题。"
  print ""

  # 丢包评价
  print "【丢包评价】"
  if (dest_loss == 0)            print "- 末跳无丢包，整体连通性良好。"
  else if (dest_loss < 3)        print "- 少量丢包（<3%），大多数业务仍可接受。"
  else if (dest_loss < 10)       print "- 丢包偏高（3%~10%），建议谨慎用于关键业务。"
  else                            print "- 丢包严重（>=10%），不建议用于重要或实时业务。"
  print ""

  # 最大延迟跳升点
  print "【可能的跨境/出海/瓶颈节点】"
  if (maxHop > 1) {
    printf "- 第 %d 跳：%s\n", maxHop, hops[maxHop]
    printf "  与上一跳平均延迟相差约 %.1f ms。\n", maxJump
  } else {
    print "- 未发现明显的延迟跳升点。"
  }
  print ""

  # 骨干/运营商识别
  print "【疑似涉及的骨干/运营商】"
  hasCarrier = 0
  for (c in carriers) {
    print "- " c
    hasCarrier = 1
  }
  if (!hasCarrier) {
    print "- 未能从主机名中识别出明显的骨干/运营商（很多运营商会隐藏信息）。"
  }
  print ""

  # 综合评分（简单启发式）
  score = 100
  score -= dest_avg / 5       # RTT 越高扣分越多
  score -= dest_stdev * 2     # 抖动影响
  score -= dest_loss * 2      # 丢包影响
  score -= maxJump / 5        # 大跳跃会扣分

  if (score < 0) score = 0
  if (score > 100) score = 100

  printf "【综合线路评分】\n- 评分: %.0f / 100 （仅供参考，基于延迟 / 抖动 / 丢包 / 最大跳变的简单模型）\n", score
  print ""
  print "（提示：如果中间某些跳出现 100% loss，但最后一跳无丢包，多半是中间路由器屏蔽 ICMP，不代表真实丢包。）"
}
' "$REPORT_FILE"

echo "==================================================="
echo
echo "[✓] 分析结束。你可以根据上面的自动报告快速判断这条线路质量。"
