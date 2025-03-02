#!/bin/bash
# 默认参数
MODEL="deepseek-chat"
TEMPERATURE=1
API_KEY="<your_deepseek_API>"  # 替换为你的 DeepSeek API Key
USER_NAME=$(whoami)  # 获取当前用户名
LANGUAGE="(answer in Chinese)"  # 默认语言提示
STREAM=true 
BUT=0

# 帮助信息
if [[ "$1" == "-?" ]]; then
  echo "Usage: ads [-v3] [-r1] [temperature]"
  echo "  -v3: 使用 deepseek-chat 模型（默认）"
  echo "  -r1: 使用 deepseek-reasoner 模型"
  echo "  -e: 输出英文（默认输出中文）"
  echo "  temperature: 可选，设置 temperature 参数，默认为 1.0"
  exit 0
fi

# 参数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -v3) MODEL="deepseek-chat"; shift ;;
    -r1) MODEL="deepseek-reasoner"; shift ;;
    -e) LANGUAGE=""; shift ;;
    *) 
      if [[ "$1" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        FORMATTED_TEMP=$(printf "%.1f" "$1")
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

# 用户输入
read -rp "<$USER_NAME>: " USER_MESSAGE
echo;echo;
# 构造请求数据
DATA=$(cat <<EOF
{
  "model": "$MODEL",
  "messages": [
    {"role": "user", "content": "$USER_MESSAGE$LANGUAGE"}
  ],
  "temperature": $TEMPERATURE,
    "response_format": {
    "type": "text"
  },
  "frequency_penalty": 0,
  "max_tokens": 2048,
  "presence_penalty": 0,
  "stop": null,
  "stream": true,
  "stream_options": null,
  "top_p": 1,
  "tools": null,
  "tool_choice": "none",
  "logprobs": false,
  "top_logprobs": null
}
EOF
)


# 发送请求并处理响应,添加-n不换行
echo  "<$MODEL,$TEMPERATURE>: "

if [ "$STREAM" = "true" ]; then
  # 流式处理
  curl -s -X POST https://api.deepseek.com/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$DATA" | while IFS= read -r line; do
    if [[ "$line" == data:* ]]; then
      if [[ "$line" == *"[DONE]"* ]]; then
        echo
        break
      fi
      JSON_DATA=$(printf "%s" "$line" | sed 's/^data: //; s/\\n/\\\\n/g')
      CONTENT=$(echo "$JSON_DATA" | jq -r '.choices[0].delta | if .content == null then .reasoning_content else .content end')
      if [ "$MODEL" == deepseek-reasoner"" ] && [ $BUT -eq 0 ] && [ "$(echo "$JSON_DATA" | jq -r '.choices[0].delta.content')" != "null" ]; then
          BUT=1
          echo -e "\n\n"
      fi
      if [[ -n "$CONTENT" ]]; then
        printf "%b" "$CONTENT"
      fi
    fi
  done
  echo -e "\n"
else
  # 非流式处理
  RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
    -H "Content-Type: application/json" \
    -H "Authorization: Bearer $API_KEY" \
    -d "$DATA")
  RCONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.reasoning_content')
  if [ "$RCONTENT" != "null" ]; then
    printf "%b" "$RCONTENT"
    echo;echo;
  fi
  CONTENT=$(echo "$RESPONSE" | jq -r '.choices[0].message.content')
  printf "%b" "$CONTENT"
#  echo "DEBUG : $CONTENT" | head -n 10 >&2
  echo -e "\n"
fi
