#!/bin/bash

API_KEY="<yourkey>"
USER_NAME=$(whoami)
LANGUAGE="(answer in Chinese)"

# 读取配置文件
CONFIG_FILE="$HOME/.dsconfig"
if [[ ! -f "$CONFIG_FILE" ]]; then
  echo "错误：配置文件 $CONFIG_FILE 不存在" >&2
  exit 1
fi

CONFIG=$(cat "$CONFIG_FILE")
messages=$(jq -c '.messages' <<< "$CONFIG")

# 帮助信息
if [[ "$1" == "-?" ]]; then
  echo "Usage: adsm [-e]"
  echo "  -e: 输出英文（默认输出中文）"
  exit 0
fi

# 参数解析
while [[ $# -gt 0 ]]; do
  case $1 in
    -e)
      LANGUAGE=""
      shift
      ;;
    -*)
      echo "错误：无效选项 $1" >&2
      exit 1
      ;;
    *)
      echo "错误：未知参数 $1" >&2
      exit 1
      ;;
  esac
done

# 对话循环
while true; do
  read -rp "<$USER_NAME>: " USER_MESSAGE
  [[ "$USER_MESSAGE" == "exit" ]] && break
  echo;echo;
  
  # 更新消息历史（添加用户消息）
  messages=$(jq -c --arg role "user" --arg content "${USER_MESSAGE}${LANGUAGE}" \
    '. + [{"role": $role, "content": $content}]' <<< "$messages")

  # 构建请求数据（使用配置文件参数并替换messages）
  DATA=$(jq -c --argjson messages "$messages" '.messages = $messages' <<< "$CONFIG")

  # 处理响应
  MODEL=$(jq -r '.model' <<< "$CONFIG")
  TEMPERATURE=$(jq -r '.temperature' <<< "$CONFIG")
  echo  "<$MODEL,$TEMPERATURE>: "
  temp_file=$(mktemp)

  # 非流式处理（根据配置文件中的stream设置）
  if [[ $(jq -r '.stream' <<< "$CONFIG") == "false" ]]; then
    RESPONSE=$(curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA")

    CONTENT=$(jq -r '
      .choices[0].message |
      ((.reasoning_content // "") + (.content // ""))
    ' <<< "$RESPONSE")
    
    printf "%b" "$CONTENT" | tee "$temp_file"
    echo -e "\n\n"
    
  else
    # 流式处理逻辑（保留原有流式处理代码）
    curl -s -X POST https://api.deepseek.com/chat/completions \
      -H "Content-Type: application/json" \
      -H "Authorization: Bearer $API_KEY" \
      -d "$DATA" | while IFS= read -r line; do
        #   # 流式处理逻辑
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
  fi

  # 更新对话历史（添加助手回复）
  assistant_content=$(cat "$temp_file")
  rm "$temp_file"
  messages=$(jq -c --arg role "assistant" --arg content "$assistant_content" \
    '. + [{"role": $role, "content": $content}]' <<< "$messages")
done

