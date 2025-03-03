#!/bin/bash

MODEL="deepseek-chat"
TEMPERATURE=1
API_KEY="<your_deepseek_API>"
USER_NAME=$(whoami)
STREAM=true 
LANGUAGE="(answer in Chinese)"
messages='[]'

# 帮助信息
if [[ "$1" == "-?" ]]; then
  echo "Usage: adsm [-v3] [-r1] [temperature]"
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
        if (( $(echo "$FORMATTED_TEMP >= 0.0 && $FORMATTED_TEMP <= 2.0" | bc -l) )); then
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

# 对话循环
while true; do
  read -rp "<$USER_NAME>: " USER_MESSAGE
  [[ "$USER_MESSAGE" == "exit" ]] && break
  echo;echo;
  # 更新消息历史
  messages=$(jq --arg role "user" --arg content "${USER_MESSAGE}${LANGUAGE}" \
    '. += [{"role": $role, "content": $content}]' <<< "$messages")

  # 构建请求
  DATA=$(jq -n \
    --arg model "$MODEL" \
    --argjson messages "$messages" \
    --argjson temperature "$TEMPERATURE" \
    --argjson stream "$STREAM" \
    '{
      model: $model,
      messages: $messages,
      temperature: $temperature,
      stream: true,
      response_format: { type: "text" },
      frequency_penalty: 0,
      max_tokens: 2048,
      presence_penalty: 0,
      stop: null,
      stream_options: null,
      top_p: 1,
      tools: null,
      tool_choice: "none",
      logprobs: false,
      top_logprobs: null
    }')

  # 处理响应
  echo  "<$MODEL,$TEMPERATURE>: "
  temp_file=$(mktemp)
  BUT=0  # 重置换行标记

  if [[ "$STREAM" == "true" ]]; then
    # 流式处理逻辑
    curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA" | while IFS= read -r line; do
      
      if [[ "$line" == data:* ]]; then
        [[ "$line" == *"[DONE]"* ]] && { echo -e "\n\n"; break; }

        JSON_DATA=$(sed 's/^data: //; s/\\n/\\\\n/g' <<< "$line")
        CONTENT=$(jq -r '.choices[0].delta | if .content == null then .reasoning_content else .content end' <<< "$JSON_DATA")
        RAW_CONTENT=$(jq -r '.choices[0].delta.content' <<< "$JSON_DATA")

        # 特殊格式处理（仅限reasoner模型）
        if [[ "$MODEL" == "deepseek-reasoner" ]]; then
          if (( BUT == 0 )) && [[ "$RAW_CONTENT" != "null" ]]; then
            BUT=1
            echo -e "\n\n" 
          fi
        fi

        [[ -n "$CONTENT" ]] && printf "%b" "$CONTENT" | tee -a "$temp_file"
      fi
    done
  else
    # 非流式处理
    RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA")
    
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

  # 更新对话历史
  assistant_content=$(cat "$temp_file")
  rm "$temp_file"
  messages=$(jq --arg role "assistant" --arg content "$assistant_content" \
    '. += [{"role": $role, "content": $content}]' <<< "$messages")
done
