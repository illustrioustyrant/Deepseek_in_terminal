以下是两个脚本的详细注释，重点解释了参数意义、代码逻辑及关键语句：

```bash
# ads.sh 注释版本
#!/bin/bash

# 模型选择，默认使用 deepseek-chat
MODEL="deepseek-chat"
# 温度参数，控制输出随机性（0-2）。0表示完全确定性，适合精确回答
TEMPERATURE=1
# DeepSeek API 密钥，需用户替换
API_KEY="<your_deepseek_API>"
# 获取当前用户名用于交互提示
USER_NAME=$(whoami)  
# 语言标记，强制中文输出（空值表示英文）
LANGUAGE="(answer in Chinese)" 
# 是否启用流式响应（true=逐字输出，false=一次性显示）
STREAM=true 
# 特殊换行标记（用于 deepseek-reasoner 模型格式处理）
BUT=0

# 帮助信息
if [[ "$1" == "-?" ]]; then
  echo "Usage: ads [-v3] [-r1] [temperature]"
  echo "  -v3: 使用 deepseek-chat 模型（默认）"
  echo "  -r1: 使用 deepseek-reasoner 模型"
  echo "  -e: 输出英文（默认输出中文）"
  echo "  temperature: 可选，设置 temperature 参数（0.0-2.0），默认为1.0"
  exit 0
fi

# 参数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -v3) MODEL="deepseek-chat"; shift ;;  # 切换聊天模型
    -r1) MODEL="deepseek-reasoner"; shift ;;  # 切换推理模型
    -e) LANGUAGE=""; shift ;;  # 切换英文输出
    *) 
      # 处理 temperature 参数（支持整数和小数）
      if [[ "$1" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        # 格式化为1位小数（例如1→1.0）
        FORMATTED_TEMP=$(printf "%.1f" "$1")
        # 验证温度值是否在0.0-2.0范围内
        if [[ "$FORMATTED_TEMP" =~ ^(2(\.0)?|1(\.[0-9])?|0(\.[0-9])?)$ ]]; then
          TEMPERATURE=$FORMATTED_TEMP
          shift
        fi
        break
      else
        break
      fi
      ;;
  esac
done

# 读取用户输入
read -rp "<$USER_NAME>: " USER_MESSAGE
echo;echo;

# 构造 API 请求的 JSON 数据
DATA=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "user", "content": "$USER_MESSAGE$LANGUAGE"}
  ],
  "temperature": $TEMPERATURE,  # 关键参数：温度值设为0时输出完全确定
  "response_format": {
    "type": "text"
  },
  "frequency_penalty": 0,  # 频率惩罚（0=不惩罚重复内容）
  "max_tokens": 2048,       # 响应最大token数
  "stream": $STREAM         # 是否启用流式传输
  # 其他参数保持默认...
}
EOF
)

# 显示当前模型和温度配置
echo  "<$MODEL,$TEMPERATURE>: "

if [ "$STREAM" = "true" ]; then
  # 流式处理：逐字显示响应内容
  curl -s -X POST https://api.deepseek.com/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$DATA" | while IFS= read -r line; do
    if [[ "$line" == data:* ]]; then
      # 结束标记检测
      if [[ "$line" == *"[DONE]"* ]]; then
        echo
        break
      fi
      # 提取JSON数据并处理转义字符,sed会将API输出的\\n吞掉，所以这里将\\n转为\\\\n，n不能漏否则会在\"周围加上不必要的/
      JSON_DATA=$(printf "%s" "$line" | sed 's/^data: //; s/\\n/\\\\n/g')
      # 解析内容字段（适配不同模型的返回结构）
      CONTENT=$(echo "$JSON_DATA" | jq -r '.choices[0].delta | if .content == null then .reasoning_content else .content end')
      # 处理 deepseek-reasoner 的特殊换行需求
      if [ "$MODEL" == "deepseek-reasoner" ] && [ $BUT -eq 0 ] && [ "$(echo "$JSON_DATA" | jq -r '.choices[0].delta.content')" != "null" ]; then
          BUT=1
          echo -e "\n\n"  # 添加推理模型的分隔空行
      fi
      # 输出非空内容
      if [[ -n "$CONTENT" ]]; then
        printf "%b" "$CONTENT"  # 保留转义字符（如\n）
      fi
    fi
  done
  echo -e "\n"
else
  # 非流式处理：一次性获取完整响应
  RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$DATA")
  # 优先提取推理内容字段
  RCONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.reasoning_content')
  if [ "$RCONTENT" != "null" ]; then
    printf "%b" "$RCONTENT"
    echo;echo;
  fi
  # 提取普通内容字段
  CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
  printf "%b" "$CONTENT"
  echo -e "\n"
fi
```

