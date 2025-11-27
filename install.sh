#!/usr/bin/env bash
#
# auto-mtr-pro-v3.sh
# 一键 mtr + 自动国家地区识别 + 跨境判断 + 骨干识别 + 评分
# by ChatGPT & Mevu

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

REPORT="/tmp/mtr_report_${TARGET//[^a-zA-Z0-9_.-]/_}.txt"

echo "[*] 正在测试：$TARGET"
echo "[*] mtr -rwzbc $COUNT $TARGET"
echo "⏳ 正在测速（预计 ${COUNT/10}~${COUNT/5} 秒）..."

spin='-\|/'
i=0
(
  while true; do
    i=$(( (i+1)%4 ))
    printf "\r运行中... %s" "${spin:$i:1}"
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
echo -e "\n✔ 测试完成\n"

echo "================ 原始 MTR 报告 ================"
cat "$REPORT"
echo "================================================"
echo

echo "================ 自动分析报告 ================"

awk '
# -------- 国家识别 --------

function detect_country(host,    h) {
  h=tolower(host)

  # 东亚
  if (h~/hongkong|hkg|\.hk/) return "HK"
  if (h~/taipei|tpe|\.tw/) return "TW"
  if (h~/beijing|bj-|shanghai|sh-|guangzhou|gz-|shenzhen|sz-|\.cn/) return "CN"
  if (h~/tokyo|osaka|kix|tyo|\.jp/) return "JP"
  if (h~/seoul|icn|busan|\.kr/) return "KR"

  # 东南亚
  if (h~/singapore|sin|\.sg/) return "SG"
  if (h~/kuala|kul|\.my/) return "MY"
  if (h~/bangkok|bkk|\.th/) return "TH"
  if (h~/manila|mnl|\.ph/) return "PH"
  if (h~/jakarta|jkt|\.id/) return "ID"
  if (h~/hanoi|saigon|hochiminh|\.vn/) return "VN"

  # 南亚
  if (h~/mumbai|delhi|bangalore|blr|\.in/) return "IN"

  # 欧洲
  if (h~/frankfurt|fra|\.de/) return "DE"
  if (h~/london|lon|\.uk|\.co\.uk/) return "GB"
  if (h~/paris|cdg|\.fr/) return "FR"
  if (h~/amsterdam|ams|\.nl/) return "NL"
  if (h~/madrid|mad|\.es/) return "ES"
  if (h~/rome|milano|mxp|fco|\.it/) return "IT"
  if (h~/stockholm|arn|\.se/) return "SE"
  if (h~/oslo|\.no/) return "NO"
  if (h~/vienna|vie|\.at/) return "AT"
  if (h~/zurich|zrh|\.ch/) return "CH"
  if (h~/prague|\.cz/) return "CZ"
  if (h~/poland|waw|\.pl/) return "PL"

  # 北美
  if (h~/newyork|nyc|ny-|\.us/) return "US"
  if (h~/losangeles|lax|sanjose|sjc|seattle|sea|chicago|chi|dallas|dfw|atlanta|atl/) return "US"
  if (h~/toronto|montreal|vancouver|\.ca/) return "CA"

  # 中东
  if (h~/dubai|dxb|\.ae/) return "AE"
  if (h~/riyadh|\.sa/) return "SA"
  if (h~/doha|\.qa/) return "QA"
  if (h~/istanbul|\.tr/) return "TR"

  # 大洋洲
  if (h~/sydney|melbourne|brisbane|\.au/) return "AU"
  if (h~/auckland|\.nz/) return "NZ"

  # 非洲
  if (h~/johannesburg|cpt|\.za/) return "ZA"

  return "UN"
}

# -------- 区域 --------
function region(c){
  if (c ~ /HK|TW|CN|JP|KR/) return "EAS"
  if (c ~ /SG|MY|TH|PH|ID|VN/) return "SEAS"
  if (c == "IN") return "SAS"
  if (c ~ /DE|GB|FR|NL|ES|IT|SE|NO|AT|CZ|CH|PL/) return "EU"
  if (c ~ /US|CA/) return "NA"
  if (c ~ /AE|SA|QA|TR/) return "ME"
  if (c ~ /AU|NZ/) return "OC"
  if (c == "ZA") return "AF"
  return "OT"
}

# -------- 骨干 --------
function detect_carrier(host,h){
  h=tolower(host)
  if(h~/ntt/)return"NTT"
  if(h~/gtt/)return"GTT"
  if(h~/telia/)return"Telia"
  if(h~/cogent/)return"Cogent"
  if(h~/he\.net/)return"HE"
  if(h~/lumen|level3/)return"Lumen"
  if(h~/pccw/)return"PCCW"
  if(h~/hgc/)return"HGC"
  if(h~/gsl|globalsecurelayer/)return"GSL"
  if(h~/nube/)return"Nube"
  if(h~/dmit/)return"DMIT"
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
  avg=$(NF-3)
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

  dest_avg=avg
  dest_loss=loss
  dest_stdev=stdev
  dest_host=host
}

END{
  # 源国家
  src="UN"
  for(i=1;i<=hop;i++){
    if(h_country[i]!="UN"){src=h_country[i];break}
  }
  # 目标国家
  dst="UN"
  for(i=hop;i>=1;i--){
    if(h_country[i]!="UN"){dst=h_country[i];break}
  }

  sR=region(src)
  dR=region(dst)

  print "目标节点: " dest_host
  print "丢包率  : " dest_loss "%"
  printf("延迟统计: Avg=%.1f ms, 抖动=%.2f ms\n\n",dest_avg,dest_stdev)

  print "【区域判断】"
  print "源端国家: " src " (" sR ")"
  print "目标国家: " dst " (" dR ")"
  print ""

  # ------- 延迟评价（区域规则） -------
  print "【延迟评价】"
  avg=dest_avg

  if(src==dst){
    if(avg<=2){rate="极佳";comm="同机房/同城极限延迟"}
    else if(avg<=5){rate="优秀";comm="本地骨干质量优秀"}
    else if(avg<=10){rate="良好";comm="本地延迟正常"}
    else{rate="一般";comm="同国延迟偏高"}
  }
  else if( (src=="HK"&&dst=="SG") || (src=="SG"&&dst=="HK") ){
    if(avg<=35){rate="优秀";comm="港↔新 优质直连骨干"}
    else if(avg<=50){rate="良好";comm="港↔新 正常水平"}
    else{rate="偏高";comm="港↔新 出现绕路"}
  }
  else if( (sR=="EAS"&&dst=="JP") || (dR=="EAS"&&src=="JP") ){
    if(avg<=25){rate="优秀";comm="东亚↔日本 顶级线路"}
    else if(avg<=35){rate="良好";comm="东亚↔日本 正常水平"}
    else{rate="偏高";comm="东亚↔日本 可能绕路"}
  }
  else if( sR=="EAS"&&dR=="NA" || sR=="SEAS"&&dR=="NA" ||
           dR=="EAS"&&sR=="NA" || dR=="SEAS"&&sR=="NA" ){
    if(avg<=160){rate="优秀";comm="亚↔美 跨太优质线路"}
    else if(avg<=220){rate="良好";comm="亚↔美 常规水平"}
    else{rate="偏高";comm="亚↔美 明显绕路"}
  }
  else{
    if(avg<=70){rate="大致良好";comm="整体 RTT 不高"}
    else if(avg<=120){rate="一般";comm="中等水平"}
    else{rate="较差";comm="延迟较高"}
  }

  print "- 综合延迟评价: " rate
  print "- 说明: " comm "\n"

  # ------- 稳定性 -------
  print "【稳定性评价】"
  if(dest_stdev<=2) print "- 非常稳定"
  else if(dest_stdev<=8) print "- 中等稳定"
  else print "- 波动较大"
  print ""

  # ------- 丢包 -------
  print "【丢包评价】"
  if(dest_loss==0) print "- 末跳无丢包"
  else if(dest_loss<3) print "- 少量丢包，可接受"
  else print "- 丢包偏高"
  print ""

  # ------- 瓶颈点 -------
  print "【可能瓶颈点】"
  if(maxHop>1){
    print "- 第 " maxHop " 跳: " h_host[maxHop]
    printf("  ↑ 延迟跳升 %.1f ms\n",maxJump)
  } else print "- 无明显瓶颈"
  print ""

  # ------- 骨干运营商 -------
  print "【骨干运营商】"
  found=0
  for(c in carriers){ print "- " c; found=1 }
  if(!found) print "- 未识别"
  print ""

  # ------- 评分（已修复） -------
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

  printf("【综合线路评分】\n- 评分: %.0f / 100\n",score)
}
' "$REPORT"

echo "================================================"
echo "[✓] 分析结束"
