#!/usr/bin/env bash

# 一键 mtr 检测脚本
# 功能：
# 1. 检查是否安装 mtr，没有就尝试自动安装
# 2. 提示输入目标 IP / 域名
# 3. 跑 mtr -rwzbc 100
# 4. 根据结果给出一个简易的人类可读报告

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
    echo "[*] 检测到 dnf（新版本 CentOS/RHEL/Fedora）"
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

REPORT_FILE="/tmp/mtr_report_${TARGET//[^a-zA-Z0-9_.-]/_}.txt"

echo
echo "[*] 开始使用 mtr 测试目标：$TARGET"
echo "[*] 命令：mtr -rwzbc 100 $TARGET"
echo

# 有些系统 mtr 需要 root 才能完整测速
if [ "$EUID" -ne 0 ]; then
  echo "[*] 当前非 root，尝试使用 sudo 运行 mtr..."
  sudo mtr -rwzbc 100 "$TARGET" > "$REPORT_FILE"
else
  mtr -rwzbc 100 "$TARGET" > "$REPORT_FILE"
fi

echo "[✓] mtr 测试完成，原始结果保存在：$REPORT_FILE"
echo

# ---------- 解析报告并生成“人话分析” ----------

echo "================== 原始 MTR 报告 =================="
cat "$REPORT_FILE"
echo "==================================================="
echo

echo "================== 自动分析报告 ==================="

awk '
BEGIN {
  maxJump = 0;
  prevAvg = -1;
  hopCount = 0;
}
# 记录每一跳，顺便计算“哪一跳延迟跳升最大”
/^[ ]*[0-9]+\./ {
  hopCount++;
  # 取最后 7 个字段（Loss% Snt Last Avg Best Wrst StDev）
  loss = $(NF-6);
  snt  = $(NF-5);
  last = $(NF-4);
  avg  = $(NF-3);
  best = $(NF-2);
  wrst = $(NF-1);
  stdev = $NF;

  # 主机名/IP 为前面的字段拼出来（除去最后 7 列）
  host="";
  for (i=2; i<=NF-7; i++) {
    host = host $i " ";
  }

  gsub(/%/, "", loss);

  hops[hopCount] = host;
  hop_avg[hopCount] = avg;

  if (prevAvg >= 0) {
    diff = avg - prevAvg;
    if (diff > maxJump) {
      maxJump = diff;
      maxHop = hopCount;
    }
  }
  prevAvg = avg;

  # 记录最后一跳（目标）
  dest_loss = loss;
  dest_snt  = snt;
  dest_last = last;
  dest_avg  = avg;
  dest_best = best;
  dest_wrst = wrst;
  dest_stdev= stdev;
  dest_host = host;
}
END {
  if (hopCount == 0) {
    print "[×] 没解析到任何跳数，可能 mtr 运行失败。";
    exit;
  }

  print "目标节点: " dest_host;
  print "发送次数: " dest_snt;
  print "丢包率  : " dest_loss "%";
  print "延迟统计: Avg=" dest_avg " ms, Best=" dest_best " ms, Worst=" dest_wrst " ms, 抖动(StDev)=" dest_stdev " ms";
  print "";

  # 延迟评价
  avg = dest_avg + 0;
  stdev = dest_stdev + 0;
  loss = dest_loss + 0;

  print "【延迟评价】";
  if (avg <= 30) {
    print "- 延迟优秀（适合游戏、实时业务、中转节点等）。";
  } else if (avg <= 80) {
    print "- 延迟中等（一般 Web / API / 日常业务都可以）。";
  } else {
    print "- 延迟较高（跨洲或绕路较多，更适合作为备线路或非实时业务）。";
  }

  print "";
  print "【稳定性评价】";
  if (stdev <= 3) {
    print "- 抖动很小，线路非常稳定。";
  } else if (stdev <= 10) {
    print "- 抖动中等，偶尔会有小尖峰。";
  } else {
    print "- 抖动较大，链路质量一般，可能有拥塞或路由不稳。";
  }

  print "";
  print "【丢包评价】";
  if (loss == 0) {
    print "- 末跳无丢包，整体连通性正常。";
  } else if (loss < 3) {
    print "- 有少量丢包（<3%），大部分业务仍可接受。";
  } else {
    print "- 丢包偏高（>=3%），建议谨慎用于重要业务。";
  }

  print "";
  print "【最大延迟跳升点（可能的跨境/出海/瓶颈处）】";
  if (maxHop > 1) {
    printf("- 第 %d 跳：%s\n", maxHop, hops[maxHop]);
    printf("  与上一跳平均延迟相差约 %.1f ms。\n", maxJump);
  } else {
    print "- 未发现明显跳升点（或只有一跳）。";
  }

  print "";
  print "（提示：中间有 100% loss 但最后一跳无丢包时，通常是中间路由器屏蔽 ICMP，不是真掉包。）";
}
' "$REPORT_FILE"

echo "==================================================="
echo
echo "[✓] 分析结束。你可以根据上面的自动报告初步判断这条线路质量。"