```bash
# adsm.sh 注释版本
#!/bin/bash

# 多轮对话版脚本

MODEL="deepseek-chat"
TEMPERATURE=1
API_KEY="<your_deepseek_API>"
USER_NAME=$(whoami)
STREAM=true 
LANGUAGE="(answer in Chinese)"
messages='[]'  # 使用JSON数组存储对话历史

# 参数解析（同ads.sh）
[...参数解析部分与ads.sh相同，此处省略...]

# 持续对话循环
while true; do
  read -rp "<$USER_NAME>: " USER_MESSAGE
  [[ "$USER_MESSAGE" == "exit" ]] && break  # 输入exit退出循环
  echo;echo;
  
  # 使用jq更新消息历史（追加用户消息）
  messages=$(jq --arg role "user" --arg content "${USER_MESSAGE}${LANGUAGE}" \
    '. += [{"role": $role, "content": $content}]' <<< "$messages")

  # 动态构建请求数据
  DATA=$(jq -n \
    --arg model "$MODEL" \
    --argjson messages "$messages" \
    --argjson temperature "$TEMPERATURE" \
    --argjson stream "$STREAM" \
    '{
      model: $model,
      messages: $messages,  # 包含历史对话的上下文
      temperature: $temperature,
      stream: true,
      response_format: { type: "text" },
      max_tokens: 2048,
      # 其他参数保持默认...
    }')

  # 创建临时文件存储本次响应内容
  temp_file=$(mktemp)
  BUT=0  # 重置换行标记

  echo  "<$MODEL,$TEMPERATURE>: "

  if [[ "$STREAM" == "true" ]]; then
    # 流式处理（实时显示）
    curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA" | while IFS= read -r line; do
      
      if [[ "$line" == data:* ]]; then
        # 结束标记处理
        [[ "$line" == *"[DONE]"* ]] && { echo -e "\n\n"; break; }

        JSON_DATA=$(sed 's/^data: //; s/\\n/\\\\n/g' <<< "$line")
        # 同时提取内容和原始内容
        CONTENT=$(jq -r '.choices[0].delta | if .content == null then .reasoning_content else .content end' <<< "$JSON_DATA")
        RAW_CONTENT=$(jq -r '.choices[0].delta.content' <<< "$JSON_DATA")

        # 推理模型的首条响应添加空行
        if [[ "$MODEL" == "deepseek-reasoner" ]]; then
          if (( BUT == 0 )) && [[ "$RAW_CONTENT" != "null" ]]; then
            BUT=1
            echo -e "\n\n" 
          fi
        fi

        # 实时输出并写入临时文件
        [[ -n "$CONTENT" ]] && printf "%b" "$CONTENT" | tee -a "$temp_file"
      fi
    done
  else
    # 非流式处理（批量显示）
    RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA")
    
    # 合并推理内容和普通内容
    CONTENT=$(jq -r '
    .choices[0].message |
    (
      (if .reasoning_content != null then "\(.reasoning_content)\n\n" else "" end) +
      (if .content != null then "\(.content)" else "" end)
    )
  ' <<< "$RESPONSE")
    printf "%b" "$CONTENT" | tee "$temp_file"
    echo -e "\n\n"
  fi

  # 将AI响应追加到消息历史
  assistant_content=$(cat "$temp_file")
  rm "$temp_file"  # 清理临时文件
  messages=$(jq --arg role "assistant" --arg content "$assistant_content" \
    '. += [{"role": $role, "content": $content}]' <<< "$messages")
done
```

### 关键参数说明
1. **temperature**：
   - 范围：`0.0-2.0`
   - `0`：完全确定性输出，适合事实性问题
   - `1`：平衡创造性（默认值）
   - `2`：最大随机性

2. **流式处理**：
   - `STREAM=true`：逐字实时显示响应，体验更自然
   - `STREAM=false`：等待完整响应后一次性显示

3. **jq操作**：
   - `jq --arg ...`：动态构建JSON对象
   - `jq '. += [...]'`：追加元素到数组
   - `jq -r`：输出原始内容（非JSON格式）

4. **消息历史**：
   - `messages`变量以JSON数组形式存储对话上下文
   - 每次交互都会追加用户输入和AI响应

### 典型场景
当设置`temperature=0`时：
```bash
ads -r1 0  # 使用推理模型+确定性输出
adsm -e 0  # 多轮英文对话+确定性输出
```

两个脚本的核心区别：
- `ads.sh`：单次对话，无上下文记忆
- `adsm.sh`：持续对话，通过`messages`变量维护上下文
