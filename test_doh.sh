#!/bin/bash

# 定义节点 URL 数组
urls=(
    "https://dns.alidns.com/dns-query?name=bilibili.com&type=A"
    "https://223.5.5.5:443/dns-query?name=bilibili.com&type=A"
    "https://doh.pub/dns-query?name=bilibili.com&type=A"
    "https://1.12.12.12:443/dns-query?name=bilibili.com&type=A"
    "https://hk1.pro.xns.one/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://45.249.245.247:5443/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://hk1.beta.xns.one/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://70.39.204.10:443/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://jp.pro.xns.one/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://142.248.150.166:443/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://jp.beta.xns.one/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
    "https://172.93.220.162:443/@whitisnotme/admin/dns-query?name=bilibili.com&type=A"
)

total_nodes=${#urls[@]}
count=5
timeout_sec=3
declare -a results

echo "开始深度测试 (每个节点 $count 次循环)..."
echo "------------------------------------------------"

node_index=0
for url in "${urls[@]}"; do
    ((node_index++))
    display_name=$(echo "$url" | sed -e 's|^https://||' -e 's|?.*||')
    
    # 清空当前节点的时间存储数组
    node_times=()
    
    for ((i=1; i<=count; i++)); do 
        # \r 让光标回到行首，\033[K 清除光标到行尾的内容（防止长短域名覆盖不干净）
        printf "\r\033[K\033[34m[%d/%d]\033[0m 正在测试: %s ... (%d/%d)" \
               "$node_index" "$total_nodes" "$display_name" "$i" "$count"
        
        t=$(curl -o /dev/null -s -w "%{time_namelookup} %{time_connect} %{time_appconnect} %{time_starttransfer} %{time_total}" \
             -m "$timeout_sec" -H "accept: application/dns-json" -k "$url")
        
        node_times+=("$t")
    done
    
    # 通过 awk 计算区间差值并求平均
    metrics=$(printf "%s\n" "${node_times[@]}" | awk -v c="$count" '
        BEGIN { sum_dns=0; sum_tcp=0; sum_tls=0; sum_proc=0; sum_tx=0; sum_total=0; valid=0 }
        {
            if ($5 > 0 && $4 > 0) {
                valid++
                sum_dns += $1
                sum_tcp += ($2 - $1)
                sum_tls += ($3 > 0 ? ($3 - $2) : 0)
                sum_proc += ($4 - ($3 > 0 ? $3 : $2))
                sum_tx += ($5 - $4)
                sum_total += $5
            }
        }
        END {
            if (valid == 0) print "Timeout";
            else printf "%.4f|%.4f|%.4f|%.4f|%.4f|%.4f", \
                 sum_total/valid, sum_dns/valid, sum_tcp/valid, sum_tls/valid, sum_proc/valid, sum_tx/valid
        }')
        
    results+=("${metrics}|${display_name}")
done

# 测试完成，擦除最后一行进度条，开始输出最终报告
printf "\r\033[K"
echo "测试完成！正在生成深度分析报告 (按总耗时从小到大排列):"

# 将结果排序并以树状图格式输出
printf "%s\n" "${results[@]}" | sort -n | while IFS='|' read -r total dns tcp tls proc tx name; do
    echo "================================================"
    if [[ "$total" == "Timeout" ]]; then
        printf "节点: %s\n" "$name"
        printf "\033[31m[×] 测试结果: 连接超时 / 节点不可用\033[0m\n"
    else
        # 根据总延迟上色
        color_code=$(awk -v t="$total" 'BEGIN {
            if (t < 0.1200) print "\033[32m"      # 极快（绿）
            else if (t < 0.3000) print "\033[33m" # 一般（黄）
            else print "\033[31m"                 # 较慢（红）
        }')
        
        printf "节点: %s\n" "$name"
        printf "${color_code}▶ 平均总耗时: %ss\033[0m\n" "$total"
        printf "   └── 1. 域名解析 (DNS) : %ss  (本地解析DoH域名的耗时)\n" "$dns"
        printf "   └── 2. 建立连接 (TCP) : %ss  (纯网络来回 RTT 延迟)\n" "$tcp"
        printf "   └── 3. 加密握手 (TLS) : %ss  (SSL 证书交换开销)\n" "$tls"
        printf "   └── 4. 服务端处理(TTFB): %ss  (服务器在上游上查域名的时间)\n" "$proc"
        printf "   └── 5. 数据传输 (Data): %ss  (结果包下发耗时)\n" "$tx"
    fi
done
echo "================================================"